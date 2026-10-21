lib LibC
  fun putchar(value : Int32) : Int32
end
class Parent
 def self.new(value : Int32); LibC.putchar(value); 0_i32; end
end
class Probe < Parent; end
Probe.new(80_i32)
