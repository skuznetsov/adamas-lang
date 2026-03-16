# Edge case: Default arguments, named arguments, splat
# EXPECT: default_args_all_ok

# Simple default args
def greet(name : String, greeting : String = "Hello") : String
  "#{greeting}, #{name}!"
end

puts greet("World")
puts greet("World", "Hi")

# Multiple defaults
def format(value : Int32, width : Int32 = 0, fill : Char = ' ', prefix : String = "") : String
  s = "#{prefix}#{value}"
  while s.size < width
    s = "#{fill}#{s}"
  end
  s
end

puts format(42)
puts format(42, 6)
puts format(42, 6, '0')
puts format(42, 6, '0', "$")

# Named arguments
def create_point(x : Int32 = 0, y : Int32 = 0) : String
  "(#{x}, #{y})"
end

puts create_point
puts create_point(x: 5)
puts create_point(y: 10)
puts create_point(x: 3, y: 7)

# Method with both positional and named
def log(message : String, level : String = "INFO", timestamp : Bool = false) : String
  parts = [] of String
  parts << "[#{level}]"
  if timestamp
    parts << "[TS]"
  end
  parts << message
  parts.join(" ")
end

puts log("started")
puts log("warning!", level: "WARN")
puts log("debug", level: "DEBUG", timestamp: true)

# Default arg using expression
def make_array(size : Int32 = 3, fill : Int32 = 0) : Array(Int32)
  result = [] of Int32
  size.times { result << fill }
  result
end

puts make_array.join(",")
puts make_array(5).join(",")
puts make_array(4, 1).join(",")

puts "default_args_all_ok"
