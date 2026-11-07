lib C
 fun putchar(c : Int32) : Int32
end
module Probe
 def self.value
 65
 end
 def self.value(&)
 yield
 end
end
C.putchar(Probe.value)
C.putchar(Probe.value { 67 })
C.putchar(10)
