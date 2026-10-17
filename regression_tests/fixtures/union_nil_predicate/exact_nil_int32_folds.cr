@[Link("c")]
lib NullablePredicateProbe
  fun putchar(value : Int32) : Int32
end

nil_value = nil
if nil_value.is_a?(Nil)
  NullablePredicateProbe.putchar(49)
else
  NullablePredicateProbe.putchar(50)
end

int_value = 5_i32
if int_value.is_a?(Nil)
  NullablePredicateProbe.putchar(51)
else
  NullablePredicateProbe.putchar(52)
end
NullablePredicateProbe.putchar(10)
