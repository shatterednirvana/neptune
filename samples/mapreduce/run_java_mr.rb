
neptune :type => "mapreduce",
  :keyname => "neptune",
  :input  => "/bigger.txt",
  :output => "/output",

  :mapreducejar => "hadoop-0.20.0-examples.jar",
  :main => "wordcount",

  :nodes_to_use => 4,

  :remove_output => true,
  :copy_input => false

