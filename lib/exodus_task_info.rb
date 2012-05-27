# Programmer: Chris Bunch


require 'task_info'


class ExodusTaskInfo

  
  def initialize(dispatched_babel_tasks)
    @babel_tasks = dispatched_babel_tasks
  end

  
  def to_s
    method_missing(:to_s)
  end


  def method_missing(id, *args, &block)
    @babel_tasks.each { |task|
      return task.send(id, *args, &block)
    }
  end


end
