lib C
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
class BottomInitializerToken
  def initialize(@code : Int32 = 65, &@callback : BottomInitializerToken -> Nil) : NoReturn
    C.exit(0)
  end
end
def consume(value : Int32)
  C.putchar(66)
end
consume(BottomInitializerToken.new { |item| nil })
