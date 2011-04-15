
status = neptune (
  #:keyname => "booscale4",
  :type => "dfsp", 
  :nodes_to_use => 1,
  :output => "/dfsp-output",
  :simulations => 20
)

if status[:result] == :success
  puts "spawned job successfully!"
elsif status[:result] == :failure
  puts "failed to spawn job"
else
  puts "omg result was #{result}"
end

