lib LibC
  fun putchar(value : Int32) : Int32
end
class Factory
  def value : Int32.class
    Int32
  end
  def choose(value : Int32.class) : Int32
    65
  end
  def run : Int32
    choose(value)
  end
end
LibC.putchar(Factory.new.run)
LibC.putchar(10)
