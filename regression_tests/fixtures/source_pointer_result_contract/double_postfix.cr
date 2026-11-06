@[Link("gc")]
lib PointerCallbackAdversaryOutput
  fun putchar(value : Int32) : Int32
end

def use(&block : -> Int32**) : Int32**
  yield
end
x=65
p=pointerof(x)
use { pointerof(p) }
PointerCallbackAdversaryOutput.putchar(65)
PointerCallbackAdversaryOutput.putchar(10)
