module LexicalOwner
  def read_value
    ONLY_ON_INCLUDER
  end
end

class Includer
  ONLY_ON_INCLUDER = 65
  include LexicalOwner
end

Includer.new.read_value
