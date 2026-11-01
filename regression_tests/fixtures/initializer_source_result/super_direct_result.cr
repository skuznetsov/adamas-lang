lib LibC
  fun getchar : Int32
  fun putchar(value : Int32) : Int32
end
class ParentReader
  def initialize(value : Int32)
    value
  end
end
class ChildReader < ParentReader
  def initialize(value : Int32)
    super(value)
  end
  def direct(value : Int32) : Int32
    initialize(value)
  end
end
value = LibC.getchar
LibC.putchar(ChildReader.new(0).direct(value))
LibC.putchar(10)
