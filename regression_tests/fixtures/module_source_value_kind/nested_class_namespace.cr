@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
class Container
  module Marker
    module Concrete
      extend Marker
    end
  end
end
def accepts(value : Container::Marker) : Int32
  65
end
C.putchar(accepts(Container::Marker::Concrete))
C.putchar(10)
