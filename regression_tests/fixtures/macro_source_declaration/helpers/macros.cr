lib LibC
  fun putchar(value : Int32) : Int32
end
macro property(field, expected_name, expected_type)
  {% if field.var.stringify == expected_name && field.type.stringify == expected_type %}
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
def block_marker
  LibC.putchar(66)
  yield
end
