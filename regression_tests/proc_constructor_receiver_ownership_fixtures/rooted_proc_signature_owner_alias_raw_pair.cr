require "proc"

lib ProcConstructorFactOutput
  fun putchar(value : Int32) : Int32
end

module RootedProcRawPairOwnerPositive
  alias Proc = ::Proc(String, String)

  def self.make
    ::Proc(Int32, Int32).new(Pointer(Void).new(0_u64), Pointer(Void).new(0_u64))
  end
end

callback = RootedProcRawPairOwnerPositive.make
ProcConstructorFactOutput.putchar(82_i32)
ProcConstructorFactOutput.putchar(10_i32)
