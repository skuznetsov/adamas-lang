lib LogicalRhsC
  fun putchar(value : Int32) : Int32
end

def nested_pair(first : Int32, second : Int32) : Bool
  LogicalRhsC.putchar(first)
  LogicalRhsC.putchar(second)
  true
end

def consume(value : Bool) : Bool
  LogicalRhsC.putchar(65_i32)
  value
end

consume(false || nested_pair 66_i32, 67_i32)
