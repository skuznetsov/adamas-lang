lib AtomicMirOracleLibC
  fun putchar(value : Int32) : Int32
end

module Atomic
  module Ops
    # Deliberately ordinary source: no @[Primitive] annotation.
    def self.cmpxchg(ptr : Int32*, cmp : Int32, new_value : Int32, success_ordering : Int32, failure_ordering : Int32) : {Int32, Bool}
      {66_i32, false}
    end
  end
end

value = 65_i32
old_value, exchanged = Atomic::Ops.cmpxchg(pointerof(value), 65_i32, 99_i32, 2_i32, 2_i32)
AtomicMirOracleLibC.putchar(exchanged ? 65_i32 : 66_i32)
AtomicMirOracleLibC.putchar(10_i32)
