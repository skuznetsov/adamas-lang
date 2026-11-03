lib LibC
  fun putchar(value : Int32) : Int32
end

GLOBAL_FALLBACK = 65

module LexicalOwner
  def read_value
    GLOBAL_FALLBACK
  end
end

class Includer
  include LexicalOwner
end

LibC.putchar(Includer.new.read_value)
LibC.putchar(10)
