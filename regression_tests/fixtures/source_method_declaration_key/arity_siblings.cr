lib C
  fun putchar(c : Int32) : Int32
end
module Probe
 def self.value
 66
 end
 def self.value(x)
 67
 end
end
module Probe
 def self.value
 65
 end
end
C.putchar(Probe.value)
C.putchar(Probe.value(1))
C.putchar(10)
