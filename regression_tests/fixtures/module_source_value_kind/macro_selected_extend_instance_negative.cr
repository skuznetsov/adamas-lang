module Marker(T)
end

module Wrapper(T)
  include Marker(T)
end

macro extend_wrapper(wrapper)
  extend {{wrapper}}
end

class Concrete(T)
  extend_wrapper Wrapper(T)
end

@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

def accept(value : Marker(Int32)) : Int32
  88
end

C.putchar(accept(Concrete(Int32).new))
C.putchar(10)
