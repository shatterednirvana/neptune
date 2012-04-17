
class TestUPC < Test::Unit::TestCase
  def test_hello_world_code
    STORAGE_TYPES.each { |storage|
      run_hello_world_code(storage)
    }
  end

  def run_hello_world_code(storage)
    expected_output = "Hello from thread 0"
    ring_code = <<BAZ
#include <upc_relaxed.h>
#include <stdio.h>

int main() {
  printf("Hello from thread %i/%i", MYTHREAD, THREADS);
  upc_barrier;
  return 0;
}

BAZ

    contents = TestHelper.get_random_alphanumeric(1024)
    folder = "hello-world-#{TestHelper.get_random_alphanumeric}"
    source = "HelloWorld.c"

    tmp_folder = "/tmp/#{folder}"
    FileUtils.mkdir_p(tmp_folder)
    compiled = "#{tmp_folder}-compiled"
    compiled_code = "#{compiled}/HelloWorld"

    local = "#{tmp_folder}/#{source}"
    TestHelper.write_file(local, ring_code)

    output = TestHelper.get_output_location(folder, storage)

    compile_upc_code(tmp_folder, source, compiled)
    start_upc_code(compiled_code, output, storage)
    get_upc_output(output, expected_output, storage)

    FileUtils.rm_rf(tmp_folder)
    FileUtils.rm_rf(compiled)
  end

  def compile_upc_code(location, main_file, compiled)
    std_out, std_err = TestHelper.compile_code(location, main_file, compiled)

    make = "/usr/local/berkeley_upc-2.12.1/upcc --network=mpi -o HelloWorld HelloWorld.c"
    msg = "The UPC code did not compile as expected. It should have " +
      "compiled with the command [#{make}] instead of [#{std_out}]."
    assert_equal(std_out, make, msg)

    msg = "The UPC code did not compile successfully. It reported " +
      "the following error: #{std_err}"
    assert_nil(std_err, msg)
  end

  def start_upc_code(code_location, output, storage)
    status = TestHelper.start_job("upc", code_location, output, storage)

    msg = "Your job was not started successfully. The failure message " +
      "reported was #{status[:msg]}"
    assert_equal(status[:result], :success, msg)
  end

  def get_upc_output(output, expected, storage)
    result = TestHelper.get_job_output(output, storage)

    msg = "The UPC job you ran did not return the expected result. " +
      "We expected to see [#{expected}] but instead saw [#{result}]"
    success = result.include?(expected)
    assert(success, msg)
  end
end 

