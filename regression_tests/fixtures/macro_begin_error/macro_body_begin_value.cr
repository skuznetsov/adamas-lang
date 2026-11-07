lib LibC
  fun putchar(value : Int32) : Int32
end

macro begin_value
  {% result = begin
       side_effect = 65
       side_effect + 1
     end %}
  {{ result }}
end

LibC.putchar(begin_value)
LibC.putchar(10)
