@[Link("gc")]
lib PointerCallbackOutput
  fun putchar(value : Int32) : Int32
end

def use(&block : -> Int32*) : Int32*
  yield
end
x=65
p=use { pointerof(x) }
PointerCallbackOutput.putchar(p.value)
PointerCallbackOutput.putchar(10)
