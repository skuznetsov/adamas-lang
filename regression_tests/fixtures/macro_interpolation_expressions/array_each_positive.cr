lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% values = [0] %}
{% [65].each { |x| values[0] = x } %}
LibC.putchar({{values[0]}})
end
probe
