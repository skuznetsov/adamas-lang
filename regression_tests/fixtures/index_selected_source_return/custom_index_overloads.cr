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
struct IndexOwner
  def [](index : Int) : Int32
    67
  end
  def [](start : Int, count : Int) : Slice(UInt8)
    Slice(UInt8).new(65_u8)
  end
end
def accept_slice(value : Slice(UInt8)) : Int32
  68
end
def run(value : IndexOwner, choose : Bool) : Int32
  result = Slice(UInt8).new(65_u8)
  if choose
    result = value[0, 1]
  end
  accept_slice(result)
end
IndexProbeC.putchar(IndexOwner.new[0])
IndexProbeC.putchar(run(IndexOwner.new, true))
IndexProbeC.putchar(10)
