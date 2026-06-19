# Combined batch bundle (mechanical concat, byte-equality verified).
# Members: test_blocks_closures test_closure upto_block_var yield_suffix_unless
# EXPECT: test_batch_blocks_procs_all_ok

# ===== test_blocks_closures =====
# Test blocks, closures, and iterators
arr = [10, 20, 30, 40, 50]

# map
doubled = arr.map { |x| x * 2 }
puts doubled.size
puts doubled[0]
puts doubled[4]

# select
big = arr.select { |x| x > 25 }
puts big.size
puts big[0]

# each_with_object / reduce pattern via manual accumulation
sum = 0
arr.each { |x| sum += x }
puts sum

# any? / all?
puts arr.any? { |x| x > 40 }
puts arr.all? { |x| x > 5 }

# index
idx = arr.index(30)
puts idx.nil? ? "nil" : idx.to_s

# compact_map (skip nil via if)
result = [] of Int32
arr.each do |x|
  result << x * 10 if x > 20
end
puts result.size
puts result[0]

# Nested blocks
matrix = [[1, 2], [3, 4], [5, 6]]
flat = [] of Int32
matrix.each do |row|
  row.each do |val|
    flat << val
  end
end
puts flat.size
puts flat[5]

puts "done"

# ===== test_closure =====
# Test closures that capture variables
x = 10
add_x = ->(n : Int32) { n + x }
puts add_x.call(5)
puts "closure_done"

# ===== upto_block_var =====
# Regression: upto with block that modifies outer variable
# Bug: while loop exit didn't propagate inline-modified variable
# Fixed: ast_to_hir.cr (while loop exit backedge value propagation)

total = 0
1.upto(5) do |i|
  total += i
end
puts "total=#{total}"  # expect 15

puts "upto_block_var_ok" if total == 15

# ===== yield_suffix_unless =====
# Regression: yield with suffix unless/if parsed incorrectly
# Bug: `yield entry, i unless entry.deleted?` parsed as
#      `yield(entry, (i unless entry.deleted?))` instead of
#      `(yield entry, i) unless entry.deleted?`
# Fixed: parser.cr (without_postfix_modifiers for yield args + postfix modifier)

# This test verifies that hash iteration correctly skips deleted entries
# (which exercises the yield...unless pattern in Hash#each_entry_with_index)

h = {} of String => Int32
8.times { |i| h["k#{i}"] = i }
4.times { |i| h.delete("k#{i * 2}") }  # delete even keys

# Trigger compaction
h["new"] = 99

each_keys = [] of String
h.each { |k, v| each_keys << k }

# All 4 odd keys + "new" should be present
puts "count=#{each_keys.size}"  # expect 5
puts "yield_suffix_unless_ok" if each_keys.size == 5

puts "test_batch_blocks_procs_all_ok"
