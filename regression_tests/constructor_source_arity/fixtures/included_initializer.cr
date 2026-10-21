lib LibC
 fun putchar(value : Int32) : Int32
end
module Initializer
 def initialize(value : Int32); LibC.putchar(value); end
end
class Probe; include Initializer; end
Probe.new(77_i32)
