lib LibC
  fun putchar(value : Int32) : Int32
end
macro install
  def self.generated
    65
  end
end
class Shadow
  def self.install
    66
  end
  install
end
LibC.putchar(Shadow.generated)
LibC.putchar(10)
