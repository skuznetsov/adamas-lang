# Crystal V2 Bootstrap TODO

Updated: 2026-04-20
Branch: `codegen`

This file is the active backlog only. Historical TODO detail before this
checkpoint remains recoverable from git history, especially:

- `65eb6f62^:TODO.md`
- archived full-file SHA256:
  `1fb4b76e8a0991a30a4716640d439cd791ecaa99035fd171adf5d31fd1eb9158`

## Current Goal

Reach a clean bootstrap corridor:

`original -> stage1 -> s2b -> s3b -> s4b -> s5b`

with normalized HIR/MIR/LLVM semantic equivalence across stages. In normal
development, prefer fast `--no-prelude` oracles; use `s1 -> s2b` as the main
integration gate and `s1 -> s5b` only occasionally.

## Active Blocker

`s1 -> s2b` does not produce `s2b` yet.

Baseline command:

```bash
BOOTSTRAP_STAGE_OUT=/tmp/cv2_bs_s2 \
BOOTSTRAP_CHAIN_STAGES=2 \
BOOTSTRAP_TIMEOUT_SEC=300 \
BOOTSTRAP_MEM_MB=4096 \
  scripts/build_bootstrap_stages.sh --stages 2 --out /tmp/cv2_bs_s2
```

Observed status:

- `s1_bootstrap` builds successfully with host Crystal.
- Stage1 plain and no-prelude smokes pass.
- Stage2 self-host build times out under `scripts/run_safe.sh`.
- Current failure class: timeout/no-progress before `STOP_AFTER_HIR`, not OOM
  and not a crash.

Important refined facts:

- `lower_main` is not stuck. `DEBUG_MAIN=1 DEBUG_MAIN_PROGRESS_EVERY=1` showed
  all 30 top-level expressions start and return.
- The live blocker is `process_pending_lower_functions` expansion:
  - queue reaches about `78k`
  - about `61k` functions lowered in the decisive pass
  - HIR functions grow about `3088 -> 64185`
  - process pending consumes about `248-260s`, then a later pending/safety-net
    pass starts and the run hits the 300s timeout.
- `CRYSTAL_V2_PENDING_EXPLOSION_TRACE=1` first deep enqueue:
  - `[PENDING_EXPLOSION] first deep Array inspect enqueued source=defer current=Object#inspect depth=1 queue=12325 name=Array(Array(Array(Tuple(UInt32, Array(Hash(String, UInt32))))))#inspect$IO`
- `DEBUG_VIRTUAL_TARGETS=1` showed that first deep enqueue is admitted through
  broad `Object#to_s` / `Object#inspect` virtual-target replay over deep
  compiler-internal containers.
- Later diagnostic with `DEBUG_PENDING_SOURCES=1 DEBUG_PENDING_SOURCES_EVERY=5000`
  showed the broader producer pattern by queue `35000`:
  - `Array#to_s: 5479`
  - `Array#inspect: 5476`
  - `Array#exec_recursive: 5448`
  - `Array#object_id: 2741`
  - `Hash::Entry#to_s: 1221`
  - `Hash::Entry#inspect: 814`
  - `Hash#to_s: 812`
  - `Hash#inspect: 810`
  - `Hash#exec_recursive: 798`
- Context-enhanced samples showed the dominant source contexts:
  - `Array#to_s` samples are enqueued from `Object#to_s`
  - `Array#inspect` samples are enqueued from `Object#inspect`
  - `Array#object_id` samples are enqueued from `Reference#same?`
  - `Hash#to_s` samples are enqueued from `Object#to_s`
  - `Hash#inspect` samples are enqueued from `Object#inspect`
  - `Hash#each` samples are enqueued from `Dir::Globber#glob`

## Refuted Fix Branches

Do not retry these without new evidence:

- Broad `Object`/`Reference` virtual-target replay gating alone.
  - It reduced or removed the first `[PENDING_EXPLOSION]`, but `process_pending`
    still lowered about `61454` functions and timed out.
- `emit_all_tracked_signatures` universal-method pruning alone.
  - The run never reached the relevant safety-net frontier; first explosion
    remained under `Object#inspect`.
- Replay gating + emit pruning combination.
  - Still timed out with essentially the same `process_pending` growth.
- `lower_function_if_needed_impl` defer/enqueue guard for universal helper
  families on deep generic/compiler-internal owners.
  - Did not move the active frontier; queue positions and first explosion
    stayed effectively unchanged.

## Fast Oracles

Run these frequently before expensive bootstrap attempts:

```bash
regression_tests/p2_bootstrap_semantic_emit_oracle.sh bin/crystal_v2
regression_tests/p2_pending_budget_no_prelude.sh bin/crystal_v2
regression_tests/p2_universal_helper_fanout_no_prelude.sh bin/crystal_v2
```

Current expected signals:

- `p2_bootstrap_semantic_emit_oracle_ok`
- `p2_pending_budget_no_prelude_ok process_delta=25 emit_delta=7 lower_missing_delta=30 total=103 max_queue=57`
- `p2_universal_helper_fanout_no_prelude_ok deep_helpers=0`

Important boundary:

- `src/crystal_v2.cr --no-prelude` is not yet a good green oracle; it currently
  exits `11` in an inline-yield recursion / force-return path before reaching
  the pending budget gate. Keep it as a separate future reducer.

## Next Work

1. Build a fast reducer/oracle for broad `Object#to_s` / `Object#inspect` /
   `Reference#same?` replay on generic containers before changing compiler
   behavior.
2. Inspect whether `Object#to_s` and `Object#inspect` are being handled as
   virtual replay demands when their bodies are just universal fallback
   adapters.
3. Only then attempt a bounded fix. Candidate direction: prevent universal
   fallback adapters from replaying every generic container owner unless a real
   runtime formatting/equality call requires the concrete owner.
4. After a bounded fix passes fast oracles, run the smallest integration gate:

```bash
BOOTSTRAP_STAGE_OUT=/tmp/cv2_bs_s2 \
BOOTSTRAP_CHAIN_STAGES=2 \
BOOTSTRAP_TIMEOUT_SEC=300 \
BOOTSTRAP_MEM_MB=4096 \
  scripts/build_bootstrap_stages.sh --stages 2 --out /tmp/cv2_bs_s2
```

5. If `s2b` is produced, compare `s1_bootstrap` and `s2b` on the fixed corpus
   before trying `s3b+`.

## Stop Conditions

- Do not run `s3b+` while `s1 -> s2b` cannot produce `s2b`.
- Do not increase timeout or memory to hide pending expansion.
- Do not modify stdlib/runtime.
- Do not land name-family guards that only remove one symptom while preserving
  the `~61k` process-pending expansion.
- If two more bounded containment fixes fail to move the frontier, pivot from
  heuristics to demand-provenance design.

## Strategic Track

The full demand-driven rewrite is documented in:

- `PLAN_DEMAND_DRIVEN_REWRITE.md`
- `PLAN_DEMAND_DRIVEN_REWRITE_RFC.md`

Those documents remain the architecture target. The current short-term track is
bootstrap containment plus fast no-prelude oracle coverage, not a full compile
path switch.
