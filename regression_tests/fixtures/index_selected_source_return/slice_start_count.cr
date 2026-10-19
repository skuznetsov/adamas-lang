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
def accept_slice(value : Slice(UInt8)) : Int32
  65
end
def run(value : Slice(UInt8), choose : Bool) : Int32
  result = value
  if choose
    result = value[0, 1]
  end
  accept_slice(result)
end
IndexProbeC.putchar(run(Slice(UInt8).new(65_u8), true))
IndexProbeC.putchar(run(Slice(UInt8).new(65_u8), false))
IndexProbeC.putchar(10)
