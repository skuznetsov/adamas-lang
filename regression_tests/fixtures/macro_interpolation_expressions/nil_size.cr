lib LibC
  fun putchar(value : Int32) : Int32
end
def marker
 LibC.putchar(65)
 0
end
macro inspect_parts(pattern)
 {% parts = pattern.expressions %}
 {% if parts.size == 3 %}
 LibC.putchar(65)
 {% else %}
 LibC.putchar(70)
 {% end %}
end
inspect_parts "a#{nil}b"
