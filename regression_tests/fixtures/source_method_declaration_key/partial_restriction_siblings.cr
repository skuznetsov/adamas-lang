lib C
  fun putchar(c : Int32) : Int32
end
module Probe
 def self.value(x : Int32, y)
 66
 end
 def self.value(x : Bool, y)
 67
 end
end
module Probe
 def self.value(x : Int32, y)
 65
 end
end
C.putchar(Probe.value(1, 2))
C.putchar(Probe.value(false, 2))
C.putchar(10)
