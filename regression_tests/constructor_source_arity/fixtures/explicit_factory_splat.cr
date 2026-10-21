lib LibC
  fun putchar(value : Int32) : Int32
end
class Probe
 def self.new(*values : Int32); LibC.putchar(83); 0_i32; end
end
Probe.new(1_i32, 2_i32, 3_i32)
