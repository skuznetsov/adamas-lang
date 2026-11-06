lib C
  fun putchar(value : Int32) : Int32
end
class Token
  def initialize(@name : Int32? = nil, &@func : Token -> Nil)
    nil
  end
  def code : Int32; 65; end
end
def inferred
  value = nil
  value ||= Token.new { |token| nil }
  value
end
def wrapper : Token
  inferred
end
C.putchar(wrapper.code)
