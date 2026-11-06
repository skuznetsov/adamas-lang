@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
module Marker
end
class Included
  include Marker
end
class Holder
  @value : Marker
  def initialize(@value : Marker); end
  def read : Marker
    @value
  end
end
def demand(&block : -> Marker)
  yield
  C.putchar(65)
  C.putchar(10)
end
demand { Holder.new(Included.new).read }
