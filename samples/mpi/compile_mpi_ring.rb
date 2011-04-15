result = neptune :type => "compile",
  #@keyname = "cluster",
  :code => "ring2",
  :main => "Ring.c",
  :output => "/baz",
  #@lang = "x10",
  :copy_to => "ring-compiled"

puts "out = #{result[:out]}"
puts "err = #{result[:err]}"
