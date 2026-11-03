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

Includer.new.read_value
