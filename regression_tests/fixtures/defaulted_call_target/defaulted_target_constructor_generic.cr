lib LibC
  fun putchar(value : Int32) : Int32
end
class SourceGeneric(T)
  def initialize(@pointer : T, @size : Int32, @read_only : Bool)
  end
  def self.new(size : Int32, *, read_only = false) : Int32
    read_only ? 66 : 65
  end
end
LibC.putchar(SourceGeneric(Int64).new(3))
LibC.putchar(SourceGeneric(Int64).new(3, read_only: true))
LibC.putchar(10)
