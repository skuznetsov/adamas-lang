lib LibC
  fun putchar(c : Int32) : Int32
  fun exit(c : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(91)
end

class MetaAliasBase
  alias TargetMeta = MetaAliasChild.class

  def self.guarded_alias : Bool
    self.is_a?(TargetMeta) && self.class_only
  end

  def self.guarded_if_alias : Bool
    if self.is_a?(TargetMeta)
      self.class_only
    else
      false
    end
  end

  def self.class_only : Bool
    false
  end
end

class MetaAliasChild < MetaAliasBase
  def self.class_only : Bool
    true
  end
end

class MetaGuardBase
  def self.guarded : Bool
    self.is_a?(MetaGuardChild.class) && self.class_only
  end

  def self.guarded_if : Bool
    if self.is_a?(MetaGuardChild.class)
      self.class_only
    else
      false
    end
  end

  def self.class_only : Bool
    false
  end
end

class MetaGuardChild < MetaGuardBase
  def self.class_only : Bool
    true
  end
end

LibC.putchar(MetaGuardBase.guarded ? 65 : 66)
LibC.putchar(MetaGuardChild.guarded ? 65 : 66)
LibC.putchar(MetaGuardBase.guarded_if ? 65 : 66)
LibC.putchar(MetaGuardChild.guarded_if ? 65 : 66)
LibC.putchar(MetaAliasBase.guarded_alias ? 65 : 66)
LibC.putchar(MetaAliasChild.guarded_alias ? 65 : 66)
LibC.putchar(MetaAliasBase.guarded_if_alias ? 65 : 66)
LibC.putchar(MetaAliasChild.guarded_if_alias ? 65 : 66)
LibC.putchar(10)
