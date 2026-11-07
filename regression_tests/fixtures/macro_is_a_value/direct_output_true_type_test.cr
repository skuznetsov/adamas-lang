lib Native
  fun putchar(value : Int32) : Int32
end

macro project(value)
  if {{value.is_a?(NumberLiteral)}}
    Native.putchar(65)
  else
    Native.putchar(66)
  end
end
project(1)
