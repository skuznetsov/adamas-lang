lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% ignored = (1..2).select { |x| true } %}
LibC.putchar(65)
end
probe
