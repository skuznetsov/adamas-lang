lib LibC
  fun putchar(value : Int32) : Int32
end
class Probe
 def self.new(value : Int32 = 70_i32); LibC.putchar(value); 0_i32; end
end
Probe.new
