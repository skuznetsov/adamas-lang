lib LibC
  fun putchar(value : Int32) : Int32
end
class Probe
 def self.new(value : Int32, flag : Bool); LibC.putchar(value); 0_i32; end
end
Probe.new(69_i32, true)
