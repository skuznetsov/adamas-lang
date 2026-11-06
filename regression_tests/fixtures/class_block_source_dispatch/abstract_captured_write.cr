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
def target(io : Base) : Int32
  value = 66
  io.lock? { value = 65 }
  value
end
C.putchar(target(Concrete.new))
C.putchar(target(Other.new))
