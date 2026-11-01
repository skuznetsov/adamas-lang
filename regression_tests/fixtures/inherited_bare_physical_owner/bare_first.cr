lib LibC
  fun putchar(value : Int32) : Int32
end
class PhysicalOwnerParent
  def value : Int32
    65
  end
end
class PhysicalOwnerChild < PhysicalOwnerParent
  def value(item)
    item
  end
end
def report(value : String) : Int32
  66
end
def report(value : Int32) : Int32
  value
end
child = PhysicalOwnerChild.new
LibC.putchar(report(child.value))
LibC.putchar(report(child.value("B")))
LibC.putchar(10)
