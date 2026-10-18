require "./factory_macro"

lib LibC
  fun putchar(c : Int32) : Int32
end

class DirectMacroFactory
  build_factory(parent, self, new(value))

  def initialize(@value : Int32)
  end

  def code : Int32
    66
  end
end

LibC.putchar(DirectMacroFactory.build(parent: 1).code)
LibC.putchar(10)
