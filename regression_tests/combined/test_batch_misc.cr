# Combined batch bundle (mechanical concat, byte-equality verified).
# Members: test_rescue postfix_if_member_call_no_parens unless_branch_local_writeback object_in_splat_broadcast io_puts_single_line env_nil_nonexistent file_join_splat slice_inherited_module_methods
# EXPECT: test_batch_misc_all_ok

# ===== test_rescue =====
# Test: exception handling
begin
  raise "test error"
rescue ex
  puts "caught: #{ex.message}"
end

begin
  arr = [1, 2, 3]
  puts arr[5]
rescue ex
  puts "index error caught"
end

puts "after rescue"

# ===== postfix_if_member_call_no_parens =====
flag = false
1_000_000.times do
  STDERR.puts "TRACE" if flag
end
puts "done"

# ===== unless_branch_local_writeback =====
# Regression: local mutations inside an unless branch must survive the branch
# merge. `lower_unless` used to save then-branch locals after popping the
# branch scope, restoring the pre-branch value.
#

plain = 0
unless false
  plain += 1
end
raise "plain" unless plain == 1

wrapping = 0
unless false
  wrapping &+= 1
end
raise "wrapping" unless wrapping == 1

puts "unless_branch_local_writeback_ok"

# ===== object_in_splat_broadcast =====
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

# ===== io_puts_single_line =====
puts "ok"

# ===== env_nil_nonexistent =====
# Regression test: ENV.[]? must return nil for non-existent keys
# Bug: union ABI extraction + re-wrap lost nil type_id, causing
# ENV.[]? to return non-nil (empty String) for missing env vars.
# Root cause: emit_union_wrap set type_id unconditionally without
# checking for null pointers from prior union ABI extraction.

key = "THIS_DOES_NOT_EXIST_XYZ_REGRESSION_987654"
v = ENV[key]?
if v.nil?
  puts "env_nil_ok"
else
  puts "FAIL: ENV[non_existent]? returned non-nil"
end

# ===== file_join_splat =====
# Regression test: File.join with multiple arguments
# Bug: splat argument handling only used first element, losing subsequent path components

a = "/tmp"
b = "subdir"
c = "file.txt"

result2 = File.join(a, b)
result3 = File.join(a, b, c)

if result2.includes?(b) && result3.includes?(c)
  puts "join_ok"
else
  puts "FAIL: join2=#{result2}, join3=#{result3}"
end

# ===== slice_inherited_module_methods =====
# Regression: inherited module methods on generic struct specializations.
# Slice(UInt8) inherits empty? from Indexable via Indexable::Mutable.
# These methods must be materialized via deferred module lookup, not stubs.
# Bug: @class_included_modules stored stripped names but @module_defs used
# parameterized keys, causing find_module_def_recursive to miss methods.

# Test 1: Bytes.empty? (inherited from Indexable#empty? via Indexable::Mutable)
empty_slice = Bytes.empty
fail = false

unless empty_slice.empty?
  STDERR.puts "FAIL: Bytes.empty should be empty"
  fail = true
end

# Test 2: Non-empty slice
filled = Bytes.new(3, 42_u8)
if filled.empty?
  STDERR.puts "FAIL: Bytes.new(3) should not be empty"
  fail = true
end

# Test 3: Slice#size still works (getter, not inherited — should not regress)
unless filled.size == 3
  STDERR.puts "FAIL: size should be 3"
  fail = true
end

if fail
  exit 1
end

puts "slice_inherited_ok"

puts "test_batch_misc_all_ok"
