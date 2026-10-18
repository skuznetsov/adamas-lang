lib LibC
  fun putchar(c : Int32) : Int32
end

class InheritedFactoryBase
  def self.build(value : Int32) : InheritedFactoryBase
    new(value)
  end

  def initialize(value : Int32)
  end

  def kind : Int32
    1
  end

  def self.choose(value : Int32) : Int32
    10
  end

  def self.choose(value : Bool) : Int32
    20
  end
end

class InheritedFactoryChild < InheritedFactoryBase
  def self.build(value : Bool, &block : -> Int32) : Int32
    block.call
  end

  def kind : Int32
    2
  end

  def self.choose(value : Bool) : Int32
    30
  end

  def self.choose(value : Float64, &block : -> Int32) : Int32
    block.call
  end
end

LibC.putchar(48 &+ InheritedFactoryChild.build(7).kind)
LibC.putchar(10)
chosen_bool = InheritedFactoryChild.choose(true)
LibC.putchar(chosen_bool &+ 35)
LibC.putchar(10)
chosen_int = InheritedFactoryChild.choose(8)
LibC.putchar(chosen_int &+ 40)
LibC.putchar(10)
