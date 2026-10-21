lib LibC
 fun putchar(value : Int32) : Int32
end
module Initializer(T)
 def initialize(value : T); LibC.putchar(value); end
end
class Probe; include Initializer(Int32); end
Probe.new(71_i32)
