# Generic pointer readiness

`pointer_generic_owner.cr` requires the compiler to admit the legal `Void*`
shorthand as a concrete generic argument. `malloc` supplies the pointer without
requiring library methods in the empty prelude. Crystal 1.22.1 prints `A` and a
newline; Adamas must match in lazy and eager modes.

The focused HIR suite also rejects unknown pointees, non-type constants, and
unresolved active formals beneath pointer and StaticArray suffix syntax.
