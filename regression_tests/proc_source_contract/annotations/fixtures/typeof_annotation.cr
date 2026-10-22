require "proc"
lib ProcSourceIdentityOutput
  fun putchar(value : Int32) : Int32
end
input = 1_i32
callback = ->(value : typeof(input)) : typeof(input) { value }
ProcSourceIdentityOutput.putchar(callback.call(65_i32))
ProcSourceIdentityOutput.putchar(10_i32)
