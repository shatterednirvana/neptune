response = neptune :type => :cicero,
                   :nodes_to_use => {"cloud1" => "http://appscale-benchmark4.appspot.com"},
                   :tasks => 10,
                   :function => "map",
                   :input1 => "boo1",
                   :output => "/output/mr/"

puts response.inspect
