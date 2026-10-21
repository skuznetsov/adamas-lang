lib LibC
  fun putchar(value : Int32) : Int32
end
class Probe
 def initialize(value : Int32); end
end
alias AliasProbe = Probe
AliasProbe.new(1_i32)
LibC.putchar(65)
