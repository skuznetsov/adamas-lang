lib LibC
  fun putchar(value : Int32) : Int32
end

module Base
  alias Result = Int32

  def value(x : Result) : Result
    x
  end
end

class Probe
  alias Result = String
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
