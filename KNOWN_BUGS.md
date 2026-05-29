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
