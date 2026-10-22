require "proc"
lib ProcSourceIdentityOutput
  fun putchar(value : Int32) : Int32
end
alias Short = Int16
alias Long = Int64
callback = ->(value : Short) : Long { 65_i64 }
if callback.call(1_i16) == 65_i64
  ProcSourceIdentityOutput.putchar(65_i32)
end
ProcSourceIdentityOutput.putchar(10_i32)
