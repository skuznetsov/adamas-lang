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

def via_instance0
  via_instance1
end
def via_instance1
  via_instance2
end
def via_instance2
  via_instance3
end
def via_instance3
  via_instance4
end
def via_instance4
  via_instance5
end
def via_instance5
  via_instance6
end
def via_instance6
  via_instance7
end
def via_instance7
  via_instance8
end
def via_instance8
  via_instance9
end
def via_instance9
  Box.new.value = 1
end

LibC.putchar(Box.new.value = Int32)
LibC.putchar(via_instance0)
LibC.putchar(10)
