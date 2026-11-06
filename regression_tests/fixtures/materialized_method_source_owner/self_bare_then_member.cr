lib C
  fun putchar(c : Int32) : Int32
end
class DefaultBodyProbe
  def emit(count = 65) : Nil
    C.putchar(count)
  end
  def trigger : Nil
    emit
    self.emit
  end
end
DefaultBodyProbe.new.trigger
