lib ConstructorProbeC
  fun putchar(value : Int32) : Int32
end
class GenericNamedConstructor(T)
  @marker : Int32 = 1
  def initialize(value : T, *, read_only : Bool = false)
    ConstructorProbeC.putchar(read_only ? 88 : value.to_i)
  end
  def self.new(value : String)
    new(89)
  end
end
GenericNamedConstructor(Int32).new(65)
GenericNamedConstructor(UInt8).new(66_u8)
