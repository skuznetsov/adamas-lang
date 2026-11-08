lib Output
  fun putchar(value : Int32) : Int32
end
class SelfCallShapes
  def optional(input : Int32 = 65) : Int32
    input
  end
  def collected(*items) : Int32
    66
  end
  def overloaded(input : Int32) : Int32
    67
  end
  def overloaded : Int32
    overloaded(0)
  end
  def run
    Output.putchar(optional)
    Output.putchar(collected)
    Output.putchar(overloaded)
  end
end
SelfCallShapes.new.run
Output.putchar(10)
