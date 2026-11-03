lib LibC
  fun putchar(value : Int32) : Int32
end
class DefaultedUnionA
  def value(seed : Int32 = 65_i32, *, tag : Int32 = 0_i32) : Int32
    seed
  end
end
class DefaultedUnionB
  def value(seed : Int32 = 66_i32, *, tag : Int32 = 0_i32) : Int32
    seed
  end
end
def defaulted_union_pick(flag : Bool) : DefaultedUnionA | DefaultedUnionB
  flag ? DefaultedUnionA.new : DefaultedUnionB.new
end
LibC.putchar(defaulted_union_pick(true).value)
LibC.putchar(defaulted_union_pick(false).value)
