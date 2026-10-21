# Numeric value conversion and bit reinterpretation controls

Original-first runtime parity for signed and unsigned fixed extern conversions,
plus emitted LLVM opcode assertions inside `__adamas_main`. Existing fixtures
are byte-identical to packet10907. UInt32 probes use 3,000,000,000 to distinguish
unsigned conversion semantics. The htonl check assumes this arm64 Darwin host
is little-endian. Explicit unsafe_as support is copied exactly from the pinned
stdlib into the no-prelude fixtures; the stdlib itself is unchanged.

This packet complements the 52-case source admission packet; it does not claim
floating-point overflow or NaN parity, callback ABI correctness, or bootstrap.
