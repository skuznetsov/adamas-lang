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

def select_carrier(value : Int64) : Int32
  if value == 4_294_967_299_i64
    C.putchar(67)
  else
    C.putchar(88)
  end
  0
end

enum Int64WideCarrier : Int64
  Wide = 4_294_967_299

  def route_value : Int32
    select_carrier(value)
  end
end

Int64WideCarrier::Wide.route_value
C.putchar(10)
