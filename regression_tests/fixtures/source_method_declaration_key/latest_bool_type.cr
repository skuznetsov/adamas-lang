lib C
  fun putchar(c : Int32) : Int32
end
module Probe
 def self.value
 65
 end
end
module Probe
 def self.value
 false
 end
end
if Probe.value
 C.putchar(65)
else
 C.putchar(66)
end
C.putchar(10)
