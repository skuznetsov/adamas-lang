lib LibC
  fun putchar(c : Int32) : Int32
  fun exit(c : Int32) : NoReturn
end
fun __crystal_raise_overflow : NoReturn
  LibC.exit(91)
end
class GuardBase
  def guarded : Bool
    self.is_a?(GuardChild) || self.child_only
  end
end
class GuardChild < GuardBase
  def child_only : Bool
    true
  end
end
GuardBase.new.guarded
