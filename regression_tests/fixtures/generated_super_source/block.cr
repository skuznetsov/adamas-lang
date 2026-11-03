lib LibC
  fun putchar(value : Int32) : Int32
end

module Base
  def value(x : Int32)
    visit(x) { |y| y }
  end

  def visit(x : Int32, &block : Int32 -> Int32) : Int32
    yield x
  end
end

class Probe
  include Base

  def value(x : Int32)
    super
  end
end

def consume(value : Int32) : Int32
  value
end

LibC.putchar(consume(Probe.new.value(65)))
LibC.putchar(10)
