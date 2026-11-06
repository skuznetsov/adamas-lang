lib C
  fun putchar(value : Int32) : Int32
end
module SizeTrait
  def code(value : Int32) : Int32
    value
  end
end
class SizeBox(T)
  include SizeTrait
  def code(value : Bool) : Int32
    66
  end
end
C.putchar(SizeBox(Int32).new.code(65))
