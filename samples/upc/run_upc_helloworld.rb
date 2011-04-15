
output = neptune (
  :type => "mpi",
  #@keyname = "cluster"
  :code => "helloworld-compiled/HelloWorld",
  :nodes_to_use => 4,
  :procs_to_use => 8,
  :output => "/baz/output2"
)

puts "job started? #{output[:result]}"
puts "message = #{output[:msg]}"
