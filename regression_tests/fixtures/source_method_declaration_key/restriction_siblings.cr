lib C
  fun putchar(c : Int32) : Int32
end
module Probe
 def self.value(x : Int32)
 66
 end
 def self.value(x : Bool)
 67
 end
end
module Probe
 def self.value(x : Int32)
 65
 end
end
C.putchar(Probe.value(1))
C.putchar(Probe.value(false))
C.putchar(10)
