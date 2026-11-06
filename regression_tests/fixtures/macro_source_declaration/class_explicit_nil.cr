lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe(field)
{% if field.value.nil? && field.value.class_name == "NilLiteral" && field.value.stringify == "nil" %}
LibC.putchar(65)
{% else %}
LibC.putchar(70)
{% end %}
end
probe @@field : Int32 = nil
