result = neptune :type => "compile",
  #@keyname = "cluster"
  :code => "helloworld",
  :main => "helloworld.c",
  :output => "/baz",
  :copy_to => "ring-compiled2"
  #:target => "clean"

puts "out = #{result[:out]}"
puts "err = #{result[:err]}"
