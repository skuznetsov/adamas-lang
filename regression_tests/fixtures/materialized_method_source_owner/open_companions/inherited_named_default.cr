lib C
  fun putchar(c : Int32) : Int32
end
require "./declarations/alias_child"
def invoke(value : AliasParent) : Nil
  value.emit
end
invoke(AliasChild.new)
