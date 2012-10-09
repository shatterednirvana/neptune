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
    optimal_cloud_resources = ExodusHelper.find_optimal_cloud_resources(job, 
      profiling_info)
    babel_tasks_to_run = ExodusHelper.generate_babel_tasks(job, 
      optimal_cloud_resources)
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

  
  # The speed of a "Compute Unit" for instances in Amazon EC2. This link
  # (http://aws.amazon.com/ec2/instance-types) cites the speed of a Compute
  # Unit at 1.0-1.2 GHz, so take the average for our calculations.
  EC2_COMPUTE_UNIT = 1100  # MHz


  CLOUD_INSTANCE_TYPES = {
    :AmazonEC2 => [

      # Standard Instances
       {
        :name => "m1.small",
        :cpu => 1 * EC2_COMPUTE_UNIT,
        :cores => 1,
        :cost => 0.08
      }, 

      {
        :name => "m1.medium",
        :cpu => 2 * EC2_COMPUTE_UNIT,
        :cores => 1,
        :cost => 0.160
      },

      {
        :name => "m1.large",
        :cpu => 2 * EC2_COMPUTE_UNIT,
        :cores => 2,
        :cost => 0.320
      }, 
      
      {
        :name => "m1.xlarge",
        :cpu => 2 * EC2_COMPUTE_UNIT,
        :cores => 4,
        :cost => 0.640
      }, 
      
      # High-Memory Instances
      {
        :name => "m2.xlarge",
        :cpu => 3.25 * EC2_COMPUTE_UNIT,
        :cores => 2,
        :cost => 0.450
      }, 
      
      {
        :name => "m2.2xlarge",
        :cpu => 3.25 * EC2_COMPUTE_UNIT,
        :cores => 4,
        :cost => 0.900
      }, 
      
      {
        :name => "m2.4xlarge",
        :cpu => 3.25 * EC2_COMPUTE_UNIT,
        :cores => 8,
        :cost => 1.800
      }, 
    
      # High-CPU Instances
      {
        :name => "c1.medium",
        :cpu => 2.5 * EC2_COMPUTE_UNIT,
        :cores => 2,
        :cost => 0.165
      }, 
      
      {
        :name => "c1.xlarge",
        :cpu => 2.5 * EC2_COMPUTE_UNIT,
        :cores => 8,
        :cost => 0.660
      }

      # No Micro or Cluster-Compute Instances for now
    ],

    :Eucalyptus => [
      # Use the default CPU profiles for now. 
      # TODO(cgb): Use euca-describe-availability-zones verbose to get
      # info on the specific cloud we're using.
       {
        :name => "m1.small",
        :cpu => 1 * EC2_COMPUTE_UNIT,
        :cores => 1,
        :cost => 0.000
      }, 

      {
        :name => "m1.large",
        :cpu => 1 * EC2_COMPUTE_UNIT,
        :cores => 2,
        :cost => 0.000
      }, 
      
      {
        :name => "m1.xlarge",
        :cpu => 1 * EC2_COMPUTE_UNIT,
        :cores => 2,
        :cost => 0.000
      }, 
      
      # High-CPU Instances
      {
        :name => "c1.medium",
        :cpu => 1 * EC2_COMPUTE_UNIT,
        :cores => 1,
        :cost => 0.000
      }, 
      
      {
        :name => "c1.xlarge",
        :cpu => 1 * EC2_COMPUTE_UNIT,
        :cores => 4,
        :cost => 0.000
      }

    ]
  }


  # The location on this machine where we can read and write profiling
  # information about jobs.
  NEPTUNE_DATA_DIR = File.expand_path("~/.neptune")


  # The command that we can run to get information about the number and speed
  # of CPUs on this machine.
  GET_CPU_INFO = "cat /proc/cpuinfo"


  OPTIMIZE_FOR_CHOICES = [:performance, :cost, :auto]


  # The number of seconds in one hour, the standard quantum of pricing in
  # Amazon EC2.
  ONE_HOUR = 3600


  # The maximum number of virtual machines that can be acquired in Amazon
  # EC2 with a standard set of AWS credentials.
  MAX_NODES_IN_EC2 = 20


  # The maximum number of virtual machines that can be acquired in Eucalyptus
  # with a standard set of Eucalyptus credentials.
  # TODO(cgb): This value is really cloud specific, and thus not a constant.
  # We should grab it from the underlying cloud via 
  # "euca-describe-availability-zones verbose" (noting that this value varies
  # based on instance type).
  MAX_NODES_IN_EUCA = 10


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

    command = "#{job[:executable]} #{job[:code]} #{job[:argv].join(' ')}"
    start_time = Time.now
    CommonFunctions.shell(command)
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
  
  
  def self.find_optimal_cloud_resources(job, profiling_info)
    min_data = { :aggregate => 1000000 } # a large number

    job[:clouds_to_use].each { |cloud|
      CLOUD_INSTANCE_TYPES[cloud].each { |instance_type|
        optimal_data = self.optimize_for_instance_type(job, profiling_info,
          instance_type, cloud)
        if optimal_data[:aggregate] < min_data[:aggregate]
          min_data = optimal_data
        elsif optimal_data[:aggregate] == min_data[:aggregate]
          # In the case of Eucalyptus, all nodes are free - for these cases,
          # pick whichever dataset gives better performance (likely the one
          # with more nodes).
          if optimal_data[:time] < min_data[:time]
            min_data = optimal_data
          end
        end
      }
    }

    return min_data
  end


  def self.optimize_for_instance_type(job, profiling_info, instance_type, cloud)
    if cloud == :AmazonEC2
      max_nodes_in_cloud = MAX_NODES_IN_EC2
    elsif cloud == :Eucalyptus
      max_nodes_in_cloud = MAX_NODES_IN_EUCA
    else
      raise NotImplementedError
    end

    if job[:max_nodes]
      max_nodes_in_cloud = [job[:max_nodes], max_nodes_in_cloud].min
    end
    num_nodes_possible = (1 .. max_nodes_in_cloud).to_a
    
    time_local = profiling_info["total_execution_time"]
    cpu_local = profiling_info["cpu_speed"]
    time_per_adjusted_cpu = instance_type[:cpu] * time_local / cpu_local

    times = num_nodes_possible.map { |n|
      job[:num_tasks] * time_per_adjusted_cpu / (n * instance_type[:cores])
    }

    costs = []
    times.each_with_index { |n, i|
      costs << self.get_num_hours_for_time(n) * num_nodes_possible[i] * instance_type[:cost]
    }

    if job[:optimize_for] == :performance
      alpha = 1.0
    elsif job[:optimize_for] == :cost
      alpha = 0.0
    elsif job[:optimize_for] == :auto
      alpha = 0.5
    end

    combined_cost = []
    num_nodes_possible.each_with_index { |n, i|
      weighted_time = alpha * times[i]

      if instance_type[:cost].zero?
        smoothing_factor = 1 / 0.00001
      else
        smoothing_factor = 1 / instance_type[:cost]
      end
      weighted_cost = (1.0 - alpha) * costs[i] * smoothing_factor

      total_cost = weighted_time + weighted_cost
      combined_cost << {
        :num_nodes => n,
        :time => times[i],
        :cost => costs[i],
        :aggregate => total_cost,
        :cloud => cloud,
        :instance_type => instance_type[:name]
      }
    }

    min_cost = combined_cost[0]
    combined_cost.each { |cost_info|
      if cost_info[:aggregate] < min_cost[:aggregate]
        min_cost = cost_info
      elsif cost_info[:aggregate] == min_cost[:aggregate]
        if cost_info[:time] < min_cost[:time]
          min_cost = cost_info
        end
      end
    }
    return min_cost
  end


  def self.get_num_hours_for_time(t)
    num_hours = 1

    loop {
      break if t < ONE_HOUR
      t -= ONE_HOUR
      num_hours += 1
    }

    return num_hours
  end


  def self.generate_babel_tasks(job, optimal_cloud_resources)
    tasks = []

    cloud = optimal_cloud_resources[:cloud]
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

    return tasks
  end


  def self.run_job(tasks_to_run)
    return babel(tasks_to_run)
  end


end
