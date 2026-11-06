module Marker(T)
end

module Wrapper(T)
  include Marker(T)
end

class Concrete(T)
  extend Wrapper(T)
end

@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

def accept(value : Marker(Int32)) : Int32
  65
end

C.putchar(accept(Concrete(String)))
C.putchar(10)
