class BaseBuffer
  def to_unsafe : UInt8*
    Pointer(UInt8).new(0_u64)
  end
end
class ChildBuffer < BaseBuffer
end
lib C
  fun free(value : UInt8*)
end
C.free(ChildBuffer.new)
