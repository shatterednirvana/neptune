
neptune :type => "mapreduce",
  :input  => "/input-7",
  :output => "/output",

  :map => "map.rb",
  :reduce => "reduce.rb",

  :nodes_to_use => 4

  #@remove_output = true
  #@copy_input = false

