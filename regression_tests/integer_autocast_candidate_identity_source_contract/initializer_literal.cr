lib LibC
  fun putchar(value : Int32) : Int32
end
class IntegerIdentityInitializer
  def initialize(value : Int64)
    LibC.putchar(value == 65_i64 ? 65 : 88)
  end
end
IntegerIdentityInitializer.new(65)
