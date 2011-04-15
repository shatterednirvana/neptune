#!/usr/bin/ruby

require 'app_controller_client'
require 'common_functions'

# Setting verbose to nil here suppresses the otherwise
# excessive SSL cert warning messages that will pollute
# stderr and worry users unnecessarily.
$VERBOSE = nil

#MPI_RUN_JOB_REQUIRED = %w{ input output code filesystem }
#MPI_REQUIRED = %w{ output }
#X10_RUN_JOB_REQUIRED = %w{ input output code filesystem }
#X10_REQUIRED = %w{ output }
#DFSP_RUN_JOB_REQUIRED = %w{ output simulations }
#DFSP_REQUIRED = %w{ output }
#CEWSSA_RUN_JOB_REQUIRED = %w{ output simulations }
#CEWSSA_REQUIRED = %w{ output }
#MR_RUN_JOB_REQUIRED = %w{ }
#MR_REQUIRED = %w{ output }

# A list of Neptune jobs that do not require nodes to be spawned
# up for computation
NO_NODES_NEEDED = ["acl", "input", "output", "compile"]

# A list of Neptune jobs that do not require the output to be
# specified beforehand
NO_OUTPUT_NEEDED = ["input"]

# A list of storage mechanisms that we can use to store and retrieve
# data to for Neptune jobs.
ALLOWED_STORAGE_TYPES = ["appdb", "gstorage", "s3", "walrus"]

# A list of jobs that require some kind of work to be done before
# the actual computation can be performed.
NEED_PREPROCESSING = ["compile", "erlang", "mpi"]

# A set of methods and constants that we've monkey-patched to enable Neptune
# support. In the future, it is likely that the only exposed / monkey-patched
# method should be job, while the others could probably be folded into either
# a Neptune-specific class or into CommonFunctions.
class Object
end

# Certain types of jobs need steps to be taken before they
# can be started (e.g., copying input data or code over).
# This method dispatches the right method to use based
# on the type of the job that the user has asked to run.
def do_preprocessing(job_data)
  job_type = job_data["@type"]
  return unless NEED_PREPROCESSING.include?(job_type)

  preprocess = "preprocess_#{job_type}".to_sym
  send(preprocess, job_data)
end

# This preprocessing method copies over the user's code to the
# Shadow node so that it can be compiled there. A future version
# of this method may also copy over libraries as well.
def preprocess_compile(job_data)
  code = File.expand_path(job_data["@code"])
  unless File.exists?(code)
    abort("The source file #{code} does not exist.")
  end

  suffix = code.split('/')[-1]
  dest = "/tmp/#{suffix}"
  keyname = job_data["@keyname"]
  shadow_ip = CommonFunctions.get_from_yaml(keyname, :shadow)

  ssh_args = "-i ~/.appscale/#{keyname}.key -o StrictHostkeyChecking=no root@#{shadow_ip}"
  remove_dir = "ssh #{ssh_args} 'rm -rf #{dest}' 2>&1"
  #puts remove_dir
  `#{remove_dir}`

  CommonFunctions.scp_to_shadow(code, dest, keyname, is_dir=true)

  job_data["@code"] = dest
end

def preprocess_erlang(job_data)
  source_code = File.expand_path(job_data["@code"])
  unless File.exists?(source_code)
    file_not_found = "The specified code, #{job_data['@code']}," +
      " didn't exist. Please specify one that exists and try again"
    abort(file_not_found)
  end
  dest_code = "/tmp/"

  keyname = job_data["@keyname"]
  CommonFunctions.scp_to_shadow(source_code, dest_code, keyname)
end

# This preprocessing method copies over the user's MPI
# code to the master node in AppScale - this node will
# then copy it to whoever will run the MPI job.
def preprocess_mpi(job_data)
  if job_data["@procs_to_use"]
    p = job_data["@procs_to_use"]
    n = job_data["@nodes_to_use"]
    if p < n
      not_enough_procs = "When specifying both :procs_to_use and :nodes_to_use" +
        ", :procs_to_use must be at least as large as :nodes_to_use. Please " +
        "change this and try again. You specified :procs_to_use = #{p} and" +
        ":nodes_to_use = #{n}."
      abort(not_enough_procs)
    end
  end

  source_code = File.expand_path(job_data["@code"])
  unless File.exists?(source_code)
    file_not_found = "The specified code, #{source_code}," +
      " didn't exist. Please specify one that exists and try again"
    abort(file_not_found)
  end

  unless File.file?(source_code)
    should_be_file = "The specified code, #{source_code}, was not a file - " +
      " it was a directory or symbolic link. Please specify a file and try again."
    abort(should_be_file)
  end

  dest_code = "/tmp/thempicode"

  keyname = job_data["@keyname"]
  puts "Copying over code..."
  CommonFunctions.scp_to_shadow(source_code, dest_code, keyname)
  puts "Done copying code!"
end

# TODO: actually use me!
#def validate_args(list)
#  list.each do |item|
#    val = instance_variable_get("@#{item}".to_sym)
#    abort("FATAL: #{item} was not defined") if val.nil?
#  end
#end

# This method is the heart of Neptune - here, we take
# blocks of code that the user has written and convert them
# into HPC job requests. At a high level, the user can
# request to run a job, retrieve a job's output, or
# modify the access policy (ACL) for the output of a
# job. By default, job data is private, but a Neptune
# job can be used to set it to public later (and
# vice-versa).
def neptune(params)
  puts "Received a request to run a job."
  puts params[:type]

  keyname = params[:keyname] || "appscale"

  shadow_ip = CommonFunctions.get_from_yaml(keyname, :shadow)
  secret = CommonFunctions.get_secret_key(keyname)
  controller = AppControllerClient.new(shadow_ip, secret)
  ssh_key = File.expand_path("~/.appscale/#{keyname}.key")

  job_data = {}
  params.each { |k, v|
    key = "@#{k}"
    job_data[key] = v
  }

  job_data["@job"] = nil
  job_data["@keyname"] = keyname || "appscale"
  type = job_data["@type"]

  if type == "upc" or type == "x10"
    job_data["@type"] = "mpi"
    type = "mpi"
  end

  if job_data["@nodes_to_use"].class == Hash
    job_data["@nodes_to_use"] = job_data["@nodes_to_use"].to_a.flatten
  end

  if !NO_OUTPUT_NEEDED.include?(type)
    if (job_data["@output"].nil? or job_data["@output"] == "")
      abort("Job output must be specified")
    end

    if job_data["@output"][0].chr != "/"
      abort("Job output must begin with a slash ('/')")
    end
  end

  if job_data["@storage"]
    storage = job_data["@storage"]
    unless ALLOWED_STORAGE_TYPES.include?(storage)
      msg = "Supported storage types are #{ALLOWED_STORAGE_TYPES.join(', ')}" +
        " - we do not support #{storage}."
      abort(msg)
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
        unless job_data["@#{item}"]
          if ENV[item]
            puts "Using #{item} from environment"
            job_data["@#{item}"] = ENV[item]
          else
            msg = "When storing data to S3, #{item} must be specified or be in " + 
              "your environment. Please do so and try again."
            abort(msg)
          end
        end
      }
    end
  else
    job_data["@storage"] = "appdb"
  end

  #if job_data["@can_run_on"].class == Range
  #  job_data["@can_run_on"] = job_data["@can_run_on"].to_a
  #elsif job_data["@can_run_on"].class == Fixnum
  #  job_data["@can_run_on"] = [job_data["@can_run_on"]]
  #end

  puts "job data = #{job_data.inspect}"

  do_preprocessing(job_data) 

  ssh_args = "-i ~/.appscale/#{keyname}.key -o StrictHostkeyChecking=no "

  if type == "input"
    # copy file to remote
    # set location
    local_file = File.expand_path(job_data["@local"])
    if !File.exists?(local_file)
      msg = "the file you specified to copy, #{local_file}, doesn't exist." + 
        " Please specify a file that exists and try again."
      abort(msg)
    end

    remote = "/tmp/neptune-input-#{rand(100000)}"
    scp_cmd = "scp #{ssh_args} #{local_file} root@#{shadow_ip}:#{remote}"
    puts scp_cmd
    `#{scp_cmd}`

    job_data["@local"] = remote
    puts "job data = #{job_data.inspect}"
    return controller.put_input(job_data)
  elsif type == "output"
    return controller.get_output(job_data)
  elsif type == "get-acl"
    job_data["@type"] = "acl"
    return controller.get_acl(job_data)
  elsif type == "set-acl"
    job_data["@type"] = "acl"
    return controller.set_acl(job_data)
  elsif type == "compile"
    compiled_location = controller.compile_code(job_data)

    copy_to = job_data["@copy_to"]

    loop {
      ssh_command = "ssh #{ssh_args} root@#{shadow_ip} 'ls #{compiled_location}' 2>&1"
      #puts ssh_command
      result = `#{ssh_command}`
      #puts "result was [#{result}]"
      if result =~ /No such file or directory/
        puts "Still waiting for code to be compiled..."
      else
        puts "compilation complete! Copying compiled code to #{copy_to}"
        break
      end
      sleep(5)
    }

    rm_local = "rm -rf #{copy_to}"
    #puts rm_local
    `#{rm_local}`

    scp_command = "scp -r #{ssh_args} root@#{shadow_ip}:#{compiled_location} #{copy_to} 2>&1"
    puts scp_command
    `#{scp_command}`

    code = job_data["@code"]
    dirs = code.split(/\//)
    remote_dir = "/tmp/" + dirs[-1] 

    ssh_command = "ssh #{ssh_args} root@#{shadow_ip} 'rm -rf #{remote_dir}' 2>&1"
    puts ssh_command
    `#{ssh_command}`

    ssh_command = "ssh #{ssh_args} root@#{shadow_ip} 'rm -rf #{compiled_location}' 2>&1"
    puts ssh_command
    `#{ssh_command}`

    out = File.open("#{copy_to}/compile_out") { |f| f.read.chomp! }
    err = File.open("#{copy_to}/compile_err") { |f| f.read.chomp! }
    return {:out => out, :err => err }
  else
    result = controller.start_neptune_job(job_data)
    if result =~ /job is now running\Z/
      return {:result => :success, :msg => result}
    else
      return {:result => :failure, :msg => result}
    end
  end
end

