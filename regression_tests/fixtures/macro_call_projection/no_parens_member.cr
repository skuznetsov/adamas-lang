lib Native
  fun putchar(value : Int32) : Int32
end
macro inspect_call(expr)
  {% for arg, i in expr.args %}
    Native.putchar({{arg}})
  {% end %}
end
inspect_call(Target.consume)
Native.putchar(67)
