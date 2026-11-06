lib LibC
 fun putchar(value : Int32) : Int32
end
macro probe(field)
{% if field.class_name == "TypeDeclaration" && field.is_a?(TypeDeclaration) %}
LibC.putchar(65)
{% else %}
LibC.putchar(70)
{% end %}
end
probe @field : Int32
