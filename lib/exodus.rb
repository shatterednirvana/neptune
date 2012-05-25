#!/usr/bin/env ruby
# Programmer: Chris Bunch


require 'custom_exceptions'


# Exodus provides further improvements to Babel. Instead of making users tell
# us what compute, storage, and queue services they want to use (required for
# babel calls), Exodus will automatically handle this for us. Callers need
# to specify what clouds their job can run over, and Exodus will automatically
# select the best cloud for their job and run it there.
def exodus(jobs)
  if jobs.class == Hash
    jobs = [jobs]
  elsif jobs.class == Array
    ExodusHelper.ensure_all_jobs_are_hashes(jobs)
  else
    raise BadConfigurationException.new("jobs was a #{jobs.class}, which is " +
      "not an acceptable class type")
  end

  jobs.each { |job|
    ExodusHelper.ensure_all_params_are_present(job)
  }
end


# This module provides convenience functions for exodus(), to avoid cluttering
# up Object or Kernel's namespace.
module ExodusHelper


  AmazonEC2 = "amazon-ec2"


  GoogleAppEngine = "google-app-engine"

  
  MicrosoftAzure = "microsoft-azure"


  # A list of clouds that users can run tasks on via Exodus.
  SUPPORTED_CLOUDS = [AmazonEC2, GoogleAppEngine, MicrosoftAzure]


  CLOUD_CREDENTIALS = {
    AmazonEC2 => [:EC2_ACCESS_KEY, :EC2_SECRET_KEY],
    GoogleAppEngine => [:appid, :appcfg_cookies, :function],
    MicrosoftAzure => []
  }


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
    end
  end


  # Given a single Exodus job, checks to make sure it has either an Array
  # of Strings or a single String listing the clouds that a given task can
  # run on. Raises a BadConfigurationException if :clouds_to_use is not in
  # the right format.
  def self.convert_clouds_to_use_to_array(job)
    clouds_class = job[:clouds_to_use].class
    if clouds_class == String
      job[:clouds_to_use] = [job[:clouds_to_use]]
    elsif clouds_class == Array
      job[:clouds_to_use].each { |cloud|
        if cloud.class != String
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


  def self.propogate_credentials_from_environment(job)

  end


end
