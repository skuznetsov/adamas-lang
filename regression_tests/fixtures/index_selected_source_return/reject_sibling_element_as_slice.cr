struct Slice(T)
  def initialize(@element : T)
  end
end
struct DualIndex(T, U)
  def initialize(@first : T, @second : U)
  end
  def [](index : UInt8) : U
    @second
  end
  def [](index : Int) : Slice(U)
    Slice(U).new(@second)
  end
end
def accept_slice_u16(value : Slice(UInt16)) : Int32
  65
end
accept_slice_u16(DualIndex(UInt8, UInt16).new(1_u8, 66_u16)[0_u8])
