# Programmer: Chris Bunch (cgb@cs.ucsb.edu)

$:.unshift File.join(File.dirname(__FILE__), "..", "..", "lib")
require 'neptune'

require 'test/unit'


class TestNeptune < Test::Unit::TestCase
  def setup
    @commonfunctions = flexmock(CommonFunctions)
    @commonfunctions.should_receive(:scp_to_shadow).and_return()
    @commonfunctions.should_receive(:shell).and_return()

    @file = flexmock(File)
    @file.should_receive(:expand_path).and_return("")

    @fileutils = flexmock(FileUtils)
    @fileutils.should_receive(:rm_f).and_return()

    @kernel = flexmock(Kernel)
    @kernel.should_receive(:puts).and_return()

    @yaml_info = {:load_balancer => "127.0.0.1",
      :shadow => "127.0.0.1",
      :secret => @secret,
      :db_master => "node-1",
      :table => "cassandra",
      :instance_id => "i-FOOBARZ"}

    @yaml = flexmock(YAML)
    @yaml.should_receive(:load_file).and_return(@yaml_info)
  end

  def test_do_preprocessing
    # Try a job that needs preprocessing
    job_data_1 = {"@type" => "ssa", "@trajectories" => 10}
    assert_nothing_raised(BadConfigurationException) { 
      NeptuneHelper.do_preprocessing(job_data_1, nil) 
    }

    # Now try a job that doesn't need it
    job_data_2 = {"@type" => "input"}
    assert_nothing_raised(BadConfigurationException) {
      NeptuneHelper.do_preprocessing(job_data_2, nil)
    }
  end

  def test_preprocess_compile
  end

  def test_preprocess_erlang_errors
    @file.should_receive(:exists?).and_return(false)

    # Try a job where we didn't specify the code
    job_data_1 = {}
    assert_raise(BadConfigurationException) {
      NeptuneHelper.preprocess_erlang(job_data_1, nil)
    }

    # Try a job where the source doesn't exist
    job_data_2 = {"@code" => "NOT-EXISTANT"}
    assert_raise(BadConfigurationException) {
      NeptuneHelper.preprocess_erlang(job_data_2, nil)
    }
  end

  def test_preprocess_erlang_no_errors
    @file.should_receive(:exists?).and_return(true)

    # Now try a job where the source does exist
    job_data_3 = {"@code" => "EXISTS"}
    assert_nothing_raised(BadConfigurationException) {
      NeptuneHelper.preprocess_erlang(job_data_3, nil)
    }
  end

  def test_preprocess_mpi
    # not specifying nodes to use or procs to use should throw an error
    job_data_1 = {"@output" => "baz", "@error" => "boo",
      "@metadata" => "bar"}
    assert_raise(BadConfigurationException) { 
      NeptuneHelper.preprocess_mpi(job_data_1, nil)
    }

    # not specifying procs to use should throw an error
    job_data_2 = job_data_1.merge({"@nodes_to_use" => 4})
    assert_raise(BadConfigurationException) { 
      NeptuneHelper.preprocess_mpi(job_data_2, nil)
    }

    # specifying procs to use == nodes to use should not throw an error
    job_data_3 = job_data_1.merge({"@nodes_to_use" => 4, "@procs_to_use" => 4})
    assert_equal(job_data_3, NeptuneHelper.preprocess_mpi(job_data_3, nil))

    # specifying procs to use < nodes to use should throw an error
    job_data_4 = job_data_1.merge({"@nodes_to_use" => 4, "@procs_to_use" => 1})
    assert_raise(BadConfigurationException) { 
      NeptuneHelper.preprocess_mpi(job_data_4, nil)
    }
 
    # specifying an empty string for argv should be ok
    job_data_5 = job_data_1.merge({"@nodes_to_use" => 4, "@procs_to_use" => 4, "@argv" => ""})
    assert_equal(job_data_5, NeptuneHelper.preprocess_mpi(job_data_5, nil))

    # specifying an empty array for argv should be ok
    job_data_6 = job_data_1.merge({"@nodes_to_use" => 4, "@procs_to_use" => 4, "@argv" => []})
    expected_job_data_6 = job_data_6.dup
    expected_job_data_6["@argv"] = ""
    assert_equal(expected_job_data_6, NeptuneHelper.preprocess_mpi(job_data_6, nil))

    # specifying something that's not a string or array for argv should throw
    # an error
    job_data_7 = job_data_1.merge({"@nodes_to_use" => 4, "@procs_to_use" => 4, "@argv" => 2})
    assert_raise(BadConfigurationException) { 
      NeptuneHelper.preprocess_mpi(job_data_7, nil)
    }

    # specifying a non-empty string for argv should be ok
    job_data_8 = job_data_1.merge({"@nodes_to_use" => 4, "@procs_to_use" => 4, "@argv" => "--file coo"})
    assert_equal(job_data_8, NeptuneHelper.preprocess_mpi(job_data_8, nil))

    # specifying a non-empty array for argv should be ok
    job_data_9 = job_data_1.merge({"@nodes_to_use" => 4, "@procs_to_use" => 4, "@argv" => ["--file", "coo"]})
    expected_job_data_9 = job_data_9.dup
    expected_job_data_9["@argv"] = "--file coo"
    assert_equal(expected_job_data_9, NeptuneHelper.preprocess_mpi(job_data_9, nil))
  end

  def test_preprocess_ssa
    job_data_1 = {}
    assert_raise(BadConfigurationException) {
      NeptuneHelper.preprocess_ssa(job_data_1, nil) 
    }

    job_data_2 = {"@trajectories" => 10}
    assert_equal(job_data_2, NeptuneHelper.preprocess_ssa(job_data_2, nil))

    job_data_3 = {"@simulations" => 10}
    expected_job_data_3 = {"@trajectories" => 10}
    assert_equal(expected_job_data_3, NeptuneHelper.preprocess_ssa(job_data_3, nil))

    job_data_4 = {"@trajectories" => 10, "@simulations" => 10}
    assert_raise(BadConfigurationException) { NeptuneHelper.preprocess_ssa(job_data_4, nil) }
  end

  def test_get_job_data
    params_1 = {:type => :mpi}
    assert_raise(BadConfigurationException) {
      NeptuneHelper.get_job_data(params_1)
    }

    params_2 = {:type => :mpi, :output => "boo"}
    assert_raise(BadConfigurationException) { 
      NeptuneHelper.get_job_data(params_2)
    }

    [:mpi, :upc, :x10].each { |type|
      params_3 = {:type => type, :output => "/boo"}
      expected_job_data_3 = {"@type" => "mpi", "@output" => "/boo",
        "@keyname" => "appscale"}
      assert_equal(expected_job_data_3, NeptuneHelper.get_job_data(params_3))
    }

    params_4 = {:type => "input"}
    expected_job_data_4 = {"@type" => "input", "@keyname" => "appscale"}
    assert_equal(expected_job_data_4, NeptuneHelper.get_job_data(params_4))

    params_5 = {:type => "input", :keyname => "boo"}
    expected_job_data_5 = {"@type" => "input", "@keyname" => "boo"}
    assert_equal(expected_job_data_5, NeptuneHelper.get_job_data(params_5))

    nodes = {"cloud1" => 1, "cloud2" => 1}
    params_6 = {:type => :mpi, :output => "/boo",
      :nodes_to_use => nodes}
    expected_job_data_6 = {"@type" => "mpi", "@output" => "/boo",
      "@keyname" => "appscale", "@nodes_to_use" => nodes.to_a.flatten}
    assert_equal(expected_job_data_6, NeptuneHelper.get_job_data(params_6))
  end

  def test_validate_storage_params
    job_data_1 = {}
    expected_job_data_1 = {"@storage" => "appdb"}
    assert_equal(expected_job_data_1, NeptuneHelper.validate_storage_params(job_data_1))

    job_data_2 = {"@storage" => "a bad value goes here"}
    assert_raise(BadConfigurationException) { 
      NeptuneHelper.validate_storage_params(job_data_2)
    }

    job_data_3 = {"@storage" => "s3"}
    assert_raise(BadConfigurationException) {
      NeptuneHelper.validate_storage_params(job_data_3)
    }

    job_data_4 = {"@storage" => "s3", "@EC2_ACCESS_KEY" => "a",
      "@EC2_SECRET_KEY" => "b", "@S3_URL" => "c"}
    assert_equal(job_data_4, NeptuneHelper.validate_storage_params(job_data_4))

    ENV['EC2_ACCESS_KEY'] = "a"
    ENV['EC2_SECRET_KEY'] = "b"
    ENV['S3_URL'] = "c"

    ["s3", "gstorage", "walrus"].each { |storage|
      job_data_5 = {"@storage" => storage}
      expected_job_data_5 = {"@storage" => "s3", "@EC2_ACCESS_KEY" => "a",
        "@EC2_SECRET_KEY" => "b", "@S3_URL" => "c"}
      assert_equal(expected_job_data_5, NeptuneHelper.validate_storage_params(job_data_5))
    }
  end

  def test_get_input
  end

  def test_wait_for_compilation_to_finish
  end

  def test_compile_code
  end

  def test_run_job_with_errors
    ssh_args = "boo!"
    shadow_ip = "localhost?"
    secret = "abcdefg"

    job_data_1 = {"@type" => "input"}
    assert_raises (BadConfigurationException) { 
      NeptuneHelper.run_job(job_data_1, ssh_args, shadow_ip, secret)
    }

    @file.should_receive(:exists?).and_return(false)
    flexmock(NeptuneManagerClient).new_instances { |instance|
      instance.should_receive(:put_input).and_return(true)
    }

    job_data_1 = {"@type" => "input", "@local" => "NON-EXISTANT"}
    actual_1 = NeptuneHelper.run_job(job_data_1, ssh_args, shadow_ip, secret)
    assert_equal(:failure, actual_1[:result])
  end

  def test_run_job_no_errors
    ssh_args = "boo!"
    shadow_ip = "localhost?"
    secret = "abcdefg"

    flexmock(NeptuneManagerClient).new_instances { |instance|
      instance.should_receive(:put_input).and_return(true)
    }


    @file.should_receive(:exists?).and_return(true)

    job_data_2 = {"@type" => "input", "@local" => "EXISTS"}
    actual_2 = NeptuneHelper.run_job(job_data_2, ssh_args, shadow_ip, secret)
    assert_equal(:success, actual_2[:result])

    # try an output job

    # try a get-acl job

    # try a set-acl job

    # try a compile job

    # try a compute job
  end

  def test_babel_job_validation
    input = "/boo/input.txt"
    output = "/boo/baz.txt"
    error = "/boo/baz-err.txt"
    metadata = "/boo/baz-meta.txt"
    code = "/boo/code.go"
    engine = "appscale-sqs"
    all_engines = [engine]

    @commonfunctions.should_receive(:get_from_yaml).and_return("127.0.0.1")
    @commonfunctions.should_receive(:get_secret_key).and_return("secret")

    flexmock(NeptuneManagerClient).new_instances { |instance|
      instance.should_receive(:start_neptune_job).and_return("babel job is now running")
      instance.should_receive(:get_supported_babel_engines).and_return(all_engines)
      # code exists - output, error, metadata do not - something else does
      instance.should_receive(:does_file_exist?).and_return(true, false, false, false, true)
    }

    # test cases where we don't give all the correct params
    params1 = {:type => :babel}
    assert_raises(BadConfigurationException) { neptune(params1) }

    params2 = {:type => :babel, :output => output}
    assert_raises(BadConfigurationException) { neptune(params2) }

    params3 = {:type => :babel, :output => output, :code => code}
    assert_raises(BadConfigurationException) { neptune(params3) }

    # test a case where we do give all the correct params

    params = {:type => :babel,
              :output => output,
              :error => error,
              :metadata => metadata,
              :code => code,
              :engine => engine,
              :argv => [input]}
    result = neptune(params)
    assert_equal(:success, result[:result])
  end

  def test_babel_where_remote_files_dont_exist
    output = "/boo/baz.txt"
    error = "/boo/baz-err.txt"
    metadata = "/boo/baz-meta.txt"
    code = "/boo/code.go"
    engine = "appscale-sqs"
    all_engines = [engine]

    @commonfunctions.should_receive(:get_from_yaml).and_return("127.0.0.1")
    @commonfunctions.should_receive(:get_secret_key).and_return("secret")

    flexmock(NeptuneManagerClient).new_instances { |instance|
      instance.should_receive(:start_neptune_job).and_return("babel job is now running")
      instance.should_receive(:get_supported_babel_engines).and_return(all_engines)
      instance.should_receive(:does_file_exist?).and_return(false)
    }

    params = {:type => :babel,
      :output => output,
      :error => error,
      :metadata => metadata,
      :code => code,
      :engine => engine}
    assert_raises(FileNotFoundException) { neptune(params) }

  end

  def test_babel_engine_validation
    # TODO(cgb): test a case where we name an unsupported engine - it should fail
  end
end
