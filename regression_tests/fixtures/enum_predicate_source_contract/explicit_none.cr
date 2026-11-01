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
  None = 0
  Read = 1
  Write = 2
end

zero = SourcePermissions.new(0_i16)
nonzero = SourcePermissions.new(1_i16)
combined = SourcePermissions.new(3_i16)

LibC.putchar(zero.none? ? 65 : 88)
LibC.putchar(nonzero.none? ? 88 : 66)
LibC.putchar(combined.read? ? 67 : 88)
LibC.putchar(combined.write? ? 68 : 88)
LibC.putchar(combined.value == SourcePermissions::All.value ? 69 : 88)
LibC.putchar(10)
