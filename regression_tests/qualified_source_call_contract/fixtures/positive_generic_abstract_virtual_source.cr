lib LibC
  fun putchar(c : Int32) : Int32
end
abstract class GenericProbeBase(T)
  abstract def generic_probe(value : T) : Int32
end
class GenericProbeChild(T) < GenericProbeBase(T)
  def generic_probe(value : T) : Int32
    71
  end
end
alias GenericProbeBaseInt32 = GenericProbeBase(Int32)
def read_generic_probe(value : GenericProbeBaseInt32) : Int32
  value.generic_probe(1_i32)
end
LibC.putchar(read_generic_probe(GenericProbeChild(Int32).new))
