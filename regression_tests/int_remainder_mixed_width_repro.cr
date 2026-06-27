modulus = 2_305_843_009_213_693_951_i64

puts 1.remainder(modulus)
puts 2.remainder(modulus)
puts Crystal::Hasher.reduce_num(1)
puts Crystal::Hasher.reduce_num(2)
