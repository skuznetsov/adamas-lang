# Atomic(Bool)#get / #set / #compare_and_set emit byte-sized (i8) atomics with
# the correct memory ordering.
#
# Pre-fix bug 1 (byte size): emit_atomic_load/store/cas used
#   @type_mapper.llvm_type(inst.type) directly, so Bool → `load atomic i1`, which
#   llc rejects ("atomic access must be byte-sized"). This blocked stage2.
# Pre-fix bug 2 (ordering): when the HIR symbol→enum autocast missed on an
#   Atomic::Ops ordering argument, the symbol (e.g. :acquire) was interned as a
#   Symbol constant and find_constant_int read the symbol *id* as the ordering
#   value — e.g. :acquire → AcqRel, which is also invalid on a load.
#
# Post-fix: Bool atomics round the access to i8 with a trunc/zext at the value
# boundary, and Symbol-typed ordering args are decoded by name in the MIR atomic
# interception. Compiling AND running this file proves the emitted IR is valid.
#
# EXPECT: ATOMIC_BOOL_OK

a = Atomic(Bool).new(false)

v0 = a.get(:acquire)                    # acquire load (was the invalid `load atomic i1 ... acq_rel`)
a.set(true, :release)                   # release store
v1 = a.get(:sequentially_consistent)    # → true
a.set(false, :relaxed)                  # relaxed store
v2 = a.get(:relaxed)                    # → false

# compare_and_set returns {old_value, success}
old1, ok1 = a.compare_and_set(false, true)   # {false, true}; value → true
v3 = a.get                                    # → true
old2, ok2 = a.compare_and_set(false, true)   # {true, false}; cmp mismatch, unchanged
v4 = a.get                                    # → true

if v0 == false && v1 == true && v2 == false &&
   old1 == false && ok1 && v3 == true &&
   old2 == true && !ok2 && v4 == true
  puts "ATOMIC_BOOL_OK"
else
  puts "FAIL v0=#{v0} v1=#{v1} v2=#{v2} old1=#{old1} ok1=#{ok1} v3=#{v3} old2=#{old2} ok2=#{ok2} v4=#{v4}"
end
