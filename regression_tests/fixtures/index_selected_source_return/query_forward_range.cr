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
  def []?(index : Int) : T?
    @element
  end
  def []?(start : Int, count : Int) : Slice(T)?
    self
  end
  def [](start : Int, count : Int) : Slice(T)
    self[start, count]? || self
  end
  def [](range : Range) : Slice(T)
    self[0, 1]
  end
  def +(offset : Int) : Slice(T)
    self
  end
end
def accept_slice(value : Slice(UInt8)) : Int32
  65
end
def accept_byte(value : UInt8) : Int32
  value.to_i32
end
def run(value : Slice(UInt8), choose : Bool) : Int32
  result = value
  if choose
    zone = value[1..] + 1
    result = value[0, 1]
    accept_slice(zone)
    accept_byte(value[0])
  end
  accept_slice(result)
end
IndexProbeC.putchar(run(Slice(UInt8).new(65_u8), true))
IndexProbeC.putchar(run(Slice(UInt8).new(65_u8), false))
IndexProbeC.putchar(10)
