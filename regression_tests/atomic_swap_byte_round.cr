# Regression: Atomic(T)#swap must exchange and return the old value.
#
# `swap` has no return-type annotation and its body is a macro-if whose else
# branch is `cast_from atomicrmw(:xchg, as_pointer, cast_to(value), ordering)`,
# gated on `T.union_types.all? { |t| t == Nil || t < Reference } && T != Nil`.
# Two bugs had to be fixed for it to work end-to-end:
#   1. The macro-if predicate `union_types.all? { ... }` was unevaluable, so the
#      whole body lowered to a nil stub (`define void ... { ret void }`).
#   2. Once the body materialized, swap's atomicrmw exposed a byte-round desync:
#      it passes `cast_to(value)` (already Int8) while the primitive binds
#      T=Bool (i1), so the emitter must not re-zext an operand already at the
#      storage width (`zext i1 %v to i8` where %v is i8 -> invalid IR).
#
# EXPECT: ATOMIC_SWAP_OK

ok = true

ab = Atomic(Bool).new(false)
old_b = ab.swap(true)
ok = false unless old_b == false && ab.get == true

ab2 = Atomic(Bool).new(true)
old_b2 = ab2.swap(false)
ok = false unless old_b2 == true && ab2.get == false

ai = Atomic(Int32).new(5)
old_i = ai.swap(10)
ok = false unless old_i == 5 && ai.get == 10

if ok
  puts "ATOMIC_SWAP_OK"
else
  puts "ATOMIC_SWAP_FAIL old_b=#{old_b} old_b2=#{old_b2} old_i=#{old_i}"
end
STDOUT.flush
