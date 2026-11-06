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
 def initialize(@kind : Type = 65)
 end
end
CarrierChild.new
