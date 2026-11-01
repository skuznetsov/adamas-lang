lib LibC
  fun putchar(value : Int32) : Int32
  fun malloc(size : UInt64) : Void*
end
class GenericPointerReadinessBox(T)
  def initialize(@pointer : T)
  end
end
GenericPointerReadinessBox(Void*).new(LibC.malloc(1_u64))
LibC.putchar(65)
LibC.putchar(10)
