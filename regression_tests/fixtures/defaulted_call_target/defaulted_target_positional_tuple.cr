lib LibC
  fun putchar(value : Int32) : Int32
end
module Probe
  PREFIXES = { {65_i32, 66_i32}, {nil, 67_i32} }
  def self.prefix(value : Int32, group : Int32 = 3, prefixes = PREFIXES) : Int32
    value
  end
  def self.take(value : Int, extra = 0) : Int32
    65_i32
  end
  CALLBACK = ->(value : Int32) do
    value = Probe.prefix(value)
    take(value)
  end
end
LibC.putchar(Probe::CALLBACK.call(3_i32))
