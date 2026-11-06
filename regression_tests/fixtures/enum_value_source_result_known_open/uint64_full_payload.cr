lib C
  fun putchar(c : Int32) : Int32
end

abstract struct Enum
  def value : Int
    previous_def
  end
end

def select_carrier(value : Int32) : Int32
  C.putchar(73)
  0
end

def select_carrier(value : UInt64) : Int32
  if value == 18_446_744_073_709_551_614_u64
    C.putchar(67)
  else
    C.putchar(88)
  end
  0
end

enum UInt64WideCarrier : UInt64
  Wide = 18_446_744_073_709_551_614

  def route_value : Int32
    select_carrier(value)
  end
end

UInt64WideCarrier::Wide.route_value
C.putchar(10)
