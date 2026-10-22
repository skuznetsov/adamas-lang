lib LogicalRhsC
  fun putchar(value : Int32) : Int32
end

def emit_value(value : Int32) : Int32
  LogicalRhsC.putchar(73_i32)
  value
end

def wrap_value(value : Int32) : Bool
  LogicalRhsC.putchar(79_i32)
  true
end

def consume(value : Bool) : Bool
  value
end

consume(false || wrap_value emit_value 65_i32)
