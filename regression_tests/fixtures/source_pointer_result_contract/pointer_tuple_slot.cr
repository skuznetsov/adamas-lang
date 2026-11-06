@[Link("gc")]
lib PointerCallbackAdversaryOutput
  fun putchar(value : Int32) : Int32
end

def use(&block : -> Tuple(Int32)*) : Tuple(Int32)*
  yield
end
slot={65}
use { pointerof(slot) }
PointerCallbackAdversaryOutput.putchar(65)
PointerCallbackAdversaryOutput.putchar(10)
