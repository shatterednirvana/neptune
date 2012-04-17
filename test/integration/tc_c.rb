
$:.unshift File.join(File.dirname(__FILE__), "..", "..", "lib")
require 'neptune'

$:.unshift File.join(File.dirname(__FILE__), "..", "test", "integration")
require 'test_helper'

require 'test/unit'

class TestC < Test::Unit::TestCase
  # unlike the other language interfaces, we don't run c code yet
  # just compile it - this may change in the future

  def test_c_compile
    ring_code = <<BAZ
#include <stdio.h>

int main() {
  printf("hello world!");
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

    output = TestHelper.get_output_location(folder)

    compile_c_code(tmp_folder, source, compiled)

    FileUtils.rm_rf(tmp_folder)
    FileUtils.rm_rf(compiled)
  end

  def compile_c_code(location, main_file, compiled)
    std_out, std_err = TestHelper.compile_code(location, main_file, compiled)

    make = "gcc -o HelloWorld HelloWorld.c -Wall"
    msg = "The C Hello World code did not compile as expected. It should have " +
      "compiled with the command [#{make}] instead of [#{std_out}]."
    assert(std_out.include?(make), msg)

    msg = "The C Hello World code did not compile successfully. It reported " +
      "the following error: #{std_err}"
    assert_nil(std_err, msg)
  end
end 

