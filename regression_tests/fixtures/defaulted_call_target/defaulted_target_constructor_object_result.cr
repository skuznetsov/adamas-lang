lib LibC
  fun putchar(value : Int32) : Int32
end
class SourceObject
  def initialize
    @value = 67
  end
  def value : Int32
    @value
  end
  def self.new(size : Int32, *, read_only = false) : self
    LibC.putchar(read_only ? 66 : 65)
    new
  end
end
LibC.putchar(SourceObject.new(3).value)
LibC.putchar(SourceObject.new(3, read_only: true).value)
LibC.putchar(10)
