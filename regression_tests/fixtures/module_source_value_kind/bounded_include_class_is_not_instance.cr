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
  C.putchar(10)
end
demand { Included }
