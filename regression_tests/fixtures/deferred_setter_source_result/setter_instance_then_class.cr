lib LibC
  fun putchar(value : Int32) : Int32
end

class Box
  def value=(value : Int32)
    65
  end

  def value=(value : Int32.class)
    66
  end
end

def via_class0
  via_class1
end
def via_class1
  via_class2
end
def via_class2
  via_class3
end
def via_class3
  via_class4
end
def via_class4
  via_class5
end
def via_class5
  via_class6
end
def via_class6
  via_class7
end
def via_class7
  via_class8
end
def via_class8
  via_class9
end
def via_class9
  Box.new.value = Int32
end

LibC.putchar(Box.new.value = 1)
LibC.putchar(via_class0)
LibC.putchar(10)
