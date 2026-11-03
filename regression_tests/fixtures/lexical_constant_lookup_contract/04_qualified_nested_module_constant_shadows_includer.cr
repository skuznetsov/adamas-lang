lib LibC
  fun putchar(value : Int32) : Int32
end

module LexicalOwner
  module Nested
    VALUE = 65
  end

  def read_value
    Nested::VALUE
  end
end

class Includer
  module Nested
    VALUE = 66
  end

  include LexicalOwner
end

LibC.putchar(Includer.new.read_value)
LibC.putchar(10)
