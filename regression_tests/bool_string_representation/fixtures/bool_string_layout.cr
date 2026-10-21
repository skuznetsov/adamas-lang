lib OracleC
  fun exit(code : Int32) : NoReturn
end

true_value = true
false_value = false
truth = true_value.to_s
falsity = false_value.to_s

# Baseline discriminator: the unpatched no-prelude backend returns a raw C
# string here, and the first content comparison must fail with status 11.
OracleC.exit(11) unless truth == "true"
OracleC.exit(12) unless falsity == "false"
OracleC.exit(13) unless truth.size == 4
OracleC.exit(14) unless falsity.size == 5

interpolated = "#{truth}/#{falsity}"
OracleC.exit(17) unless interpolated == "true/false"

# Exercise both raw direct Bool writers and String consumers on the converted
# values. The converted values were computed from Bool variables above.
print(true)
print(false)
puts(true)
puts(false)
puts(truth)
puts(falsity)
puts(interpolated)
