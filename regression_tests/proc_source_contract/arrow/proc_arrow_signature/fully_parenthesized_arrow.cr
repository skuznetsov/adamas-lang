require "proc"

lib ProcSignatureRuntime
  fun putchar(value : Int32) : Int32
end

alias SecondInput = ((Int32, Int32) -> Int32)
reader = SecondInput.new { |first, second| second }
ProcSignatureRuntime.putchar(reader.call(65_i32, 67_i32))
ProcSignatureRuntime.putchar(10_i32)
