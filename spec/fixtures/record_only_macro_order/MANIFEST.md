# Record-only macro declaration probes

Run the fixtures independently with the stock Crystal compiler and the
candidate compiler, using the same no-prelude mode.

- `inheritance_parent_before_child.cr`: accepted; stdout is `A\n`.
- `inheritance_child_before_parent.cr`: rejected because
  `LaterParent` is declared after its use as the superclass.
- `namespace_parent_declared.cr`: accepted; stdout is `A\n`.
- `namespace_parent_missing.cr`: accepted by the stock compiler; it exits 0
  and emits no stdout. This fixture does not establish that an undeclared
  namespace should be rejected, so it is only a parity control.
- `enum_body_method_native_control.cr`: accepted; stdout is `A\n`.
