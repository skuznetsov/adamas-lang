lib LogicalRhsC
  fun putchar(value : Int32) : Int32
end

def nested_one(value : Int32) : Bool
  LogicalRhsC.putchar(66_i32)
  true
end

def consume_pair(left : Bool, right : Int32) : Bool
  LogicalRhsC.putchar(65_i32)
  LogicalRhsC.putchar(right)
  left
end

consume_pair(false || (nested_one 66_i32), 67_i32)
