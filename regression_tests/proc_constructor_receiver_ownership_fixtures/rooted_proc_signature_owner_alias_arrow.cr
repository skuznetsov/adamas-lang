require "proc"

lib ProcConstructorFactOutput
  fun putchar(value : Int32) : Int32
end

module RootedProcArrowOwnerPositive
  alias Proc = ::Proc(String, String)

  def self.make : ::Proc(Int32, Int32)
    ->(value : Int32) : Int32 { value }
  end
end

callback = RootedProcArrowOwnerPositive.make
if callback.call(67_i32) == 67_i32
  ProcConstructorFactOutput.putchar(67_i32)
end
ProcConstructorFactOutput.putchar(10_i32)
