lib LibC
  fun putchar(c : Int32) : Int32
end

class OrdinaryFactoryBase
  def self.build(parent value : Int32) : self
    new(value)
  end

  def initialize(@value : Int32)
  end

  def code : Int32
    66
  end
end

class OrdinaryFactoryChild < OrdinaryFactoryBase
  def code : Int32
    68
  end
end

LibC.putchar(OrdinaryFactoryChild.build(parent: 1).code)
LibC.putchar(10)
