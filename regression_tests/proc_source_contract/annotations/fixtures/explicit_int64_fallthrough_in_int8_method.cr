require "proc"
lib ProcAnnotationOutput
  fun putchar(value : Int32) : Int32
end
def enclosing : Int8
  value = -> : Int64 { 301_i64 }
  if value.call == 301_i64
    ProcAnnotationOutput.putchar(66_i32)
  else
    ProcAnnotationOutput.putchar(88_i32)
  end
  74_i8
end
if enclosing == 74_i8
  ProcAnnotationOutput.putchar(78_i32)
else
  ProcAnnotationOutput.putchar(88_i32)
end
ProcAnnotationOutput.putchar(10_i32)
