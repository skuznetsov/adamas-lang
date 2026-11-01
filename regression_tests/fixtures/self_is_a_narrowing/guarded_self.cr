lib LibC
  fun putchar(c : Int32) : Int32
  fun exit(c : Int32) : NoReturn
end
fun __crystal_raise_overflow : NoReturn
  LibC.exit(91)
end
class GuardBase
  def guarded : Bool
    self.is_a?(GuardChild) && self.child_only
  end
  def guarded_if : Bool
    if self.is_a?(GuardChild)
      self.child_only
    else
      false
    end
  end
  def grouped : Bool
    (self).is_a?(GuardChild) && self.child_only
  end
  def keep_self : GuardBase
    self.is_a?(GuardChild) && self.child_only
    self
  end
end
class GuardChild < GuardBase
  def child_only : Bool
    true
  end
end
LibC.putchar(GuardBase.new.guarded ? 65 : 66)
LibC.putchar(GuardChild.new.guarded ? 65 : 66)
LibC.putchar(GuardBase.new.guarded_if ? 65 : 66)
LibC.putchar(GuardChild.new.guarded_if ? 65 : 66)
LibC.putchar(GuardBase.new.grouped ? 65 : 66)
LibC.putchar(GuardChild.new.grouped ? 65 : 66)
LibC.putchar(GuardBase.new.keep_self.guarded ? 65 : 66)
LibC.putchar(GuardChild.new.keep_self.guarded ? 65 : 66)
LibC.putchar(10)
