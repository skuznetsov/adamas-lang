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
 def initialize(@kind : Type = Type::Stream)
 end
 def check : CarrierBase::Type
  @kind
 end
end
def observed(value : CarrierBase::Type) : Int32
 C.putchar(65)
end
observed(CarrierChild.new.check)
C.putchar(10)
