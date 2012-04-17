result = neptune( :type => "input",
 :local => "hello",
 :remote => "/neptune-testbin/helloR",
 :storage => "s3"
)

puts result.inspect

