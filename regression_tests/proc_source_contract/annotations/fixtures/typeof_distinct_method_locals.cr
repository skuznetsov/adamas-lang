require "proc"
lib ProcSourceIdentityOutput
  fun putchar(value : Int32) : Int32
end
def typed_i32
  input = 1_i32
  callback = ->(value : typeof(input)) : typeof(input) { value }
  ProcSourceIdentityOutput.putchar(callback.call(65_i32))
end
def typed_i64
  input = 1_i64
  callback = ->(value : typeof(input)) : typeof(input) { value }
  if callback.call(66_i64) == 66_i64
    ProcSourceIdentityOutput.putchar(66_i32)
  end
end
typed_i32
typed_i64
ProcSourceIdentityOutput.putchar(10_i32)
