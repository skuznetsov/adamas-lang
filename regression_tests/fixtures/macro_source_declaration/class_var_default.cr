lib LibC
  fun putchar(value : Int32) : Int32
end
macro property(field)
  {% if field.type.stringify == "Int32" %}
    LibC.putchar(65)
  {% else %}
    LibC.putchar(70)
  {% end %}
  {% unless field.value.nil? %}
    {{ field.value }}
  {% end %}
end
def marker
  LibC.putchar(66)
  7
end
property @@field : Int32 = marker
LibC.putchar(10)
