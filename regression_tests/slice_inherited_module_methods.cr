# Regression: inherited module methods on generic struct specializations.
# Slice(UInt8) inherits empty? from Indexable via Indexable::Mutable.
# These methods must be materialized via deferred module lookup, not stubs.
# EXPECT: slice_inherited_ok
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
