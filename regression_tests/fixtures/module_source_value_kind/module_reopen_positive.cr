module Marker(T)
end

module Marker(T)
  def marker_tag
    1
  end
end

module Wrapper(T)
  include Marker(T)
end

module Wrapper(T)
  def wrapper_tag
    2
  end
end

class Concrete(T)
  extend Wrapper(T)
end

@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

def accept(value : Marker(Int32)) : Int32
  82
end

C.putchar(accept(Concrete(Int32)))
C.putchar(10)
