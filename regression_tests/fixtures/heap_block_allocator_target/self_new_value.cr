lib C
  fun putchar(value : Int32) : Int32
end
class ValueFactory
  def self.new : Int32
    65
  end
  def self.from_self : Int32
    self.new
  end
end
C.putchar(ValueFactory.from_self)
