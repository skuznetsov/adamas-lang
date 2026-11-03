lib LibC
  fun putchar(c : Int32) : Int32
end
module LexicalOwner
  def read_value
    Nested::VALUE
  end
end

class Includer
  module Nested
    VALUE = 65
  end

  include LexicalOwner
end

LibC.putchar(Includer.new.read_value)
LibC.putchar(10)
