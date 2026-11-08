lib LibC
  fun putchar(value : Int32) : Int32
end
def pick(value : Int32) : Int32
  65
end
def pick(value : Bool) : Int32
  66
end
class Box
  def value=(value : Int32)
    false
  end
  def []=(index : Int32, value : Int32)
    false
  end
end
box = Box.new
LibC.putchar(pick(box.value = 42))
LibC.putchar(pick(box.value=(42)))
LibC.putchar(pick(box[0] = 42))
LibC.putchar(pick(box.[]=(0, 42)))
LibC.putchar(10)
