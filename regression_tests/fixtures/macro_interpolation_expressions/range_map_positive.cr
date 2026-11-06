lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% values = (64..64).map { |x| x + 1 } %}
LibC.putchar({{values[0]}})
end
probe
