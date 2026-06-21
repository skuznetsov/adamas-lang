# A' BEHAVIOR: main-inlined Array(C) eligibility (closes the v1 bv-limit).
#
# Before the bv-extension, the safe-set `bv` signal was detected ONLY from gep_dyn
# buffer_value inside monomorphic `Array(C)#` BODIES. A type used purely via
# main-inlined `arr[i]` / `arr[i] = v` (ArrayGet/ArraySet MIR ops, no Array(C)#
# unsafe_fetch/push call bodies) got bv=0 → ineligible — eligibility was
# usage-pattern-dependent. Now ArrayGet/ArraySet on an Array(C) container also
# establish bv, so MW (used via main-inlined index get/set) is eligible and the
# inline ABI flips correctly. The companion script asserts ELIGIBLE MW + behavior
# identity gate ON vs OFF.
struct MW
  getter a : Int32
  getter b : Int32
  getter c : Int32

  def initialize(@a : Int32, @b : Int32, @c : Int32)
  end
end

arr = [] of MW
i = 0
while i < 6
  arr << MW.new(i, i * 10, i * 100)
  i += 1
end
arr[0] = MW.new(99, 98, 97)   # main-inlined ArraySet
sum = 0
j = 0
while j < arr.size
  v = arr[j]                  # main-inlined ArrayGet
  sum += v.a + v.b + v.c
  j += 1
end
STDERR.puts "RESULT sum=#{sum} a0=#{arr[0].a},#{arr[0].b},#{arr[0].c} last=#{arr[5].c}"
STDOUT.flush
exit(0)
