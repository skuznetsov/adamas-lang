lib C
  fun putchar(x : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

def raise(message) : NoReturn
  C.exit(99)
end

abstract class Base
  abstract def lock?(&) : Bool
end

module Lock
  def lock?(&) : Bool
    yield
    C.putchar(77) # M: inherited module implementation
    true
  end
end

class Concrete < Base
  include Lock
end

class Inherited < Concrete
end

class Direct < Concrete
  def lock?(&) : Bool
    yield
    C.putchar(68) # D: direct override
    false
  end
end

class Other < Base
  def lock?(&) : Bool
    false
  end
end

def run(io : Base)
  io.lock? { C.putchar(88) } # X: callback ran
end

run(Concrete.new)
C.putchar(10)
run(Inherited.new)
C.putchar(10)
run(Direct.new)
C.putchar(10)
run(Other.new)
C.putchar(78) # N: no-yield direct implementation
C.putchar(10)
