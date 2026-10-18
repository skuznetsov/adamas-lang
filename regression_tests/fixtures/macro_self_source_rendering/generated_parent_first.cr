require "./factory_macro"
require "./parent_first_base"
require "./parent_first_child"

lib LibC
  fun putchar(c : Int32) : Int32
end

LibC.putchar(GeneratedParentFirstChild.build(parent: 1).code)
LibC.putchar(GeneratedParentFirstChild.build(foster: 1) &+ 33)
LibC.putchar(10)
