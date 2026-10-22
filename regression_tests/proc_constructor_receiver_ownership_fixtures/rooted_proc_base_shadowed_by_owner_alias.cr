require "proc"
lib ProcStructuralOutput
  fun putchar(value : Int32) : Int32
end
module RootedProcBaseShadowOwner
  alias Proc = Int64
  def self.make
    ::Proc(Int32, Int32).new { |value| value }
  end
end
if RootedProcBaseShadowOwner.make.call(65_i32) == 65_i32
  ProcStructuralOutput.putchar(65_i32)
end
ProcStructuralOutput.putchar(10_i32)
