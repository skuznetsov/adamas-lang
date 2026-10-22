lib LogicalRhsC
  fun putchar(value : Int32) : Int32
end

def emit_byte(value : Int32) : Bool
  LogicalRhsC.putchar(value)
  true
end

def consume_pair(left : Bool, right : Bool) : Bool
  right
end

consume_pair(false || (emit_byte 69_i32), true && (emit_byte 70_i32))
