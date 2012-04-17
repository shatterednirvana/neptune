response = neptune :type => :cicero,
                   :keyname => "booscale2",
                   :nodes_to_use => {"cloud1" => "http://ec2-107-20-95-123.compute-1.amazonaws.com:8080"},
                   :tasks => 100,
                   :function => "dfsp",
                   :output => "/output/mr/"

puts response.inspect
