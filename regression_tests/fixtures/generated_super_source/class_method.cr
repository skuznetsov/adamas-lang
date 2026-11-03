lib LibC
  fun putchar(value : Int32) : Int32
end

class Base
  alias Result = Int32

  def self.value(x : Result) : Result
    x
  end
end

class Probe < Base
  alias Result = String

  def self.value(x : Int32)
    super
  end
end

def consume(value : Int32) : Int32
  value
end

LibC.putchar(consume(Probe.value(65)))
LibC.putchar(10)
