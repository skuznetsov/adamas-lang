lib LibC
  fun putchar(c : Int32) : Int32
  fun exit(c : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(91)
end

class AliasMetaBase
  alias TargetMeta = AliasMetaChild.class

  def self.guard : Bool
    self.is_a?(TargetMeta) && self.child_only
  end

  def self.child_only : Bool
    false
  end
end

class AliasMetaChild < AliasMetaBase
  def self.child_only : Bool
    true
  end
end

LibC.putchar(AliasMetaBase.guard ? 65 : 66)
LibC.putchar(AliasMetaChild.guard ? 65 : 66)
LibC.putchar(10)
