lib ConstructorProbeC
  fun putchar(value : Int32) : Int32
end
class PositionalDefaultConstructor
  @marker : Int32 = 1
  def initialize(value : Int32, suffix : Int32 = 68, *, read_only : Bool = false)
    ConstructorProbeC.putchar(value)
    ConstructorProbeC.putchar(read_only ? 88 : suffix)
  end
  def self.new(value : String)
    new(88, 89)
  end
end
PositionalDefaultConstructor.new(65)
PositionalDefaultConstructor.new(66, 67)
