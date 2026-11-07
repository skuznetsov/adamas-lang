lib Native
  fun putchar(value : Int32) : Int32
end
macro project(expr)
 {% if expr.is_a?(Call) %}
 Native.putchar(65)
 {% else %}
 Native.putchar(88)
 {% end %}
end
project(Target.consume)
