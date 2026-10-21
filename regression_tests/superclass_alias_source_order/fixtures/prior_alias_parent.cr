lib LibC
  fun putchar(value : Int32) : Int32
end
class AliasOrderParent
  def marker : Int32
    65_i32
  end
end
alias KnownParentAlias = AliasOrderParent
class AliasOrderChild < KnownParentAlias
end
LibC.putchar(AliasOrderChild.new.marker)
