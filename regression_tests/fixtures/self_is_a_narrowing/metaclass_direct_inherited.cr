lib LibC
  fun putchar(c : Int32) : Int32
  fun exit(c : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(91)
end

class DirectMetaBase
  def self.guard : Bool
    self.is_a?(DirectMetaChild.class) && self.child_only
  end

  def self.child_only : Bool
    false
  end
end

class DirectMetaChild < DirectMetaBase
  def self.child_only : Bool
    true
  end
end

LibC.putchar(DirectMetaBase.guard ? 65 : 66)
LibC.putchar(DirectMetaChild.guard ? 65 : 66)
LibC.putchar(10)
