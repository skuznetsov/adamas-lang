@[Link("c")]
lib LibC
  fun putchar(c : Int32) : Int32
end
macro begin_output
  {{ begin
    side_effect = 65
    side_effect
  end }}
end
LibC.putchar(begin_output)
LibC.putchar(10)
