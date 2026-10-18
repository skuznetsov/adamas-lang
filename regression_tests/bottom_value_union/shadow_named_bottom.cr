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

module Shadow
  struct NoReturn
  end
end
def shadow_union(flag : Bool)
  if flag
    65_i64
  else
    Shadow::NoReturn.new
  end
end
bottom_consume(value: shadow_union(true))
