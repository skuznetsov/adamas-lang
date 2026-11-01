lib LibC
  fun putchar(value : Int32) : Int32
end
struct DefaultValue
  @value : Int32
  def initialize(@value : Int32)
  end
  def value : Int32
    @value
  end
end
class DefaultOwner
  DEFAULT = DefaultValue.new(65)
  def initialize(@every = DEFAULT)
  end
  def every
    @every
  end
end
LibC.putchar(DefaultOwner.new.every.value)
LibC.putchar(10)
