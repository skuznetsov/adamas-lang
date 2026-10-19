lib IndexProbeC
  fun putchar(value : Int32) : Int32
end
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
def accept_u16(value : UInt16) : Int32
  67
end
def accept_slice_u16(value : Slice(UInt16)) : Int32
  68
end
owner = DualIndex(UInt8, UInt16).new(1_u8, 66_u16)
IndexProbeC.putchar(accept_u16(owner[0_u8]))
IndexProbeC.putchar(accept_slice_u16(owner[0]))
IndexProbeC.putchar(10)
