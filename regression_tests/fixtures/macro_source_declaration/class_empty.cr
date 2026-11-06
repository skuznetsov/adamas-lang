lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe(field)
{% if field.var.stringify == "@@field" && field.type.stringify == "Int32" && field.id.stringify == "@@field : Int32" && field.value.nil? %}
LibC.putchar(65)
{% else %}
LibC.putchar(70)
{% end %}
end
probe @@field : Int32
