lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% ignored = 1.map { |x| x } %}
LibC.putchar(65)
end
probe
