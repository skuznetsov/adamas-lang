lib Native
  fun putchar(value : Int32) : Int32
end

macro project(value)
  Native.putchar({{value.is_a?(NumberLiteral) ? 65 : "wrong"}})
end
project("x")
