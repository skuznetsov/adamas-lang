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

enum SourceColor : Int16
  None = 0
  Red
  Blue
end

LibC.putchar(SourceColor::None.none? ? 65 : 88)
LibC.putchar(SourceColor::Red.none? ? 88 : 66)
LibC.putchar(SourceColor::Red.red? ? 67 : 88)
LibC.putchar(SourceColor::Blue.value == 2 ? 68 : 88)
LibC.putchar(10)
