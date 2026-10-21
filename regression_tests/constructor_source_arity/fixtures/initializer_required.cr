lib LibC
  fun putchar(value : Int32) : Int32
end
class Probe
 def initialize(value : Int32, flag : Bool); LibC.putchar(value); end
end
Probe.new(73_i32, true)
