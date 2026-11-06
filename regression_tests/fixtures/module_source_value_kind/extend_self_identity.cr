module Exported
  extend self
end

@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

def accepts(value : Exported) : Int32
  65
end

C.putchar(accepts(Exported))
C.putchar(10)
