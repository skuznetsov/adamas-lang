lib LibC
  fun putchar(value : Int32) : Int32
end
def emit_rest
  LibC.putchar(48)
end
def emit_rest(first : Int32)
  LibC.putchar(49)
  LibC.putchar(first)
end
class Constructed
  @tag : Int32
  def initialize(@tag : Int32 = 65, *items, suffix : Int32 = 90)
    emit_rest(*items)
    LibC.putchar(suffix)
  end
  def tag : Int32
    @tag
  end
end
LibC.putchar(Constructed.new.tag)
LibC.putchar(Constructed.new(66, 67, suffix: 68).tag)
LibC.putchar(Constructed.new(69, 70).tag)
LibC.putchar(10)
