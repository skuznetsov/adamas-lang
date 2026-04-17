# Crystal V2 — Known Bugs

Known V2-specific compiler bugs that have reducers but no fix yet. Pin the
reducer path and (where possible) the relevant file/line so the next pass
doesn't have to re-derive context.

## In?(Array) — STUB on `Int32#in?$Array(Int32)` at runtime
- **Reducer**: `/tmp/cv2_nor/reducers/in_array_range.cr`
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
- **Status**: not caused by the bare-Tuple guard fix; separate follow-up.
