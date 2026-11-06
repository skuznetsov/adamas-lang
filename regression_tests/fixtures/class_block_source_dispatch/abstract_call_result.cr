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
    true
  end
end
class Concrete < Base
  include Lock
end
class Other < Base
  def lock?(&) : Bool
    false
  end
end
def target(io : Base) : Bool
  io.lock? { C.putchar(65) }
end
if target(Concrete.new)
  C.putchar(84)
end
if target(Other.new)
  C.putchar(88)
else
  C.putchar(70)
end
