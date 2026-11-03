lib LibC
  fun putchar(value : Int32) : Int32
end
class Product
  CODE = 65
  @code : Int32
  def initialize(value : Int32)
    @code = CODE
  end
  def code : Int32
    @code
  end
end
module Factory
  def product
    Product.new(0)
  end
end
class Caller
  include Factory
end
RESULT = Caller.new.product
LibC.putchar(RESULT.code)
LibC.putchar(10)
