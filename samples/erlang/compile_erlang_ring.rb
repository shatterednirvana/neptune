result = neptune :type => "compile",
  #@keyname = "cluster"
  :code => "ring",
  :main => "ring.erl",
  :output => "/baz",
  :copy_to => "ring-compiled"
  #:target => "clean"

puts "out = #{result[:out]}"
puts "err = #{result[:err]}"
