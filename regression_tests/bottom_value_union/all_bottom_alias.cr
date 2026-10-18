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

alias AllBottom = NoReturn | NoReturn

def all_bottom_alias : AllBottom
  bottom_stop
end

def branch_bottom(flag : Bool)
  if flag
    65_i64
  else
    all_bottom_alias
  end
end
bottom_consume(value: branch_bottom(true))
