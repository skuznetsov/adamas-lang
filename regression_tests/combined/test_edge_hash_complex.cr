# Edge case: Complex hash operations
# EXPECT: hash_complex_all_ok

# Hash with various operations
h = {} of String => Int32
h["one"] = 1
h["two"] = 2
h["three"] = 3

puts h.size
puts h["one"]
puts h["three"]
puts h.has_key?("two")
puts h.has_key?("four")

# Hash delete and re-insert
h.delete("two")
puts h.size
puts h.has_key?("two")
h["two"] = 22
puts h["two"]

# Hash iteration
total = 0
h.each { |k, v| total += v }
puts total

# Hash with default value
counts = Hash(String, Int32).new(0)
["apple", "banana", "apple", "cherry", "banana", "apple"].each do |fruit|
  counts[fruit] = (counts[fruit]? || 0) + 1
end
puts counts["apple"]
puts counts["banana"]
puts counts["cherry"]

# Hash keys and values
puts h.keys.sort.join(",")
puts h.values.sort.join(",")

# Hash merge via iteration
h2 = {"a" => 10, "b" => 20}
h3 = {"b" => 30, "c" => 40}
merged = {} of String => Int32
h2.each { |k, v| merged[k] = v }
h3.each { |k, v| merged[k] = v }
puts merged["a"]
puts merged["b"]
puts merged["c"]

# Nested hash
registry = {} of String => Hash(String, Int32)
registry["users"] = {"alice" => 1, "bob" => 2}
registry["items"] = {"sword" => 10, "shield" => 5}
puts registry["users"]["alice"]
puts registry["items"]["shield"]

puts "hash_complex_all_ok"
