lib LibC
  fun exit(status : Int32) : NoReturn
end

alias PairOrDouble = Tuple(Int32) | Tuple(Int32, Int32)

# Keep the call sites behind a function whose declared result is the union.
# Passing tuple literals directly lets the compiler specialize each call to a
# concrete tuple and bypasses the union iteration path under test.
def choose_tuple(which : Int32) : PairOrDouble
  if which == 0
    {3}
  elsif which == 1
    {0, 2}
  else
    {1, 2}
  end
end

def sum_each(value : PairOrDouble) : Int32
  sum = 0
  value.each do |part|
    sum += part
  end
  sum
end

def sum_with_next(value : PairOrDouble) : Int32
  sum = 0
  value.each do |part|
    next if part == 0
    sum += part
  end
  sum
end

def sum_until_two(value : PairOrDouble) : Int32
  sum = 0
  value.each do |part|
    break if part == 2
    sum += part
  end
  sum
end

def return_if_two(value : PairOrDouble) : Int32
  sum = 0
  value.each do |part|
    if part == 2
      return 100 + part
    end
    sum += part
  end
  sum
end

def return_first(value : PairOrDouble) : Int32
  value.each do |part|
    return part
  end
  -1
end

def check_tuple_controls(value : PairOrDouble) : Int32
  sum_each(value) * 1_000_000 + sum_with_next(value) * 10_000 +
    sum_until_two(value) * 100 + return_if_two(value) * 10 + return_first(value)
end

# Separate returns preserve the producer tags. A ternary joining Tuple.new
# with a nonempty tuple currently loses its tag before iteration (separate bug).
def choose_empty(empty : Bool) : Tuple() | Tuple(Int32)
  return Tuple.new if empty
  {3}
end

def sum_empty(value : Tuple() | Tuple(Int32)) : Int32
  total = 0
  value.each { |part| total += part }
  total
end

def first_empty(value : Tuple() | Tuple(Int32)) : Int32
  value.each { |part| return part }
  99
end

def check_paths : String
  posix_plain = Path.posix("root")
  posix_slash = Path.posix("root/")
  windows_plain = Path.windows("root")
  windows_slash = Path.windows("root\\")

  "#{posix_plain.ends_with_separator? ? 1 : 0},#{posix_slash.ends_with_separator? ? 1 : 0}," \
    "#{windows_plain.ends_with_separator? ? 1 : 0},#{windows_slash.ends_with_separator? ? 1 : 0};" \
    "#{posix_plain.join("/child/")};#{windows_plain.join("\\child\\")}"
end

puts "short=#{check_tuple_controls(choose_tuple(0))}"
puts "zero-long=#{check_tuple_controls(choose_tuple(1))}"
puts "long=#{check_tuple_controls(choose_tuple(2))}"
puts "paths=#{check_paths}"

ok = sum_empty(choose_empty(true)) == 0 && sum_empty(choose_empty(false)) == 3 &&
  first_empty(choose_empty(true)) == 99 && first_empty(choose_empty(false)) == 3 &&
  check_tuple_controls(choose_tuple(0)) == 3_030_333 &&
  check_tuple_controls(choose_tuple(1)) == 2_021_020 &&
  check_tuple_controls(choose_tuple(2)) == 3_031_121 &&
  check_paths == "0,1,0,1;root/child/;root\\child\\"
LibC.exit(ok ? 0 : 91)
