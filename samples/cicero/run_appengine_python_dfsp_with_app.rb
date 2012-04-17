response = neptune :type => :cicero,
                   :nodes_to_use => {"cloud1" => 1},
                   :tasks => 10,
                   :function => "dfsp",
                   :output => "/output/mr/",
                   :app => "~/dfsp-taskq",
                   :appscale_tools => "~/clients/tools/trunk-tools",
                   :app_name => "appscale-benchmark0"

puts response.inspect
