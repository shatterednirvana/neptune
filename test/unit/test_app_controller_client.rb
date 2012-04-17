# Programmer: Chris Bunch (cgb@cs.ucsb.edu)

$:.unshift File.join(File.dirname(__FILE__), "..", "..", "lib")
require 'app_controller_client'

require 'test/unit'

class FakeConnection
  # Since all the methods we're faking take the same arguments and have
  # the same semantics (return true or abort), just cover it all in one place.
  def method_missing(id, *args, &block)
    method_names = ["neptune_start_job", "neptune_put_input"] +
      ["neptune_get_output", "neptune_get_acl", "neptune_set_acl"] +
      ["neptune_compile_code"]

    if method_names.include?(id.to_s)
      job_data = args[0]
      if job_data.include?("OK")
        return true
      else
        return "Error:"
      end
    else
      super
    end
  end
end

class TestAppControllerClient < Test::Unit::TestCase
  def setup
    @client = AppControllerClient.new("localhost", "secret")
    @client.conn = FakeConnection.new()

    @job_data_ok = ["OK"]
    @job_data_err = ["ERR"]
  end

  def test_make_call
    no_timeout = -1
    retry_on_exception = true
    no_retry_on_exception = false

    call_number = 0
    assert_nothing_raised(AppControllerException) {
      @client.make_call(no_timeout, retry_on_exception) {
        call_number += 1
        case call_number
        when 1
          raise Errno::ECONNREFUSED
        when 2
          raise OpenSSL::SSL::SSLError
        when 3
          raise Exception
        else
          0
        end
      }
    }

    assert_raise(AppControllerException) {
      @client.make_call(no_timeout, no_retry_on_exception) {
        raise Errno::ECONNREFUSED
      }
    }

    assert_raise(AppControllerException) {
      @client.make_call(no_timeout, no_retry_on_exception) {
        raise Exception
      }
    }

  end

  # The remaining tests are identical since the implemented methods are all
  # extremely similar - these methods all make a SOAP call and return the
  # result unless it has 'Error:' in it. If it does, it aborts execution.
  def test_start_neptune_job
    assert(@client.start_neptune_job(@job_data_ok))
    assert_raise(AppControllerException) { @client.start_neptune_job(@job_data_err) }
  end

  def test_put_input
    assert(@client.put_input(@job_data_ok))
    assert_raise(AppControllerException) { @client.put_input(@job_data_err) }
  end

  def test_get_output
    assert(@client.get_output(@job_data_ok))
    assert_raise(AppControllerException) { @client.get_output(@job_data_err) }
  end

  def test_get_acl
    assert(@client.get_acl(@job_data_ok))
    assert_raise(AppControllerException) { @client.get_acl(@job_data_err) }
  end

  def test_set_acl
    assert(@client.set_acl(@job_data_ok))
    assert_raise(AppControllerException) { @client.set_acl(@job_data_err) }
  end

  def test_compile_code
    assert(@client.compile_code(@job_data_ok))
    assert_raise(AppControllerException) { @client.compile_code(@job_data_err) }
  end
end
