struct Slice(T)
  def initialize(@element : T)
  end
end

module IndexAliasContract
  alias Result = Slice(UInt8)

  def [](start : Int32, count : Int32) : Result
    Result.new(68_u8)
  end
end

class ReceiverAliasIndex
  include IndexAliasContract
  alias Result = UInt8
end

def accept_element(value : UInt8) : Int32
  68
end

accept_element(ReceiverAliasIndex.new[0, 1])
