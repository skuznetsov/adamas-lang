module Left
  module Marker(T)
  end

  module Wrapper(T)
    include Marker(T)
  end

  class Concrete(T)
    extend Wrapper(T)
  end
end

module Right
  module Marker(T)
  end
end

@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

def accept(value : Right::Marker(Int32)) : Int32
  82
end

C.putchar(accept(Left::Concrete(Int32)))
C.putchar(10)
