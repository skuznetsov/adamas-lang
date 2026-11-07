lib C
  fun putchar(value : Int32) : Int32
end

class Object
  def value : UInt64
    value(7_u64)
  end
end

class Reference < Object
end

class ConcreteReference < Reference
  def value(item)
    item
  end
  def step0 : UInt64
    step1
  end
  def step1 : UInt64
    step2
  end
  def step2 : UInt64
    step3
  end
  def step3 : UInt64
    step4
  end
  def step4 : UInt64
    step5
  end
  def step5 : UInt64
    step6
  end
  def step6 : UInt64
    self.value
  end
end
result = ConcreteReference.new.step0
C.putchar(65) if result == 7_u64
C.putchar(10)
