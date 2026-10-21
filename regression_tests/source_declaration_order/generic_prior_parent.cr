lib LibC
  fun putchar(value : Int32) : Int32
end

class PriorGenericParent(T)
end
class PriorGenericChild < PriorGenericParent(Int32)
end
LibC.putchar(65_i32)

