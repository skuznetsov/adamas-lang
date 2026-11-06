@[Link("gc")]
lib PointerCallbackAdversaryOutput
  fun putchar(value : Int32) : Int32
end

def use(&block : -> (Int32* | Nil)) : Int32* | Nil
  yield
end
x=65
use { pointerof(x) }
PointerCallbackAdversaryOutput.putchar(65)
PointerCallbackAdversaryOutput.putchar(10)
