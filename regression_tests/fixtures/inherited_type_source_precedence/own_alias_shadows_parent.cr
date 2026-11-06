lib C
 fun putchar(c : Int32) : Int32
end
module Unrelated
 alias Type = Bool | String
end
class CarrierBase
 enum Type
  Stream = 65
 end
end
class CarrierChild < CarrierBase
 alias Type = Int32
 def initialize(@value : Type = 65)
 end
 def result : Int32
  @value
 end
end
C.putchar(CarrierChild.new.result)
C.putchar(10)
