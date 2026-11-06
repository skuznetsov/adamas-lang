lib C
  fun putchar(value : Int32) : Int32
end
class GenericToken(T)
  def initialize(@value : T, &@callback : GenericToken(T) -> Nil)
    nil
  end
  def value : T
    @value
  end
  def activate : Nil
    @callback.call(self)
  end
end
token = GenericToken(Int32).new(65) { |item| C.putchar(item.value) }
token.activate
