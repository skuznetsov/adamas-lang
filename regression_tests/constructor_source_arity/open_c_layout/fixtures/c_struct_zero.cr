lib LibC
  fun putchar(value : Int32) : Int32
  struct Pair
    left : Int32
    right : Int32
  end
  union Box
    value : Int32
  end
end
value = LibC::Pair.new
value.left = 65
LibC.putchar(value.left)
value = LibC::Pair.new()
value.right = 66
LibC.putchar(value.right)
