lib LibC
  fun putchar(value : Int32) : Int32
end

macro inactive_handler_branch
  {% result = if false
       begin
         66
       ensure
         raise "inactive handler branch was evaluated"
       end
     else
       65
     end %}
  {{ result }}
end

LibC.putchar(inactive_handler_branch)
LibC.putchar(10)
