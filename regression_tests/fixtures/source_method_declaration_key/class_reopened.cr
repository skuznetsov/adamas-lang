lib C
  fun putchar(c : Int32) : Int32
end
class Probe
  def self.value : Int32
    {% raise "fallback body executed" %}
  end
end
class Probe
  def self.value
    65
  end
end
C.putchar(Probe.value)
C.putchar(10)
