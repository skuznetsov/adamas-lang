lib Native
  fun putchar(value : Int32) : Int32
end
macro project(expr)
 {% for arg in expr.args %}
 {% if arg.is_a?(Splat) %}
 Native.putchar({{arg.exp}})
 {% else %}
 Native.putchar(88)
 {% end %}
 {% end %}
end
project(Target.consume(*65))
