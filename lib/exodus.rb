#!/usr/bin/env ruby
# Programmer: Chris Bunch

def exodus(jobs)
  case jobs.class
  when Hash
    jobs = [jobs]
  when Array
    # do nothing
  else
    raise BadConfigurationException.new("jobs was a #{jobs.class}, which is " +
      "not an acceptable class type")
  end

end
