#!/usr/bin/env ruby
# Programmer: Chris Bunch


require 'rubygems'
require 'json'


require 'babel'
require 'common_functions'
require 'custom_exceptions'
require 'exodus_task_info'


# Exodus provides further improvements to Babel. Instead of making users tell
# us what compute, storage, and queue services they want to use (required for
# babel calls), Exodus will automatically handle this for us. Callers need
# to specify what clouds their job can run over, and Exodus will automatically
# select the best cloud for their job and run it there.
def exodus(jobs)
  if jobs.class == Hash
    job_given_as_hash = true
    jobs = [jobs]
  elsif jobs.class == Array
    job_given_as_hash = false
    ExodusHelper.ensure_all_jobs_are_hashes(jobs)
  else
    raise BadConfigurationException.new("jobs was a #{jobs.class}, which " +
      "is not an acceptable class type")
  end

  tasks = []

  jobs.each { |job|
    ExodusHelper.ensure_all_params_are_present(job)
    profiling_info = ExodusHelper.get_profiling_info(job)
    clouds_to_run_task_on = ExodusHelper.get_clouds_to_run_task_on(job, 
      profiling_info)
    babel_tasks_to_run = ExodusHelper.generate_babel_tasks(job, 
      clouds_to_run_task_on)
    dispatched_tasks = ExodusHelper.run_job(babel_tasks_to_run)
    tasks << ExodusTaskInfo.new(dispatched_tasks)
  }

  if job_given_as_hash
    return tasks[0]
  else
    return tasks
  end
end


# This module provides convenience functions for exodus(), to avoid cluttering
# up Object or Kernel's namespace.
module ExodusHelper


  # A list of clouds that users can run tasks on via Exodus.
  SUPPORTED_CLOUDS = [:AmazonEC2, :Eucalyptus, :GoogleAppEngine, 
    :MicrosoftAzure]


  CLOUD_CREDENTIALS = {
    :AmazonEC2 => [:EC2_ACCESS_KEY, :EC2_SECRET_KEY, :EC2_URL, :S3_URL,
      :S3_bucket_name],
    :Eucalyptus => [:EUCA_ACCESS_KEY, :EUCA_SECRET_KEY, :EUCA_URL, 
      :WALRUS_URL, :Walrus_bucket_name],
    :GoogleAppEngine => [:appid, :appcfg_cookies, :function, 
      :GStorage_bucket_name],
    :MicrosoftAzure => [:WAZ_Account_Name, :WAZ_Access_Key, 
      :WAZ_Container_Name]
  }

  
  CLOUD_BABEL_PARAMS = {
    :AmazonEC2 => {
      :storage => "s3",
      :engine => "executor-sqs"
    },
    :Eucalyptus => {
      :storage => "walrus",
      :engine => "executor-rabbitmq"
    },
    :GoogleAppEngine => {
      :storage => "gstorage",
      :engine => "appengine-push-q"
    },
    :MicrosoftAzure => {
      :storage => "waz-storage",
      :engine => "waz-push-q"
    }
  }


  # The location on this machine where we can read and write profiling
  # information about jobs.
  NEPTUNE_DATA_DIR = File.expand_path("~/.neptune")


  # The command that we can run to get information about the number and speed
  # of CPUs on this machine.
  GET_CPU_INFO = "cat /proc/cpuinfo"


  OPTIMIZE_FOR_CHOICES = [:performance, :cost, :auto]


  # Given an Array of jobs to run, ensures that they are all Hashes, the
  # standard format for Neptune jobs.
  def self.ensure_all_jobs_are_hashes(jobs)
    jobs.each { |job|
      if job.class != Hash
        raise BadConfigurationException.new("A job passed to exodus() was " +
          "not a Hash, but was a #{job.class}")
      end
    }
  end


  # Given an Exodus job, validates its parameters, raising a 
  # BadConfigurationException for any missing params.
  def self.ensure_all_params_are_present(job)
    if job[:clouds_to_use].nil?
      raise BadConfigurationException.new(":clouds_to_use was not specified")
    else
      self.convert_clouds_to_use_to_array(job)
      self.validate_clouds_to_use(job)
      self.validate_optimize_for_param(job)
      self.validate_files_argv_executable(job)
    end
  end


  # Given a single Exodus job, checks to make sure it has either an Array
  # of Strings or a single String listing the clouds that a given task can
  # run on. Raises a BadConfigurationException if :clouds_to_use is not in
  # the right format.
  def self.convert_clouds_to_use_to_array(job)
    clouds_class = job[:clouds_to_use].class
    if clouds_class == Symbol
      job[:clouds_to_use] = [job[:clouds_to_use]]
    elsif clouds_class == Array
      job[:clouds_to_use].each { |cloud|
        if cloud.class != Symbol
          raise BadConfigurationException.new("#{cloud} was not a String, " +
            "but was a #{cloud.class}")
        end
      }
    else
      raise BadConfigurationException.new("#{job[:clouds_to_use]} was not " +
        "a String or Array, but was a #{clouds_class}")
    end
  end


  # Given a single Exodus job, checks to make sure that we can actually run
  # it in this version of Neptune, and that the user has given us all the 
  # credentials needed to use that cloud.
  def self.validate_clouds_to_use(job)
    self.ensure_credentials_are_in_correct_format(job)
    self.propogate_credentials_from_environment(job)

    job[:clouds_to_use].each { |cloud|
      if SUPPORTED_CLOUDS.include?(cloud)
        CLOUD_CREDENTIALS[cloud].each { |required_credential|
          val_for_credential = job[:credentials][required_credential]
          if val_for_credential.nil? or val_for_credential.empty?
            raise BadConfigurationException.new("To use #{cloud}, " +
              "#{required_credential} must be specified.")
          end
        }
      else
        raise BadConfigurationException.new("#{cloud} was specified as in " +
          ":clouds_to_use, which is not a supported cloud.")
      end
    }
  end


  def self.ensure_credentials_are_in_correct_format(job)
    if job[:credentials].nil?
      raise BadConfigurationException.new("No credentials were specified.")
    end

    if job[:credentials].class != Hash
      raise BadConfigurationException.new("Credentials given were not a " +
        "Hash, but were a #{job[:credentials].class}")
    end
  end


  # Searches the caller's environment variables, and adds any that could
  # be used in this Exodus job. Only takes in credentials from the
  # environment if the job does not specify it.
  def self.propogate_credentials_from_environment(job)
    CLOUD_CREDENTIALS.each { |cloud_name, credential_list|
      credential_list.each { |cred|
        if job[:credentials][cred].nil? and !ENV[cred.to_s].nil?
          job[:credentials][cred] = ENV[cred.to_s]
        end
      }
    }
  end


  def self.validate_optimize_for_param(job)
    if job[:optimize_for].nil?
      raise BadConfigurationException.new(":optimize_for needs to be " +
        "specified when running Exodus jobs")
    end

    if !OPTIMIZE_FOR_CHOICES.include?(job[:optimize_for])
      raise BadConfigurationException.new("The value given for " +
        ":optimize_for was not an acceptable value. Acceptable values are: " +
        "#{OPTIMIZE_FOR_CHOICES.join(', ')}")
    end
  end


  def self.validate_files_argv_executable(job)
    [:code, :argv, :executable].each { |param|
      if job[param].nil?
        raise BadConfigurationException.new("#{param} was not specified")
      end
    }
  end


  def self.get_profiling_info(job)
    key = self.get_key_from_job_data(job)

    if !File.exists?(NEPTUNE_DATA_DIR)
      FileUtils.mkdir(NEPTUNE_DATA_DIR)
    end

    profiling_info_file = "#{NEPTUNE_DATA_DIR}/#{key}.json"
    if File.exists?(profiling_info_file)
      contents = File.open(profiling_info_file) { |f| f.read() }
      return JSON.load(contents)
    end

    # If we don't have any profiling info on this job, run it locally and
    # gather the data ourselves.

    start_time = Time.now
    # TODO(cgb): exec the user's code
    end_time = Time.now
    
    # To find out how fast this computer is, just check the file that has
    # this info on it and take the first processor. This should be fine
    # since we assume the user's code is not-multi-core aware and that
    # all processors on this box are the same speed.
    cpu_speed = Float(CommonFunctions.shell(GET_CPU_INFO).
      scan(/cpu MHz\s*:\s*(\d+\.\d+)/).flatten[0])

    json_info = {
      "total_execution_time" => end_time - start_time,
      "cpu_speed" => cpu_speed
    }

    File.open(profiling_info_file, "w+") { |file| 
      file.write(JSON.dump(json_info)) 
    }

    return json_info
  end


  # TODO(cgb): what is a job's key?
  def self.get_key_from_job_data(job)
    return job[:code].gsub(/[\/\.]/, "")
  end

  
  def self.get_clouds_to_run_task_on(job, profiling_info)
    optimize_for = job[:optimize_for]
    if optimize_for == :performance or optimize_for == :cost
      return self.get_minimum_val_in_data(job, profiling_info)
    else
      return self.find_optimal_cloud_for_task(job, profiling_info)
    end
  end


  def self.get_minimum_val_in_data(job, profiling_info)
    min_cloud = nil
    min_val = 1_000_000  # infinity
    optimize_for = job[:optimize_for].to_s

    clouds_to_run_on = []
    job[:clouds_to_use].each { |cloud|
      # If we have no information on this cloud, then add it to the list
      # of clouds we should run the task on, since it could potentially be
      # lower than the minimum in the data we've seen so far.
      if profiling_info[cloud.to_s].nil?
        clouds_to_run_on << cloud
        next
      end

      val = self.average(profiling_info[cloud.to_s][optimize_for])
      if val < min_val
        min_cloud = cloud
        min_val = val
      end
    }

    if !min_cloud.nil?
      clouds_to_run_on << min_cloud
    end

    return clouds_to_run_on
  end


  # Given an Array of values, calculates and returns their average.
  def self.average(vals)
    sum = vals.reduce(0.0) { |running_total, val|
      running_total + val
    }

    return sum / vals.length
  end


  def self.find_optimal_cloud_for_task(job, profiling_info)
    raise NotImplementedError
  end


  def self.generate_babel_tasks(job, clouds_to_run_task_on)
    tasks = []

    clouds_to_run_task_on.each { |cloud|
      task = { :type => "babel",
        :code => job[:code],
        :argv => job[:argv],
        :executable => job[:executable],
        :is_remote => false,
        :run_local => false
      }

      CLOUD_CREDENTIALS[cloud].each { |credential|
        task[credential] = job[:credentials][credential]
      }

      task.merge!(CLOUD_BABEL_PARAMS[cloud])
      tasks << task
    }

    return tasks
  end


  def self.run_job(tasks_to_run)
    return babel(tasks_to_run)
  end


end
