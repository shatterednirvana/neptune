# Programmer: Chris Bunch (cgb@cs.ucsb.edu)


$:.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'exodus'


require 'rubygems'
require 'flexmock/test_unit'


class TestExodus < Test::Unit::TestCase


  def setup
    # all sleeps should immediately return
    flexmock(Kernel).should_receive(:sleep).and_return()

    # all shell calls should fail except those okay'ed by tests
    flexmock(CommonFunctions).should_receive(:shell).with("").and_return()

    # assume that appscale is always running for keyname=appscale
    location_file = File.expand_path("~/.appscale/locations-appscale.yaml")
    flexmock(File).should_receive(:exists?).with(location_file).
      and_return(true)

    # set up some dummy data that will get read when we try to read the
    # locations file
    yaml_info = {
      :shadow => "127.0.0.1",
      :secret => "secret"
    }
    flexmock(YAML).should_receive(:load_file).and_return(yaml_info)

    @ec2_credentials = {
      :EC2_ACCESS_KEY => "boo",
      :EC2_SECRET_KEY => "baz",
      :EC2_URL => "http://ec2.url",
      :S3_URL => "http://s3.url",
      :S3_bucket_name => "bazbucket"
    }

    flexmock(FileUtils).should_receive(:mkdir).and_return()
  end


  def test_exodus_job_format_validation
    # calling exodus with something that's not an Array or Hash should fail
    assert_raises(BadConfigurationException) {
      exodus(2)
    }

    # also, if we give exodus an Array, it had better be an array of Hashes
    assert_raises(BadConfigurationException) {
      exodus([2])
    }
  end


  def test_ensure_all_params_are_present
    # calling exodus without specifying :clouds should fail
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({})
    }

    # calling exodus with invalid clouds specified should fail
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :BazCloud,
        :credentials => {}
      })
    }

    # doing the same but with an array should also fail
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => [:BazCloud],
        :credentials => {}
      })
    }

    # giving an array of not strings should fail
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({:clouds_to_use => [1, 2, 3]})
    }

    # giving not a string should fail
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({:clouds_to_use => 1})
    }

    # giving an acceptable cloud but with no credentials should fail
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({:clouds_to_use => :GoogleAppEngine})
    }

    # similarly, specifying credentials in a non-Hash format should fail
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :GoogleAppEngine,
        :credentials => 1
      })
    }

    # if a credential is nil or empty, it should fail
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => {
          :EC2_ACCESS_KEY => nil,
          :EC2_SECRET_KEY => "baz"
        }
      })
    }

    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => {
          :EC2_ACCESS_KEY => "",
          :EC2_SECRET_KEY => "baz"
        }
      })
    }

    # make sure that the user tells us to optimize their task for either
    # performance or cost
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => @ec2_credentials
      })
    }

    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => @ec2_credentials,
        :optimize_for => 2
      })
    }

    # failing to specify files, argv, or executable
    # should fail

    # first, files
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => @ec2_credentials,
        :optimize_for => :cost
      })
    }

    # next, argv
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => @ec2_credentials,
        :optimize_for => :cost,
        :code => "/foo/bar.rb"
      })
    }

    # finally, executable
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => @ec2_credentials,
        :optimize_for => :cost,
        :code => "/foo/bar.rb",
        :argv => []
      })
    }

    # and of course, calling this function the right way should not fail
    assert_nothing_raised(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => @ec2_credentials,
        :optimize_for => :cost,
        :code => "/foo/bar.rb",
        :argv => [],
        :executable => "ruby"
      })
    }

    # similarly, if the credentials were in the user's environment instead
    # of in the job specification, exodus should pull them in for us
    ENV['EC2_ACCESS_KEY'] = "boo"
    ENV['EC2_SECRET_KEY'] = "baz"
    ENV['EC2_URL'] = "http://ec2.url"
    ENV['S3_URL'] = "http://s3.url"
    ENV['S3_bucket_name'] = "bazbucket"
    assert_nothing_raised(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => {
        },
        :optimize_for => :cost,
        :code => "/foo/bar.rb",
        :argv => [],
        :executable => "ruby"
      })
    }
    ENV['EC2_ACCESS_KEY'] = nil
    ENV['EC2_SECRET_KEY'] = nil
    ENV['EC2_URL'] = nil
    ENV['S3_URL'] = nil
    ENV['S3_bucket_name'] = nil
  end


  def test_get_task_info_from_neptune_manager
    # this test sets the expectations for what should happen if
    # we ask the neptune manager for info about a job and it has
    # never seen this job before

    job = {
      :clouds_to_use => :AmazonEC2,
      :credentials => {
        :EC2_ACCESS_KEY => "boo",
        :EC2_SECRET_KEY => "baz"
      },
      :optimize_for => :cost,
      :code => "/foo/bar.rb",
      :argv => [],
      :executable => "ruby"
    }

    # let's say they've never run an exodus job before, so they have
    # no profiling data stored locally
    flexmock(File).should_receive(:exists?).
      with(ExodusHelper::NEPTUNE_DATA_DIR).and_return(false)
    flexmock(FileUtils).should_receive(:mkdir).
      with(ExodusHelper::NEPTUNE_DATA_DIR).and_return()

    # mock out the gathering of profiling info
    profiling_filename = "#{ExodusHelper::NEPTUNE_DATA_DIR}/#{ExodusHelper.get_key_from_job_data(job)}.json"
    flexmock(File).should_receive(:exists?).
      with(profiling_filename).and_return(false)

    # mock out timing the user's code
    flexmock(Time).should_receive(:now).and_return(1.0, 2.0)

    # then mock out exec'ing the user's code
    flexmock(CommonFunctions).should_receive(:shell).
      with("ruby /foo/bar.rb ").and_return("")

    # mock out getting cpuinfo
    flexmock(CommonFunctions).should_receive(:shell).
      with(ExodusHelper::GET_CPU_INFO).and_return("cpu MHz: 666.66")

    # finally, mock out writing the profiling information
    flexmock(File).should_receive(:open).with(profiling_filename, "w+", Proc).
      and_return()

    expected = {
      "total_execution_time" => 1.0,
      "cpu_speed" => 666.66
    }
    actual = ExodusHelper.get_profiling_info(job)
    assert_equal(expected, actual)
  end


  def test_find_fastest_cloud_resources_in_ec2
    job = {
      :clouds_to_use => [:AmazonEC2],
      :credentials => {
        :EC2_ACCESS_KEY => "boo",
        :EC2_SECRET_KEY => "baz",
        :EC2_URL => "http://ec2.url",
        :S3_URL => "http://s3.url",
        :S3_bucket_name => "bazbucket"
      },
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :optimize_for => :performance,
      :num_tasks => 1000
    }

    profiling_info = {
      "total_execution_time" => 1000,  # seconds
      "cpu_speed" => 2000  # MHz
    }

    # if we want to run our tasks as fast as possible
    # (optimize_for => performance), then we should be running it over as many
    # nodes as possible
    actual = ExodusHelper.find_optimal_cloud_resources(job, profiling_info)
    assert_equal(:AmazonEC2, actual[:cloud])
    assert_equal(ExodusHelper::MAX_NODES_IN_EC2, actual[:num_nodes])
    assert_equal("c1.xlarge", actual[:instance_type])
  end


  def test_find_optimal_cloud_resources_in_euca
    job = {
      :clouds_to_use => [:Eucalyptus],
      :credentials => {
        :EUCA_ACCESS_KEY => "boo",
        :EUCA_SECRET_KEY => "baz",
        :EUCA_URL => "http://euca.url",
        :WALRUS_URL => "http://walrus.url",
        :Walrus_bucket_name => "bazbucket"
      },
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :optimize_for => :auto,
      :num_tasks => 1000
    }

    profiling_info = {
      "total_execution_time" => 1000,  # seconds
      "cpu_speed" => 2000  # MHz
    }

    # if we want to run our tasks "optimally" and we're in euca, then the 
    # boxes are considered free - in this case, we should be running it over as
    # many nodes as possible (and thus as fast as possible)
    actual = ExodusHelper.find_optimal_cloud_resources(job, profiling_info)
    assert_equal(:Eucalyptus, actual[:cloud])
    assert_equal(ExodusHelper::MAX_NODES_IN_EUCA, actual[:num_nodes])
    assert_equal("c1.xlarge", actual[:instance_type])
  end


  def test_find_cheapest_cloud_resources_in_euca
    job = {
      :clouds_to_use => [:Eucalyptus],
      :credentials => {
        :EUCA_ACCESS_KEY => "boo",
        :EUCA_SECRET_KEY => "baz",
        :EUCA_URL => "http://euca.url",
        :WALRUS_URL => "http://walrus.url",
        :Walrus_bucket_name => "bazbucket"
      },
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :optimize_for => :cost,
      :num_tasks => 1000
    }

    profiling_info = {
      "total_execution_time" => 1000,  # seconds
      "cpu_speed" => 2000  # MHz
    }

    # if we want to run our tasks as cheaply as possible and we're in euca, 
    # then the boxes are considered free - in this case, all options cost the
    # same and we should be running it over as
    # many nodes as possible (and thus as fast as possible)
    actual = ExodusHelper.find_optimal_cloud_resources(job, profiling_info)
    assert_equal(:Eucalyptus, actual[:cloud])
    assert_equal(ExodusHelper::MAX_NODES_IN_EUCA, actual[:num_nodes])
    assert_equal("c1.xlarge", actual[:instance_type])
 end


 def test_find_cloud_resources_with_max_set
    job = {
      :clouds_to_use => [:AmazonEC2],
      :credentials => {
        :EC2_ACCESS_KEY => "boo",
        :EC2_SECRET_KEY => "baz",
        :EC2_URL => "http://ec2.url",
        :S3_URL => "http://s3.url",
        :S3_bucket_name => "bazbucket"
      },
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :optimize_for => :cost,
      :num_tasks => 1000,
      :max_nodes => 1
    }

    profiling_info = {
      "total_execution_time" => 1000,  # seconds
      "cpu_speed" => 2000  # MHz
    }

    # here, we're saying that no more than one machine should be used,
    # and since we're optimizing for cost, we should expect that the
    # cheapest instance type will be chosen
    actual = ExodusHelper.find_optimal_cloud_resources(job, profiling_info)
    assert_equal(:AmazonEC2, actual[:cloud])
    assert_equal(1, actual[:num_nodes])
  end


  def test_generate_babel_tasks_one_task
    job = {
      :clouds_to_use => [:AmazonEC2, :Eucalyptus, :GoogleAppEngine],
      :credentials => {
        :EUCA_ACCESS_KEY => "boo",
        :EUCA_SECRET_KEY => "baz",
        :EUCA_URL => "http://euca.url",
        :WALRUS_URL => "http://walrus.url",
        :Walrus_bucket_name => "bazbucket"
      },
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :optimize_for => :cost,
      :num_tasks => 2
    }

    optimal_cloud_resources = {
      :cloud => :Eucalyptus
    }

    expected_one_task = {
      :type => "babel",
      :EUCA_ACCESS_KEY => "boo",
      :EUCA_SECRET_KEY => "baz",
      :EUCA_URL => "http://euca.url",
      :WALRUS_URL => "http://walrus.url",
      :Walrus_bucket_name => "bazbucket",
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :is_remote => false,
      :run_local => false,
      :storage => "walrus",
      :engine => "executor-rabbitmq",
      :keyname => "appscale"
    }
    expected = [expected_one_task, expected_one_task]
    actual = ExodusHelper.generate_babel_tasks(job, optimal_cloud_resources)
    assert_equal(expected, actual)
  end


  def test_generate_babel_tasks_many_tasks
    job = {
      :clouds_to_use => [:AmazonEC2, :Eucalyptus, :GoogleAppEngine],
      :credentials => {
        # ec2 credentials
        :EC2_ACCESS_KEY => "boo",
        :EC2_SECRET_KEY => "baz",
        :EC2_URL => "http://ec2.url",
        :S3_URL => "http://s3.url",
        :S3_bucket_name => "bazbucket1",

        # google app engine credentials
        :appid => "bazappid",
        :appcfg_cookies => "~/.appcfg_cookies",
        :function => "bazboo()",
        :GStorage_bucket_name => "bazbucket2"
      },
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :optimize_for => :cost,
      :num_tasks => 1,
      :keyname => "appscale"
    }

    optimal_cloud_resources = {
      :cloud => :AmazonEC2
    }

    ec2_task = {
      :type => "babel",
      :EC2_ACCESS_KEY => "boo",
      :EC2_SECRET_KEY => "baz",
      :EC2_URL => "http://ec2.url",
      :S3_URL => "http://s3.url",
      :S3_bucket_name => "bazbucket1",
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :is_remote => false,
      :run_local => false,
      :storage => "s3",
      :engine => "executor-sqs",
      :keyname => "appscale"
    }   
    
    appengine_task = {
      :type => "babel",
      :appid => "bazappid",
      :appcfg_cookies => "~/.appcfg_cookies",
      :function => "bazboo()",
      :GStorage_bucket_name => "bazbucket2",
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :is_remote => false,
      :run_local => false,
      :storage => "gstorage",
      :engine => "appengine-push-q"
    }

    expected = [ec2_task]
    actual = ExodusHelper.generate_babel_tasks(job, optimal_cloud_resources)
    assert_equal(expected, actual)
  end


  def test_exodus_run_job_with_one_babel_task
    ec2_task = {
      :type => "babel",
      :EC2_ACCESS_KEY => "boo",
      :EC2_SECRET_KEY => "baz",
      :EC2_URL => "http://ec2.url",
      :S3_URL => "http://s3.url",
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :is_remote => false,
      :run_local => false,
      :storage => "s3",
      :engine => "executor-sqs",
      :bucket_name => "bazbucket"
    }
    babel_tasks = [ec2_task]

    # mock out calls to the NeptuneManager
    flexmock(NeptuneManagerClient).new_instances { |instance|
      # let's say that all checks to see if temp files exist tell us that
      # the files don't exist
      instance.should_receive(:does_file_exist?).
        with(/\A\/bazbucket\/babel\/temp-[\w]+\Z/, Hash).
        and_return(false)

      # assume that our code got put in the remote datastore fine
      instance.should_receive(:does_file_exist?).
        with(/\A\/bazbucket\/babel\/foo\/bar.rb\Z/, Hash).
        and_return(true)

      # also, calls to put_input should succeed
      instance.should_receive(:put_input).with(Hash).and_return(true)

      # mock out the call to get_supported_babel_engines and put in
      # SQS and rabbitmq (which is always supported)
      instance.should_receive(:get_supported_babel_engines).with(Hash).
        and_return(["executor-rabbitmq", "executor-sqs"])

      # neptune jobs should start fine
      instance.should_receive(:start_neptune_job).with(Hash).
        and_return("babel job is now running")

      # getting the output of the job should return it the first time
      instance.should_receive(:get_output).with(Hash).
        and_return("task output yay!")
    }

    # mock out filesystem checks
    # we'll say that our code does exist
    flexmock(File).should_receive(:exists?).with("/foo").and_return(true)

    # mock out scp calls - assume they go through with no problems
    flexmock(CommonFunctions).should_receive(:shell).with(/\Ascp/).
      and_return()

    dispatched_tasks = ExodusHelper.run_job(babel_tasks)
    exodus_task = ExodusTaskInfo.new(dispatched_tasks)

    expected = "task output yay!"
    assert_equal(expected, exodus_task.to_s)
  end


  def test_exodus_job_that_generates_two_babel_tasks
    job = {
      :clouds_to_use => :AmazonEC2,
      :credentials => {
        :EC2_ACCESS_KEY => "boo",
        :EC2_SECRET_KEY => "baz",
        :EC2_URL => "http://ec2.url",
        :S3_URL => "http://s3.url",
        :S3_bucket_name => "bazbucket"
      },
      :optimize_for => :cost,
      :code => "/foo/bar.rb",
      :argv => [],
      :executable => "ruby",
      :num_tasks => 2
    }

    # mock out the random generation of output, error, and metadata paths
    # so that we can can put non-random values in there and identify
    # which task is which later
    flexmock(CommonFunctions).should_receive(:get_random_alphanumeric).
      and_return("output1", "error1", "metadata1", "output2", "error2", 
        "metadata2") 

    expected1 = "task output 1 yay!"
    expected2 = "task output 2 yay!"

    # mock out calls to the NeptuneManager
    flexmock(NeptuneManagerClient).new_instances { |instance|
      # let's say that all checks to see if temp files exist tell us that
      # the files don't exist
      instance.should_receive(:does_file_exist?).
        with(/\A\/bazbucket\/babel\/temp-[\w]+\Z/, Hash).
        and_return(false)

      # assume that our code got put in the remote datastore fine
      instance.should_receive(:does_file_exist?).
        with(/\A\/bazbucket\/babel\/foo\/bar.rb\Z/, Hash).
        and_return(true)

      # also, calls to put_input should succeed
      instance.should_receive(:put_input).with(Hash).and_return(true)

      # mock out the call to get_supported_babel_engines and put in
      # SQS and rabbitmq (which is always supported)
      instance.should_receive(:get_supported_babel_engines).with(Hash).
        and_return(["executor-rabbitmq", "executor-sqs"])

      # neptune jobs should start fine
      instance.should_receive(:start_neptune_job).with(Array).
        and_return("babel job is now running")

      # getting the output of the jobs should return it the first time
      instance.should_receive(:get_output).with(on { |job_data|
        if job_data["@output"] =~ /output1\Z/
          true
        else
          false
        end
      }).and_return(expected1)

      instance.should_receive(:get_output).with(on { |job_data|
        if job_data["@output"] =~ /output2\Z/
          true
        else
          false
        end
      }).and_return(expected2)
    }

    # mock out filesystem checks
    # we'll say that our code does exist
    flexmock(File).should_receive(:exists?).with("/foo").and_return(true)

    # let's say that we have a neptune profiling directory
    flexmock(File).should_receive(:exists?).
      with(ExodusHelper::NEPTUNE_DATA_DIR).and_return(true)

    # and let's say that we've never run the job before
    # start by mocking out its filesystem reads
    key = ExodusHelper.get_key_from_job_data(job)
    profiling_key = "#{ExodusHelper::NEPTUNE_DATA_DIR}/#{key}.json"
    flexmock(File).should_receive(:exists?).
      with(profiling_key).and_return(false)

    # mock out timing the user's code
    flexmock(Time).should_receive(:now).and_return(1.0, 2.0)

    # then mock out exec'ing the user's code
    flexmock(CommonFunctions).should_receive(:shell).
      with("ruby /foo/bar.rb ").and_return()

    # mock out getting cpuinfo
    flexmock(CommonFunctions).should_receive(:shell).
      with(ExodusHelper::GET_CPU_INFO).and_return("cpu MHz: 666.66")

    # finally, mock out writing the profiling information
    flexmock(File).should_receive(:open).with(profiling_key, "w+", Proc).
      and_return()

    # mock out scp calls - assume they go through with no problems
    flexmock(CommonFunctions).should_receive(:shell).with(/\Ascp/).
      and_return()

    # first, let's make sure that exodus calls work fine if we give it
    # a Hash, that generates two babel tasks
    actual = exodus(job)
    assert_equal(expected1, actual[0].to_s)
    assert_equal(expected1, actual[0].stdout)

    assert_equal(expected2, actual[1].to_s)
    assert_equal(expected2, actual[1].stdout)
  end


end
