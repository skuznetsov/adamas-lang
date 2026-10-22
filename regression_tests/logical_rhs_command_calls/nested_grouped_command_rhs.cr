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

consume(false || (
  # Grouping and trivia before the command root must preserve the exception.
  ((emit_byte 67_i32))
))
