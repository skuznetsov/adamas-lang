lib Native
  fun putchar(value : Int32) : Int32
end
macro project(call)
  {% args = begin
    call.args
  end %}
  {% for arg in args %}
    Native.putchar({{arg}})
  {% end %}
end
project(Target.consume(65, 66))
