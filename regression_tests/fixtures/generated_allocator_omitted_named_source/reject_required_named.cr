lib ConstructorProbeC
  fun putchar(value : Int32) : Int32
end
class RequiredNamedConstructor
  @marker : Int32 = 1
  def initialize(value : Int32, *, read_only : Bool)
    ConstructorProbeC.putchar(value)
  end
  def self.new(value : String)
    new(88, read_only: true)
  end
end
RequiredNamedConstructor.new(65)
