lib IndexProbeC
  fun putchar(value : Int32) : Int32
end
struct Range(B, E)
  def initialize(@begin : B, @end : E, @exclusive : Bool = false)
  end
end
struct Slice(T)
  def initialize(@element : T)
  end
  def [](index : Int) : T
    @element
  end
  def [](start : Int, count : Int) : Slice(T)
    self
  end
  def [](range : Range) : Slice(T)
    self
  end
end
def accept_element(value : UInt8) : Int32
  65
end
IndexProbeC.putchar(accept_element(Slice(UInt8).new(65_u8)[0, 1]))
