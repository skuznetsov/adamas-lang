lib LibC
  fun putchar(c : Int32) : Int32
end

class StrictTypeOwner
  class Type
  end
end

module Unrelated
  alias Type = Int32
end

class StrictTypeChild < StrictTypeOwner
  def self.accept(value : Type)
    LibC.putchar(65)
  end
end

StrictTypeChild.accept(65)
LibC.putchar(10)
