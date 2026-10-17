@[Link("c")]
lib NullablePredicateProbe
  fun getpid : Int32
  fun putchar(value : Int32) : Int32
end

value = if NullablePredicateProbe.getpid > 0
          1_i32
        else
          nil
        end

if value.is_a?(Nil)
  NullablePredicateProbe.putchar(49)
else
  NullablePredicateProbe.putchar(50)
end
NullablePredicateProbe.putchar(10)
