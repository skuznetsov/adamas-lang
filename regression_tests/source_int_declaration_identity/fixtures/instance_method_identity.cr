lib C
  fun putchar(value : Int32) : Int32
end
class Probe
  def choose(value : Int32)
    C.putchar(68)
  end
  def choose(value : Int)
    missing_unused_broad_body
  end
end
Probe.new.choose(1_i32)
