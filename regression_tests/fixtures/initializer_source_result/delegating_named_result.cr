lib LibC
  fun getchar : Int32
  fun putchar(value : Int32) : Int32
end
class Reader
  def initialize(value : Int32)
    initialize(forwarded: value)
  end
  def initialize(*, forwarded value : Int32)
    value
  end
  def direct(value : Int32) : Int32
    initialize(value)
  end
end
value = LibC.getchar
LibC.putchar(Reader.new(0).direct(value))
LibC.putchar(10)
