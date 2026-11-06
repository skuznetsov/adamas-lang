lib LibC
  fun putchar(c : Int32) : Int32
end

class DirectAliasScope
  alias Type = Int32

  def self.emit(value : Type)
    LibC.putchar(value)
  end
end

DirectAliasScope.emit(65)
LibC.putchar(10)
