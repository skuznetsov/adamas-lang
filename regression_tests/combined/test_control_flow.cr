# Combined: Control flow, exceptions, break/next, case/when
# EXPECT: control_flow_all_ok

# --- Basic if/elsif/else ---
x = 10
if x > 20
  puts "big"
elsif x > 5
  puts "medium"
else
  puts "small"
end

# --- Ternary ---
puts x > 0 ? "positive" : "non-positive"

# --- While loop ---
i = 0
sum = 0
while i < 10
  sum += i
  i += 1
end
puts sum

# --- Until ---
j = 10
until j <= 0
  j -= 3
end
puts j

# --- Case/when with values ---
val = 3
case val
when 1
  puts "one"
when 2
  puts "two"
when 3
  puts "three"
else
  puts "other"
end

# --- Case/when with ranges ---
score = 85
grade = case score
        when 90..100
          "A"
        when 80..89
          "B"
        when 70..79
          "C"
        else
          "F"
        end
puts grade

# --- Case/when with types ---
mixed : Int32 | String | Bool = "hello"
case mixed
when Int32
  puts "int: #{mixed}"
when String
  puts "str: #{mixed}"
when Bool
  puts "bool: #{mixed}"
end

# --- Break in block ---
found = -1
[10, 20, 30, 40, 50].each_with_index do |v, idx|
  if v == 30
    found = idx
    break
  end
end
puts found

# --- Next in block ---
evens = [] of Int32
(1..10).each do |n|
  next if n % 2 != 0
  evens << n
end
puts evens.size
puts evens.join(",")

# --- Rescue basic ---
begin
  raise "test error"
rescue ex
  puts "caught: #{ex.message}"
end

# --- Rescue with type ---
begin
  arr = [1, 2, 3]
  arr[10]
rescue IndexError
  puts "index error caught"
rescue ex
  puts "other: #{ex.message}"
end

# --- Nested rescue ---
begin
  begin
    raise "inner"
  rescue inner_ex
    puts "inner: #{inner_ex.message}"
    raise "outer"
  end
rescue outer_ex
  puts "outer: #{outer_ex.message}"
end

# --- Ensure ---
result = begin
  42
ensure
  puts "ensure ran"
end
puts result

# --- Return from method with rescue ---
def safe_divide(a : Int32, b : Int32) : Int32
  a // b
rescue DivisionByZeroError
  0
end

puts safe_divide(10, 3)
puts safe_divide(10, 0)

puts "control_flow_all_ok"
