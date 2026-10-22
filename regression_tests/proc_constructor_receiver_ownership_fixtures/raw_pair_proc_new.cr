require "proc"

lib ProcConstructorFactOutput
  fun putchar(value : Int32) : Int32
end

callback = Proc(Int32, Int32).new(Pointer(Void).new(0_u64), Pointer(Void).new(0_u64))
ProcConstructorFactOutput.putchar(80_i32)
ProcConstructorFactOutput.putchar(10_i32)
