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
      ExodusHelper.ensure_all_params_are_present({:clouds_to_use => "not an acceptable value"})
    }

    # doing the same but with an array should also fail
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => ["not an acceptable value"],
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
        :credentials => {
          :EC2_ACCESS_KEY => "boo",
          :EC2_SECRET_KEY => "baz"
        }
      })
    }

    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => {
          :EC2_ACCESS_KEY => "boo",
          :EC2_SECRET_KEY => "baz"
        },
        :optimize_for => 2
      })
    }

    # failing to specify files, argv, or executable
    # should fail

    # first, files
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => {
          :EC2_ACCESS_KEY => "boo",
          :EC2_SECRET_KEY => "baz"
        },
        :optimize_for => :cost
      })
    }

    # next, argv
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => {
          :EC2_ACCESS_KEY => "boo",
          :EC2_SECRET_KEY => "baz"
        },
        :optimize_for => :cost,
        :code => "/foo/bar.rb"
      })
    }

    # finally, executable
    assert_raises(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => {
          :EC2_ACCESS_KEY => "boo",
          :EC2_SECRET_KEY => "baz"
        },
        :optimize_for => :cost,
        :code => "/foo/bar.rb",
        :argv => []
      })
    }

    # and of course, calling this function the right way should not fail
    assert_nothing_raised(BadConfigurationException) {
      ExodusHelper.ensure_all_params_are_present({
        :clouds_to_use => :AmazonEC2,
        :credentials => {
          :EC2_ACCESS_KEY => "boo",
          :EC2_SECRET_KEY => "baz"
        },
        :optimize_for => :cost,
        :code => "/foo/bar.rb",
        :argv => [],
        :executable => "ruby"
      })
    }
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


end
