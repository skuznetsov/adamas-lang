lib LibC
  fun putchar(value : Int32) : Int32
  fun exit(value : Int32) : NoReturn
end
def raise(message : String) : NoReturn
  LibC.exit(77)
end
class Token
  def self.code : Int32; 65; end
end
module Defaults(T)
  @code : Int32 = T.code
  def code : Int32; @code; end
end
class Subject
  include Defaults(Token)
end
LibC.putchar(Subject.new.code)
LibC.putchar(10)
