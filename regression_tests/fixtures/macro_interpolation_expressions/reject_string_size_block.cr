lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe
{% ignored = "abc".size { 65 } %}
LibC.putchar(65)
end
probe
