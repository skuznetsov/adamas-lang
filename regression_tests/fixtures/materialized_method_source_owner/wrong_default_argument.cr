lib C
  fun putchar(c : Int32) : Int32
end
class WrongDefaultArgument
  def emit(count : Int32 = 65) : Nil
    C.putchar(count)
  end
  def trigger : Nil
    emit
    self.emit("bad")
  end
end
WrongDefaultArgument.new.trigger
