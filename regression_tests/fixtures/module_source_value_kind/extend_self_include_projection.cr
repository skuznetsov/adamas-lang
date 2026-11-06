module Formatter
end

module Exported
  include Formatter
  extend self
end

@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end

def accepts(value : Formatter) : Int32
  70
end

C.putchar(accepts(Exported))
C.putchar(10)
