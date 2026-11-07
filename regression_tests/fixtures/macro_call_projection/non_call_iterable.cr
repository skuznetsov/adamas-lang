lib Native
  fun putchar(value : Int32) : Int32
end
macro project(expr)
 {% for arg in expr.args %}
 Native.putchar(65)
 {% end %}
end
project(65)
