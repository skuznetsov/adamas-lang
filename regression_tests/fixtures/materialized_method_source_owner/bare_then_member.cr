lib C
  fun putchar(c : Int32) : Int32
end
class DefaultBodyProbe
  def emit(count = 65) : Nil
    C.putchar(count)
  end
  def trigger : Nil
    emit
  end
end
p = DefaultBodyProbe.new
p.trigger
p.emit
