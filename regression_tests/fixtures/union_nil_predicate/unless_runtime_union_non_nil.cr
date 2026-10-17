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

unless value.is_a?(Nil)
  NullablePredicateProbe.putchar(51)
else
  NullablePredicateProbe.putchar(52)
end
NullablePredicateProbe.putchar(10)
