# Abstract Int source declaration identity

These nine original-first cases exercise the declaration key collision between
abstract Int and concrete Int32, which share a physical storage TypeRef. Eight
runtime controls cover declaration order, aliases, qualified owners, methods,
full-width signed/unsigned arguments and multiple live numeric instances. One
semantic negative rejects a nonnumeric argument. The runner and fixtures are
byte-for-byte copies of packet10721 except for the case inventory.

The two remaining packet10721 negatives deliberately call a C function with a
Bool in the selected body. They expose the independent FFI contract gap, not
source overload-key identity. They remain intact in packet10721 and must pass
after that separate fix; run10939 qualifies the full eleven-case matrix on the
composed compiler. This packet does not change or relax any production checks.

All native compiler and program execution uses scripts/run_safe.sh. Exact
stdout, semantic status 1/no executable, and primary diagnostics are required.
Prelude, constructor family order, bootstrap and LavinMQ parity remain open.
