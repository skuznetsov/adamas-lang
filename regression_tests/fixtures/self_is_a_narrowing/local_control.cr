lib LibC
  fun putchar(c : Int32) : Int32
  fun exit(c : Int32) : NoReturn
end
fun __crystal_raise_overflow : NoReturn
  LibC.exit(91)
end
class GuardBase
  def guarded : Bool
    false
  end
end
class GuardChild < GuardBase
  def child_only : Bool
    true
  end
end
def local_guard(value : GuardBase) : Bool
  value.is_a?(GuardChild) && value.child_only
end
LibC.putchar(local_guard(GuardBase.new) ? 65 : 66)
LibC.putchar(local_guard(GuardChild.new) ? 65 : 66)
LibC.putchar(10)
