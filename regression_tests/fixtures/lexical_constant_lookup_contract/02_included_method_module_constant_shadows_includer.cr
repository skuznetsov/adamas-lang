lib LibC
  fun putchar(value : Int32) : Int32
end

module LexicalOwner
  VALUE = 65

  def read_value
    VALUE
  end
end

class Includer
  VALUE = 66
  include LexicalOwner
end

LibC.putchar(Includer.new.read_value)
LibC.putchar(10)
