lib LibC
 fun putchar(value : Int32) : Int32
end
def marker
 1
end
macro inspect_parts(pattern)
 {% parts = pattern.expressions %}
 {% if parts[1].class_name == "NumberLiteral" && parts[1].stringify == "1_i128" %}
 LibC.putchar(65)
 {% else %}
 LibC.putchar(70)
 {% end %}
end
inspect_parts "a#{1_i128}b"
