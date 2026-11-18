lib C
  fun putchar(c : Int32) : Int32
end
struct Token
end
class FlagBox
  def initialize(@value : Bool)
  end
  def code
    @value ? 84 : 70
  end
end
def tag_value(input : Token)
  73
end
def tag_value(input : Token.class)
  67
end
def flag(is_class : Bool = false)
  FlagBox.new(is_class).code
end
def kind(arg_class)
  tag_value(arg_class)
end
module Forward
  def via_module(is_class : Bool)
    FlagBox.new(is_class).code
  end
  def self.kind(value_class)
    tag_value(value_class)
  end
end
class Reader
  include Forward
  def via_method(is_class : Bool)
    FlagBox.new(is_class).code
  end
  def kind(value_class)
    tag_value(value_class)
  end
end
reader = Reader.new
C.putchar(flag)
C.putchar(flag(true))
C.putchar(reader.via_method(false))
C.putchar(reader.via_module(true))
C.putchar(kind(Token))
C.putchar(kind(Token.new))
C.putchar(reader.kind(Token.new))
C.putchar(reader.kind(Token))
C.putchar(Forward.kind(Token))
C.putchar(Forward.kind(Token.new))
C.putchar(10)
