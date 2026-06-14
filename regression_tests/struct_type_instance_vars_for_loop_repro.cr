# EXPECT: STRUCT_REFLECT_OK
#
# Regression: `@type.instance_vars` must iterate inside a method-body
# `{% for %}` loop. The HIR lowering path (macro_for_iterable_values_with_context)
# previously had no MemberAccessNode/CallNode case, so the reflection iterable
# evaluated to nil → 0 iterations. That silently collapsed stdlib
# `Struct#==` / `Struct#hash` / `Struct#to_s` (all of which loop over
# `@type.instance_vars`):
#   - `==`   degraded to "always true for same type"
#   - `hash` became a no-op → every key landed in one bucket
# so `Hash(SomeStruct, V)` merged all distinct keys into a single entry.
#
# Fix: macro_for_iterable_values_with_context delegates reflection iterables to
# MacroExpander#evaluate_for_iterable, which resolves them against owner_type.

struct Sig
  getter base_name : String
  getter arity : Int32
  getter has_block : Bool

  def initialize(@base_name : String, @arity : Int32, @has_block : Bool)
  end
end

# 1) auto `==` (uses @type.instance_vars) must distinguish distinct values
a = Sig.new("alpha", 1, true)
b = Sig.new("beta", 2, false)
distinct_ok = (a != b) && (a == Sig.new("alpha", 1, true))

# 2) Hash(Struct, V) must NOT collapse distinct keys into one bucket
h = Hash(Sig, Int32).new
i = 0
while i < 50
  h[Sig.new("m#{i}", i % 4, i.even?)] = i
  i += 1
end
hash_ok = h.size == 50

if distinct_ok && hash_ok
  puts "STRUCT_REFLECT_OK"
else
  puts "STRUCT_REFLECT_FAIL distinct=#{distinct_ok} hash_size=#{h.size}"
end
STDOUT.flush
