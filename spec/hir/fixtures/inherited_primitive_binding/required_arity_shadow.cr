lib PrimitiveBindingProbe
  fun putchar(value : Int32) : Int32
end

struct Int
  def inherited_marker : Int32
    65
  end
end

struct Int64
  def inherited_marker(value : Int32) : Int32
    value
  end
end

PrimitiveBindingProbe.putchar(1_i64.inherited_marker)
PrimitiveBindingProbe.putchar(1_i64.inherited_marker(66))
PrimitiveBindingProbe.putchar(10)
