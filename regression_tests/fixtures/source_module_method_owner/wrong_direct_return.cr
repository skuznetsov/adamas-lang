lib C
  fun putchar(value : Int32) : Int32
end
module SizeTrait
  def size : Int32
    66
  end
end
class SizeBox(T)
  include SizeTrait
  def size : Int32
    true
  end
end
SizeBox(Int32).new.size
