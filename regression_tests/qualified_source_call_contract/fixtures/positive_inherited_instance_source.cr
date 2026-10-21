lib LibC
  fun putchar(c : Int32) : Int32
end
class InheritedProbeBase
  def inherited_probe : Int32
    72
  end
end
class InheritedProbeChild < InheritedProbeBase
end
def read_inherited_probe(value : InheritedProbeChild) : Int32
  value.inherited_probe
end
LibC.putchar(read_inherited_probe(InheritedProbeChild.new))
