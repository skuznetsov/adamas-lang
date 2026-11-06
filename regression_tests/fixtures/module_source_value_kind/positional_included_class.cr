module Formatter
end
module Decorator
  include Formatter
end
abstract struct Extended
  extend Decorator
end
struct ExtendedChild < Extended
end
struct Included
  include Decorator
end
alias AliasChild = ExtendedChild
@[Link("c")]
lib C
  fun putchar(value : Int32) : Int32
end
def accept(value : Formatter) : Int32
  65
end
C.putchar(accept(Included))
C.putchar(10)
