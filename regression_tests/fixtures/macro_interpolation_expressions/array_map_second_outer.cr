lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% outer = 65 %}
{% values = [7].map { |x, outer| outer } %}
LibC.putchar({{values[0]}})
end
probe
