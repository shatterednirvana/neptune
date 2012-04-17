
output = neptune :type => "output",
  :storage => "s3",
  :output => "/neptune-testbin/helloR/output.txt"

puts output.inspect
