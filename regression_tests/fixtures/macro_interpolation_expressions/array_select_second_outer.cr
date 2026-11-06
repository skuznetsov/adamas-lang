lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% flag = false %}
{% values = [7].select { |x, flag| flag } %}
LibC.putchar({{65 + values.size}})
end
probe
