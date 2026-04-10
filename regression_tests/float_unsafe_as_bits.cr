# Regression: Float64#unsafe_as(UInt64) must preserve the IEEE bit pattern.
#
# Before the LLVM backend fix, same-width float->int unsafe_as casts were
# coerced to fptoui/fptosi, so 236.15_f64.unsafe_as(UInt64) produced 236
# instead of 0x406d84cccccccccd. That broke Ryu-based float formatting and made
# benchmark timing lines print bogus 0.000 values.
#
# EXPECT:
# bits=4642512806033018061
# hex=406d84cccccccccd

value = 236.15_f64
bits = value.unsafe_as(UInt64)

puts "bits=#{bits}"
puts "hex=#{bits.to_s(16)}"
