args = {1.25_f64}
value = args.fetch(0) { 0.0_f64 }
raise "tuple fetch lost its Float64 value" unless value == 1.25_f64

puts "formatter-tuple-fetch-ok"
puts sprintf("%s", "formatter-tuple-string-ok")
puts sprintf("%f", value)
precision = sprintf("%.3f", value)
raise "formatter precision lost its requested width" unless precision == "1.250"
puts "formatter-precision-ok"
