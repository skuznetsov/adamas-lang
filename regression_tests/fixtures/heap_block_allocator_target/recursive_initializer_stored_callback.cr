lib C
  fun putchar(value : Int32) : Int32
end
class RecursiveToken
  def initialize(@outer : Bool, @child : RecursiveToken? = nil, &@callback : RecursiveToken -> Nil)
    if @outer
      @child = RecursiveToken.new(false) { |item| C.putchar(65) }
    end
    nil
  end
  def activate : Nil
    if child = @child
      child.activate
    else
      @callback.call(self)
    end
  end
end
token = RecursiveToken.new(true) { |item| nil }
token.activate
