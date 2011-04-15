
class TestX10 < Test::Unit::TestCase
  def test_ring_code
    STORAGE_TYPES.each { |storage|
      run_ring_code(storage)
    }
  end

  def run_ring_code(storage)
    expected_output = "All done!"
    ring_code = <<BAZ
import x10.lang.Math;
import x10.util.Timer;

public class Ring {

  static val NUM_MESSAGES = 1;

  // A global datastructure with one integer cell per place
  static A = PlaceLocalHandle.make[Cell[Long]](Dist.makeUnique(), ()=>new Cell[Long](-1));

  public static def send (msg:Long, depth:Int) {
    A()() = msg;
    if (depth==0) return;
    async at (here.next()) send(msg, depth-1);
  }

  public static def main(args:Array[String](1)) {

    val startTime = Timer.milliTime();
    finish send(42L, NUM_MESSAGES * Place.MAX_PLACES);
    val endTime = Timer.milliTime();

    val totalTime = (endTime - startTime) / 1000.0;

    Console.OUT.printf("#{expected_output}");
  }
}

BAZ

    contents = TestHelper.get_random_alphanumeric(1024)
    folder = "ring-#{TestHelper.get_random_alphanumeric}"
    source = "Ring.x10"

    tmp_folder = "/tmp/#{folder}"
    FileUtils.mkdir_p(tmp_folder)
    compiled = "#{tmp_folder}-compiled"
    compiled_code = "#{compiled}/Ring"

    local = "#{tmp_folder}/#{source}"
    TestHelper.write_file(local, ring_code)

    output = TestHelper.get_output_location(folder, storage)

    compile_x10_code(tmp_folder, source, compiled)
    start_x10_code(compiled_code, output, storage)
    get_x10_output(output, expected_output, storage)

    FileUtils.rm_rf(tmp_folder)
    FileUtils.rm_rf(compiled)
  end

  def compile_x10_code(location, main_file, compiled)
    std_out, std_err = TestHelper.compile_code(location, main_file, compiled)

    make = "/usr/local/x10/x10.dist/bin/x10c++ -x10rt mpi -o Ring Ring.x10"
    msg = "The X10 Ring code did not compile as expected. It should have " +
      "compiled with the command [#{make}] instead of [#{std_out}]."
    assert_equal(std_out, make, msg)

    msg = "The X10 Ring code did not compile successfully. It reported " +
      "the following error: #{std_err}"
    compile_success = !std_err.include?("error")
    assert(compile_success, msg)
  end

  def start_x10_code(code_location, output, storage)
    status = TestHelper.start_job("x10", code_location, output, storage)

    msg = "Your job was not started successfully. The failure message " +
      "reported was #{status[:msg]}"
    assert_equal(status[:result], :success, msg)
  end

  def get_x10_output(output, expected, storage)
    result = TestHelper.get_job_output(output, storage)

    msg = "The X10 job you ran did not return the expected result. " +
      "We expected to see [#{expected}] but instead saw [#{result}]"
    assert_equal(result, expected, msg)
  end
end 

