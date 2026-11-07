lib Native
  fun putchar(value : Int32) : Int32
end

macro project(value)
  Native.putchar({{value.is_a?(NumberLiteral) ? 65 : raise "inactive type branch"}})
end
project(1)
