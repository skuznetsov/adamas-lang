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
  Read = 1
  Write = 2

  def read? : Bool
    false
  end
end

both = SourcePermissions.new(3_i16)
LibC.putchar(both.read? ? 65 : 88)
LibC.putchar(both.write? ? 66 : 88)
LibC.putchar(10)
