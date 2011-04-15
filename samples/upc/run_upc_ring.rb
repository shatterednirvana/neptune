
output = neptune(
  :type => "mpi",
  #:keyname => "cluster",
  :code => "ring-compiled/Ring",
  :nodes_to_use => 4,
  :procs_to_use => 4,
  :output => "/baz/output"
)

puts "job started? #{output[:result]}"
puts "message = #{output[:msg]}"
