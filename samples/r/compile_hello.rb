result = neptune :type => "compile",
  :code => "hello",
  :main => "hello.r",
  :output => "/neptune-testbin/helloR",
  :copy_to => "hello-compiled",
  :storage => "s3"


puts "out = #{result[:out]}"
puts "err = #{result[:err]}"
