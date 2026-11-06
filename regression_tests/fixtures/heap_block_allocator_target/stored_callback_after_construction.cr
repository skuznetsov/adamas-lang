lib C
  fun putchar(value : Int32) : Int32
end
class CallbackToken
  def initialize(@code : Int32, &@callback : CallbackToken -> Nil)
    nil
  end
  def code : Int32
    @code
  end
  def activate : Nil
    @callback.call(self)
  end
end
token = CallbackToken.new(65) { |item| C.putchar(item.code) }
token.activate
