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
lib C
  fun rand : Int32
end
demand { C.rand == 0 ? Marker : Included.new }
