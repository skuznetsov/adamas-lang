# Combined batch bundle (mechanical concat, byte-equality verified).
# Members: test_array_simple test_hash_simple test_flat_map hash_compaction hash_stress
# EXPECT: test_batch_collections_all_ok

# ===== test_array_simple =====
arr = [10, 20, 30]
puts arr.size
puts arr[0]
puts arr[1]
puts arr[2]
arr << 40
puts arr.size
puts arr.includes?(20)
puts arr.includes?(99)
puts "array_simple_done"

# ===== test_hash_simple =====
h = {"a" => 1, "b" => 2}
puts h["a"]
puts h.size
puts "hash_simple_done"

# ===== test_flat_map =====
# Test flat_map with nested arrays (exercises union yield through block-to-proc)
nested = [[1, 2], [3, 4], [5]]
flat = nested.flat_map { |a| a }

if flat.size == 5
  puts "PASS: flat_map size"
else
  puts "FAIL: flat_map size expected 5 got #{flat.size}"
end

if flat == [1, 2, 3, 4, 5]
  puts "PASS: flat_map values"
else
  puts "FAIL: flat_map values"
end

# flat_map with transform
result = [1, 2, 3].flat_map { |x| [x, x * 10] }
if result.size == 6
  puts "PASS: flat_map transform size"
else
  puts "FAIL: flat_map transform size expected 6 got #{result.size}"
end

# ===== hash_compaction =====
# Regression: Hash entries lost after delete + insert (compaction)
# Bug: yield suffix `unless` parsed as argument modifier, AND
#      loop exit didn't propagate inline-modified new_entry_index
# Fixed: parser.cr (yield postfix modifier) + ast_to_hir.cr (while loop exit)

h = {} of String => Int32

# Fill 16 entries
16.times do |i|
  h["k#{i}"] = i
end

# Delete 8 even keys
8.times do |i|
  h.delete("k#{i * 2}")
end

# Insert one new key (triggers compaction)
h["new0"] = 100

# Verify size
puts "size=#{h.size}"  # expect 9

# Verify each iterates all entries
each_count = 0
h.each { |k, v| each_count += 1 }
puts "each_count=#{each_count}"  # expect 9

# Verify all odd keys present via lookup
missing = 0
8.times do |i|
  k = "k#{i * 2 + 1}"
  v = h[k]?
  unless v
    puts "MISSING: #{k}"
    missing += 1
  end
end
puts "missing=#{missing}"  # expect 0

# Expected output:
# size=9
# each_count=9
# missing=0
puts "hash_compaction_ok" if missing == 0 && each_count == 9

# ===== hash_stress =====
# Regression: Multiple rounds of hash insert/delete/compaction
# Tests that compaction works correctly across multiple cycles

h = {} of String => Int32

# Round 1: fill 32, delete 16
32.times { |i| h["r1_#{i}"] = i }
16.times { |i| h.delete("r1_#{i * 2}") }
h["trigger1"] = 1000

c1 = 0
h.each { |k, v| c1 += 1 }
puts "r1: size=#{h.size} each=#{c1}"  # expect 17

# Round 2: add more, delete some
16.times { |i| h["r2_#{i}"] = i + 100 }
8.times { |i| h.delete("r2_#{i * 2}") }
h["trigger2"] = 2000

c2 = 0
h.each { |k, v| c2 += 1 }
puts "r2: size=#{h.size} each=#{c2}"  # expect 26

# Verify no keys missing
missing = 0
16.times do |i|
  k = "r1_#{i * 2 + 1}"
  missing += 1 unless h[k]?
end
8.times do |i|
  k = "r2_#{i * 2 + 1}"
  missing += 1 unless h[k]?
end
puts "missing=#{missing}"  # expect 0
puts "hash_stress_ok" if missing == 0

puts "test_batch_collections_all_ok"
