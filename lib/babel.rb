#!/usr/bin/ruby
# Programmer: Chris Bunch (cgb@cs.ucsb.edu)

require 'common_functions'
require 'custom_exceptions'
require 'neptune'
require 'neptune_manager_client'
require 'task_info'


# The promise gem gives us futures / promises out-of-the-box, which we need
# to hide the fact that babel jobs are asynchronous.
require 'rubygems'
require 'promise'
require 'future'


# If the user doesn't give us enough info to infer what bucket we should place
# their code in, this message is displayed and execution aborts.
NEEDS_BUCKET_INFO = "When running Babel jobs with local inputs / code, the " +
  "bucket to store them in must be specified by either the :bucket_name " +
  "parameter or the BABEL_BUCKET_NAME environment variable."


# The constant string that a Neptune output job returns if the output does not
# yet exist.
DOES_NOT_EXIST = "error: output does not exist"


# The initial amount of time, in seconds, to sleep between output job requests.
# An exponential backoff is used with this value as the starting sleep time.
SLEEP_TIME = 5  # seconds


# The maximum amount of time that we should sleep to, when waiting for output
# job requests.
MAX_SLEEP_TIME = 60  # seconds


# Babel provides a nice wrapper around Neptune jobs. Instead of making users
# write multiple Neptune jobs to actually run code (e.g., putting input in the
# datastore, run the job, get the output back), Babel automatically handles
# this.
def babel(jobs)
  # Since this whole function should run asynchronously, we run it as a future.
  # It automatically starts running in a new thread, and attempting to get the
  # value of what this returns causes it to block until the job completes.
  #future {
    if jobs.class == Hash
      was_one_job = true
      jobs = [jobs]
    else
      was_one_job = false
    end

    job_data_list = []
    jobs.each { |params|
      job_data = BabelHelper.convert_from_neptune_params(params)
      job_data['@metadata_info'] = {'time_to_store_inputs' => 0.0}

      # Add in S3 storage parameters
      NeptuneHelper.validate_storage_params(job_data)

      # :code is the only required parameter
      # everything else can use default vals
      NeptuneHelper.require_param("@code", job_data)
      BabelHelper.check_output_files(job_data)

      if job_data["@is_remote"]
        #BabelHelper.validate_inputs(job_data)
      else
        BabelHelper.put_code(job_data)
        BabelHelper.put_inputs(job_data)
      end

      job_data_list << job_data
    }

    BabelHelper.run_job(job_data_list)

    # Return an object to the user that has all the information about their
    # task, including its standard out, err, debugging info, and profiling
    # info. Since the job may not be done when the user asks for this info,
    # its the responsibility of TaskInfo objects to block until that info
    # is ready. We don't explicitly return the TaskInfo object, because it's
    # in a Future block - it will automatically return whatever the last
    # statement returns.
    tasks = []
    job_data_list.each { |job_data|
      tasks << TaskInfo.new(job_data)
    }

    if was_one_job
      tasks[0]
    else
      tasks
    end
  #}
end


# This module provides convenience functions for babel().
module BabelHelper


  # If the user fails to give us an output location, this function will generate
  # one for them, based on either the location of their code (for remotely
  # specified code), or a babel parameter (for locally specified code).
  def self.generate_output_location(job_data)
    if job_data["@is_remote"]
      # We already know the bucket name - the same one that the user
      # has told us their code is located in.
      prefix = job_data["@code"].scan(/\/(.*?)\//)[0].to_s
    else
      prefix = self.get_bucket_for_local_data(job_data)
    end
      
    return "/#{prefix}/babel/temp-#{CommonFunctions.get_random_alphanumeric()}"
  end


  # Provides a common way for callers to get the name of the bucket that
  # should be used for Neptune jobs where the code is stored locally.
  def self.get_bucket_for_local_data(job_data)
    bucket_name = job_data["@bucket_name"] || ENV['BABEL_BUCKET_NAME'] ||
      job_data["@S3_bucket_name"] || job_data["@Walrus_bucket_name"] ||
      job_data["@GStorage_bucket_name"] || job_data["@WAZ_Container_Name"]

    if bucket_name.nil?
      raise BadConfigurationException.new(NEEDS_BUCKET_INFO)
    end

    # If the bucket name starts with a slash, remove it
    if bucket_name[0].chr == "/"
      bucket_name = bucket_name[1, bucket_name.length]
    end

    return bucket_name
  end

  
  # babel() callers do not have to specify a location where the standard output
  # and error the task produces should be placed. If they don't, generate
  # locations for them and make sure they don't exist beforehand.
  def self.check_output_files(job_data)
    ["@output", "@error", "@metadata"].each { |item|
      if job_data[item].nil? or job_data[item].empty?
        job_data[item] = BabelHelper.generate_output_location(job_data)
      else
        BabelHelper.ensure_output_does_not_exist(job_data, job_data[item])
      end
      }
  end


  # For jobs where the code is stored remotely, this method ensures that 
  # the code and any possible inputs actually do exist, before attempting to
  # use them for computation.
  def self.validate_inputs(job_data)
    controller = self.get_neptune_manager_client(job_data)

    # First, make sure the code exists
    NeptuneHelper.require_file_to_exist(job_data["@code"], job_data, controller)

    if job_data["@argv"].nil? or job_data["@argv"].empty?
      return
    end

    # We assume anything that begins with a slash is a remote file
    job_data["@argv"].each { |arg|
      if arg[0].chr == "/"
        NeptuneHelper.require_file_to_exist(arg, job_data, controller)
      end
    }
  end


  # To avoid accidentally overwriting outputs from previous jobs, we first
  # check to make sure an output file doesn't exist before starting a new job
  # with the given name.
  def self.ensure_output_does_not_exist(job_data, remote_file)
    controller = self.get_neptune_manager_client(job_data)
    NeptuneHelper.require_file_to_not_exist(remote_file, job_data, controller)
  end


  # Returns an NeptuneManagerClient for the given job data.
  def self.get_neptune_manager_client(job_data)
    keyname = job_data["@keyname"] || "appscale"
    shadow_ip = CommonFunctions.get_from_yaml(keyname, :shadow)
    secret = CommonFunctions.get_secret_key(keyname)
    return NeptuneManagerClient.new(shadow_ip, secret)
  end


  # Stores the user's code (and the directory it's in, and directories in the
  # same directory as the user's code, since there could be libraries used)
  # in the remote datastore.
  def self.put_code(job_data)
    code_dir = File.dirname(job_data["@code"])
    code = File.basename(job_data["@code"])
    remote_code_dir = self.put_file(code_dir, job_data)
    job_data["@code"] = remote_code_dir + "/" + code
    return job_data["@code"]
  end


  # If any input files are specified, they are copied to the remote datastore
  # via Neptune 'input' jobs. Inputs are assumed to be files on the local
  # filesystem if they begin with a slash, and job_data gets updated with
  # the remote location of these files.
  def self.put_inputs(job_data)
    if job_data["@argv"].nil? or job_data["@argv"].empty?
      return job_data
    end

    job_data["@argv"].each_index { |i|
      arg = job_data["@argv"][i]
      if arg[0].chr == "/"
        job_data["@argv"][i] = self.put_file(arg, job_data)
      end
    }

    return job_data
  end


  # If the user gives us local code or local inputs, this function will
  # run a Neptune 'input' job to store the data remotely.
  def self.put_file(local_path, job_data)
    input_data = self.convert_to_neptune_params(job_data)
    input_data[:type] = "input"
    input_data[:local] = local_path

    bucket_name = self.get_bucket_for_local_data(job_data)
    input_data[:remote] = "/#{bucket_name}/babel#{local_path}"

    start = Time.now
    Kernel.neptune(input_data)
    fin = Time.now
    
    if job_data['@metadata_info'].nil?
      job_data['@metadata_info'] = {'time_to_store_inputs' => 0.0}
    end

    job_data['@metadata_info']['time_to_store_inputs'] += fin - start

    return input_data[:remote]
  end


  # Neptune internally uses job_data with keys of the form @name, but since the
  # user has given them to us in the form :name, we convert it here.
  # TODO(cgb): It looks like this conversion to/from may be unnecessary since
  # neptune() just re-converts it - how can we remove it?
  def self.convert_from_neptune_params(params)
    job_data = {}
    params.each { |k, v|
      key = "@#{k}"
      job_data[key] = v
    }
    return job_data
  end


  # Neptune input jobs expect keys of the form :name, but since we've already
  # converted them to the form @name, this function reverses that conversion.
  def self.convert_to_neptune_params(job_data)
    neptune_params = {}

    job_data.each { |k, v|
      key = k.delete("@").to_sym
      neptune_params[key] = v
    }

    return neptune_params
  end


  # Constructs a Neptune job to run the user's code as a Babel job (task queue)
  # from the given parameters.
  def self.run_job(job_data_list)
    run_data_list = []

    job_data_list.each { |job_data|
      run_data = self.convert_to_neptune_params(job_data)

      # Default to babel as the job type, if the user doesn't specify one.
      if run_data[:type].nil? or run_data[:type].empty?
        run_data[:type] = "babel"
      end

      # TODO(cgb): Once AppScale+Babel gets support for RabbitMQ, change this to
      # exec tasks over it, instead of locally.
      if job_data["@run_local"].nil?
        run_data[:run_local] = true
        run_data[:engine] = "executor-sqs"
      end

      run_data[:failed_attempts] = 0
      run_data_list << run_data
    }

    loop {
      if run_data_list.length == 1
        run_job = Kernel.neptune(run_data_list[0])
      else
        run_job = Kernel.neptune(run_data_list)
      end

      if run_job[:result] == :success
        return run_job
      else
        run_data_list[0][:failed_attempts] += 1
        Kernel.sleep(SLEEP_TIME)  # TODO(cgb): this should exponentially backoff
      end
    }
  end


  # Constructs a Neptune job to get the output of a Babel job. If the job is not
  # yet finished, this function waits until it does, and then returns the output
  # of the job.
  def self.wait_and_get_output(job_data, output_location)
    output_data = self.convert_to_neptune_params(job_data)
    output_data[:type] = "output"
    output_data[:output] = output_location

    output = ""
    time_to_sleep = SLEEP_TIME
    loop {
      output = Kernel.neptune(output_data)[:output]
      if output == DOES_NOT_EXIST
        # Exponentially back off, up to a limit of MAX_SLEEP_TIME
        Kernel.sleep(time_to_sleep)
        #if time_to_sleep < MAX_SLEEP_TIME
        #  time_to_sleep *= 2
        #end
      else
        break
      end
    }
  
    return output
  end
end
