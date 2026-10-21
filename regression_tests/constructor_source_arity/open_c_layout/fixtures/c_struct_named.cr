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
value = LibC::Pair.new(left: 67, right: 68)
LibC.putchar(value.left)
LibC.putchar(value.right)
