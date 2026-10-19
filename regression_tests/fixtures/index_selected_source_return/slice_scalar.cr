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
def accept_byte(value : UInt8) : Int32
  66
end
def run(value : Slice(UInt8), choose : Bool) : Int32
  result = 65_u8
  if choose
    result = value[0]
  end
  accept_byte(result)
end
IndexProbeC.putchar(run(Slice(UInt8).new(65_u8), true))
IndexProbeC.putchar(10)
