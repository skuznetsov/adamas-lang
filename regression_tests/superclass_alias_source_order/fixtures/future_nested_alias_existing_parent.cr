class AliasNestedScope
  class Parent
  end
  class Child < FutureParentAlias
  end
  alias FutureParentAlias = Parent
end
