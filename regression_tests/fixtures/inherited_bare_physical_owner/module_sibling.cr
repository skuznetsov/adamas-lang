lib LibC
  fun putchar(value : Int32) : Int32
end
class PhysicalOwnerParent
  def value : Int32
    65
  end
end
module PhysicalOwnerModule(T)
  def chosen(item : T)
    item
  end
  def value(item)
    chosen(item)
  end
end
class PhysicalOwnerChild < PhysicalOwnerParent
  include PhysicalOwnerModule(String)
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
LibC.putchar(report(child.value))
LibC.putchar(10)
