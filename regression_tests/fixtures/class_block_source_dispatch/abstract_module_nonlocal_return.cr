lib C
  fun putchar(x : Int32) : Int32
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
def target(io : Base) : Int32
  io.lock? { return 65 }
  66
end
C.putchar(target(Concrete.new))
