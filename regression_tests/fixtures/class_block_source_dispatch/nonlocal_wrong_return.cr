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
class Other < Base
  def lock?(&) : Bool
    false
  end
end
def target(io : Base) : Bool
  io.lock? { return 65 }
  false
end
target(Concrete.new)
