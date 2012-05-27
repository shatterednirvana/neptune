# Programmer: Chris Bunch (cgb@cs.ucsb.edu)


$:.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'exodus'


require 'rubygems'
require 'flexmock/test_unit'


class TestExodus < Test::Unit::TestCase


  def setup
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

    # mock out the SOAP call for get_profiling_info
    no_job_data = {
    }
    flexmock(NeptuneManagerClient).new_instances { |instance|
      instance.should_receive(:get_profiling_info).with(job[:code]).
        and_return(no_job_data)
    }

    profiling_info = ExodusHelper.get_profiling_info(job)
    assert_equal(true, profiling_info.empty?)
  end


  def test_get_clouds_to_run_task_on_with_no_data
    job = {
      :clouds_to_use => [:AmazonEC2, :Eucalyptus],
      :credentials => {
        :EC2_ACCESS_KEY => "boo",
        :EC2_SECRET_KEY => "baz"
      },
      :code => "/foo/bar.rb",
      :argv => [],
      :executable => "ruby"
    }

    # in this entirely hypothetical example, let us assume we have never run
    # our task previously, so we have no data on what its performance and
    # cost characteristics look like
    profiling_info = {
    }

    job[:optimize_for] = :performance
    clouds_to_run_task_on = ExodusHelper.get_clouds_to_run_task_on(job,
      profiling_info)
    assert_equal(job[:clouds_to_use], clouds_to_run_task_on)

    job[:optimize_for] = :cost
    clouds_to_run_task_on = ExodusHelper.get_clouds_to_run_task_on(job,
      profiling_info)
    assert_equal(job[:clouds_to_use], clouds_to_run_task_on)
  end

  def test_get_clouds_to_run_task_on_with_data
    job = {
      :clouds_to_use => [:AmazonEC2, :Eucalyptus],
      :credentials => {
        :EC2_ACCESS_KEY => "boo",
        :EC2_SECRET_KEY => "baz"
      },
      :code => "/foo/bar.rb",
      :argv => [],
      :executable => "ruby"
    }

    # in this entirely hypothetical example, let us assume we have run our
    # task previously on Amazon EC2 and Eucalyptus, and that it runs
    # faster on EC2, but cheaper on Eucalyptus (that is, for free).
    profiling_info = {
      'AmazonEC2' => {
        'performance' => [30.2, 40.6, 35.8, 41.2, 38.9],
        'cost' => [0.40, 0.40, 0.40, 0.40, 0.40]
      },
      'Eucalyptus' => {
        'performance' => [60.0, 65.0, 55.0, 70.3, 63.2],
        'cost' => [0.0, 0.0, 0.0, 0.0, 0.0]
      }
    }

    job[:optimize_for] = :performance
    clouds_to_run_task_on = ExodusHelper.get_clouds_to_run_task_on(job,
      profiling_info)
    assert_equal([:AmazonEC2], clouds_to_run_task_on)

    job[:optimize_for] = :cost
    clouds_to_run_task_on = ExodusHelper.get_clouds_to_run_task_on(job,
      profiling_info)
    assert_equal([:Eucalyptus], clouds_to_run_task_on)
  end


  def test_get_clouds_to_run_task_on_when_profiling_lacks_data
    job = {
      :clouds_to_use => [:AmazonEC2, :Eucalyptus, :GoogleAppEngine],
      :credentials => {
        :EC2_ACCESS_KEY => "boo",
        :EC2_SECRET_KEY => "baz"
      },
      :code => "/foo/bar.rb",
      :argv => [],
      :executable => "ruby"
    }

    # this example is similar to the prior one, but this time, we have data
    # on EC2 and Eucalyptus but not Google App Engine. Here, we expect to
    # run the job on the best one that we're trying to optimize for as well
    # as anywhere we've never run it before (that is, Google App Engine)
    profiling_info = {
      'AmazonEC2' => {
        'performance' => [30.2, 40.6, 35.8, 41.2, 38.9],
        'cost' => [0.40, 0.40, 0.40, 0.40, 0.40]
      },
      'Eucalyptus' => {
        'performance' => [60.0, 65.0, 55.0, 70.3, 63.2],
        'cost' => [0.0, 0.0, 0.0, 0.0, 0.0]
      }
    }

    job[:optimize_for] = :performance
    clouds_to_run_task_on = ExodusHelper.get_clouds_to_run_task_on(job,
      profiling_info)
    assert_equal(true, clouds_to_run_task_on.include?(:AmazonEC2))
    assert_equal(true, clouds_to_run_task_on.include?(:GoogleAppEngine))

    job[:optimize_for] = :cost
    clouds_to_run_task_on = ExodusHelper.get_clouds_to_run_task_on(job,
      profiling_info)
    assert_equal(true, clouds_to_run_task_on.include?(:Eucalyptus))
    assert_equal(true, clouds_to_run_task_on.include?(:GoogleAppEngine))
  end


  def test_generate_babel_tasks_one_task
    job = {
      :clouds_to_use => [:AmazonEC2, :Eucalyptus, :GoogleAppEngine],
      :credentials => {
        :EUCA_ACCESS_KEY => "boo",
        :EUCA_SECRET_KEY => "baz",
        :EUCA_URL => "http://euca.url",
        :WALRUS_URL => "http://walrus.url"
      },
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :optimize_for => :cost
    }

    clouds_to_run_task_on = [:Eucalyptus]

    expected = [{
      :type => "babel",
      :EUCA_ACCESS_KEY => "boo",
      :EUCA_SECRET_KEY => "baz",
      :EUCA_URL => "http://euca.url",
      :WALRUS_URL => "http://walrus.url",
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :is_remote => false,
      :run_local => false,
      :storage => "walrus",
      :engine => "executor-rabbitmq"
    }]
    actual = ExodusHelper.generate_babel_tasks(job, clouds_to_run_task_on)
    assert_equal(expected, actual)
  end


  def test_generate_babel_tasks_many_tasks
    job = {
      :clouds_to_use => [:AmazonEC2, :Eucalyptus, :GoogleAppEngine],
      :credentials => {
        :EC2_ACCESS_KEY => "boo",
        :EC2_SECRET_KEY => "baz",
        :EC2_URL => "http://ec2.url",
        :S3_URL => "http://s3.url",
        :appid => "bazappid",
        :appcfg_cookies => "~/.appcfg_cookies",
        :function => "bazboo()"
      },
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :optimize_for => :cost
    }

    clouds_to_run_task_on = [:AmazonEC2, :GoogleAppEngine]

    ec2_task = {
      :type => "babel",
      :EC2_ACCESS_KEY => "boo",
      :EC2_SECRET_KEY => "baz",
      :EC2_URL => "http://ec2.url",
      :S3_URL => "http://s3.url",
      :appid => "bazappid",
      :appcfg_cookies => "~/.appcfg_cookies",
      :function => "bazboo()",
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :is_remote => false,
      :run_local => false,
      :storage => "s3",
      :engine => "executor-sqs"
    }   
    
    appengine_task = {
      :type => "babel",
      :EC2_ACCESS_KEY => "boo",
      :EC2_SECRET_KEY => "baz",
      :EC2_URL => "http://ec2.url",
      :S3_URL => "http://s3.url",
      :appid => "bazappid",
      :appcfg_cookies => "~/.appcfg_cookies",
      :function => "bazboo()",
      :code => "/foo/bar.rb",
      :argv => [2],
      :executable => "ruby",
      :is_remote => false,
      :run_local => false,
      :storage => "gstorage",
      :engine => "appengine-push-q"
    }

    expected = [ec2_task, appengine_task]
    actual = ExodusHelper.generate_babel_tasks(job, clouds_to_run_task_on)
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


end
