@[Link("gc")]
lib PointerCallbackOutput
  fun putchar(value : Int32) : Int32
end

def use(&block : -> UInt8*) : UInt8*
  yield
end
x=65
use { pointerof(x) }
PointerCallbackOutput.putchar(88)
PointerCallbackOutput.putchar(10)
