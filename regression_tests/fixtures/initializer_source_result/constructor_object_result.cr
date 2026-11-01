@[Link("c")]
lib C
  fun getchar : Int32
  fun putchar(value : Int32) : Int32
end
class Reader
  @value : Int32
  @[NoInline]
  def initialize(@value : Int32)
    @value
  end
  def marker : Int32
    @value
  end
end
C.putchar(Reader.new(C.getchar).marker)
C.putchar(10)
