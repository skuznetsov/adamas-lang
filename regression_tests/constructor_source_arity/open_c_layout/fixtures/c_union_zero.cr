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
value = LibC::Box.new
value.value = 69
LibC.putchar(value.value)
value = LibC::Box.new()
value.value = 70
LibC.putchar(value.value)
