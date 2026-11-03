lib LibC
  fun putchar(value : Int32) : Int32
end
class PlainDefaultOwner
  def initialize(@pointer : Int64, @size : Int32, @read_only : Bool)
  end
  def self.new(size : Int32, *, read_only = false) : Int32
    read_only ? 66 : 65
  end
end
LibC.putchar(PlainDefaultOwner.new(3))
LibC.putchar(PlainDefaultOwner.new(3, read_only: true))
LibC.putchar(10)
