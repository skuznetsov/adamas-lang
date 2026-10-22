require "proc"

lib ProcSignatureRuntime
  fun putchar(value : Int32) : Int32
end

alias OmittedOutput = Int32 ->
alias ExplicitVoidOutput = Int32 -> Void
alias ExplicitNilOutput = Int32 -> Nil

def take_omitted(callback : Proc(Int32, Void))
  ProcSignatureRuntime.putchar(73_i32)
end

def take_void(callback : Proc(Int32, Void))
  ProcSignatureRuntime.putchar(86_i32)
end

def take_nil(callback : Proc(Int32, Nil))
  ProcSignatureRuntime.putchar(78_i32)
end

take_omitted(OmittedOutput.new { |value| value })
take_void(ExplicitVoidOutput.new { |value| value })
take_nil(ExplicitNilOutput.new { |value| nil })
ProcSignatureRuntime.putchar(10_i32)
