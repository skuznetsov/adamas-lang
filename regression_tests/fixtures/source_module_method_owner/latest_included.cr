lib C
  fun putchar(value : Int32) : Int32
end
module First
  def code(value : Int32) : Int32
    66
  end
end
module Second
  def code(value : Int32) : Int32
    value
  end
end
class SizeBox(T)
  include First
  include Second
end
C.putchar(SizeBox(Int32).new.code(65))
