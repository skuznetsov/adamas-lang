lib LibC
  fun putchar(c : Int32) : Int32
end
module LexicalOwner
  def read_value
    ONLY_ON_INCLUDER
  end
end

class Includer
  ONLY_ON_INCLUDER = 65
  include LexicalOwner
end

LibC.putchar(Includer.new.read_value)
LibC.putchar(10)
