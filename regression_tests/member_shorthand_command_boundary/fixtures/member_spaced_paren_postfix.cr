lib Runtime
  fun putchar(Int32) : Int32
end
class Receiver
  def consume(a : Int32, b : Int32)
    Runtime.putchar(a)
    Runtime.putchar(b)
  end
end

def apply
  yield Receiver.new
end

def mark(value : Int32)
  Runtime.putchar(value)
  value
end

class Argument
  def code
    65
  end
end
Receiver.new.consume (Argument.new).code, 66
Runtime.putchar(10)
