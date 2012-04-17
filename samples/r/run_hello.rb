result = neptune(
  :type => :r,
  :output => "/neptune-testbin/helloR/output.txt",
  :code => "/neptune-testbin/helloR/hello.r",
  :storage => "s3"
)

puts result.inspect

