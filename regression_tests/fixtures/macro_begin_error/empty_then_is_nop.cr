lib LibC
  fun putchar(value : Int32) : Int32
end

macro empty_then_is_nop
  {% value = if begin true end
     else
       66
     end %}
  {{ value.class_name == "Nop" ? 65 : 66 }}
end

LibC.putchar(empty_then_is_nop)
LibC.putchar(10)
