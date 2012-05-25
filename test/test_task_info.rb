# Programmer: Chris Bunch (cgb@cs.ucsb.edu)


$:.unshift File.join(File.dirname(__FILE__), "..", "lib")
require 'task_info'


require 'rubygems'
require 'flexmock/test_unit'


class TestTaskInfo < Test::Unit::TestCase


  def test_init
    assert_raises(BadConfigurationException) {
      TaskInfo.new("not a Hash")
    }
  end

  
  def test_to_from_json
    job_data = {'a' => 'b', 'c' => 'd'}
    task = TaskInfo.new(job_data)

    task_as_json = task.to_json
    task_as_task = TaskInfo.new(task_as_json)
    assert_equal(task.job_data, task_as_task.job_data)
  end


end
