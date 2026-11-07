lib LibC
  fun putchar(value : Int32) : Int32
end

macro empty_begin_value
  {% result = begin
     end %}
  {{ result.class_name == "Nop" ? 65 : 66 }}
end

LibC.putchar(empty_begin_value)
LibC.putchar(10)
