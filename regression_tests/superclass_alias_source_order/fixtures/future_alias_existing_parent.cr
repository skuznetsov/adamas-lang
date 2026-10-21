class AliasOrderParent
end
class AliasOrderChild < FutureParentAlias
end
alias FutureParentAlias = AliasOrderParent
