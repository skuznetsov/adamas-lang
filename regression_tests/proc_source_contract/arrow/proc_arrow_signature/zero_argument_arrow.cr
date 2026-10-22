require "proc"

lib ProcSignatureRuntime
  fun putchar(value : Int32) : Int32
end

alias ZeroArgument = () -> Int32
reader = ZeroArgument.new { 90_i32 }
ProcSignatureRuntime.putchar(reader.call)
ProcSignatureRuntime.putchar(10_i32)
