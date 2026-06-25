# Regression: lower_short_circuit_condition leaked a condition-context truthy/falsy
# narrowing (UnionUnwrap) out of its dominance region. After `if x && cond; end`,
# the narrowed `x` binding (defined in the &&'s non-dominating rhs_block) survived
# into the later `y = x || default`, which read it along a path where it was
# undefined -> the backend dropped the non-dominating phi incoming to `null` ->
# SIGSEGV on `y.id`. This is the minimal source-level form of the s2b
# `hir_type_is_lib_struct?` frontier (lower_assign's `field_type = ivar_type ||
# ctx.type_of(value_id)` inside an `&&` condition).
# Fixed by with_scoped_condition_narrowing (ast_to_hir.cr): the condition-context
# narrowing is restored after lowering the RHS condition, so the branch-local
# UnionUnwrap does not leak past the condition's dominance region. lower_if
# independently re-narrows in its dominating then_block, so the then-body narrowing
# is preserved.
# EXPECT: RESULT=7
struct Wrap
  getter id : UInt32

  def initialize(@id : UInt32)
  end
end

def get_flag : Bool
  true
end

x : Wrap? = Wrap.new(7_u32)
# `x && get_flag` narrows `x` in the &&'s rhs_block; that block does not dominate
# the code after the `if`, so a leaked narrowing would make `x` null below.
if x && get_flag
end
y = x || Wrap.new(9_u32)
puts "RESULT=#{y.id}"
STDOUT.flush
