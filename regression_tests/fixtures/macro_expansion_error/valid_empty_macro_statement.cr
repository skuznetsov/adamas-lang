lib LibC
  fun putchar(value : Int32) : Int32
end

macro noop
  {% if false %}
    LibC.putchar(88)
  {% end %}
end

noop
LibC.putchar(65)
LibC.putchar(10)
