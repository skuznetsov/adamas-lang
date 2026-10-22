require "proc"
lib ProcAnnotationOutput
  fun putchar(value : Int32) : Int32
end
value = -> : Nil { 65_i32 }
value.call
ProcAnnotationOutput.putchar(78_i32)
ProcAnnotationOutput.putchar(10_i32)
