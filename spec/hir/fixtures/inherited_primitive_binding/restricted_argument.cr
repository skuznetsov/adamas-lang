lib PrimitiveRestrictionOutput
  fun putchar(value : Int32) : Int32
end

struct RestrictedPrimitiveProbe
  def self.accept(value : Int32) : Int32
    65
  end
  def self.wide : Int64
    1_i64
  end
end

struct Int
  def inherited_restricted_argument : Int32
    RestrictedPrimitiveProbe.accept(RestrictedPrimitiveProbe.wide)
  end
end

PrimitiveRestrictionOutput.putchar(1_i32.inherited_restricted_argument)
