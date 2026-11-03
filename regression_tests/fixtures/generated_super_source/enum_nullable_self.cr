lib LibC
  fun putchar(value : Int32) : Int32
end

abstract struct Enum
  def self.make(value : Int32) : self?
    return nil if value == 0
    new(value)
  end

  def self.build(value : Int32) : self
    make(value) || new(value)
  end
end

enum SuperNullableDay
  Answer = 65

  def self.build(value : Int32) : self
    super(value)
  end
end

LibC.putchar(SuperNullableDay.build(65).value)
LibC.putchar(10)
