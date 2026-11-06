lib C
  fun putchar(c : Int32) : Int32
end
class WrongDefaultReturn
  def value(count = 65) : Int32
    false
  end
  def trigger : Int32
    value
    self.value
  end
end
C.putchar(WrongDefaultReturn.new.trigger)
