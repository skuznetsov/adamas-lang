lib LibC
  fun putchar(value : Int32) : Int32
end

macro handler_in_macro_value
  {% result = begin
       65
     ensure
       66
     end %}
  {{ result }}
end

LibC.putchar(handler_in_macro_value)
