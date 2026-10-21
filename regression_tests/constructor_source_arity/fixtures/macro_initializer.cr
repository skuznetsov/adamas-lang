lib LibC
 fun putchar(value : Int32) : Int32
end
class Probe
 {% begin %}
 def initialize(value : Int32); LibC.putchar(value); end
 {% end %}
end
Probe.new(65_i32)
