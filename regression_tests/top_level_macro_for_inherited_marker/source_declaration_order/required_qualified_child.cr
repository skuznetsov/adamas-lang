lib LibC
  fun putchar(value : Int32) : Int32
end
require "./dependencies/parent"
class MacroOrderDestination
end
class MacroOrderDestination::GeneratedChild < MacroOrderParent
end
LibC.putchar(MacroOrderDestination::GeneratedChild.new.marker)
