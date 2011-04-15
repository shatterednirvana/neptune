result = neptune (
  :type => "compile",
  #:keyname = "cluster",
  :code = "helloworld",
  :output = "/baz",
  :copy_to = "helloworld-compiled"
)

puts "out = #{result[:out]}"
puts "err = #{result[:err]}"
