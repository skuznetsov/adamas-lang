lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe(field)
{% if field.stringify == "field : Int32 = 7" %}
LibC.putchar(65)
{% else %}
LibC.putchar(70)
{% end %}
end
probe field : Int32 = 7
