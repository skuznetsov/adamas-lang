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

def make_bytes
  bytes = uninitialized UInt8[4]
  bytes[0] = 65_u8
  {bytes, 3}
end

bytes, count = make_bytes
puts bytes[0]
puts count
