lib LibC
  fun putchar(c : Int32) : Int32
end

class TypeOwner
  class Type
    def code
      65
    end
  end
end

module Unrelated
  alias Type = Int32
end

class TypeChild < TypeOwner
  def self.emit(value : Type)
    LibC.putchar(value.code)
  end
end

TypeChild.emit(TypeOwner::Type.new)
LibC.putchar(10)
