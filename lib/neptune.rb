#!/usr/bin/ruby
# Programmer: Chris Bunch (cgb@cs.ucsb.edu)

require 'common_functions'
require 'custom_exceptions'
require 'neptune_manager_client'


# Setting verbose to nil here suppresses the otherwise
# excessive SSL cert warning messages that will pollute
# stderr and worry users unnecessarily.
$VERBOSE = nil


# A list of all the Neptune job types that we support
ALLOWED_JOB_TYPES = %w{acl cicero compile erlang mpi input output ssa babel upc x10 mapreduce}


# The string to display for disallowed job types.
JOB_TYPE_NOT_ALLOWED = "The job type you specified is not supported."


# A list of Neptune jobs that do not require nodes to be spawned
# up for computation
NO_NODES_NEEDED = ["acl", "input", "output", "compile"]


# A list of Neptune jobs that do not require the output to be
# specified beforehand
NO_OUTPUT_NEEDED = ["input"]


# A list of storage mechanisms that we can use to store and retrieve
# data to for Neptune jobs.
ALLOWED_STORAGE_TYPES = %w{appdb gstorage s3 walrus waz-storage}


# A list of jobs that require some kind of work to be done before
# the actual computation can be performed.
NEED_PREPROCESSING = ["babel", "compile", "erlang", "mpi", "ssa"]


# Since we're monkeypatching Object to add neptune() and babel(), a short
# blurb is necessary here to make rdoc happy.
class Object
end


# Make neptune() public so that babel() can call it
public


# This method is the heart of Neptune - here, we take blocks of code that the
# user has written and convert them into HPC job requests. At a high level, 
# the user can request to run a job, retrieve a job's output, or modify the 
# access policy (ACL) for the output of a job. By default, job data is private,
# but a Neptune job can be used to set it to public later (and vice-versa).
def neptune(jobs)
  # Kernel.puts "Received a request to run a job."
  # Kernel.puts params[:type]
  if jobs.class == Hash
    jobs = [jobs]
  end

  job_data_list = []
  shadow_ip = nil
  ssh_args = ""
  secret = ""
  controller = nil

  jobs.each { |params|
    job_data = NeptuneHelper.get_job_data(params)
    NeptuneHelper.validate_storage_params(job_data)
    # Kernel.puts "job data = #{job_data.inspect}"
    keyname = job_data["@keyname"]

    shadow_ip = CommonFunctions.get_from_yaml(keyname, :shadow)
    secret = CommonFunctions.get_secret_key(keyname)
    ssh_key = File.expand_path("~/.appscale/#{keyname}.key")
    ssh_args = "-i ~/.appscale/#{keyname}.key -o StrictHostkeyChecking=no "

    controller = NeptuneManagerClient.new(shadow_ip, secret)
    NeptuneHelper.do_preprocessing(job_data, controller)
    job_data_list << job_data
  }

  if job_data_list.length == 1
    return NeptuneHelper.run_job(job_data_list[0], ssh_args, shadow_ip, 
      secret)
  else  # right now we only support batch run_job operations
    msg = controller.start_neptune_job(job_data_list)
    result = {}
    result[:msg] = msg
    if result[:msg] =~ /job is now running\Z/
      result[:result] = :success
    else
      result[:result] = :failure
    end

    return result
  end
end


# NeptuneHelper provides methods that are used by neptune() and babel() to 
# validate parameters and run the user's job.
module NeptuneHelper


  # Certain types of jobs need steps to be taken before they
  # can be started (e.g., copying input data or code over).
  # This method dispatches the right method to use based
  # on the type of the job that the user has asked to run.
  def self.do_preprocessing(job_data, controller)
    job_type = job_data["@type"]
    if !NEED_PREPROCESSING.include?(job_type)
      return
    end

    # Don't worry about adding on the self. prefix - send will resolve
    # it the right way
    preprocess = "preprocess_#{job_type}".to_sym
    send(preprocess, job_data, controller)
  end


  # This preprocessing method copies over the user's code to the
  # Shadow node so that it can be compiled there. A future version
  # of this method may also copy over libraries as well.
  def self.preprocess_compile(job_data, controller)
    code = File.expand_path(job_data["@code"])
    if !File.exists?(code)
      raise BadConfigurationException.new("The source file #{code} does not exist.")
    end

    suffix = code.split('/')[-1]
    dest = "/tmp/#{suffix}"
    keyname = job_data["@keyname"]
    shadow_ip = CommonFunctions.get_from_yaml(keyname, :shadow)

    ssh_args = "-i ~/.appscale/#{keyname}.key -o StrictHostkeyChecking=no root@#{shadow_ip}"
    remove_dir = "ssh #{ssh_args} 'rm -rf #{dest}' 2>&1"
    # Kernel.puts remove_dir
    CommonFunctions.shell(remove_dir)
    CommonFunctions.scp_to_shadow(code, dest, keyname, is_dir=true)

    job_data["@code"] = dest
  end


  # This preprocessing method makes sure that the user's Erlang code exists
  # and copies it over to the AppScale Shadow node.
  def self.preprocess_erlang(job_data, controller)
    self.require_param("@code", job_data)

    source_code = File.expand_path(job_data["@code"])
    if !File.exists?(source_code)
      raise BadConfigurationException.new("The specified code, #{job_data['@code']}," +
        " didn't exist. Please specify one that exists and try again")
    end
    dest_code = "/tmp/"

    keyname = job_data["@keyname"]
    CommonFunctions.scp_to_shadow(source_code, dest_code, keyname)
  end


  # This preprocessing method verifies that the user specified the number of nodes
  # to use. If they also specified the number of processes to use, we also verify
  # that this value is at least as many as the number of nodes (that is, nodes
  # can't be underprovisioned in MPI).
  def self.preprocess_mpi(job_data, controller)
    self.require_param("@nodes_to_use", job_data)
    self.require_param("@procs_to_use", job_data)
    self.require_param("@output", job_data)
    self.require_param("@error", job_data)
    self.require_param("@metadata", job_data)

    if job_data["@procs_to_use"]
      p = job_data["@procs_to_use"]
      n = job_data["@nodes_to_use"]
      if p < n
        raise BadConfigurationException.new(":procs_to_use must be at least as " +
          "large as :nodes_to_use.") 
      end
    end

    if job_data["@argv"]
      argv = job_data["@argv"]

      if argv.class == String
        job_data["@argv"] = argv
      elsif argv.class == Array
        job_data["@argv"] = argv.join(' ')
      else
        raise BadConfigurationException.new(":argv must be either a String or Array") 
      end
    end

    return job_data
  end


  # This preprocessing method verifies that the user specified the number of
  # trajectories to run, via either :trajectories or :simulations. Both should
  # not be specified - only one or the other, and regardless of which they
  # specify, convert it to be :trajectories.
  def self.preprocess_ssa(job_data, controller)
    if job_data["@simulations"] and job_data["@trajectories"]
      raise BadConfigurationException.new(":simulations and :trajectories " +
        "not both be specified.")
    end

    if job_data["@simulations"]
      job_data["@trajectories"] = job_data["@simulations"]
      job_data.delete("@simulations")
    end

    self.require_param("@trajectories", job_data)
    return job_data
  end


  # This helper method aborts if the given parameter is not present in the
  # job data provided.
  def self.require_param(param, job_data)
    if !job_data[param]
      raise BadConfigurationException.new("#{param} must be specified")
    end
  end


  # This helper method asks the NeptuneManager if the named file exists,
  # and if it does not, throws an exception.
  def self.require_file_to_exist(file, job_data, controller)
    if controller.does_file_exist?(file, job_data)
      return
    else
      raise FileNotFoundException.new("Expecting file #{file} to exist " +
        "in the remote datastore, which did not exist.")
    end
  end


  # This helper method performs the opposite function of require_file_to_exist,
  # raising an exception if the named file does exist.
  def self.require_file_to_not_exist(file, job_data, controller)
    begin
      self.require_file_to_exist(file, job_data, controller)
      # no exception thrown previously means that the output file exists
      raise BadConfigurationException.new('Output specified already exists')
    rescue FileNotFoundException
      return
    end
  end


  # This preprocessing method verifies that the user specified code that
  # should be run, where the output should be placed, and an engine to run over.
  # It also verifies that all files to be used are actually reachable.
  # Supported engines can be found by contacting an AppScale node.
  def self.preprocess_babel(job_data, controller)
    self.require_param("@code", job_data)
    self.require_param("@engine", job_data)
    self.require_param("@output", job_data)
    self.require_param("@error", job_data)
    self.require_param("@metadata", job_data)

    # For most code types, the file's name given is the thing to exec.
    # For Java, the actual file to search for is whatever the user gives
    # us, with a .class extension.
    code_file_name = job_data["@code"]
    if !job_data["@executable"].nil? and job_data["@executable"] == "java"
      code_file_name += ".class"
    end

    self.require_file_to_exist(code_file_name, job_data, controller)
    self.require_file_to_not_exist(job_data["@output"], job_data, controller)
    self.require_file_to_not_exist(job_data["@error"], job_data, controller)
    self.require_file_to_not_exist(job_data["@metadata"], job_data, controller)

    if job_data["@argv"]
      argv = job_data["@argv"]
      if argv.class != Array
        raise BadConfigurationException.new("argv must be an array")
      end

      argv.each { |arg|
        if arg =~ /\/.*\/.*/
          self.require_file_to_exist(arg, job_data, controller)
        end
      }
    end

    if job_data["@appcfg_cookies"]
      self.require_file_to_exist(job_data["@appcfg_cookies"], job_data, controller)
    end

    user_specified_engine = job_data["@engine"]

    # validate the engine here
    engines = controller.get_supported_babel_engines(job_data)
    if !engines.include?(user_specified_engine)
      raise BadConfigurationException.new("The engine you specified, " +
        "#{user_specified_engine}, is not a supported engine. Supported engines" +
        " are: #{engines.join(', ')}")
    end
  end


  # This method takes in a hash in the format that users write neptune/babel
  # jobs in {:a => "b"} and converts it to the legacy format that Neptune
  # used to use {"@a" => "b"}, and is understood by the NeptuneManager.
  def self.get_job_data(params)
    job_data = {}
    params.each { |k, v|
      key = "@#{k}"
      job_data[key] = v
    }

    job_data.delete("@job")
    job_data["@keyname"] = params[:keyname] || "appscale"

    job_data["@type"] = job_data["@type"].to_s
    type = job_data["@type"]

    if !ALLOWED_JOB_TYPES.include?(type)
      raise BadConfigurationException.new(JOB_TYPE_NOT_ALLOWED)
    end

    if type == "upc" or type == "x10"
      job_data["@type"] = "mpi"
      type = "mpi"
    end

    # kdt jobs also run as mpi jobs, but need to pass along an executable
    # parameter to let mpiexec know to use python to exec it
    if type == "kdt"
      job_data["@type"] = "mpi"
      type = "mpi"

      job_data["@executable"] = "python"
    end

    if job_data["@nodes_to_use"].class == Hash
      job_data["@nodes_to_use"] = job_data["@nodes_to_use"].to_a.flatten
    end

    if !NO_OUTPUT_NEEDED.include?(type)
      if (job_data["@output"].nil? or job_data["@output"].empty?)
        raise BadConfigurationException.new("Job output must be specified")
      end

      if job_data["@output"][0].chr != "/"
        raise BadConfigurationException.new("Job output must begin with a slash ('/')")
      end
    end

    return job_data
  end


  # This method looks through the given job data and makes sure that the correct
  # parameters are present for the storage mechanism specified. It throws an
  # exception if there are errors in the job data or if a needed parameter is
  # missing.
  def self.validate_storage_params(job_data)
    job_data["@storage"] ||= "appdb"

    storage = job_data["@storage"]
    if !ALLOWED_STORAGE_TYPES.include?(storage)
      raise BadConfigurationException.new("Supported storage types are " +
        "#{ALLOWED_STORAGE_TYPES.join(', ')} - #{storage} is not supported.")
    end

    # Our implementation for storing / retrieving via Google Storage
    # and Walrus uses
    # the same library as we do for S3 - so just tell it that it's S3
    if storage == "gstorage" or storage == "walrus"
      storage = "s3"
      job_data["@storage"] = "s3"
    end

    if storage == "s3"
      ["EC2_ACCESS_KEY", "EC2_SECRET_KEY", "S3_URL"].each { |item|
        if job_data["@#{item}"]
          # Kernel.puts "Using specified #{item}"
        else
          if ENV[item]
            # Kernel.puts "Using #{item} from environment"
            job_data["@#{item}"] = ENV[item]
          else
            raise BadConfigurationException.new("When storing data to S3, #{item} must be specified or be in " + 
              "your environment. Please do so and try again.")
          end
        end
      }
    end

    return job_data
  end


  # This method takes a file on the local user's computer and stores it remotely
  # via AppScale. It returns a hash map indicating whether or not the job
  # succeeded and if it failed, the reason for it.
  def self.get_input(job_data, ssh_args, shadow_ip, controller)
    result = {:result => :success}

    self.require_param("@local", job_data)

    local_file = File.expand_path(job_data["@local"])
    if !File.exists?(local_file)
      reason = "the file you specified to copy, #{local_file}, doesn't exist." + 
          " Please specify a file that exists and try again."
      return {:result => :failure, :reason => reason}  
    end

    remote = "/tmp/neptune-input-#{rand(100000)}"
    scp_cmd = "scp -r #{ssh_args} #{local_file} root@#{shadow_ip}:#{remote}"
    # Kernel.puts scp_cmd
    CommonFunctions.shell(scp_cmd)

    job_data["@local"] = remote
    # Kernel.puts "job data = #{job_data.inspect}"
    response = controller.put_input(job_data)
    if response
      return {:result => :success}
    else
      # TODO - expand this to include the reason why it failed
      return {:result => :failure}
    end
  end


  # This method waits for AppScale to finish compiling the user's code, indicated
  # by AppScale copying the finished code to a pre-determined location.
  def self.wait_for_compilation_to_finish(ssh_args, shadow_ip, compiled_location)
    loop {
      ssh_command = "ssh #{ssh_args} root@#{shadow_ip} 'ls #{compiled_location}' 2>&1"
      # Kernel.puts ssh_command
      ssh_result = CommonFunctions.shell(ssh_command)
      # Kernel.puts "result was [#{ssh_result}]"
      if ssh_result =~ /No such file or directory/
        # Kernel.puts "Still waiting for code to be compiled..."
      else
        # Kernel.puts "compilation complete! Copying compiled code to #{copy_to}"
        return
      end
      sleep(5)
    }
  end


  # This method sends out a request to compile code, waits for it to finish, and
  # gets the standard out and error returned from the compilation. This method
  # returns a hash containing the standard out, error, and a result that indicates
  # whether or not the compilation was successful.
  def self.compile_code(job_data, ssh_args, shadow_ip)
    compiled_location = controller.compile_code(job_data)
    copy_to = job_data["@copy_to"]
    self.wait_for_compilation_to_finish(ssh_args, shadow_ip, compiled_location)

    FileUtils.rm_rf(copy_to)

    scp_command = "scp -r #{ssh_args} root@#{shadow_ip}:#{compiled_location} #{copy_to} 2>&1"
    # Kernel.puts scp_command
    CommonFunctions.shell(scp_command)

    code = job_data["@code"]
    dirs = code.split(/\//)
    remote_dir = "/tmp/" + dirs[-1] 

    [remote_dir, compiled_location].each { |remote_files|
      ssh_command = "ssh #{ssh_args} root@#{shadow_ip} 'rm -rf #{remote_files}' 2>&1"
      # Kernel.puts ssh_command
      CommonFunctions.shell(ssh_command)
    }

    return get_std_out_and_err(copy_to)
  end


  # This method returns a hash containing the standard out and standard error
  # from a completed job, as well as a result field that indicates whether or
  # not the job completed successfully (success = no errors).
  def self.get_std_out_and_err(location)
    result = {}

    out = File.open("#{location}/compile_out") { |f| f.read.chomp! }
    result[:out] = out

    err = File.open("#{location}/compile_err") { |f| f.read.chomp! }
    result[:err] = err

    if result[:err]
      result[:result] = :failure
    else
      result[:result] = :success
    end    

    return result
  end


  # This method uploads a Google App Engine application into AppScale, for use
  # with Cicero jobs. It requires the AppScale tools to be installed.
  def self.upload_app_for_cicero(job_data)
    if !job_data["@app"]
      # Kernel.puts "No app specified, not uploading..." 
      return
    end

    app_location = File.expand_path(job_data["@app"])
    if !File.exists?(app_location)
      raise BadConfigurationException.new("The app you specified, #{app_location}, does not exist." + 
        "Please specify one that does and try again.")
    end

    keyname = job_data["@keyname"] || "appscale"
    if job_data["@appscale_tools"]
      upload_app = File.expand_path(job_data["@appscale_tools"]) +
        File::SEPARATOR + "bin" + File::SEPARATOR + "appscale-upload-app"
    else
      upload_app = "appscale-upload-app"
    end

    # Kernel.puts "Uploading AppEngine app at #{app_location}"
    upload_command = "#{upload_app} --file #{app_location} --test --keyname #{keyname}"
    # Kernel.puts upload_command
    # Kernel.puts `#{upload_command}`
  end


  # This method actually runs the Neptune job, given information about the job
  # as well as information about the node to send the request to.
  def self.run_job(job_data, ssh_args, shadow_ip, secret)
    controller = NeptuneManagerClient.new(shadow_ip, secret)

    # TODO - right now the job is assumed to succeed in many cases
    # need to investigate the various failure scenarios
    result = { :result => :success }

    case job_data["@type"]
    when "input"
      result = self.get_input(job_data, ssh_args, shadow_ip, controller)
    when "output"
      result[:output] = controller.get_output(job_data)
    when "get-acl"
      job_data["@type"] = "acl"
      result[:acl] = controller.get_acl(job_data)
    when "set-acl"
      job_data["@type"] = "acl"
      result[:acl] = controller.set_acl(job_data)
    when "compile"
      result = self.compile_code(job_data, ssh_args, shadow_ip)
    when "cicero"
      self.upload_app_for_cicero(job_data)
      msg = controller.start_neptune_job(job_data)
      result[:msg] = msg
      result[:result] = :failure if result[:msg] !~ /job is now running\Z/
    else
      msg = controller.start_neptune_job(job_data)
      result[:msg] = msg
      result[:result] = :failure if result[:msg] !~ /job is now running\Z/
    end

    return result
  end
end
