lib C
  fun putchar(value : Int32) : Int32
end
module Scope
module SizeTrait
  def size : Int32
    66
  end
end
class SizeBox
  include SizeTrait
  def size : Int32
    65
  end
end
end
C.putchar(Scope::SizeBox.new.size)
