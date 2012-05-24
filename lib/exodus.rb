#!/usr/bin/env ruby
# Programmer: Chris Bunch


require 'custom_exceptions'


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


module ExodusHelper


  SUPPORTED_CLOUDS = %w{amazon-ec2 microsoft-azure google-app-engine}


  def self.ensure_all_jobs_are_hashes(jobs)
    jobs.each { |job|
      if job.class != Hash
        raise BadConfigurationException.new("A job passed to exodus() was " +
          "not a Hash, but was a #{job.class}")
      end
    }
  end


  def self.ensure_all_params_are_present(job)
    if job[:clouds_to_use].nil?
      raise BadConfigurationException.new(":clouds_to_use was not specified")
    else
      self.convert_clouds_to_use_to_array(job)
      self.validate_clouds_to_use(job)
    end
  end


  def self.convert_clouds_to_use_to_array(job)
    if job[:clouds_to_use].class == String
      job[:clouds_to_use] = [job[:clouds_to_use]]
    elsif job[:clouds_to_use].class == Array
      job[:clouds_to_use].each { |cloud|
        if cloud.class != String
          raise BadConfigurationException.new("#{cloud} was not a String, " +
            "but was a #{cloud.class}")
        end
      }
    else

    end
  end


  def self.validate_clouds_to_use(job)
    job[:clouds_to_use].each { |cloud|
      if !SUPPORTED_CLOUDS.include?(cloud)
        raise BadConfigurationException.new("#{cloud} was specified as in " +
          ":clouds_to_use, which is not a supported cloud.")
      end
    }
  end


end
