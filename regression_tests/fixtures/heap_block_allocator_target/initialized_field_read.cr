lib C
  fun putchar(value : Int32) : Int32
end
class FieldToken
  def initialize(@code : Int32 = 65, &@callback : FieldToken -> Nil)
    nil
  end
  def code : Int32
    @code
  end
end
token = FieldToken.new { |item| nil }
C.putchar(token.code)
