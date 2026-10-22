lib LogicalRhsC
  fun putchar(value : Int32) : Int32
end

class EndOfInput
end

def raise(error : EndOfInput) : Int32
  LogicalRhsC.putchar(71_i32)
  1_i32
end

def consume(value : Bool) : Bool
  value
end

consume(false || ((raise EndOfInput.new) > 0_i32))
