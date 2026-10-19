lib IndexAliasProbeC
  fun putchar(value : Int32) : Int32
end

struct Slice(T)
  def initialize(@element : T)
  end
end

class DirectAliasIndex
  alias Result = Slice(UInt8)

  def [](start : Int32, count : Int32) : Result
    Result.new(65_u8)
  end
end

def accept_slice(value : Slice(UInt8)) : Int32
  65
end

IndexAliasProbeC.putchar(accept_slice(DirectAliasIndex.new[0, 1]))
