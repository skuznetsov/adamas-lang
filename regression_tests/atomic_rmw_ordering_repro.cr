# Atomic#add / #sub / #min / #max emit atomicrmw with the right ordering.
# Pre-fix: Atomic::Ops.atomicrmw was a STUB returning 0, so Atomic#add returned
# the previous accumulator unchanged and reads stayed at 0.
# Post-fix: HIR-level symbol→enum conversion + MIR-level primitive interception
# emit `atomicrmw <op> ptr ..., iN ... <ordering>` directly.
#
# EXPECT: ATOMIC_OK

a = Atomic(Int32).new(0)

# add returns the OLD value
v0 = a.add(5)         # → 0
v1 = a.add(7)         # → 5
v2 = a.get            # → 12

# sub returns the OLD value
v3 = a.sub(2)         # → 12
v4 = a.get            # → 10

# set + get round-trip
a.set(42)
v5 = a.get            # → 42

# compare_and_set: returns {old_value, success_bool}
old, ok = a.compare_and_set(42, 100)
v6 = a.get            # → 100

if v0 == 0 && v1 == 5 && v2 == 12 && v3 == 12 && v4 == 10 && v5 == 42 &&
   old == 42 && ok && v6 == 100
  puts "ATOMIC_OK"
else
  puts "FAIL v0=#{v0} v1=#{v1} v2=#{v2} v3=#{v3} v4=#{v4} v5=#{v5} old=#{old} ok=#{ok} v6=#{v6}"
end
