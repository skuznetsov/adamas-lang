@[Link("c")]
lib LibC
  fun putchar(c : Int32) : Int32
end
macro handler_then_later_error
  {% result = begin
       65
     rescue
       66
     end
     raise "later sentinel"
  %}
  {{ result }}
end
LibC.putchar(handler_then_later_error)
