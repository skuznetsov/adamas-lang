lib Output
  fun putchar(value : Int32) : Int32
end
class BaseShape
  def value(input : Int32) : Int32
    input
  end
  def run : Int32
    value()
  end
end
class ChildShape < BaseShape
  def value : Int32
    65
  end
end
Output.putchar(BaseShape.new.run)
Output.putchar(10)
