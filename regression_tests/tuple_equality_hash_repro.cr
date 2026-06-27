a = {"a", "b", 1, false}
b = {"a", "b", 1, false}
c = {"a", "b", 2, false}

puts a == b
puts a == c
puts a.hash == b.hash
puts a.hash == c.hash
