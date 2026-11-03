lib LibC
  fun putchar(value : Int32) : Int32
end
class SourceParent
  def initialize(@pointer : Int64, @size : Int32, @read_only : Bool)
  end
  def self.new(size : Int32, *, read_only = false) : Int32
    read_only ? 66 : 65
  end
end
class SourceChild < SourceParent
end
LibC.putchar(SourceChild.new(3))
LibC.putchar(SourceChild.new(3, read_only: true))
LibC.putchar(10)
