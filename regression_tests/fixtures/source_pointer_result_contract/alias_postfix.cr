@[Link("gc")]
lib PointerCallbackAdversaryOutput
  fun putchar(value : Int32) : Int32
end

alias Slot = Int32*
def use(&block : -> Slot) : Slot
  yield
end
x=65
p=use { pointerof(x) }
PointerCallbackAdversaryOutput.putchar(p.value)
PointerCallbackAdversaryOutput.putchar(10)
