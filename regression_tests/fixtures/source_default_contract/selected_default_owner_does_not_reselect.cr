@[Link("c")]
lib DefaultOwnerC
  fun putchar(value : Int32) : Int32
end

module Marker
end

class Concrete
  extend Marker

  def self.byte
    65
  end
end

def choose(value : Marker = Concrete)
  value.byte
end

def choose(value : Concrete.class)
  88
end

DefaultOwnerC.putchar(choose())
DefaultOwnerC.putchar(10)
