struct Slice(T)
  def initialize(@element : T)
  end
end

module GenericIndexContract(T)
  def [](start : Int32, count : Int32) : Slice(T)
    Slice(T).new(65_u8)
  end
end

class GenericIndexCaller(T)
  include GenericIndexContract(UInt8)
end

def accept_word_slice(value : Slice(UInt16)) : Int32
  66
end

accept_word_slice(GenericIndexCaller(UInt16).new[0, 1])
