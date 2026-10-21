lib LibC
  fun putchar(value : Int32) : Int32
end
class LaterAliasOwner
  def value : LaterReturnAlias
    65_i32
  end
end
alias LaterReturnAlias = Int32
LibC.putchar(LaterAliasOwner.new.value)
