lib LibC
  fun putchar(value : Int32) : Int32
end
def marker
  LibC.putchar(65)
  0
end
macro visit(pattern)
  {% for part in pattern.expressions %}
    {% if part.is_a?(StringLiteral) %}
      LibC.putchar(83)
    {% else %}
      LibC.putchar(69)
      {{ part }}
    {% end %}
  {% end %}
end
visit "p#{begin marker; 7 end}q"
LibC.putchar(10)
