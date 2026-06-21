# Minimal standalone reproducer for the s2b STARTUP CRASH root: the String#split
# nilable-`limit` MONOMORPHIZATION COLLISION (distinct from the wrong-count bug in
# string_split_default_nil_limit_repro.cr).
#
# When BOTH an Int32-limit Char-separator split AND a nil-limit Char-separator split
# exist in the same program, the shared block-specialized inner function
# `String#split$Char$$arity3_block` is monomorphized with a SINGLE `i32 %limit`
# signature (driven by the Int32 call-site). The nil-limit wrapper
# `String#split$Char_Nil_Bool` holds `limit` as a nilable `ptr` (null for nil), and
# bridges to the i32 signature with an UNGUARDED `load i32, ptr %limit` on the NULL
# pointer -> SIGSEGV.
#
# This is exactly the s2b startup crash: the compiler's own code has Int32-limit
# Char splits, poisoning `arity3_block` to `i32 %limit`; then Dir::Globber's
# `glob.split('/', remove_empty: true)` (nil limit) hits the null `load i32` and
# crashes during require-glob resolution. See docs/string_split_overload_and_nil_limit_census.md
# and memory `s2b_startup_crash_split_glob_localization`.
#
# CORRECT behavior: a=2 (limit 2 -> ["a", "b/c/d"]), b=4 (remove_empty -> 4 parts),
# and NO crash. Currently this program SIGSEGVs before printing.
a = "a/b/c/d".split('/', 2)                    # Int32 limit -> ["a", "b/c/d"] (size 2)
b = "a/b/c/d".split('/', remove_empty: true)   # nil limit, shares arity3_block -> 4
STDERR.puts "RESULT int_limit=#{a.size} nil_limit=#{b.size}"
STDERR.flush
exit(0)
