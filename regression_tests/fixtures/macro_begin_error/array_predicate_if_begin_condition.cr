@[Link("c")]
lib LibC
  fun putchar(c : Int32) : Int32
end
macro predicate_begin
  {% if [true].all? { |item| if begin item end; true; else false; end } %}
    65
  {% else %}
    66
  {% end %}
end
LibC.putchar(predicate_begin)
LibC.putchar(10)
