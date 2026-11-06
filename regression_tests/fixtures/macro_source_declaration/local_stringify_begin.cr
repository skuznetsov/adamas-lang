lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe(field)
{% if field.stringify == "field : Int32 = begin\n  LibC.putchar(65)\n  66\nend" %}
LibC.putchar(65)
{% else %}
LibC.putchar(70)
{% end %}
end
probe(field : Int32 = begin
  LibC.putchar(65)
  66
end)
