@[Link("c")]
lib C
  fun exit(value : Int32) : NoReturn
  fun putchar(value : Int32) : Int32
end
class TerminalReader
  @[NoInline]
  def initialize(value : Int32)
    C.exit(value)
  end
end
TerminalReader.new(67)
C.putchar(88)
