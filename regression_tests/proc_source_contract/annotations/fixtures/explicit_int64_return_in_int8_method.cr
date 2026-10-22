require "proc"
lib ProcAnnotationOutput
  fun putchar(value : Int32) : Int32
end
def enclosing : Int8
  value = -> : Int64 { return 300_i64 }
  if value.call == 300_i64
    ProcAnnotationOutput.putchar(65_i32)
  else
    ProcAnnotationOutput.putchar(88_i32)
  end
  return 73_i8
end
if enclosing == 73_i8
  ProcAnnotationOutput.putchar(77_i32)
else
  ProcAnnotationOutput.putchar(88_i32)
end
ProcAnnotationOutput.putchar(10_i32)
