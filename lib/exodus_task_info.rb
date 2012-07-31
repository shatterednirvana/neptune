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
    loop {
      @babel_tasks.each_with_index { |task, i|
      begin
        Timeout::timeout(2) {
          result = task.send(id, *args, &block)
          return result
        }
      rescue Timeout::Error
        next
      end
      }
    }
  end


end
