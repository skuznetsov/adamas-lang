lib Native
  fun putchar(value : Int32) : Int32
end
macro inspect_call(expr)
  {% for arg, i in expr.args %}
    Native.putchar({{arg}})
  {% end %}
end
macro forward_call(expr)
  inspect_call({{expr}})
end
forward_call(Target.consume(65, 66))
