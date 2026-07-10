def dynamic_map_next(parts : Array(String)) : String
  parts.map do |part|
    next part unless part.starts_with?('%')
    part + "!"
  end.join(",")
end

def literal_map_next : String
  ["a", "%b"].map do |part|
    next part unless part.starts_with?('%')
    part + "!"
  end.join(",")
end

def map_with_index_next(parts : Array(String)) : String
  parts.map_with_index do |part, index|
    next part if index == 0
    part + "!"
  end.join(",")
end

def nested_next_ownership : Array(Int32)
  [1].map do |value|
    1.times do
      next
    end
    value + 1
  end
end

def mixed_nested_next_ownership : Array(Int32)
  [1].map do |value|
    next value if value < 0
    1.times do
      next
    end
    value + 1
  end
end

def next_with_noreturn_fallthrough : Array(Int32)
  [1].map do |value|
    next value if value > 0
    raise "unreachable map fallthrough"
  end
end

def syntactic_next_with_all_noreturn_paths(values : Array(Int32)) : Array(Int32)
  values.map do |value|
    next value if false
    raise "expected map failure"
  end
end

def tuple_next_merge : Array(Tuple(Int32 | Int64))
  [0, 1].map do |value|
    next({1}) if value == 0
    {1_i64}
  end
end

def case_in_next(values : Array(Int32)) : Array(Int32)
  values.map do |value|
    case value
    in 1
      next value
    else
      value + 1
    end
  end
end

expected = "a,%b!"
raise "dynamic map next" unless dynamic_map_next(["a", "%b"]) == expected
raise "literal map next" unless literal_map_next == expected
raise "map_with_index next" unless map_with_index_next(["a", "%b"]) == expected
nested = nested_next_ownership
raise "nested next ownership" unless nested.size == 1 && nested[0] == 2
mixed = mixed_nested_next_ownership
raise "mixed nested next ownership" unless mixed.size == 1 && mixed[0] == 2
noreturn = next_with_noreturn_fallthrough
raise "next with noreturn fallthrough" unless noreturn.size == 1 && noreturn[0] == 1

caught = false
begin
  syntactic_next_with_all_noreturn_paths([1])
rescue
  caught = true
end
raise "all-noreturn map body was revived" unless caught

tuples = tuple_next_merge
raise "tuple next merge size" unless tuples.size == 2
raise "tuple next merge first" unless tuples[0][0] == 1
raise "tuple next merge second" unless tuples[1][0] == 1_i64

case_in = case_in_next([1, 2])
raise "case/in next size" unless case_in.size == 2
raise "case/in next first" unless case_in[0] == 1
raise "case/in next second" unless case_in[1] == 3
