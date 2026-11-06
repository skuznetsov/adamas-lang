lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% values = {one: 65, two: 66}.reject { |k, v| v == 66 } %}
{% if values.class_name == "NamedTupleLiteral" %}
LibC.putchar({{values[:one]}})
{% else %}
LibC.putchar(70)
{% end %}
end
probe
