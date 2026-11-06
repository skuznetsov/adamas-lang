lib C
  fun putchar(c : Int32) : Int32
end
class TypedDefaultBody
  def value(count : Int32 = 66) : Int32
    count
  end
  def trigger : Int32
    value
    self.value
  end
end
C.putchar(TypedDefaultBody.new.trigger)
