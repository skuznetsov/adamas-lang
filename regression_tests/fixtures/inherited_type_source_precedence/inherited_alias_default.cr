lib C
 fun putchar(c : Int32) : Int32
end
module Unrelated
 alias Type = Bool | String
end
class AliasBase
 alias Type = Int32
end
class AliasChild < AliasBase
 def initialize(@value : Type = 65)
 end
 def result : Int32
  @value
 end
end
C.putchar(AliasChild.new.result)
C.putchar(10)
