result = neptune (
  :type => "compile",
  #:keyname => "cluster",
  :code => "ring",
  :main => "Ring.x10",
  :output => "/baz",
  :copy_to => "ring-compiled"
)

puts "out = #{result[:out]}"
puts "err = #{result[:err]}"

