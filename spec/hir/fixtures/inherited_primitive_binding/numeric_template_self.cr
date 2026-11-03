lib PrimitiveBindingOutput
  fun putchar(value : Int32) : Int32
end

struct Int
  def source_identity : self
    self
  end
  def inherited_marker : Int32
    65
  end
end

struct Float
  def source_identity : self
    self
  end
  def inherited_marker : Int32
    66
  end
end

PrimitiveBindingOutput.putchar(1_i32.source_identity.inherited_marker)
PrimitiveBindingOutput.putchar(1_u64.source_identity.inherited_marker)
PrimitiveBindingOutput.putchar(1_f32.source_identity.inherited_marker)
PrimitiveBindingOutput.putchar(1_f64.source_identity.inherited_marker)
PrimitiveBindingOutput.putchar(10)
