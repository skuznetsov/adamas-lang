lib LibC
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(251)
end

abstract struct Enum
  def value : Int
    previous_def
  end

  def ==(other : self) : Bool
    value == other.value
  end

  def includes?(other : self) : Bool
    (value & other.value) == other.value
  end
end

@[::Flags]
enum SourcePermissions : Int16
  OwnerRead = 0o400
  OwnerWrite = 0o200
  OtherRead = 0o004

  def implicit_owner_read? : Bool
    owner_read?
  end

  def explicit_owner_write? : Bool
    self.owner_write?
  end

  def absent_other_read? : Bool
    other_read?
  end
end

enum SourceColor : Int16
  Red = 1
  Blue = 2

  def implicit_red? : Bool
    red?
  end

  def explicit_blue? : Bool
    self.blue?
  end
end

permissions = SourcePermissions.new(0o600_i16)
LibC.putchar(permissions.implicit_owner_read? ? 65 : 88)
LibC.putchar(permissions.explicit_owner_write? ? 66 : 88)
LibC.putchar(permissions.absent_other_read? ? 88 : 67)
color = SourceColor.new(1_i16)
LibC.putchar(color.implicit_red? ? 68 : 88)
LibC.putchar(color.explicit_blue? ? 88 : 69)
LibC.putchar(10)
