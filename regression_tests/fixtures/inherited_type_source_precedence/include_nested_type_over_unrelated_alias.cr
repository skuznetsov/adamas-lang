lib C
 fun putchar(c : Int32) : Int32
end
module Unrelated
 alias Type = Bool | String
end
module CarrierMixin
 enum Type
  Stream = 65
 end
end
class CarrierChild
 include CarrierMixin
 def initialize(@kind : Type = Type::Stream)
 end
 def check : CarrierMixin::Type
  @kind
 end
end
def observed(value : CarrierMixin::Type) : Int32
 C.putchar(65)
end
observed(CarrierChild.new.check)
C.putchar(10)
