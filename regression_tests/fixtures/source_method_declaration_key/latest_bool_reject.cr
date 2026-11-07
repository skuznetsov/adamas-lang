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
C.putchar(Probe.value)
