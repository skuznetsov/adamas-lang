lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% values = {one: 64}.map { |k, v| v + 1 } %}
{% if values.class_name == "ArrayLiteral" %}
LibC.putchar({{values[0]}})
{% else %}
LibC.putchar(70)
{% end %}
end
probe
