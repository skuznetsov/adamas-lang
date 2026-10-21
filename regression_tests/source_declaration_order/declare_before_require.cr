lib LibC
  fun putchar(value : Int32) : Int32
end

class RequireOwner
  class Parent
    def marker : Int32
      65_i32
    end
  end
end
require "./dependencies/child"
LibC.putchar(RequireChild.new.marker)
