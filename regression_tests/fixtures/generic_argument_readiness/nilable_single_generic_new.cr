lib LibC
  fun putchar(value : Int32) : Int32
end
class ProbeBox(V)
  def initialize(@capacity : Int32 = 66)
  end
  def capacity : Int32
    @capacity
  end
end
LibC.putchar(ProbeBox(Int64?).new(65).capacity)
LibC.putchar(10)
