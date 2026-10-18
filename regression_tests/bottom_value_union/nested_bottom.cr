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

def branch_bottom(flag : Bool)
  if flag
    65_i64
  else
    bottom_stop
  end
end
def tuple_consume(*, value : Tuple(Int64))
  C.putchar(value[0] == 65_i64 ? 65 : 66)
end
tuple_consume(value: {branch_bottom(true)})
