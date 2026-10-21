lib LibC
  fun putchar(value : Int32) : Int32
end

class RegisteredParent
  def marker : Int32
    68_i32
  end
end
class RegisteredChild < RegisteredParent
end
LibC.putchar(RegisteredChild.new.marker)
