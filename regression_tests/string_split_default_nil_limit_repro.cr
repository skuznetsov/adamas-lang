# Minimal standalone reproducer for BUG 1 = String#split OVERLOAD MISDISPATCH.
# This is INDEPENDENT of Bug 2 (the nilable-limit monomorphization collision that is the
# actual s2b startup crash; see string_split_int32_nil_limit_collision_repro). The earlier
# "nilable-limit miscompile underlying the s2b crash" wording was STALE and is refuted by
# the census (docs/string_split_overload_and_nil_limit_census.md).
#
# Bug 1: `"a/b/c/d".split('/')` with ONLY the Char argument mis-resolves to the no-separator
# WHITESPACE overload `def split(limit : Int32? = nil)` (stdlib string.cr:3954). The Char
# `'/'` (codepoint 47) is bound to that overload's `limit : Int32?` parameter, so the string
# is split on whitespace (none present) -> 1 part. Decisive disambiguator: `"a a a".split('b')`
# yields 3 (a real whitespace split ran), proving it is overload misdispatch, NOT a nil-limit
# mis-evaluation inside the Char-separator overload. With a 2nd positional arg (`split('/', 2)`)
# or a named arg (`remove_empty: true`) the correct Char overload is selected. Root: overload
# resolution (ast_to_hir.cr resolve_untyped_overload prefer_non_named skips the named-only
# Char overload). Fix target = overload resolution, NOT backend.
a = "a/b/c/d".split('/')                       # default nil limit -> SHOULD be 4
b = "a/b/c/d".split('/', remove_empty: true)   # nil limit, remove_empty -> 4 (works today)
STDERR.puts "RESULT default=#{a.size} remove_empty=#{b.size}"
STDERR.flush
exit(0)
