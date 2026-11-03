lib LibC
  fun putchar(value : Int32) : Int32
end
module AFirst
  def value(x : Int32) : Int32
    66
  end
end
module ZLast
  def value(x : Int32) : Int32
    x
  end
end
class Probe
  include AFirst
  include ZLast
  def value(x : Int32)
    super
  end
end
def consume(x : Int32)
  LibC.putchar(x)
end
consume(Probe.new.value(65))
LibC.putchar(10)
