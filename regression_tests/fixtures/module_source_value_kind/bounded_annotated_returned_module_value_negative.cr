@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
module Marker
end
class Included
  include Marker
end
def demand(&block : -> Marker)
 yield
 C.putchar(65)
end
def returned : Marker.class
  Marker
end
demand { returned }
