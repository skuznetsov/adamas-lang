lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% values = [0] %}
{% [0, 64].each_with_index { |x, idx| values[0] = x + idx } %}
LibC.putchar({{values[0]}})
end
probe
