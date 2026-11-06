lib C
  fun putchar(value : Int32) : Int32
end
module SizeTrait
  def size : Int32
    66
  end
  def source_size : Int32
    size
  end
end
struct Tuple
  include SizeTrait
  def size : Int32
    65
  end
end
C.putchar({1, 2}.size)
