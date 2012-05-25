# Programmer: Chris Bunch (cgb@cs.ucsb.edu)


$:.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'babel'


require 'rubygems'
require 'flexmock/test_unit'


class TestBabel < Test::Unit::TestCase
  def test_babel_mpi_job
    keyname = "appscale"
    file = "/bucket/file.py"
    params = { :type => "mpi",
      :code => file,
      :executable => 'python',
      :procs_to_use => 1,
      :nodes_to_use => 1,
      :storage => "s3",
      :EC2_ACCESS_KEY => "boo",
      :EC2_SECRET_KEY => "baz",
      :S3_URL => "http://baz.com",
      :is_remote => true,
      :keyname => keyname,
      :metadata_info => {'time_to_store_inputs' => 0.0}
    }

    job_data = {}
    params.each { |k, v|
      job_data["@#{k}"] = v
    }

    output = "/bucket/babel/temp-0123456789"
    job_data["@output"] = output
    job_data_no_err = job_data.dup

    error = "/bucket/babel/temp-1111111111"
    job_data["@error"] = error
    job_data_no_metadata = job_data.dup

    metadata = "/bucket/babel/temp-2222222222"
    job_data["@metadata"] = metadata

    run_job_data = job_data.dup
    run_job_data["@engine"] = "executor-sqs"
    run_job_data["@run_local"] = true
    run_job_data["@failed_attempts"] = 0

    run_job_data_second_try = run_job_data.dup
    run_job_data["@failed_attempts"] = 1

    output_job_data = job_data.dup
    output_job_data["@type"] = "output"

    error_job_data = output_job_data.dup
    error_job_data['@output'] = error

    metadata_job_data = output_job_data.dup
    metadata_job_data['@output'] = metadata
    json_metadata = JSON.dump({'command' => 'ls /home/baz', 'return_value' => 0})

    kernel = flexmock(Kernel)
    kernel.should_receive(:puts).and_return()
    kernel.should_receive(:rand).and_return(0,1,2,3,4,5,6,7,8,9,1,1,1,1,1,1,1,1,1,1,2,2,2,2,2,2,2,2,2,2)
    kernel.should_receive(:sleep).and_return()

    flexmock(NeptuneManagerClient).new_instances { |instance|
      instance.should_receive(:does_file_exist?).with(file, job_data).
        and_return(true)
      instance.should_receive(:does_file_exist?).with(output, job_data_no_err).
        and_return(false)
      instance.should_receive(:does_file_exist?).
        with(error, job_data_no_metadata).and_return(false)
      instance.should_receive(:does_file_exist?).with(metadata, job_data).
        and_return(false)

      # So the first time we start the job, let's say that it failed, so that
      # we can make sure that the caller properly catches this and tries again.
      instance.should_receive(:start_neptune_job).with(run_job_data).
        and_return("error")
      instance.should_receive(:start_neptune_job).with(run_job_data_second_try).
        and_return("MPI job is now running")

      instance.should_receive(:get_output).with(output_job_data).
        and_return("output")
      instance.should_receive(:get_output).with(error_job_data).
        and_return("error")
      instance.should_receive(:get_output).with(metadata_job_data).
        and_return(json_metadata)
    }

    commonfunctions = flexmock(CommonFunctions)
    commonfunctions.should_receive(:get_from_yaml).with(keyname, :shadow).
      and_return("127.0.0.1")
    commonfunctions.should_receive(:get_secret_key).with(keyname).
      and_return("secret")

    # Calling either to_s or stdout will return the standard out that the
    # program produced.
    expected = "output"
    actual = babel(params)
    assert_equal(expected, actual.to_s)
    assert_equal(expected, actual.stdout)

    # Calling stderr returns the standard error that we are expecting.
    assert_equal("error", actual.stderr)

    # Calling command returns the command that was remotely exec'ed, hidden in
    # the metadata.
    assert_equal("ls /home/baz", actual.command)

    # Calling success? returns true if the command's return value is zero,
    # also hidden in the metadata
    assert_equal(true, actual.success?)
    
    # We're using method_missing under the hood, so make sure that a method call
    # that doesn't exist fails accordingly
    assert_raise(NoMethodError) { actual.baz }
  end

  def test_bad_babel_params
    job_data_no_code_param = {}
    assert_raise(BadConfigurationException) {
      # Since babel is using futures/promises, the babel invocation won't
      # actually throw the exception to us unless we use the value in any
      # way - so just print it, knowing it will never get to stdout.
      a = babel(job_data_no_code_param)
      Kernel.puts(a)
    }
  end

  def test_generate_output
    # Since output is generated randomly, make it non-random for now.
    commonfunctions = flexmock(CommonFunctions)
    commonfunctions.should_receive(:get_random_alphanumeric).and_return(10)

    job_data_local_code = {"@code" => "boo.rb"}

    # If neither @bucket_name nor the BABEL_BUCKET_NAME env var are specified,
    # this should fail.
    assert_raise(BadConfigurationException) {
      BabelHelper.generate_output_location(job_data_local_code)
    }

    # Now specify the @bucket_name - it should succeed.
    job_data_local_code["@bucket_name"] = "/baz"
    expected_local = "/baz/babel/temp-10"
    actual_local_1 = BabelHelper.generate_output_location(job_data_local_code)
    assert_equal(expected_local, actual_local_1)

    # Specifying the BABEL_BUCKET_NAME environment variable should be OK.
    job_data_local_code["@bucket_name"] = nil
    ENV['BABEL_BUCKET_NAME'] = "/baz"
    actual_local_2 = BabelHelper.generate_output_location(job_data_local_code)
    assert_equal(expected_local, actual_local_2)
    ENV['BABEL_BUCKET_NAME'] = nil

    # Not putting the initial slash on the bucket name should be fine too.
    ENV['BABEL_BUCKET_NAME'] = "baz"
    actual_local_3 = BabelHelper.generate_output_location(job_data_local_code)
    assert_equal(expected_local, actual_local_3)
    ENV['BABEL_BUCKET_NAME'] = nil

    # Finally, if we run a job and specify remote code, that should be used
    # as the bucket.
    job_data_remote_code = {"@code" => "/baz/boo/code.baz", "@storage" => "s3",
      "@is_remote" => true}
    expected_remote = "/baz/babel/temp-10"

    actual_remote = BabelHelper.generate_output_location(job_data_remote_code)
    assert_equal(expected_remote, actual_remote)
  end

  def test_put_code
    job_data = {"@code" => "/baz/boo/code.baz", "@bucket_name" => "/remote"}

    neptune_params = {
      :type => "input",
      :local => "/baz/boo",
      :remote => "/remote/babel/baz/boo",
      :bucket_name => "/remote",
      :code => "/baz/boo/code.baz"
    }

    kernel = flexmock(Kernel)
    kernel.should_receive(:neptune).with(neptune_params)

    expected = "/remote/babel/baz/boo/code.baz"
    actual = BabelHelper.put_code(job_data)
    assert_equal(expected, actual)
  end

  def test_put_inputs
    # If we specify no inputs or no file inputs, we should get back exactly what
    # we give it
    job_data = {"@code" => "/baz/boo/code.baz", "@bucket_name" => "/remote"}
    actual_1 = BabelHelper.put_inputs(job_data)
    assert_equal(job_data, actual_1)

    job_data["@argv"] = ["boo", "baz", "gbaz"]
    actual_2 = BabelHelper.put_inputs(job_data)
    assert_equal(job_data, actual_2)

    # If we specify inputs on the file system, they should be uploaded and 
    # replaced with remote file locations
    neptune_params = {
      :type => "input",
      :local => "/baz",
      :remote => "/remote/babel/baz",
      :bucket_name => "/remote",
      :code => "/baz/boo/code.baz",
      :argv => ["boo", "/baz", "gbaz"]
    }

    kernel = flexmock(Kernel)
    kernel.should_receive(:neptune).with(neptune_params)

    time = flexmock(Time)
    time.should_receive(:now).and_return(0.0)

    job_data["@argv"] = ["boo", "/baz", "gbaz"]
    expected = job_data.dup
    expected["@argv"] = ["boo", "/remote/babel/baz", "gbaz"]
    expected["@metadata_info"] = {"time_to_store_inputs" => 0.0}
    actual_3 = BabelHelper.put_inputs(job_data.dup)
    assert_equal(expected, actual_3)
  end

  def test_run_babel_job
    # Running a job with no @type specified means it should be a Babel job
    job_data = [{
      "@code" => "/baz/boo/code.baz",
      "@argv" => ["boo", "/remote/babel/baz", "gbaz"]
    }]

    neptune_params = {
      :type => "babel",
      :code => "/baz/boo/code.baz",
      :argv => ["boo", "/remote/babel/baz", "gbaz"],
      :run_local => true,
      :engine => "executor-sqs",
      :failed_attempts => 0
    }

    result = { :result => :success }
    kernel = flexmock(Kernel)
    kernel.should_receive(:neptune).with(neptune_params).and_return(result)

    expected = :success
    actual = BabelHelper.run_job(job_data)[:result]
    assert_equal(expected, actual)
  end

  def test_run_mpi_job
    # Running a job with @type specified should preserve the job type
    job_data = [{
      "@type" => "mpi",
      "@code" => "/baz/boo/code.baz",
      "@argv" => ["boo", "/remote/babel/baz", "gbaz"]
    }]

    neptune_params = {
      :type => "mpi",
      :code => "/baz/boo/code.baz",
      :argv => ["boo", "/remote/babel/baz", "gbaz"],
      :run_local => true,
      :engine => "executor-sqs",
      :failed_attempts => 0
    }

    result = { :result => :success }
    kernel = flexmock(Kernel)
    kernel.should_receive(:neptune).with(neptune_params).and_return(result)

    expected = :success
    actual = BabelHelper.run_job(job_data)[:result]
    assert_equal(expected, actual)
  end

  def test_get_output
    job_data = {
      "@output" => "/baz/boo/code.baz"
    }

    neptune_params = {
      :type => "output",
      :output => "/baz/boo/code.baz"
    }

    result1 = { :output => DOES_NOT_EXIST }
    result2 = { :output => "output goes here" }
    kernel = flexmock(Kernel)
    kernel.should_receive(:neptune).with(neptune_params).and_return(result1, result2)
    kernel.should_receive(:sleep).and_return()

    expected = "output goes here"
    actual = BabelHelper.wait_and_get_output(job_data, job_data['@output'])
    assert_equal(expected, actual)
  end

  def test_batch_tasks_operation
    # if we give babel an array of hashes, it should should give us back
    # task information for each of the jobs we asked it to run
    # essentially this saves us the overhead of the repeated SOAP calls
    # to AppScale

    neptune_params = {
      :type => "babel",
      :code => "/baz/boo/code.baz",
      :argv => ["boo", "/remote/babel/baz", "gbaz"],
      :output => "/baz/output",
      :error => "/baz/error",
      :metadata => "/baz/metadata",
      :run_local => true,
      :engine => "executor-sqs",
      :failed_attempts => 0,
      :metadata_info => {'time_to_store_inputs' => 0.0},
      :storage => "appdb",
      :keyname => "appscale"
    }
    tasks = [neptune_params, neptune_params]

    job_data = {}
    neptune_params.each { |k, v|
      job_data["@#{k}"] = v
    }

    # mocks - mock out most of the babel stuff, since we just want to verify
    # the semantics of passing in an array of hashes instead of just a hash
    babelhelper = flexmock(BabelHelper)
    babelhelper.should_receive(:check_output_files).and_return()
    babelhelper.should_receive(:validate_inputs).and_return()
    babelhelper.should_receive(:put_code).and_return()
    babelhelper.should_receive(:put_inputs).and_return()

    # mocks for neptune
    neptunehelper = flexmock(NeptuneHelper)
    neptunehelper.should_receive(:require_file_to_exist).and_return()
    neptunehelper.should_receive(:require_file_to_not_exist).and_return()

    # finally, mock out the libraries that neptune uses
    commonfunctions = flexmock(CommonFunctions)
    commonfunctions.should_receive(:get_from_yaml).with("appscale", :shadow).
      and_return("public_ip")
    commonfunctions.should_receive(:get_from_yaml).with("appscale", :secret, 
      true).and_return("secret")

    appcontroller = flexmock('appcontroller')
    appcontroller.should_receive(:get_supported_babel_engines).with(job_data).
      and_return(["executor-sqs"])
    appcontroller.should_receive(:start_neptune_job).
      and_return("babel job is now running")
    flexmock(NeptuneManagerClient).should_receive(:new).and_return(appcontroller)

    flexmock(TaskInfo).new_instances { |instance|
      instance.should_receive(:stdout).and_return("output")
    }

    expected = ["output", "output"]
    actual = []
    babel(tasks).each { |task|
      actual << task.stdout
    }
    assert_equal(expected, actual)
  end

end
