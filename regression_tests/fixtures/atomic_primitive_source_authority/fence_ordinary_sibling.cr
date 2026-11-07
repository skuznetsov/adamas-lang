lib LibC
  fun putchar(c : Int32) : Int32
end
module Atomic::Ops
  def self.fence(ordering : Int32, singlethread : Bool) : Nil
    LibC.putchar(66)
    nil
  end
end
Atomic::Ops.fence(5, false)
LibC.putchar(10)
