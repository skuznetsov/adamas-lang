lib LibC
  fun putchar(value : Int32) : Int32
end
class Parent
 def initialize(value : Int32, flag : Bool); LibC.putchar(value); end
end
class Probe < Parent; end
Probe.new(72_i32, true)
