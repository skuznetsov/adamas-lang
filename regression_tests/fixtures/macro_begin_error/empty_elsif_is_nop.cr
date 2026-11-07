lib LibC
  fun putchar(value : Int32) : Int32
end

macro empty_elsif_is_nop
  {% value = if begin false end
       66
     elsif begin true end
     else
       67
     end %}
  {{ value.class_name == "Nop" ? 65 : 66 }}
end

LibC.putchar(empty_elsif_is_nop)
LibC.putchar(10)
