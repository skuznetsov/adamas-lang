lib LibC
  fun putchar(value : Int32) : Int32
end
class Payload
end
class BindingBox(K, V)
end
class Adapter
  class Payload
  end
  def self.transform(& : Int32 -> Tuple(K, V)) forall K, V
    result = BindingBox(K, V).new
    yield 1
    result
  end
end
def accept(value : BindingBox(::Payload.class, Bool)) : Int32
  65
end
LibC.putchar(accept(Adapter.transform { |item| {Payload, true} }))
LibC.putchar(10)
