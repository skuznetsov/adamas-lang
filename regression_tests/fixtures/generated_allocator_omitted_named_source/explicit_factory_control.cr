lib ConstructorProbeC
  fun putchar(value : Int32) : Int32
end
class OmittedNamedConstructor
  @marker : Int32 = 1
  def initialize(value : Int32, *, read_only : Bool = false)
    ConstructorProbeC.putchar(read_only ? 88 : value)
  end
  def self.new(value : String)
    new(66)
  end
end
OmittedNamedConstructor.new("factory")
OmittedNamedConstructor.new(67)
