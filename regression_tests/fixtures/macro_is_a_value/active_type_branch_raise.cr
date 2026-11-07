lib Native
  fun putchar(value : Int32) : Int32
end

macro project(value)
  Native.putchar({{value.is_a?(NumberLiteral) ? 65 : raise "active type branch"}})
end
project("x")
