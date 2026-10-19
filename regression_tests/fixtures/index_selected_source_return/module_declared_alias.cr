lib IndexAliasProbeC
  fun putchar(value : Int32) : Int32
end

struct Slice(T)
  def initialize(@element : T)
  end
end

module IndexAliasContract
  alias Result = Slice(UInt8)

  def [](start : Int32, count : Int32) : Result
    Result.new(66_u8)
  end
end

class ReceiverAliasIndex
  include IndexAliasContract
  alias Result = UInt8
end

def accept_slice(value : Slice(UInt8)) : Int32
  66
end

IndexAliasProbeC.putchar(accept_slice(ReceiverAliasIndex.new[0, 1]))
