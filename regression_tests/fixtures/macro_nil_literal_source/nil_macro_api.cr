lib LibC
  fun putchar(c : Int32) : Int32
end

macro emit(value = nil)
  {% if value.nil? %} LibC.putchar(65) {% else %} LibC.putchar(66) {% end %}
  {% if value %} LibC.putchar(84) {% else %} LibC.putchar(70) {% end %}
  {% if value.class_name == "NilLiteral" %} LibC.putchar(67) {% else %} LibC.putchar(68) {% end %}
  {% if value.stringify == "nil" %} LibC.putchar(83) {% else %} LibC.putchar(88) {% end %}
  {% if value.id.stringify == "nil" %} LibC.putchar(73) {% else %} LibC.putchar(88) {% end %}
end
emit
LibC.putchar(10)
