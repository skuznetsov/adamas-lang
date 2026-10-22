require "proc"
lib ProcAnnotationOutput
  fun putchar(value : Int32) : Int32
end
value = -> : Void { 65_i32 }
value.call
ProcAnnotationOutput.putchar(86_i32)
ProcAnnotationOutput.putchar(10_i32)
