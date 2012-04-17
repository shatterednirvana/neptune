
class TestStorage < Test::Unit::TestCase
  def test_acl
    STORAGE_TYPES.each { |storage|
      run_in_acl(storage)
    }
  end

  def test_in_out
    STORAGE_TYPES.each { |storage|
      run_in_out(storage)
    }
  end

  def test_run_in_out_w_env
    STORAGE_TYPES.each { |storage|
      run_in_out_w_env(storage)
    }
  end

  def test_no_creds
    creds = %w{
GSTORAGE_ACCESS_KEY GSTORAGE_SECRET_KEY GSTORAGE_URL 
S3_ACCESS_KEY S3_SECRET_KEY S3_URL 
WALRUS_ACCESS_KEY WALRUS_SECRET_KEY WALRUS_URL
}

    old_creds = {}
    creds.each { |c|
      old_creds[c] = ENV[c]
      ENV[c] = nil
    }

    # try an input job with creds in env but not in job
    # should succeed

    STORAGE_TYPES.each { |storage|
      params = { :storage => storage }
      testhelper = flexmock(TestHelper)
      testhelper.should_receive(:get_storage_params).with(storage).and_return(params)

      no_msg = "Trying to start a storage job and failing to specify " +
        "necessary credentials should not have failed, but it did." +
        " The storage type used was #{storage}."

      msg = "Trying to start a storage job and failing to specify " +
        "necessary credentials should have failed, but it didn't." +
        " The storage type used was #{storage}."

      if storage == "appdb"
        assert_nothing_raised(SystemExit, no_msg) {
          run_in_out(storage)
        }
      else
        assert_raise(SystemExit, msg) {
          run_in_out(storage)
        }
      end
    }

    creds.each { |c|
      ENV[c] = old_creds[c]
    }
  end

  def test_bad_storage
    msg = "Specifying an incorrect storage backend should have thrown an " + 
      "exception, when in fact it did not."
    assert_raise(SystemExit, msg) { run_in_out("blarg_storage") }
  end

  def test_bad_output_location
    output = "baz-boo-for-me-too"

    STORAGE_TYPES.each { |storage|
      end_of_msg = " should have thrown an exception, when in fact it did not." +
        "Here we tested with #{storage} as the storage backend."

      no_slash_msg = "Specifying an output location without a leading slash"

      assert_raise(SystemExit, no_slash_msg + end_of_msg) { 
        TestHelper.get_job_output(output, storage) 
      }

      no_output_msg = "Specifying an output job with a blank output parameter"
      assert_raise(SystemExit, no_output_msg + end_of_msg) {
        TestHelper.get_job_output("", storage)
      }

      nil_output_msg = "Specifying an output job with a nil output" 
      assert_raise(SystemExit, nil_output_msg + end_of_msg) {
        TestHelper.get_job_output(nil, storage)
      }
    }
  end

  def run_in_acl(storage)
    contents = TestHelper.get_random_alphanumeric(1024) + "+&baz"
    suffix = "neptune-testfile-#{TestHelper.get_random_alphanumeric}"
    local = "/tmp/#{suffix}"
    TestHelper.write_file(local, contents)
    remote = TestHelper.get_output_location(suffix, storage)

    in_params = {
      :type => "input",
      :local => local,
      :remote => remote
    }.merge(TestHelper.get_storage_params(storage))

    input_result = neptune(in_params)

    msg = "We were unable to store a file in the datastore. We " +
      " got back this: #{msg}"
    assert(input_result, msg)

    get_params = {
      :type => "get-acl",
      :output => remote
    }.merge(TestHelper.get_storage_params(storage))

    acl = neptune(get_params)

    get_acl_msg1 = "The default ACL should be private, but was [#{acl}] instead."
    assert_equal("private", acl, get_acl_msg1)

    # TODO: set acl is currently broken - once we fix it, we should
    # do the following:

    # set acl to something else
    # verify that it was set correctly

    FileUtils.rm_rf(local)
  end
 
  def run_in_out_w_env(storage)
    creds = %w{
GSTORAGE_ACCESS_KEY GSTORAGE_SECRET_KEY GSTORAGE_URL 
S3_ACCESS_KEY S3_SECRET_KEY S3_URL 
WALRUS_ACCESS_KEY WALRUS_SECRET_KEY WALRUS_URL
}

    old_creds = {}
    creds.each { |c|
      old_creds[c] = ENV[c]
    }

    s3_creds = %w{ EC2_ACCESS_KEY EC2_SECRET_KEY S3_URL }

    needed_creds = TestHelper.get_storage_params(storage)
    puts needed_creds.inspect

    params = { :storage => storage }
    testhelper = flexmock(TestHelper)
    testhelper.should_receive(:get_storage_params).with(storage).and_return(params)

    s3_creds.each { |c|
      ENV[c] = needed_creds[c.to_sym]
    }

    run_in_out(storage)

    s3_creds.each { |c|
      ENV[c] = nil
    }
    
    creds.each { |c|
      ENV[c] = old_creds[c]
    }

    testhelper.flexmock_teardown
  end

  def run_in_out(storage)
    contents = TestHelper.get_random_alphanumeric(1024) + "+&baz"
    suffix = "neptune-testfile-#{TestHelper.get_random_alphanumeric}"
    local = "/tmp/#{suffix}"
    TestHelper.write_file(local, contents)
    
    run_input(local, suffix, storage)
    run_output(contents, suffix, storage)

    FileUtils.rm_rf(local)
  end

  def run_input(local, suffix, storage)
    params = {
      :type => "input",
      :local => local,
      :remote => TestHelper.get_output_location(suffix, storage)
    }.merge(TestHelper.get_storage_params(storage))

    input_result = neptune(params)

    msg = "We were unable to store a file in the database. We " +
      " got back this: #{msg}"
    assert(input_result, msg)
  end

  def run_output(local, suffix, storage)
    output = TestHelper.get_output_location(suffix, storage)
    remote = TestHelper.get_job_output(output, storage)

    msg = "We were unable to verify that the remote file matches the " +
      "local version. The local copy's contents are: " +
      "[#{local}], while the remote copy's contents are [#{remote}]."
    assert_equal(local, remote, msg)
  end
end 

