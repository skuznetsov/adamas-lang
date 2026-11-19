lib LibC
  fun putchar(value : Int32) : Int32
end

struct StackSlot(N)
  def initialize
    @length = 1_u16
  end

  def size=(@length : UInt16) : UInt16
    @length
  end
end

class Marker
  def exact=(value : Int32) : Int32
    LibC.putchar(67)
  end

  def exact=(value : UInt16) : Int32
    LibC.putchar(88)
  end

  def wide=(value : UInt16) : Bool
    LibC.putchar(value == 7_u16 ? 69 : 88)
    false
  end

  def narrow_value : UInt8
    LibC.putchar(68)
    7_u8
  end
end

def check(value : Bool) : Int32
  value ? 88 : 70
end

slot = StackSlot(62).new
LibC.putchar((slot.size = 0) == 0_u16 ? 65 : 88)
LibC.putchar((slot.size = 65535_i32) == 65535_u16 ? 66 : 88)
marker = Marker.new
marker.exact = 0
LibC.putchar(check(marker.wide = marker.narrow_value))
LibC.putchar(10)
