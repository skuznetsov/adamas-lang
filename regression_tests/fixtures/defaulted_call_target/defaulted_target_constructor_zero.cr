lib LibC
  fun putchar(value : Int32) : Int32
end
class SourceZero
  def initialize(@pointer : Int64, @size : Int32, @read_only : Bool)
  end
  def self.new(size : Int32 = 3, *, read_only = false) : Int32
    read_only ? 66 : 65
  end
end
LibC.putchar(SourceZero.new)
LibC.putchar(SourceZero.new())
LibC.putchar(SourceZero.new(read_only: true))
LibC.putchar(10)
