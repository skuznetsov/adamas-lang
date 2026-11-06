lib C
  fun putchar(c : Int32) : Int32
end
class ClassDefaultBody
  def self.emit(count = 65) : Nil
    C.putchar(count)
  end
  def self.trigger : Nil
    emit
    self.emit
  end
end
ClassDefaultBody.trigger
