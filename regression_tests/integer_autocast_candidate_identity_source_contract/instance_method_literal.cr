lib LibC
  fun putchar(value : Int32) : Int32
end
class IntegerIdentityInstance
  def consume(value : Int64) : Int32
    value == 65_i64 ? 65 : 88
  end
end
LibC.putchar(IntegerIdentityInstance.new.consume(65))
