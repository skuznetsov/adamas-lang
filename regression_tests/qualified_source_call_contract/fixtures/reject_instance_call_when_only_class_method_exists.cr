lib LibC
  fun putchar(c : Int32) : Int32
end
class ClassSideOnlyProbe
  def self.side_probe : Int32
    65
  end
  def self.invoke(value : ClassSideOnlyProbe) : Int32
    value.side_probe
  end
end
LibC.putchar(ClassSideOnlyProbe.invoke(ClassSideOnlyProbe.new))
