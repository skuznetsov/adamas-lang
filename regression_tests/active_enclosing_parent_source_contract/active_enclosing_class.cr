lib LibC
  fun putchar(value : Int32) : Int32
end

class ActiveParentOwner
  def marker : Int32
    65_i32
  end
  class Child < ActiveParentOwner
  end
end
LibC.putchar(ActiveParentOwner::Child.new.marker)
