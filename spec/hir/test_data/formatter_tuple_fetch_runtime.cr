args = {1.25_f64}
value = args.fetch(0) { 0.0_f64 }
raise "tuple fetch lost its Float64 value" unless value == 1.25_f64

puts "formatter-tuple-fetch-ok"
puts sprintf("%s", "formatter-tuple-string-ok")
