lib LibC
  fun putchar(c : Int32) : Int32
end

class InheritedTypedFactoryBase(T)
  def self.build(value : T) : self
    new(value)
  end

  def initialize(@value : T)
  end

  def value : T
    @value
  end
end

class InheritedTypedIntFactory < InheritedTypedFactoryBase(Int32)
  def code : Int32
    value &+ 30
  end
end

class InheritedTypedBoolFactory < InheritedTypedFactoryBase(Bool)
  def code : Int32
    value ? 1 : 0
  end
end

LibC.putchar(InheritedTypedBoolFactory.build(true).code &+ 65)
LibC.putchar(10)
LibC.putchar(InheritedTypedIntFactory.build(7).code &+ 40)
LibC.putchar(10)
LibC.putchar(InheritedTypedBoolFactory.build(false).code &+ 65)
LibC.putchar(10)
LibC.putchar(InheritedTypedIntFactory.build(8).code &+ 40)
LibC.putchar(10)
