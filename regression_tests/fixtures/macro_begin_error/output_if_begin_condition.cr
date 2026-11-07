@[Link("c")]
lib LibC
  fun putchar(c : Int32) : Int32
end
macro output_if_begin
  {{ if begin true end
    65
  else
    66
  end }}
end
LibC.putchar(output_if_begin)
LibC.putchar(10)
