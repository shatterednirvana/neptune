result = neptune(
  :type => :go,
  :output => "/neptune-testbin/hello/output.txt",
  :code => "/neptune-testbin/hello/hello",
  :storage => "s3"
)

puts result.inspect

