lib C
  fun putchar(value : Int32) : Int32
end
module Space
  alias Integral = Int
  class Probe
    def self.choose(value : Int32)
      C.putchar(69)
    end
    def self.choose(value : Integral)
      missing_unused_broad_body
    end
  end
end
Space::Probe.choose(1_i32)
