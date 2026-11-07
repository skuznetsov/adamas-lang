lib Native
  fun putchar(value : Int32) : Int32
end
macro project(expr)
 {% if expr.named_args.is_a?(Nop) %}
 Native.putchar(65)
 {% else %}
 Native.putchar(88)
 {% end %}
end
project(Target.consume(88))
