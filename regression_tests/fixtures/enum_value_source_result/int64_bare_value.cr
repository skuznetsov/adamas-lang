lib C
  fun putchar(c : Int32) : Int32
end

# Mirror the stock Enum#value source body. These calls are made from another
# Enum instance method through a bare identifier, not through `obj.value`.
abstract struct Enum
  def value : Int
    previous_def
  end
end

def select_carrier(value : Int64) : Int32
  C.putchar(67)
  0
end

enum Int64Carrier : Int64
  Answer = 3

  def route_value : Int32
    select_carrier(value)
  end
end

Int64Carrier::Answer.route_value
C.putchar(10)
