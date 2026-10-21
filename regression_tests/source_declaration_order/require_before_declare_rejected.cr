lib LibC
  fun putchar(value : Int32) : Int32
end

require "./dependencies/child"
class RequireOwner
  class Parent
    def marker : Int32
      65_i32
    end
  end
end
