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
class RequireChild < RequireOwner::Parent
end
LibC.putchar(RequireChild.new.marker)
