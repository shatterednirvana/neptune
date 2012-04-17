response = neptune :type => :cicero,
                   :nodes_to_use => {"cloud1" => 1},
                   :tasks => 10,
                   :function => "map",
                   :output => "/output/mr/"

puts response.inspect
