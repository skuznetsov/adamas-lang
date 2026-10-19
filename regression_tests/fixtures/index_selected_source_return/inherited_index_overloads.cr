lib IndexProbeC
  fun putchar(value : Int32) : Int32
end
struct Slice(T)
  def initialize(@element : T)
  end
end
class IndexParent(T)
  def initialize(@element : T)
  end
  def [](index : UInt8) : T
    @element
  end
end
class IndexChild(T) < IndexParent(T)
  def [](index : Int32) : Slice(T)
    Slice(T).new(self[0_u8])
  end
end
def accept_u8(value : UInt8) : Int32
  69
end
def accept_slice_u8(value : Slice(UInt8)) : Int32
  70
end
child = IndexChild(UInt8).new(69_u8)
IndexProbeC.putchar(accept_u8(child[0_u8]))
IndexProbeC.putchar(accept_slice_u8(child[0]))
IndexProbeC.putchar(10)
