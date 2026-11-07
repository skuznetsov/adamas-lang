lib OracleC
  fun putchar(value : Int32) : Int32
end
class Parent
  def self.new(value : Int32) : Int32
    OracleC.putchar(value)
  end
end
class Child < Parent
  def initialize(value : Int32, *, file : Int32)
    nil
  end
end
Child.new(65)
OracleC.putchar(10)
