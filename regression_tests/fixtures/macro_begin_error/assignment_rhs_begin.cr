@[Link("c")]
lib LibC
  fun putchar(c : Int32) : Int32
end
macro assigned_begin
  {% value = begin
    side_effect = 65
    side_effect
  end %}
  {{ value }}
end
LibC.putchar(assigned_begin)
LibC.putchar(10)
