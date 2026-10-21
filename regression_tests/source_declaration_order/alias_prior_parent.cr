lib LibC
  fun putchar(value : Int32) : Int32
end

class PriorAliasedParent
end
alias PriorParentAlias = PriorAliasedParent
class AliasChild < PriorParentAlias
end
LibC.putchar(65_i32)

