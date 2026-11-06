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
macro show_source(expression)
  LibC.puts({{ expression.stringify }}.to_unsafe)
end
show_source("a#{identity(items[index], left + (right * third))}z")
