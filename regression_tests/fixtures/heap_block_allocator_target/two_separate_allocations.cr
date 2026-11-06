lib C
  fun putchar(value : Int32) : Int32
end
class SeparateToken
  def initialize(@code : Int32, &@callback : SeparateToken -> Nil)
    nil
  end
  def code : Int32
    @code
  end
  def activate : Nil
    @callback.call(self)
  end
end
first = SeparateToken.new(65) { |item| C.putchar(item.code) }
second = SeparateToken.new(66) { |item| C.putchar(item.code) }
first.activate
second.activate
