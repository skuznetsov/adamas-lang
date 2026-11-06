lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% values = [7].map { |x, missing| missing } %}
LibC.putchar(65)
end
probe
