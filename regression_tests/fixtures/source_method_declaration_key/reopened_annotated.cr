lib C
  fun putchar(c : Int32) : Int32
end
module Probe
  def self.value : Int32
    {% raise "fallback body executed" %}
  end
end
module Probe
  def self.value
    65
  end
end
C.putchar(Probe.value)
C.putchar(10)
