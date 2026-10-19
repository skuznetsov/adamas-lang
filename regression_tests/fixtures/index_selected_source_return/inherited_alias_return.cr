lib InheritedIndexProbeC
  fun putchar(value : Int32) : Int32
end

struct Slice(T)
  def initialize(@element : T)
  end
end

class BaseAliasIndex
  alias Result = Slice(UInt8)
  def [](start : Int32, count : Int32) : Result
    Result.new(65_u8)
  end
end

class ChildAliasIndex < BaseAliasIndex
  alias Result = UInt8
end

def accept_byte_slice(value : Slice(UInt8)) : Int32
  65
end
InheritedIndexProbeC.putchar(accept_byte_slice(ChildAliasIndex.new[0, 1]))
