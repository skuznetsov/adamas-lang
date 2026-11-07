lib Native
  fun putchar(value : Int32) : Int32
end
macro project(expr)
 {% if expr.receiver.is_a?(Nop) %}
 Native.putchar(65)
 {% else %}
 Native.putchar(88)
 {% end %}
end
project(consume(88))
