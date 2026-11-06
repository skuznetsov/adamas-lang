@[Link("gc")]
lib PointerCallbackAdversaryOutput
  fun putchar(value : Int32) : Int32
end

def use(&block : -> Tuple(UInt8)*) : Tuple(UInt8)*
  yield
end
slot={65}
use { pointerof(slot) }
PointerCallbackAdversaryOutput.putchar(88)
PointerCallbackAdversaryOutput.putchar(10)
