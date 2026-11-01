lib LibC
  fun putchar(value : Int32) : Int32
  fun exit(status : Int32) : NoReturn
end

fun __crystal_raise_overflow : NoReturn
  LibC.exit(251)
end

module TupleBlockInput(E)
  def marker(value : E, current ignored : Int32, &block : E -> Int32) : Int32
    yield value
  end
end

struct Tuple
  include TupleBlockInput(Union(*T))
end

LibC.putchar({0, 0_i64}.marker(65, current: 0) { |value| value.to_i32 })
LibC.putchar({0, 0_i64}.marker(66_i64, current: 0) { |value| value.to_i32 })
LibC.putchar(10)
