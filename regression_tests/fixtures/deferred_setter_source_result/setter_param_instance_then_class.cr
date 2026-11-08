lib LibC
  fun putchar(value : Int32) : Int32
end
class Box
  def value=(value : Int32)
    value
  end
  def value=(value : Int32.class)
    value
  end
  def pick(value : Int32) : Int32
    65
  end
  def pick(value : Int32.class) : Int32
    66
  end
  def instance_route : Int32
    self.pick(self.value = 1)
  end
  def class_route : Int32
    self.pick(self.value = Int32)
  end
end
def instance_route_chain0(box : Box)
  instance_route_chain1(box)
end
def instance_route_chain1(box : Box)
  instance_route_chain2(box)
end
def instance_route_chain2(box : Box)
  instance_route_chain3(box)
end
def instance_route_chain3(box : Box)
  instance_route_chain4(box)
end
def instance_route_chain4(box : Box)
  instance_route_chain5(box)
end
def instance_route_chain5(box : Box)
  instance_route_chain6(box)
end
def instance_route_chain6(box : Box)
  instance_route_chain7(box)
end
def instance_route_chain7(box : Box)
  instance_route_chain8(box)
end
def instance_route_chain8(box : Box)
  instance_route_chain9(box)
end
def instance_route_chain9(box : Box)
  box.instance_route
end
def class_route_chain0(box : Box)
  class_route_chain1(box)
end
def class_route_chain1(box : Box)
  class_route_chain2(box)
end
def class_route_chain2(box : Box)
  class_route_chain3(box)
end
def class_route_chain3(box : Box)
  class_route_chain4(box)
end
def class_route_chain4(box : Box)
  class_route_chain5(box)
end
def class_route_chain5(box : Box)
  class_route_chain6(box)
end
def class_route_chain6(box : Box)
  class_route_chain7(box)
end
def class_route_chain7(box : Box)
  class_route_chain8(box)
end
def class_route_chain8(box : Box)
  class_route_chain9(box)
end
def class_route_chain9(box : Box)
  box.class_route
end
box = Box.new
LibC.putchar(instance_route_chain0(box))
LibC.putchar(class_route_chain0(box))
LibC.putchar(10)
