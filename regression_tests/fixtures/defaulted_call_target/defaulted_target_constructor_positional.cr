lib LibC
  fun putchar(value : Int32) : Int32
end
class SourcePositional
  def initialize(@pointer : Int64, @size : Int32, @read_only : Bool)
  end
  def self.new(size : Int32, read_only = false) : Int32
    read_only ? 66 : 65
  end
end
LibC.putchar(SourcePositional.new(3))
LibC.putchar(SourcePositional.new(3, true))
LibC.putchar(10)
