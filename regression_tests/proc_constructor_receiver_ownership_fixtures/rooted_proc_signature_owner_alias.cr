require "proc"

lib ProcConstructorFactOutput
  fun putchar(value : Int32) : Int32
end

module RootedProcSignatureOwnerPositive
  alias Proc = ::Proc(String, String)

  def self.make : ::Proc(Int32, Int32)
    ::Proc(Int32, Int32).new { |value| value }
  end
end

callback = RootedProcSignatureOwnerPositive.make
if callback.call(65_i32) == 65_i32
  ProcConstructorFactOutput.putchar(65_i32)
end
ProcConstructorFactOutput.putchar(10_i32)
