require "./factory_macro"

lib LibC
  fun putchar(c : Int32) : Int32
end

class ExplicitConstructorBase
  build_factory(parent, ExplicitConstructorBase, ExplicitConstructorBase.new(value))

  def initialize(@value : Int32)
  end

  def code : Int32
    66
  end
end

class ExplicitConstructorChild < ExplicitConstructorBase
  build_factory(foster, Int32, 67)

  def code : Int32
    68
  end
end

LibC.putchar(ExplicitConstructorChild.build(parent: 1).code)
LibC.putchar(ExplicitConstructorChild.build(foster: 1) &+ 33)
LibC.putchar(10)
