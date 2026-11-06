@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
module Other;end
class OtherIncluded; include Other; end
module Marker
end
class Included
  include Marker
end
class Holder
 @value : Other
 def initialize(@value : Other);end
 def read : Other
 @value
 end
end
def demand(&block : -> Marker)
  yield
  C.putchar(65)
  C.putchar(10)
end
demand { Holder.new(OtherIncluded.new).read }
