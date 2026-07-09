# Repro for the NEXT self-host bootstrap floor exposed after session-25
# (String ivar-capture fix `20b9a2a7`).
#
# Symptom: the self-host stage2 compiler mis-infers the element types of a
# multiple-assignment destructuring of a Tuple. For
#   `bytes, count = method_returning_Tuple(StaticArray(UInt8,4), Int32)`
# stage2 gives `bytes` the UNION of BOTH tuple elements (`Int32 | Array(UInt8)`)
# instead of the first element, then emits `store ptr <union-value>` into a
# union payload slot -> llc rejects ("defined with type '...union' but expected
# 'ptr'"). The host-built stage1 lowers this correctly (0 unions, 0 bad stores).
#
# This is the reason a stage2-compiled `puts "hello"` fails to compile once
# String has correct ivars: String#ends_with?(Char) uses exactly this pattern
# via String.char_bytes_and_bytesize.
#
# In stage2 the tuple-returning method even lowers to `define void @make_bytes()`
# (return type dropped), so the root is a MultipleAssign / tuple element-type
# inference divergence in HIR, NOT a String-specific bug.
#
# Verify: compile with the host stage1 (bin/adamas) -> OK; compile with a
# self-compiled stage2 -> llc "store ptr <union>" failure.
#
# FIXED (session-26): the union mis-inference is gone. Root cause was NOT in the
# tuple element-type extraction itself but in `if index` truthiness: in the
# `tuple_element_type$$..._Int32` monomorphization the `Int32?` param `index`
# collapses to a bare Int32, yet its condition value transiently read as POINTER
# during body lowering, so `if index` lowered to `index != nullptr` -- which is
# FALSE for index 0. That sent element 0 down the `merged = union(all elements)`
# fallback branch. Fix = `sanitize_scalar_pointer_nil_checks`, a finalized-HIR
# pass that folds `scalar != nil` -> true / `scalar == nil` -> false (a bare
# scalar is never null; no valid program compares one to a null pointer).
# stage2 now compiles this file and `puts "hello"` with no llc union error.
# Residual (separate NEXT floor): a stage2-compiled binary of THIS file still
# segfaults at run time on the `uninitialized UInt8[4]` StaticArray value path
# (host stage1 runs it correctly, printing 65 then 3).

def make_bytes
  bytes = uninitialized UInt8[4]
  bytes[0] = 65_u8
  {bytes, 3}
end

bytes, count = make_bytes
puts bytes[0]
puts count
