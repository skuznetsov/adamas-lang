lib C
  fun putchar(c : Int32) : Int32
end

def select_carrier(v : UInt8) : Int32
  C.putchar(65)
  0
end

def select_carrier(v : Int32) : Int32
  C.putchar(88)
  0
end

class PlainAbstractNumeric
  def number : Int
    7_u8
  end

  def route : Int32
    select_carrier(number)
  end
end

PlainAbstractNumeric.new.route
C.putchar(10)
