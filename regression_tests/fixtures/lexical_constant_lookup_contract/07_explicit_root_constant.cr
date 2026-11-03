lib LibC
  fun putchar(value : Int32) : Int32
end

ROOT_VALUE = 65

module LexicalOwner
  ROOT_VALUE = 66

  def self.read_value
    ::ROOT_VALUE
  end
end

LibC.putchar(LexicalOwner.read_value)
LibC.putchar(10)
