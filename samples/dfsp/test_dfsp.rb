
start = Time.now
`neptune run_dfsp.np`
`neptune get_dfsp_output.np`
fin = Time.now

puts "time taken = #{fin-start}"

