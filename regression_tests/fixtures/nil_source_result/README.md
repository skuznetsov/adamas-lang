# Nil source-result preservation

A proven Nil is a concrete source result, not a placeholder for a second
return lookup. Deferred callback-bound Nil results retain their overload,
including explicit and implicit returns. Nullable returning arms remain
separate and incompatible Int32/union returns must still be rejected.

The unrelated wrong_outer_early_return falsifier still fails with an unresolved
T diagnostic and is not certified by this gate. Void/pointer placeholder
recovery is unchanged by this Nil-specific correction.
