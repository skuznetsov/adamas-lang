lib Native
  fun putchar(value : Int32) : Int32
end

macro project
  {% counter = 0 %}
  Native.putchar({{(counter = counter + 1).is_a?(NumberLiteral) ? counter + 64 : 88}})
  Native.putchar({{counter + 65}})
end
project
