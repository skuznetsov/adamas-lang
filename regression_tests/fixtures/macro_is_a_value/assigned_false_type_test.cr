lib Native
  fun putchar(value : Int32) : Int32
end

macro project(value)
  {% matches = value.is_a?(NumberLiteral) %}
  {% if matches %}
    Native.putchar(65)
  {% else %}
    Native.putchar(66)
  {% end %}
end
project("x")
