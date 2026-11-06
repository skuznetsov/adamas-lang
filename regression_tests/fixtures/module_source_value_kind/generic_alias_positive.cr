module Marker(T)
end

alias IntMarker = Marker(Int32)

module Wrapper(T)
  include Marker(T)
end

class Concrete(T)
  extend Wrapper(T)
end

alias IntConcrete = Concrete(Int32)

@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

def accept(value : IntMarker) : Int32
  77
end

C.putchar(accept(IntConcrete))
C.putchar(10)
