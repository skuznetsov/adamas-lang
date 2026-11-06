lib C
  fun putchar(c : Int32) : Int32
end
module DefaultBodyModule
  def emit(count = 65) : Nil
    C.putchar(count)
  end
end
class DefaultBodyProbe
  include DefaultBodyModule
end
DefaultBodyProbe.new.emit
