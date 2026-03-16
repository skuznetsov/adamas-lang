# Combined: Array, Hash, Range, Tuple operations
# EXPECT: collections_all_ok

# --- Array basics ---
arr = [10, 20, 30, 40, 50]
puts arr.size
puts arr[0]
puts arr[-1]
puts arr.first
puts arr.last

# --- Array push/pop/shift ---
arr << 60
puts arr.size
puts arr.pop
puts arr.size
puts arr.shift
puts arr.size

# --- Array map/select/reject ---
nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
evens = nums.select { |n| n % 2 == 0 }
puts evens.size
odds = nums.reject { |n| n % 2 == 0 }
puts odds.size
doubled = nums.map { |n| n * 2 }
puts doubled[0]
puts doubled[9]

# --- Array any?/all?/none? ---
puts nums.any? { |n| n > 5 }
puts nums.all? { |n| n > 0 }
puts nums.none? { |n| n > 100 }

# --- Array each_with_index ---
names = ["alice", "bob", "charlie"]
names.each_with_index do |name, i|
  puts "#{i}:#{name}"
end

# --- Array flat_map ---
nested = [[1, 2], [3, 4], [5]]
flat = nested.flat_map { |a| a }
puts flat.size

# --- Array includes? ---
puts names.includes?("bob")
puts names.includes?("dave")

# --- Array sum/min/max ---
puts nums.sum
puts nums.min
puts nums.max

# --- Hash basics ---
h = {"name" => "crystal", "version" => "2.0"}
puts h.size
puts h["name"]
puts h["version"]
puts h.has_key?("name")
puts h.has_key?("missing")

# --- Hash insert/delete ---
h["author"] = "matz"
puts h.size
h.delete("author")
puts h.size

# --- Hash each ---
counts = {"a" => 1, "b" => 2, "c" => 3}
sum = 0
counts.each { |k, v| sum += v }
puts sum

# --- Hash keys/values ---
puts counts.keys.size
puts counts.values.sum

# --- Range ---
r = (1..5)
puts r.includes?(3)
puts r.includes?(6)
range_sum = 0
(1..10).each { |i| range_sum += i }
puts range_sum

# --- Tuple ---
t = {1, "hello", true}
puts t[0]
puts t[1]
puts t[2]
puts t.size

# --- NamedTuple ---
nt = {name: "crystal", year: 2024}
puts nt[:name]
puts nt[:year]

puts "collections_all_ok"
