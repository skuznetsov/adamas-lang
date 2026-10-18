require "./factory_macro"

lib LibC
  fun putchar(c : Int32) : Int32
end

class ExplicitReturnBase
  build_factory(parent, ExplicitReturnBase, new(value))

  def initialize(@value : Int32)
  end

  def code : Int32
    66
  end
end

class ExplicitReturnChild < ExplicitReturnBase
  build_factory(foster, Int32, 67)

  def code : Int32
    68
  end
end

LibC.putchar(ExplicitReturnChild.build(parent: 1).code)
LibC.putchar(ExplicitReturnChild.build(foster: 1) &+ 33)
LibC.putchar(10)
