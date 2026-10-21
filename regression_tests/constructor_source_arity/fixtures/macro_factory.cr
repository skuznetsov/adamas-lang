lib LibC
 fun putchar(value : Int32) : Int32
end
class Probe
 {% begin %}
 def self.new(value : Int32); LibC.putchar(value); 0_i32; end
 {% end %}
end
Probe.new(66_i32)
