@[Link("c")]
lib LibC
  fun putchar(c : Int32) : Int32
end
macro passthrough(value)
  {{ value }}
end
LibC.putchar(passthrough(begin
  65
end))
LibC.putchar(10)
