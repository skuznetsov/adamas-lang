# Regression guard for bare-Tuple `Object#in?(*values : Object)` splat path.
#
# Root cause (pre-fix 28036d5c):
#   `Object#in?(*values : Object)`'s body calls `in?(values)` with `values`
#   typed as bare `Tuple` (arity-erased). The struct-fallback branch in
#   `ast_to_hir.cr#lower_call` then emitted `Tuple#includes?$X` for every
#   reachable receiver type X — a broadcast of 500+ NOR bodies on larger
#   programs (channel-ping-pong observed 571 such NOR emissions).
#
# Fix: skip bare `Tuple` (and `Nil`) in the non-tuple struct `in?` fallback,
# so the bare-Tuple case goes through normal virtual dispatch. Concrete
# `Tuple(...)` is still handled inline above and stays fast.
#
# This test exercises several receiver types to force the broadcast pattern
# and both truthy/falsy paths. It is a *semantic* guard: both the old
# struct-fallback path and the new virtual-dispatch path produce correct
# runtime behaviour — the regression the fix addresses is HIR body-count
# bloat, which isn't a stable CI-level metric. Keep this test + the
# comment so a future refactor of `Object#in?(*values)` can't silently
# break the splat path.
# EXPECT: in_splat_ok

ok = true

ok = false unless 2.in?(1, 2, 3)
ok = false if     4.in?(1, 2, 3)

ok = false unless "b".in?("a", "b", "c")
ok = false if     "z".in?("a", "b", "c")

ok = false unless :b.in?(:a, :b, :c)
ok = false if     :z.in?(:a, :b, :c)

ok = false unless true.in?(true, false)
ok = false if     (1_u8).in?(2_u8, 3_u8, 4_u8)

puts(ok ? "in_splat_ok" : "in_splat_FAIL")
