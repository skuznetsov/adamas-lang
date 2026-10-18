lib LibC
  fun putchar(c : Int32) : Int32
end

class InheritedGenericFactoryBase(T)
  def self.build(value : T) : self
    new(value)
  end

  def initialize(@value : T)
  end

  def kind : Int32
    1
  end
end

class InheritedGenericFactoryChild(T) < InheritedGenericFactoryBase(T)
  def self.build(value : Bool, &block : -> Int32) : Int32
    block.call
  end

  def kind : Int32
    2
  end
end

LibC.putchar(48 &+ InheritedGenericFactoryChild(Int32).build(7).kind)
LibC.putchar(10)
