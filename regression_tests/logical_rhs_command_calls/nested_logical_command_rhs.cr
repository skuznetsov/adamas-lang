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

consume(false || (true && (emit_byte 68_i32)))
