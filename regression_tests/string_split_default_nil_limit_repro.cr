# Minimal standalone reproducer for the String#split nilable-`limit` miscompile that
# underlies the s2b startup crash (memory: s2b_startup_crash_split_glob_localization).
#
# `String#split(separator : Char, limit = nil, *, remove_empty = false)` with the DEFAULT
# nil limit and remove_empty=false returns the WRONG count: the nil `limit` is mis-handled
# (treated as a small int <= 1), so `if limit && limit <= 1; yield self; return` fires and
# only ONE part is produced. With `remove_empty: true` the same nil-limit path works.
#
# In the full self-host compiler the SAME nilable-limit mishandling is worse: the inner
# `String#split$Char$$arity3_block` monomorphizes with `i32 %limit` (some site passes an
# Int32 limit), and the Globber's `glob.split('/', remove_empty: true)` (limit=nil)
# coerces Nil->i32 by `load i32, ptr %limit` on a NULL ptr -> SIGSEGV. Same root: nilable
# `limit` lowering. This minimal probe reproduces the wrong-count manifestation directly.
a = "a/b/c/d".split('/')                       # default nil limit -> SHOULD be 4
b = "a/b/c/d".split('/', remove_empty: true)   # nil limit, remove_empty -> 4 (works today)
STDERR.puts "RESULT default=#{a.size} remove_empty=#{b.size}"
STDERR.flush
exit(0)
