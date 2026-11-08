lib LibC
  fun putchar(value : Int32) : Int32
end

class Box
  def value=(value : Int32.class)
    value
  end
end

def accept(value : Int32.class) : Int32
  65
end

LibC.putchar(accept(Box.new.value = Int32))
LibC.putchar(10)
