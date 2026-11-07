lib LibC
  fun putchar(value : Int32) : Int32
end

macro if_without_else_is_nop
  {% value = if begin false end
       66
     end %}
  {{ value.class_name == "Nop" ? 65 : 66 }}
end

LibC.putchar(if_without_else_is_nop)
LibC.putchar(10)
