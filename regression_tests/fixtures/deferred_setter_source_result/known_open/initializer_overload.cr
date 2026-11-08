lib LibC
  fun putchar(value : Int32) : Int32
end
def pick(value : Int32) : Int32
  65
end
def pick(value : Nil) : Int32
  66
end
class R
  def initialize(value : Int32)
    65
  end
  def initialize
    result = initialize(1)
    LibC.putchar(pick(result))
  end
end
R.new
LibC.putchar(10)
