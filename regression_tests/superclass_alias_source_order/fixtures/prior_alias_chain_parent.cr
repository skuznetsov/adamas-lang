lib LibC
  fun putchar(value : Int32) : Int32
end
class AliasChainParent
  def marker : Int32
    65_i32
  end
end
alias KnownParentAlias = AliasChainParent
alias KnownParentChain = KnownParentAlias
class AliasChainChild < KnownParentChain
end
LibC.putchar(AliasChainChild.new.marker)
