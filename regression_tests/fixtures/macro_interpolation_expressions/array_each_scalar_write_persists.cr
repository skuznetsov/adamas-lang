lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% value = 0 %}
{% [65].each { |x| value = x } %}
LibC.putchar({{value}})
end
probe
