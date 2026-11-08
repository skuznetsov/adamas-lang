lib LibC
  fun putchar(value : Int32) : Int32
end

def pick(value : Int32.class) : Int32
  65
end

def pick(value : Int32) : Int32
  66
end

class Box
  def value=(value : Int32)
    Int32
  end
end

LibC.putchar(pick(Box.new.value = 1))
LibC.putchar(10)
