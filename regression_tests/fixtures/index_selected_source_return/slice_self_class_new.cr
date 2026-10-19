lib IndexProbeC
  fun putchar(value : Int32) : Int32
end
struct Slice(T)
  def initialize(@element : T)
  end
  def [](index : Int) : T
    @element
  end
  def [](start : Int, count : Int) : Slice(T)
    self.class.new(@element)
  end
end
def accept_slice(value : Slice(UInt8)) : Int32
  65
end
IndexProbeC.putchar(accept_slice(Slice(UInt8).new(65_u8)[0, 1]))
IndexProbeC.putchar(10)
