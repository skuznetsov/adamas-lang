# Complex: Closure capture, mutation, nested closures, proc storage
# EXPECT: closures_capture_all_ok

# --- Capture and mutate ---
x = 0
inc = -> { x += 1; x }
puts inc.call
puts inc.call
puts inc.call
puts x

# --- Capture multiple variables ---
a = 10
b = 20
sum_fn = -> { a + b }
puts sum_fn.call
a = 100
puts sum_fn.call

# --- Closure in loop ---
results = [] of Int32
5.times do |i|
  results << i * i
end
puts results.join(",")

# --- Method returning closure ---
def make_adder(n : Int32) : Proc(Int32, Int32)
  ->(x : Int32) { x + n }
end

add5 = make_adder(5)
add10 = make_adder(10)
puts add5.call(3)
puts add10.call(3)

# --- Closure capturing class instance ---
class Counter
  property value : Int32

  def initialize(@value : Int32 = 0)
  end

  def make_incrementer : Proc(Nil)
    -> { @value += 1; nil }
  end
end

c = Counter.new
inc2 = c.make_incrementer
inc2.call
inc2.call
inc2.call
puts c.value

# --- Block passed to method that stores result ---
def collect_even(arr : Array(Int32)) : Array(Int32)
  result = [] of Int32
  arr.each do |n|
    result << n if n % 2 == 0
  end
  result
end

puts collect_even([1, 2, 3, 4, 5, 6]).join(",")

# --- Nested iteration with capture ---
matrix = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
total = 0
matrix.each do |row|
  row.each do |val|
    total += val
  end
end
puts total

# --- Block with early return (break) ---
def find_first_over(arr : Array(Int32), threshold : Int32) : Int32?
  arr.each do |n|
    return n if n > threshold
  end
  nil
end

if v = find_first_over([1, 5, 3, 8, 2], 4)
  puts v
end

puts "closures_capture_all_ok"
