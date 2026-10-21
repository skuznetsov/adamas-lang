lib LibC
  fun putchar(value : Int32) : Int32
end

require "./dependencies/parent_then_child"
LibC.putchar(RequireChild.new.marker)
