lib LibC
  fun putchar(value : Int32) : Int32
end
require "./dependencies/parent"
class GeneratedChild < MacroOrderParent
end
LibC.putchar(GeneratedChild.new.marker)
