lib LibC
  fun putchar(value : Int32) : Int32
end

struct Box(T)
  def helper : Int32
    67
  end

  def apply : Int32
    helper
  end
end

box = Box(Proc(Int32.class, Int32)).new
LibC.putchar(box.apply)
LibC.putchar(10)
