lib LibC
  fun putchar(c : Int32) : Int32
end
module Atomic::Ops
  def self.store(ptr : Pointer(Int32), value : Int32, ordering : Int32, volatile : Bool) : Nil
    LibC.putchar(66)
    nil
  end
end
value = 65
Atomic::Ops.store(pointerof(value), 67, 2, false)
LibC.putchar(10)
