module Marker(T)
end

module Wrapper(T)
  include Marker(T)
end

struct Included(T)
  include Wrapper(T)
end

@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

def accept(value : Marker(Int32)) : Int32
  73
end

C.putchar(accept(Included(Int32)))
C.putchar(10)
