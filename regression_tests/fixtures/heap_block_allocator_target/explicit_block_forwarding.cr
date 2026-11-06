lib C
  fun putchar(value : Int32) : Int32
end
class ForwardToken
  def initialize(@value : Int32, &@callback : ForwardToken -> Nil)
    nil
  end
  def value : Int32
    @value
  end
  def activate : Nil
    @callback.call(self)
  end
end
def build_token(&callback : ForwardToken -> Nil) : ForwardToken
  ForwardToken.new(65, &callback)
end
token = build_token { |item| C.putchar(item.value) }
token.activate
