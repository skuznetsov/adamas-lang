# Explicit Void generic arguments

Run `regression_tests/explicit_void_generic_args_repro.sh /path/to/adamas`.
The runner qualifies the fixtures with original Crystal before testing Adamas.
Every compiler and program runs through `scripts/run_safe.sh`.

- `pointer_void_owner_overload`: ordinary `Pointer(Void).new` chooses the
  `Pointer(Void)` overload, while an explicit nested pointer chooses its own
  overload (stdout `AB`).
- `pointer_void_alias`: an alias for `Void` preserves the element type (`A`).
- `pointer_void_static_index`: generic owners in static `Type[...]` expressions
  preserve explicit `Void` and distinct nested pointer types (`AB`).
- `reject_nested_as_void`: an actual `Pointer(Pointer(Void))` cannot satisfy a
  `Pointer(Void)` parameter; require type rejection, exit 1 and no executable.

These fixtures use the empty prelude. `Pointer.null` is a stdlib method and is
outside this primitive-only contract. Unknown and typeof-derived fallback
behavior is unchanged and needs separate qualification.
