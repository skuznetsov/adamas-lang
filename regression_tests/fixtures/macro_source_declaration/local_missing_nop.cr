lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe(field)
{% if field.value.nil? && field.value.class_name == "Nop" && field.value.stringify == "" %}
LibC.putchar(65)
{% else %}
LibC.putchar(70)
{% end %}
end
probe field : Int32
