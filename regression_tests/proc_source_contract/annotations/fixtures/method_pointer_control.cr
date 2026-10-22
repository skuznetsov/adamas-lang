require "proc"
lib ProcAnnotationOutput
  fun putchar(value : Int32) : Int32
end
def method_pointer_source : Int64
  321_i64
end
def enclosing_method_pointer_control : Int8
  value = ->method_pointer_source
  if value.call == 321_i64
    ProcAnnotationOutput.putchar(80_i32)
  else
    ProcAnnotationOutput.putchar(88_i32)
  end
  73_i8
end
if enclosing_method_pointer_control == 73_i8
  ProcAnnotationOutput.putchar(77_i32)
else
  ProcAnnotationOutput.putchar(88_i32)
end
ProcAnnotationOutput.putchar(10_i32)
