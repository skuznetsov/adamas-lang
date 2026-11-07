lib LibC
  fun putchar(c : Int32) : Int32
end
module Atomic::Ops
  def self.atomicrmw(op : Int32, ptr : Pointer(Int32), value : Int32, ordering : Int32, singlethread : Bool) : Int32
    66
  end
end
value = 65
result = Atomic::Ops.atomicrmw(1, pointerof(value), 1, 2, false)
LibC.putchar(result)
LibC.putchar(10)
