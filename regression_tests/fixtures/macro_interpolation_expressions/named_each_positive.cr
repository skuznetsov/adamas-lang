lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% values = [0] %}
{% {one: 65}.each { |k, v| values[0] = v } %}
LibC.putchar({{values[0]}})
end
probe
