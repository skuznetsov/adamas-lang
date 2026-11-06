@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
class Container
  module Marker(T)
  end
  module Concrete
    extend Marker(Int32)
  end
end
def accepts(value : Container::Marker(Int32)) : Int32
  65
end
C.putchar(accepts(Container::Concrete))
C.putchar(10)
