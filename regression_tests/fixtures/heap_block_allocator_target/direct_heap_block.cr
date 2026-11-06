lib C
  fun putchar(value : Int32) : Int32
end
class Token
  def initialize(&@func : Token -> Nil)
    nil
  end
  def code : Int32; 65; end
end
def wrapper : Token
  Token.new { |token| nil }
end
C.putchar(wrapper.code)
