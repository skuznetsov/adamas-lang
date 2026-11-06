lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% outer = 65 %}
{% values = [0] %}
{% [7].each { |x, outer| values[0] = outer } %}
LibC.putchar({{values[0]}})
end
probe
