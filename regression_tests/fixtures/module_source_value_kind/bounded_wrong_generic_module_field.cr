@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
module Marker(T)
end
class Included
  include Marker(Int32)
end
class Holder
  @value : Marker(Int32)
  def initialize(@value : Marker(Int32)); end
  def read : Marker(Int32)
    @value
  end
end
def demand(&block : -> Marker(Int64))
  yield
  C.putchar(65)
  C.putchar(10)
end
demand { Holder.new(Included.new).read }
