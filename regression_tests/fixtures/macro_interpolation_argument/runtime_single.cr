@[Link("c")]
lib LibC
  fun puts(value : UInt8*) : Int32
  fun putchar(value : Int32) : Int32
end
class String
  def to_unsafe : UInt8*
    pointerof(@c)
  end
  def self.interpolation(value : String) : String
    value
  end
end
macro pass(expression)
  {{ expression }}
end
def payload : String
  LibC.putchar(65)
  "B"
end
LibC.puts(pass("#{payload}").to_unsafe)
