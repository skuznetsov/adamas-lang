# Combined: String operations, join, interpolation, conversion
# EXPECT: strings_join_all_ok

# --- String interpolation ---
name = "world"
msg = "hello #{name}"
puts msg

num = 42
puts "num=#{num}"

# --- String methods ---
s = "Hello, World!"
puts s.size
puts s.upcase
puts s.downcase
puts s.reverse
puts s.includes?("World")
puts s.includes?("xyz")

# --- String split/join ---
parts = "a,b,c,d".split(",")
puts parts.size
puts parts.join("-")
puts parts.join("")
puts parts.join(", ")

# --- Array#join with various types ---
ints = [1, 2, 3]
puts ints.join(", ")
puts ints.join("")

bools = [true, false, true]
puts bools.join("|")

strs = ["hello", "world"]
puts strs.join(" ")

# --- Empty array join ---
empty = [] of String
puts empty.join(",")
puts empty.join(",").size

# --- Single element join ---
single = ["only"]
puts single.join(",")

# --- String to numeric conversions ---
puts "123".to_i
puts "255".to_u8
puts "65535".to_u16
puts "42".to_i64

# --- String comparison ---
puts "abc" == "abc"
puts "abc" == "def"
puts "abc" < "def"
puts "def" > "abc"

# --- String * repeat ---
puts "ab" * 3

# --- Char operations ---
c = 'A'
puts c
puts c.ord

puts "strings_join_all_ok"
