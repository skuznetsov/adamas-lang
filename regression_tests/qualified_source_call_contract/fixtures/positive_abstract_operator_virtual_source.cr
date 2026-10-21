lib LibC
  fun putchar(c : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(92_i32)
end
abstract class VirtualOperatorBase
  abstract def +(other : Int32) : Int32
end
class VirtualOperatorChild < VirtualOperatorBase
  def +(other : Int32) : Int32
    other + 64
  end
end
def apply_virtual_operator(value : VirtualOperatorBase) : Int32
  value + 1
end
LibC.putchar(apply_virtual_operator(VirtualOperatorChild.new))
