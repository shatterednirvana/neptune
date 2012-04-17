
class TestDWSSA < Test::Unit::TestCase
  def test_dwssa
    STORAGE_TYPES.each { |storage|
      run_dwssa(storage)
    }
  end

  def run_dwssa(storage)
    expected_output = ""
    contents = TestHelper.get_random_alphanumeric(1024)
    folder = "dwssa-#{TestHelper.get_random_alphanumeric}"
    output = TestHelper.get_output_location(folder, storage)

    start_dwssa_code(output, storage)
    get_dwssa_output(output, expected_output, storage)
 end

  def start_dwssa_code(output, storage)
    params = { :simulations => 10 }
    status = TestHelper.start_job("cewssa", nil, output, storage, params)

    msg = "Your job was not started successfully. The failure message " +
      "reported was #{status[:msg]}"
    assert_equal(status[:result], :success, msg)
  end

  def get_dwssa_output(output, expected, storage)
    result = TestHelper.get_job_output(output, storage)

    msg = "The dwSSA job you ran did not return the expected result. " +
      "We expected to see [#{expected}] but instead saw [#{result}]"
    success = result.include?(expected)
    assert(success, msg)
    sleep(30) # wait for appscale to free up nodes
  end
end 

