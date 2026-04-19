# Codex status — closure-env ABI P1 scaffold

Date: 2026-04-19
Branch: `closure-env-abi-p1-wip`

## Current HEAD

- This status file is maintained as a handoff log; inspect `git log --oneline`
  for the exact latest commit hash after each Codex update.
- Latest Codex update in this file: entry-box requirement scaffold for boxed
  capture predeclaration.
- `a1fcb5fd docs: add closure env ABI handoff status`
- `85c39c79 scaffold(proc-abi): require seeded entry hoists for boxed locals`
- `cc4d0f31 perf(hir): cache debug env lookups`
- Parent context: `31878cbd` introduced I14-monotonic dominance by entry-block allocation.

## What changed after Claude's last handoff

1. Resolved the local `src/compiler/hir/ast_to_hir.cr` conflict between:
   - closure-env P1 scaffold (`BoxedLocal`, `LocalsSnapshot`, I14-monotonic), and
   - stashed perf/env-gate hoist (`@trace_shovel_types_enabled`, `@debug_type_literal_enabled`, negative env cache).

2. Landed `cc4d0f31`:
   - caches hot debug/env gates in HIR lowering;
   - keeps behavior unchanged when debug env vars are unset.

3. Hardened I14 in `85c39c79`:
   - `hoist_box_for_local` now takes `initial_value`;
   - emits the Box allocation in `function.entry_block`;
   - emits a seed `PointerStore` from the current local value;
   - rejects invocation unless `ctx.current_block == ctx.function.entry_block`.

## Important correction

Entry-block allocation alone was not enough. The previous zero-init model was only correct for variables whose current value was zero. A captured local with an earlier non-zero assignment, for example `counter = 5`, would read `0` from the Box after a late branch-local hoist.

Current invariant:

- P1 must predeclare boxed captures before branch/case/loop lowering.
- Box hoist must happen at local declaration / first assignment, with the current local value seeded into the Box.
- `lower_proc_literal` must not discover and late-hoist an already-initialized parent local from inside a branch. It should find `ctx.lookup_boxed_local(name)` or stop.

## Forward guards

Updated non-zero reducers:

- `regression_tests/conditional_closure_capture_repro.sh`
- `regression_tests/escaping_branch_closure_capture_repro.sh`

Both expect `12\n12` from `counter = 5; p.call(7); puts counter`. This catches the invalid "allocation + zero-init is enough" shortcut.

## Verification run

- `crystal build src/crystal_v2.cr -o bin/crystal_v2 --error-trace` — green, only the known `Random::DEFAULT` warning.
- `regression_tests/spawn_capture_block_param_repro.sh bin/crystal_v2` — exit 0, reproduced expected known-red sums `(16, 12)`.
- `regression_tests/conditional_closure_capture_repro.sh bin/crystal_v2` — exit 1, correct forward-guard output.
- `regression_tests/escaping_branch_closure_capture_repro.sh bin/crystal_v2` — exit 1, correct forward-guard output.
- `bin/crystal_v2 regression_tests/test_proc_basic.cr -o /tmp/test_proc_basic_codex && scripts/run_safe.sh /tmp/test_proc_basic_codex 5 512` — prints `7`, `50`, `proc_test_done`.
- `bin/crystal_v2 regression_tests/channel_ping_pong_repro.cr -o /tmp/channel_ping_pong_codex && scripts/run_safe.sh /tmp/channel_ping_pong_codex 10 512` — prints `channel_ping_pong_ok`.
- `git diff --check` — clean.

## Next safe step

Do not start the atomic Proc ABI flip until boxed-capture predeclaration is consumed at binding sites and verified.

Additive scaffold now present:

- `LoweringContext#require_entry_box_for_local(name)` stores function-scope, name-only entry-box requirements.
- `LoweringContext#entry_box_required?(name)` is the future binding-site guard.
- `collect_proc_literal_box_requirements(body, candidate_names)` finds proc literals nested in a body that reference candidate locals. It is intentionally dormant until P1 wires the two-stage flow:
  pre-scan owner body → mark requirements → hoist at local declaration / first assignment with the real initial value.
- `seed_entry_box_requirements_for_body` is wired behind `CRYSTAL_V2_SEED_ENTRY_BOX_REQUIREMENTS=1`; it seeds the requirement set but still does not change reads/writes because no binding site consumes it yet.

Next implementation unit should be additive or explicitly WIP:

1. Wire local declaration / first assignment lowering to call `hoist_box_for_local(ctx, name, payload_type, initial_value)` when `ctx.entry_box_required?(name)` and the binding still occurs in the function entry block.
2. Make `lower_proc_literal` / `lower_block_to_proc` require an existing `BoxedLocal` for boxed captures instead of late-hoisting.
3. Only then start the atomic MakeClosure/MakeProc ABI flip.
