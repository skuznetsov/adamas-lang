lib PrimitiveBindingProbe
  fun putchar(value : Int32) : Int32
end

struct Int
  def floor : self
    self
  end

  def inherited_marker : Int32
    65
  end
end

PrimitiveBindingProbe.putchar(1_i32.floor.inherited_marker)
PrimitiveBindingProbe.putchar(1_i64.floor.inherited_marker)
PrimitiveBindingProbe.putchar(10)
