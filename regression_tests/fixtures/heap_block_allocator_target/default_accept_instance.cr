lib C
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end
class BottomInitializerToken
  def initialize(@code : Int32 = 65, &@callback : BottomInitializerToken -> Nil)
    C.putchar(65)
    C.exit(0)
  end
end
def wrapper : BottomInitializerToken
  BottomInitializerToken.new { |item| nil }
end
wrapper
C.putchar(66)
