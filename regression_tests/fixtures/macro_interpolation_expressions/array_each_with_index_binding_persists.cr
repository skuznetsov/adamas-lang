lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% ignored = [65].each_with_index { |value, index| value } %}
LibC.putchar({{value}})
end
probe
