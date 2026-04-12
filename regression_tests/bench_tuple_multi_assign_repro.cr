# Tuple multi-assign must use IndexGet/tuple layout (not Time::Instant FieldGet path).
# EXPECT: tuple_multi_ok
a, b = {11_i32, 22_i32}
puts a
puts b
puts "tuple_multi_ok"
