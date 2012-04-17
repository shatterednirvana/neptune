response = neptune :type => :cicero,
                   :nodes_to_use => {"cloud1" => 1},
                   :tasks => 10,
                   :function => "map",
                   :input1 => "boo1",
                   :output => "/output/mr/",
                   :app => "~/mapreduce-taskq",
                   :appscale_tools => "~/clients/tools/trunk-tools",
                   :app_name => "appscale-benchmark4"

puts response.inspect
