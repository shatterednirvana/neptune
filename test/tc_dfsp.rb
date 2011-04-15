
class TestDFSP < Test::Unit::TestCase
  def test_dfsp
    STORAGE_TYPES.each { |storage|
      run_dfsp(storage)
    }
  end

  def run_dfsp(storage)
    expected_output = "sim_output"
    contents = TestHelper.get_random_alphanumeric(1024)
    folder = "dfsp-#{TestHelper.get_random_alphanumeric}"
    output = TestHelper.get_output_location(folder, storage)

    start_dfsp_code(output, storage)
    get_dfsp_output(output, expected_output, storage)
 end

 def start_dfsp_code(output, storage)
   params = { :simulations => 10 }
   status = TestHelper.start_job("dfsp", nil, output, storage, params)

   msg = "Your job was not started successfully. The failure message " +
     "reported was #{status[:msg]}"
   assert_equal(status[:result], :success, msg)
  end

  def get_dfsp_output(output, expected, storage)
    result = TestHelper.get_job_output(output, storage)

    msg = "The DFSP job you ran did not return the expected result. " +
      "We expected to see [#{expected}] but instead saw [#{result}]"
    success = result.include?(expected)
    assert(success, msg)
  end
end 

