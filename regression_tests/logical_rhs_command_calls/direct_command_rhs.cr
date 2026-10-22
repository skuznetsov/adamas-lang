lib LogicalRhsC
  fun putchar(value : Int32) : Int32
end

def emit_byte(value : Int32) : Bool
  LogicalRhsC.putchar(value)
  true
end

def consume(value : Bool) : Bool
  value
end

consume(false || emit_byte 65_i32)
