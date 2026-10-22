require "proc"
lib ProcSourceIdentityOutput
  fun putchar(value : Int32) : Int32
end
def identity_callback(input : T) forall T
  ->(value : T) : T { value }
end
ProcSourceIdentityOutput.putchar(identity_callback(1_i32).call(65_i32))
ProcSourceIdentityOutput.putchar(10_i32)
