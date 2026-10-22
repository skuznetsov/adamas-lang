require "proc"

lib ProcSignatureRuntime
  fun putchar(value : Int32) : Int32
end

alias OmittedOutput = Int32 ->
alias ExplicitVoidOutput = Int32 -> Void
alias ExplicitNilOutput = Int32 -> Nil

def take_nil(callback : Proc(Int32, Nil), marker : Int32)
  callback.call(65_i32)
  ProcSignatureRuntime.putchar(marker)
end

take_nil(OmittedOutput.new { |value| value }, 79_i32)
take_nil(ExplicitVoidOutput.new { |value| value }, 86_i32)
take_nil(ExplicitNilOutput.new { |value| nil }, 78_i32)
ProcSignatureRuntime.putchar(10_i32)
