lib C
  fun putchar(value : Int32) : Int32
  fun abort : NoReturn
end

def bottom_stop : NoReturn
  C.abort
end

def bottom_consume(*, value : Int64)
  C.putchar(value == 65_i64 ? 65 : 66)
end

alias BottomArm = NoReturn
alias ReachableValue = Int64 | BottomArm
value : ReachableValue = 65_i64
bottom_consume(value: value)
