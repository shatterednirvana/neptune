# Programmer: Chris Bunch


# Imports from Ruby's stdlib
require 'thread'  # needed for Mutex


# Imports for RubyGems
require 'rubygems'
require 'json'


# Imports for other Neptune libraries
require 'babel'
require 'custom_exceptions'


# TaskInfo represents the result of a babel call, an object with all the
# information that the user would be interested in relating to their task.
# At the simplest level, this is just the output of their job, but it also
# can includes profiling information (e.g., performance and cost), as well
# as information that may help with debugging (e.g. info about the environment
# we executed the task in).
class TaskInfo


  # A Hash consisting of the parameters that the user passed to babel().
  attr_accessor :job_data


  # Creates a new TaskInfo object, storing the parameters the user gave us to
  # invoke the job for later use. The user can give us a Hash containing the
  # parameters that the job was started with, or a String that is the
  # JSON-dumped version of that data (also obtainable from TaskInfo objects
  # via to_json).
  def initialize(job_data)
    if job_data.class == String
      begin
        job_data = JSON.load(job_data)
      rescue JSON::ParserError
        raise BadConfigurationException.new("job data not JSONable")
      end
    end

    if job_data.class != Hash
      raise BadConfigurationException.new("job data not a Hash, but was a " +
        "#{job_data.class} - #{job_data}")
    end
    @job_data = job_data

    # To prevent us from repeatedly grabbing (potentially) large files over the
    # network repeatedly, we keep a local, cached copy of the task's standard
    # output, error, and metadata - initially empty, but pulled in the first
    # time that the user asks for it. Since we expose this functionality through
    # the accessor methods below, we should not use attr_accessor or attr_reader
    # to directly expose this variables.
    @output = nil
    @error = nil
    @metadata = nil

    # To prevent concurrent threads from pulling in output multiple times, we
    # guard access to remotely grabbing output/error/metadata with this
    # lock.
    @lock = Mutex.new
  end


  # Returns a string with the standard output produced by this Babel task. If
  # the task has not yet completed, this call blocks until it completes.
  def stdout
    if @output.nil?
      @lock.synchronize {
        @output = BabelHelper.wait_and_get_output(@job_data,
          @job_data['@output'])
      }
    end

    return @output
  end


  # Returns a string with the standard error produced by this Babel task. While
  # all jobs should produce standard output, they may not produce standard
  # error, so it is reasonable that this could return an empty string to the
  # user.
  def stderr
    if @error.nil?
      @lock.synchronize {
        @error = BabelHelper.wait_and_get_output(@job_data, @job_data['@error'])
      }
    end

    return @error
  end


  # An alias for stdout.
  def to_s
    return stdout
  end


  # A common operation that users may perform is asking if the task executed
  # successfully, indicated by a return value of zero. This method provides
  # a quick alias for that functionality.
  def success?
    return return_value.zero?
  end


  # Converts this object to JSON, so that it can be written to disk or
  # passed over the network. Since our stdout/stderr/metadata objects
  # are all locally cached, we don't need to write them (and thus can
  # potentially save a lot of space).
  def to_json
    return JSON.dump(@job_data)
  end


  private


  # We store all the task information that isn't standard out or standard err
  # as a JSON-encoded Hash in a metadata file. This function provides easy
  # access to that hash, retrieving it remotely if needed. It's private since
  # we intend for other methods in this class to call it, and not the user
  # directly.
  def metadata
    if @metadata.nil?
      @lock.synchronize {
        info = BabelHelper.wait_and_get_output(@job_data, 
          @job_data['@metadata'])
        @metadata = JSON.load(info)
      }
    end

    return @metadata
  end


  # We would like to be able to directly call .name on anything in the metadata
  # hash for a task. One way to avoid having to add all of these method calls
  # ourselves and keep it in sync with whatever Neptune over AppScale offers
  # is just to use method_missing and automatically respond to anything that
  # is a key in the metadata hash.
  def method_missing(id, *args, &block)
    methods_available = metadata()
    if methods_available[id.to_s].nil?
      super
    else
      return methods_available[id.to_s]
    end
  end


end
