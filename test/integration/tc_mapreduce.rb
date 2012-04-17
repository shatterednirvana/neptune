
class TestMapReduce < Test::Unit::TestCase
  def test_java_mr_code
    STORAGE_TYPES.each { |storage|
      # TODO: once files api is good in appscale, test this use case
      next if storage == "appdb"
      run_java_mr_code(storage)
    }
  end

  def test_mr_streaming_code
    STORAGE_TYPES.each { |storage|
      run_streaming_code(storage)
    }
  end

  def run_java_mr_code(storage)
    local_input = File.expand_path("~/neptune/samples/mapreduce/the-end-of-time.txt")
    unless File.exists?(local_input)
      abort("missing input corpus - please download it and try again.")
    end
    input = TestHelper.read_file(local_input)

    local_code = File.expand_path("~/neptune/samples/mapreduce/hadoop-0.20.0-examples.jar")
    unless File.exists?(local_code)
      abort("missing hadoop examples jar - please download it and try again.")
    end
    main = "wordcount"

    local_output = File.expand_path("~/neptune/samples/mapreduce/expected-output.txt")
    unless File.exists?(local_output)
      abort("missing expected output - please download it and try again.")
    end
    expected_output = TestHelper.read_file(local_output)

    folder = "wordcount-#{TestHelper.get_random_alphanumeric}"
    tmp_folder = "/tmp/#{folder}"
    FileUtils.mkdir_p(tmp_folder)

    input_name = "input"
    local_input = "#{tmp_folder}/#{input_name}"
    TestHelper.write_file(local_input, input)

    remote_input = TestHelper.get_output_location("#{folder}-input", storage)
    remote_code = TestHelper.get_output_location("#{folder}-code.jar", storage, notxt=true)
    remote_output = TestHelper.get_output_location("#{folder}-output", storage)

    put_file_in_storage(local_input, remote_input, storage)
    put_file_in_storage(local_code, remote_code, storage)

    start_mr_code(remote_input, remote_output, remote_code, main, storage)
    get_mr_output(remote_output, expected_output, storage)
  end


  def start_mr_code(input, output, code, main, storage)
    params = {
      :type => "mapreduce",
      :input  => input,
      :output => output,
      :mapreducejar => code,
      :main => main,
      :nodes_to_use => 1
    }.merge(TestHelper.get_storage_params(storage))

    status = nil

    loop {
      status = neptune(params)
      if status[:msg] =~ /not enough free nodes/
        puts status[:msg]
      else
        break
      end
      sleep(5)
    }

    msg = "Your job was not started successfully. The failure message " +
      "reported was #{status[:msg]}"
    assert_equal(status[:result], :success, msg)
  end

  def run_streaming_code(storage)
    expected_output = "sum x ="
    input = <<BAZ
1	32
33	64
65	96
97	128
BAZ

    map_code = <<BAZ
#!/usr/bin/ruby -w
# Programmer: Chris Bunch
# mapper-ruby.rb: Solves part of the EP parallel benchmark via the 
# MapReduce framework as follows:
# Input: Takes in ranges of k values to compute over STDIN.
# Output: list [l, X_k, Y_k]

A = 5 ** 13
S = 271828183
MIN_VAL = 2 ** -46
MAX_VAL = 2 ** 46

def generate_random(k)
  xk = (A ** k) * S % MAX_VAL
  MIN_VAL * xk
end

def ep(k)
  k = Integer(k)
  
  xj = generate_random(k)
  yj = generate_random(k+1)
  
  t = xj * xj + yj * yj
  
  if t <= 1
    xk = xj * Math.sqrt(-2 * Math.log(t) / t)
    yk = yj * Math.sqrt(-2 * Math.log(t) / t)
    
    max = [xk.abs, yk.abs].max
    l = max.floor
    puts l.to_s + " " + xk.to_s + " " + yk.to_s
  end
end

loop {
  input = STDIN.gets
  break if input.nil?
  start, fin = input.chomp.split
  start = Integer(start)
  fin = Integer(fin)
  current = start
  loop {
    ep(current)
    current = current + 2
    break if current > fin
  }
}

BAZ

    red_code = <<BAZ
#!/usr/bin/ruby -w
# Programmer: Chris Bunch
# reducer-ruby.rb: Solves part of the EP parallel benchmark via the 
# MapReduce framework as follows:
# Input: list [l, X_k, Y_k]
# Output: [l, sum(X_k), sum(Y_k)]

current_l = nil

x_count = 0
y_count = 0

sum_x = 0.0
sum_y = 0.0

loop {
  input = STDIN.gets
  break if input.nil?
  l, x, y = input.chomp.split
  l = Integer(l)
  x = Float(x)
  y = Float(y)
  
  current_l = l if current_l.nil?
  
  if l != current_l
    puts "bucket = " + current_l.to_s + ", |x| = " + x_count.to_s + ", |y| = " + y_count.to_s
    current_l = l
    x_count = 0
    y_count = 0
  end
  
  sum_x = sum_x + x
  sum_y = sum_y + y

  abs_x = x.abs
  abs_y = y.abs

  if abs_x > abs_y
    x_count = x_count + 1
  else
    y_count = y_count + 1 
  end
}

puts "bucket = " + current_l.to_s + ", |x| = " + x_count.to_s + ", |y| = " + y_count.to_s
puts "sum x = " + sum_x.to_s + ", sum y = " + sum_y.to_s

BAZ

    contents = TestHelper.get_random_alphanumeric(1024)
    folder = "ep-#{TestHelper.get_random_alphanumeric}"

    input_name = "input"
    map_source = "map.rb"
    red_source = "reduce.rb"

    tmp_folder = "/tmp/#{folder}"
    FileUtils.mkdir_p(tmp_folder)

    local_input = "#{tmp_folder}/#{input_name}"
    local_map = "#{tmp_folder}/#{map_source}"
    local_red = "#{tmp_folder}/#{red_source}"

    TestHelper.write_file(local_input, input)
    TestHelper.write_file(local_map, map_code)
    TestHelper.write_file(local_red, red_code)

    remote_input = TestHelper.get_output_location("#{folder}-input", storage)
    remote_map = TestHelper.get_output_location("#{folder}-map.rb", storage, notxt=true)
    remote_red = TestHelper.get_output_location("#{folder}-reduce.rb", storage, notxt=true)
    remote_output = TestHelper.get_output_location("#{folder}-output", storage)

    put_file_in_storage(local_input, remote_input, storage)
    put_file_in_storage(local_map, remote_map, storage)
    put_file_in_storage(local_red, remote_red, storage)

    start_mr_streaming_code(remote_input, remote_output, remote_map, remote_red, storage)
    get_mr_output(remote_output, expected_output, storage)

    FileUtils.rm_rf(local_input)
    FileUtils.rm_rf(local_map)
    FileUtils.rm_rf(local_red)
  end

  def put_file_in_storage(local, remote, storage)
    params = {
      :type => "input",
      :local => local,
      :remote => remote
    }.merge(TestHelper.get_storage_params(storage))

    input_result = neptune(params)

    msg = "We were unable to store a file in the database. We " +
      " got back this: #{msg}"
    assert(input_result, msg)
  end

  def start_mr_streaming_code(input, output, map, reduce, storage)
    params = {
      :type => "mapreduce",
      :input  => input,
      :output => output,
      :map => map,
      :reduce => reduce,
      :nodes_to_use => 1
    }.merge(TestHelper.get_storage_params(storage))

    status = nil

    loop {
      status = neptune(params)
      if status[:msg] =~ /not enough free nodes/
        puts status[:msg]
      else
        break
      end
      sleep(5)
    }

    msg = "Your job was not started successfully. The failure message " +
      "reported was #{status[:msg]}"
    assert_equal(status[:result], :success, msg)
  end

  def get_mr_output(output, expected, storage)
    result = TestHelper.get_job_output(output, storage)

    TestHelper.write_file("/tmp/result", result)

    msg = "The MapReduce job you ran did not return the expected result. " +
      "We expected to see [#{expected}] but instead saw [#{result}]"
    success = result.include?(expected)
    assert(success, msg)
  end
end 

