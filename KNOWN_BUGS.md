# Crystal V2 — Known Bugs

Known V2-specific compiler bugs that have reducers but no fix yet. Pin the
reducer path and (where possible) the relevant file/line so the next pass
doesn't have to re-derive context.

## In?(Array) — STUB on `Int32#in?$Array(Int32)` at runtime
- **Status**: known-red, separate follow-up. Not fixed by the bare-Tuple
  `in?` fallback guard (commit `28036d5c`, 2026-04-16) — that fix closed an
  HIR bloat path, this is a distinct RTA/lowering gap.
- **Reducer (committed)**: `regression_tests/in_array_stub_repro.sh`
  - Stable command: `regression_tests/in_array_stub_repro.sh bin/adamas`
  - Exits 0 while the bug reproduces (STUB observed), exits 1 once fixed.
  - Self-contained source (also embedded in the script):
    ```crystal
    a = [1, 2, 3]
    puts 2.in?(a)
    r = 1..3
    puts 2.in?(r)
    ```
- **Symptom**: runtime abort
  ```
  STUB CALLED: Int32$Hin$Q$$Array$LInt32$R
  [CRASH] Abort (exit 134)
  ```
- **Scope**: occurs at baseline (independent of the 2026-04-16 bare-Tuple
  guard in `lower_call`). Happens when a local of type `Array(T)` is passed
  as the only arg to `.in?`. The mangled symbol `Int32#in?$Array(Int32)`
  resolves to a STUB, meaning the method body was registered/referenced but
  never lowered.
- **Likely area**: `Object#in?(collection : Object)` monomorphization skips
  lowering for `X#in?$Array(T)` when `collection` is a local array. Probably
  related to how `remember_callsite_arg_types` deliberately bypasses `#in?`
  (`ast_to_hir.cr:56715`: `return if base_key.ends_with?("#in?")`) combined
  with an RTA tracking gap for local-bound `Array`.
- **Regression tests (combined suite)** likely exercising this path fail
  with the same STUB signature — see `regression_tests/combined/` output.

## Phantom generic type from constructor call in a fallback block
- **Status**: known-red, found 2026-07-07 (session-13) while closing L11.
  Pre-existing: reproduces on pre-L11-fix compilers too.
- **Reducer (committed)**: `regression_tests/phantom_generic_ctor_block_repro.sh`
  - Stable command: `regression_tests/phantom_generic_ctor_block_repro.sh bin/adamas`
  - Exits 0 while the bug reproduces (crash), 1 once fixed.
- **Symptom**: segfault/bus error at an address of shape `0x{v}0000{type_id}`
  (the object's leading `{i32 type_id, i32 field}` bytes dereferenced as a
  pointer), e.g. `0x50000043c` with `type_id=1084`, `v=5`.
- **Mechanism**: `Box` is NOT generic, but lowering `Box.new(6)` as the tail
  of a block that reaches the inline-yield fallback (proc-materialized) path
  synthesizes a phantom type `Box(Int32)` (symbols `Box$LInt32$R$...`) with
  no ivar metadata. Its getter lowers `@v` as a pointer field at offset 0
  (`load ptr [self+0]; load i32 [that]`) while `initialize`/`$Dnew` use the
  real layout — the getter derefs the object header bytes as a pointer.
  Trigger needs ≥2 same-shape callsites whose blocks tail-call a constructor
  with args (triple-nested `with_map` exceeds `INLINE_YIELD_MAX_REPEAT=2`).
- **Likely area**: block-return-type naming for constructor tails
  (`block_return_type_name` / lowered-block inference) producing
  `Name(ArgTypes)` for a non-generic class and `type_ref_for_name`
  registering it as a fresh type without ivars. Family:
  Hash dual-TypeRef phantom (`9641755d`).
