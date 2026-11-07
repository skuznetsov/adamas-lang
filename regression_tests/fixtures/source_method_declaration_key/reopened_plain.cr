lib C
  fun putchar(c : Int32) : Int32
end
module Probe
  def self.value
    66
  end
end
module Probe
  def self.value
    65
  end
end
C.putchar(Probe.value)
C.putchar(10)
