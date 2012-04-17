
output = neptune :type => "output",
  :storage => "s3",
  :output => "/neptune-testbin/hello/output.txt"

puts output.inspect
