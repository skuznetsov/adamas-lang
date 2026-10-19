lib GenericModuleIndexProbeC
  fun putchar(value : Int32) : Int32
end

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

def accept_byte_slice(value : Slice(UInt8)) : Int32
  65
end

GenericModuleIndexProbeC.putchar(accept_byte_slice(GenericIndexCaller(UInt16).new[0, 1]))
