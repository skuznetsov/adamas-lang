lib C
  fun putchar(c : Int32) : Int32
  fun getpid : Int32
end
class Token
  def self.code
    65
  end
end
def choose(flag : Bool) : Token.class | Nil
  if flag
    Token
  else
    nil
  end
end
value = choose(C.getpid > 0)
callback = ->(arg : Token.class | Nil) { 65 }
C.putchar(callback.call(value))
C.putchar(10)
