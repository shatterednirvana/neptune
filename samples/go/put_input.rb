result = neptune( :type => "input",
 :local => "hello-compiled",
 :remote => "/neptune-testbin/hello",
 :storage => "s3"
)

puts result.inspect

