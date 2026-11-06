lib C
  fun putchar(x : Int32) : Int32
end
abstract class Base
  abstract def lock?(&) : Bool
end
class Concrete < Base
  def lock?(&) : Bool
    yield
    true
  end
end
def target(io : Base) : Int32
  io.lock? { return 65 }
  66
end
C.putchar(target(Concrete.new))
