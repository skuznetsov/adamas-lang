lib LibC
  fun putchar(value : Int32) : Int32
end
def marker
 LibC.putchar(65)
 0
end
macro inspect_parts(pattern)
 {% parts = pattern.expressions %}
 {% if parts[1].is_a?(NumberLiteral) %}
 LibC.putchar(65)
 {% else %}
 LibC.putchar(70)
 {% end %}
end
inspect_parts "a#{7}b"
