lib C
  fun putchar(c : Int32) : Int32
end
class DefaultBodyProbe
  def emit(count = 65) : Nil
    C.putchar(count)
  end
end
def invoke(p : DefaultBodyProbe) : Nil
  p.emit
end
invoke(DefaultBodyProbe.new)
