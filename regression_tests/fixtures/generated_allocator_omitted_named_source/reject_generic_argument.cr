lib ConstructorProbeC
  fun putchar(value : Int32) : Int32
end
class Wrapper(T)
  @marker : Int32 = 1
  def initialize(@value : T)
  end
end
class GenericRestrictionConstructor
  @marker : Int32 = 1
  def initialize(value : Wrapper(Int32), *, read_only : Bool = false)
  end
  def self.new(value : Int32)
    new(Wrapper(Int32).new(value))
  end
end
GenericRestrictionConstructor.new(Wrapper(String).new("wrong"))
