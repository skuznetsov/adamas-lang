lib LibC
  fun putchar(value : Int32) : Int32
end
class Parent
 def initialize(value : Int32, flag : Bool); end
end
class Probe < Parent; end
Probe.new(1_i32)
