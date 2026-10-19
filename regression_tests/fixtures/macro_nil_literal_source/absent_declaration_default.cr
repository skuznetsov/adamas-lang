lib LibC
  fun putchar(c : Int32) : Int32
end
macro emit(declaration)
  {% if declaration.value.nil? %} LibC.putchar(65) {% else %} LibC.putchar(88) {% end %}
  {% if declaration.value.stringify == "" %} LibC.putchar(66) {% else %} LibC.putchar(88) {% end %}
end
emit(value : Int32)
LibC.putchar(10)
