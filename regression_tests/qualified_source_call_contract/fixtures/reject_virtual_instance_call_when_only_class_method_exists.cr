lib LibC
  fun putchar(c : Int32) : Int32
end
abstract class VirtualSideOnlyProbe
  abstract def required_instance_probe : Int32
  def self.virtual_side_probe : Int32
    65
  end
end
class VirtualSideOnlyProbeChild < VirtualSideOnlyProbe
  def required_instance_probe : Int32
    66
  end
end
def invoke_missing_virtual_side(value : VirtualSideOnlyProbe) : Int32
  value.virtual_side_probe
end
LibC.putchar(invoke_missing_virtual_side(VirtualSideOnlyProbeChild.new))
