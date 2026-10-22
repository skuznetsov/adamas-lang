require "proc"
lib ProcSourceIdentityOutput
  fun putchar(value : Int32) : Int32
end
module ProcSourceOwner
  alias Argument = Int32
  alias Result = Int64
  def self.make
    ->(value : Argument) : Result { 65_i64 }
  end
end
if ProcSourceOwner.make.call(1_i32) == 65_i64
  ProcSourceIdentityOutput.putchar(65_i32)
end
ProcSourceIdentityOutput.putchar(10_i32)
