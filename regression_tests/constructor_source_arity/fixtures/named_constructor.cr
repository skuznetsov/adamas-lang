lib LibC
  fun putchar(value : Int32) : Int32
end
class Probe
 def initialize(value : Int32, flag : Bool); LibC.putchar(value); end
end
Probe.new(flag: true, value: 78_i32)
