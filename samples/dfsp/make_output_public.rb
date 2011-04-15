
retval = neptune (
  :type => "set-acl",
  :output => "/dfsp-output",
  :acl => "public"
)

puts "hey guy could we change the acl? #{retval}"

