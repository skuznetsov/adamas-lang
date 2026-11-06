lib C
  fun putchar(c : Int32) : Int32
end
class GenericDefaultBodyProbe(T)
  def emit(count = 65) : Nil
    C.putchar(count)
  end
end
GenericDefaultBodyProbe(Int32).new.emit
