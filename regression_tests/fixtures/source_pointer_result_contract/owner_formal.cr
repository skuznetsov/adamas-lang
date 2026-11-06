@[Link("gc")]
lib PointerCallbackAdversaryOutput
  fun putchar(value : Int32) : Int32
end

class PointerOwner(T)
  def use(&block : -> T*) : T*
    yield
  end
end
x=65
p=PointerOwner(Int32).new.use { pointerof(x) }
PointerCallbackAdversaryOutput.putchar(p.value)
PointerCallbackAdversaryOutput.putchar(10)
