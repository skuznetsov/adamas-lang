lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% ignored = [65].map(1) { |x| x } %}
LibC.putchar(65)
end
probe
