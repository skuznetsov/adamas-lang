require "./alias_parent"
class AliasChild < AliasParent
  def emit(*, flag : Bool = true) : Nil
    C.putchar(65)
  end
end
