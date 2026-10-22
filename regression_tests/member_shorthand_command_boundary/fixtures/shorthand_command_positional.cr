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
apply &.consume mark(65), mark(66)
Runtime.putchar(10)
