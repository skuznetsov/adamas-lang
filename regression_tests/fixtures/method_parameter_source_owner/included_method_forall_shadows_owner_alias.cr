lib LibC
  fun putchar(value : Int32) : Int32
end

module ForallAliasOwner
  alias T = Bool

  def emit(value : T) forall T
    LibC.putchar(value)
  end
end

class ForallAliasHost
  include ForallAliasOwner
end

ForallAliasHost.new.emit(65)
LibC.putchar(10)
