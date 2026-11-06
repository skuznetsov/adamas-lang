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
 def output(value : Type) : Int32
  C.putchar(65)
 end
end
CarrierChild.new.output(CarrierBase::Type::Stream)
C.putchar(10)
