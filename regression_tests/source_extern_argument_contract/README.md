# Numeric value conversion and source extern contract oracle

Successor to frozen 10905, whose four unsafe_as controls were invalid without
prelude: the original compiler reported that the method was undefined. Only
those four fixtures add the exact Object#unsafe_as body from pinned object.cr
and Pointer(T)#value primitive declaration from pinned primitives.cr. The
source library is unchanged. All expected output and other 48 fixtures remain
unchanged; the complete original-first matrix still runs before the candidate.

The FFI path must convert numeric values, while explicit unsafe_as must preserve
the bits. The inherited float-union controls distinguish payload dispatch from
same-width numeric Cast behavior. Unknown/nonnumeric union conversions and exact
callback ABI remain open capabilities.
