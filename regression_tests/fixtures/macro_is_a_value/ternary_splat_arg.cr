lib Native
  fun putchar(value : Int32) : Int32
end

macro project(call)
  {% for arg in call.args %}
    Native.putchar({{arg.is_a?(Splat) ? arg.exp : arg}})
  {% end %}
end
project(Target.consume(*65))
