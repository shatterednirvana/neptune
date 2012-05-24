#!/usr/bin/env ruby
# Programmer: Chris Bunch

def exodus(jobs)
  if jobs.class == Hash
    jobs = [jobs]
  elsif jobs.class == Array
    ExodusHelper.ensure_all_jobs_are_hashes(jobs)
  else
    raise BadConfigurationException.new("jobs was a #{jobs.class}, which is " +
      "not an acceptable class type")
  end
end


module ExodusHelper
  def self.ensure_all_jobs_are_hashes(jobs)
    jobs.each { |job|
      if job.class != Hash
        raise BadConfigurationException.new("A job passed to exodus() was " +
          "not a Hash, but was a #{job.class}")
      end
    }
  end
end
