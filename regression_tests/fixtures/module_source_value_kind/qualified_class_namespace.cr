@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
class Container
end
module Container::Marker
  module Concrete
    extend Marker
  end
end
def accepts(value : Container::Marker) : Int32
  65
end
C.putchar(accepts(Container::Marker::Concrete))
C.putchar(10)
