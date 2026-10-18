require "./factory_macro"
require "./child_first_base"
require "./child_first_child"

lib LibC
  fun putchar(c : Int32) : Int32
end

LibC.putchar(GeneratedChildFirstChild.build(foster: 1) &+ 33)
LibC.putchar(GeneratedChildFirstChild.build(parent: 1).code)
LibC.putchar(10)
