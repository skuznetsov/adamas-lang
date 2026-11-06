lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% values = [65].map { |x, unused| true ? x : unused } %}
LibC.putchar({{values[0]}})
end
probe
