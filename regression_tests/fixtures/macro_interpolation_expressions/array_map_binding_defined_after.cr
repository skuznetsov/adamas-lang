lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% ignored = [65].map { |value| value } %}
LibC.putchar({{value}})
end
probe
