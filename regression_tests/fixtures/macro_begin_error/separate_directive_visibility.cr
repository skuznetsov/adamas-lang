@[Link("c")]
lib LibC
  fun putchar(c : Int32) : Int32
end
{% top_result = begin
  side_effect = 65
  side_effect + 1
end %}
LibC.putchar({{top_result}})
LibC.putchar(10)
