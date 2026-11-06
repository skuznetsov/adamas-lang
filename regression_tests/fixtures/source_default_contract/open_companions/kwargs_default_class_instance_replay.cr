lib C
  fun putchar(c : Int32) : Int32
end

module Marker
end

class Concrete
  include Marker
end

class Other
  include Marker
end

def choose(value : Concrete.class)
  C.putchar(65)
end

def choose(value : Other.class)
  C.putchar(66)
end

def choose(value : Marker)
  C.putchar(73)
end

def dispatch(value = Concrete, **opts)
  choose(value)
end

dispatch(flag: true)
dispatch(Other, flag: true)
dispatch(Concrete.new, flag: true)
C.putchar(10)
