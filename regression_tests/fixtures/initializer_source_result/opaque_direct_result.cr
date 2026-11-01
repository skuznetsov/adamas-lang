@[Link("c")]
lib C
  fun getchar : Int32
  fun putchar(value : Int32) : Int32
end
class Reader
  @[NoInline]
  def initialize(value : Int32)
    value
  end
  @[NoInline]
  def direct(value : Int32) : Int32
    initialize(value)
  end
end
value = C.getchar
C.putchar(Reader.new(0).direct(value))
C.putchar(10)
