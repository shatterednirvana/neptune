result = neptune :type => "compile",
  :code => "hello",
  :main => "hello.go",
  :output => "/neptune-testbin/hello",
  :copy_to => "hello-compiled",
  :storage => "s3"


puts "out = #{result[:out]}"
puts "err = #{result[:err]}"
