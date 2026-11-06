lib LibC
  fun putchar(c : Int32) : Int32
end

class AliasOwner
  alias Type = Bool
end

module Unrelated
  alias Type = Int32
end

class AliasChild < AliasOwner
  def self.emit(value : Type)
    if value
      LibC.putchar(65)
    end
  end
end

AliasChild.emit(true)
LibC.putchar(10)
