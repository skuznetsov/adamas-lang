lib LibC
  fun putchar(value : Int32) : Int32
end
class Probe
 def initialize(value : Int32 = 68_i32); LibC.putchar(value); end
end
Probe.new
