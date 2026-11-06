lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% ignored = {one: 65}.each(extra: 1) { |k, v| v } %}
LibC.putchar(65)
end
probe
