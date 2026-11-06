@[Link("gc")]
lib PointerCallbackAdversaryOutput
  fun putchar(value : Int32) : Int32
end

module PointerShadow
  class Pointer(T)
  end
  def self.use(&block : -> Int32*) : Int32*
    yield
  end
end
x=65
p=PointerShadow.use { pointerof(x) }
PointerCallbackAdversaryOutput.putchar(p.value)
PointerCallbackAdversaryOutput.putchar(10)
