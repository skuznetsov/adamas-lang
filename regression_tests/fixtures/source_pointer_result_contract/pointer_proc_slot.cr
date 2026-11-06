@[Link("gc")]
lib PointerCallbackAdversaryOutput
  fun putchar(value : Int32) : Int32
end

def use(&block : -> Proc(Int32, Int32)*) : Proc(Int32, Int32)*
  yield
end
callback = ->(x : Int32) { x }
use { pointerof(callback) }
PointerCallbackAdversaryOutput.putchar(65)
PointerCallbackAdversaryOutput.putchar(10)
