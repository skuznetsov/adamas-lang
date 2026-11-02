lib LibC
  fun putchar(c : Int32) : Int32
end
macro emit
  {% text = <<-BODY
    control payload
    BODY
  %}
  LibC.putchar(65)
end
emit
LibC.putchar(10)
