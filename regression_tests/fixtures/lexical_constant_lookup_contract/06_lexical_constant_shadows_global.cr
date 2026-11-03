lib LibC
  fun putchar(value : Int32) : Int32
end

SHARED = 65

module LexicalOwner
  SHARED = 66

  def self.read_value
    SHARED
  end
end

LibC.putchar(LexicalOwner.read_value)
LibC.putchar(10)
