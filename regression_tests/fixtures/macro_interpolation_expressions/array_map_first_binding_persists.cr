lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% value = 65 %}
{% ignored = [66].map { |value| value } %}
LibC.putchar({{value}})
end
probe
