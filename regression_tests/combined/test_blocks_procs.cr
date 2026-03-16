# Combined: Blocks, procs, closures, iterators
# EXPECT: blocks_procs_all_ok

# --- Basic block yield ---
def twice(&block : ->)
  yield
  yield
end

count = 0
twice { count += 1 }
puts count

# --- Block with args ---
def apply(x : Int32, &block : Int32 -> Int32) : Int32
  yield x
end

puts apply(5) { |n| n * n }

# --- Block with return value ---
def transform(arr : Array(Int32), &block : Int32 -> Int32) : Array(Int32)
  result = [] of Int32
  arr.each { |x| result << yield(x) }
  result
end

doubled = transform([1, 2, 3]) { |x| x * 2 }
puts doubled.join(",")

# --- Closure capturing outer variable ---
multiplier = 10
result = [1, 2, 3].map { |x| x * multiplier }
puts result.join(",")

# --- Closure mutation ---
counter = 0
3.times { counter += 1 }
puts counter

# --- Nested blocks ---
matrix = [[1, 2], [3, 4], [5, 6]]
flat = [] of Int32
matrix.each do |row|
  row.each do |val|
    flat << val
  end
end
puts flat.join(",")

# --- each_with_object ---
words = ["hello", "world", "foo"]
lengths = words.map { |w| w.size }
puts lengths.join(",")

# --- Reduce/inject pattern ---
nums = [1, 2, 3, 4, 5]
sum = 0
nums.each { |n| sum += n }
puts sum

product = 1
nums.each { |n| product *= n }
puts product

# --- Block with index ---
["a", "b", "c"].each_with_index do |val, idx|
  puts "#{idx}=#{val}"
end

# --- Method that takes optional block ---
def greet(name : String) : String
  "Hello, #{name}!"
end

puts greet("World")

# --- Chained methods with blocks ---
result2 = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  .select { |n| n % 2 == 0 }
  .map { |n| n * 10 }
puts result2.size
puts result2.first
puts result2.last

# --- upto/downto ---
vals = [] of Int32
1.upto(5) { |i| vals << i }
puts vals.join(",")

# --- times ---
items = [] of Int32
5.times { |i| items << i }
puts items.join(",")

puts "blocks_procs_all_ok"
