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

def accept_element(value : UInt8) : Int32
  66
end
accept_element(ChildAliasIndex.new[0, 1])
