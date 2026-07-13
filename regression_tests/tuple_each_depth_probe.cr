require "../src/stdlib/tuple"

def tuple_each_probe
  {1, 2}.each { |value| value }
  0
end

def tuple_each_nested_probe
  {1, 2}.each { |value| {3, 4}.each { |nested| nested } }
  0
end

def tuple_each_nested_break_probe
  acc = 0
  {1, 2}.each do |outer|
    {3, 4}.each do |inner|
      acc = acc * 10 + inner
      break if inner == 3
    end
  end
  acc
end

def tuple_empty_probe
  Tuple.new.each { }
  0
end

def tuple_each_next_probe
  acc = 0
  {1, 2, 3}.each do |value|
    next if value == 2
    acc = acc * 10 + value
  end
  acc
end

def tuple_each_break_probe
  acc = 0
  {1, 2, 3}.each do |value|
    acc = acc * 10 + value
    break if value == 2
  end
  acc
end

def tuple_each_break_outer_loop_probe
  acc = 0
  i = 0
  while i < 2
    {1, 2, 3}.each do |value|
      acc = acc * 10 + value
      break if value == 2
    end
    i += 1
  end
  acc
end

def tuple_each_break_inner_loop_probe
  acc = 0
  {1, 2, 3}.each do |value|
    j = 0
    while j < 2
      acc = acc * 10 + value
      break
      j += 1
    end
  end
  acc
end

def tuple_each_heterogeneous_probe
  actual_name = nil.as(String?)
  base_method_name = "base"
  resolved_method_name = nil.as(String?)
  {actual_name, base_method_name, resolved_method_name}.each do |name|
    next unless name
    next if name.empty?
    break if name == "base"
    name
  end
  0
end

def repeat_once
  yield 1
end

def non_tuple_yield_probe
  repeat_once { |value| value }
  0
end

puts tuple_each_probe
puts tuple_each_nested_probe
puts tuple_each_nested_break_probe
puts tuple_empty_probe
puts tuple_each_next_probe
puts tuple_each_break_probe
puts tuple_each_break_outer_loop_probe
puts tuple_each_break_inner_loop_probe
puts tuple_each_heterogeneous_probe
puts non_tuple_yield_probe
