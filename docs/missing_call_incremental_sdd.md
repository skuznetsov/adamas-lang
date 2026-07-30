# Missing-Call Incremental Scan Frontier SDD

Document status: **GUARD-ONLY VERIFIED; PRODUCTION PROMOTION REJECTED.**

Current frontier: `AstToHir#lower_missing_call_targets` retains the legacy full
HIR scan as production authority. The default-off exact shadow can reconstruct
ordered raw and occurrence-admitted demand segments, but it still discovers
segment changes by performing that full scan. B4-F remains measured-red.

Bounded context:

- HIR function creation, removal, and body mutation in
  `src/compiler/hir/hir.cr`;
- function-definition, lowering-state, pending-queue, and HIR call rewrites in
  `src/compiler/hir/ast_to_hir.cr`;
- function-return/type-table mutations that can change call resolution;
- exact shadow falsifiers in
  `spec/hir/missing_incremental_shadow_spec.cr`.

ProblemCardRef: repeated missing-call scans are expensive, but skipping a
function without a complete mutation certificate can lose a concrete lowering
demand and emit an LLVM abort stub.

## 1. Admitted surface

- The legacy full scan, exact first-seen ordering, budget prefix, work queue,
  and function-count stop remain production authority.
- Monotonic in-memory revisions may describe observed HIR/function-definition/
  lowering-state/queue mutations.
- A default-off shadow may report whether a revision certificate *would* reuse
  a segment and compare that decision with the exact full-scan result.
- Any missing, wrapped, inconsistent, or unqualified revision fails closed to
  rescan.
- Revision coordinates remain a vector. They are not folded into one readiness
  score or treated as a performance result.

## 2. Rejected surface

- No revision certificate may skip a production scan in this slice.
- Raw function count, function-array length, object address, wall time, or a
  probabilistic fingerprint is not an invalidation certificate.
- An end-of-scan body/state snapshot cannot replace occurrence-time admission.
- Queue membership alone cannot decide availability.
- A body/state/queue revision does not certify function-definition lookup,
  module/include resolution, or same-scan accessor materialization.
- No speedup, B4-F admission, or post-process fixed-point claim follows from a
  zero false-reuse count.

## 3. Guard-only revision vector

The implemented diagnostic tracks these monotonic coordinates:

```text
MissingScanRevisionVector {
  function_set_revision
  hir_body_revision
  function_def_revision
  function_type_revision
  lowering_state_revision
  pending_queue_revision
  function_body_revision
  function_demand_revision
}
```

The first six coordinates are global invalidators. The last two coordinates are
owned by one live `Function#id`. This is deliberately conservative: global
coordinates may over-invalidate, but an unchanged vector must not hide a
changed exact segment.

## 4. Design laws

1. **Mutation ownership.** Every admitted coordinate has one write API. Direct
   writes outside that API are a falsifier, not an alternate route.
2. **Semantic bumps.** New/replaced/removed semantic state bumps exactly once;
   no-op writes do not need to bump.
3. **Stable identity.** Function segment identity is monotonic `Function#id`.
   Remove/recreate is a new identity even under the same symbol.
4. **Demand mutation.** Adding/replacing a `Call`, rewriting its
   `method_name`, changing its arguments, or changing function params/return
   type bumps the owning function's demand revision. Non-call instruction
   insertion/replacement need not bump the demand coordinate, but still changes
   the HIR body coordinate.
5. **Body mutation.** Function creation is not a body. Adding an instruction or
   a real terminator changes body state and bumps the HIR body coordinate.
6. **Definition mutation.** A new or different `DefNode` under a function key
   bumps the function-definition coordinate. Reinstalling the same node does
   not.
7. **Type-table mutation.** A new or different inferred function type bumps
   the function-type coordinate. Reinstalling the same type does not.
8. **State and queue mutation.** Lowering-state changes and queue order/content
   changes use centralized helpers. Duplicate queue entries are observable.
9. **Same-scan side effects.** The certificate is sampled immediately around
   the pure HIR collection window. Any scan-time coordinate change rejects
   would-reuse for that iteration; intentional queue/process mutations remain
   inputs to the next iteration's certificate.
10. **Closed-world census.** The compiler source must contain no direct mutation
    bypasses. Public mutable HIR arrays/properties remain an explicit residual
    boundary: external/spec-only mutation is not a production certificate and
    must never authorize a skipped scan.
11. **Fail closed.** Revision equality is necessary, never sufficient, until the
   exact full-scan shadow reports no false reuse across the admitted gates.

## 5. Execution order

1. Capture per-function revision vectors immediately before the legacy HIR
   collection window.
2. Run the unchanged full HIR collection and collect exact raw/admitted
   segments.
3. Capture vectors immediately after collection, before enqueue/process.
4. Refresh exact cached segments as today.
5. Compare each would-reuse decision with exact segment equality.
6. Emit bounded false-reuse diagnostics.
7. Continue through the unchanged legacy budget/queue/process path.

## 6. Falsifier roster

- **F1 — function replacement:** remove and recreate the same symbol; identity
  and function-set revision must change even when body/state labels match.
- **F2 — call rewrite:** add a call, then rewrite `method_name`; the owning
  demand revision must change and exact raw order must reflect the new name.
- **F3 — same-scan materialization:** a later accessor/union resolution changes
  body/state after an earlier call occurrence; occurrence-admitted parity must
  remain exact and would-reuse must be rejected.
- **F4 — definition replacement:** replace a `DefNode` under an existing key;
  definition revision must change, while reinstalling the same node is a no-op.
- **F4b — inferred type replacement:** replace an inferred function return type;
  type revision must change, while reinstalling the same type is a no-op.
- **F5 — queue order/duplicate:** append, duplicate, and clear queue entries;
  queue revision and exact snapshot must observe each semantic change.
- **F6 — mutation census:** bounded source search must find no direct admitted
  state/queue/definition/type writes outside the named helpers and no
  production instruction/call mutation that bypasses the body/demand mutator.
- **F7 — staged system gate:** isolated staged snapshot HIR plus same-source
  ON/OFF iteration boundary must preserve exact raw/admitted/budget/queue shape.

## 7. Stop rules

- Stop on the first unchanged certificate paired with a changed exact segment.
- Stop if mutation ownership cannot be bounded by source inventory.
- Stop if default-off behavior, HIR output, no-prelude smoke, or staged ON/OFF
  shape diverges.
- Do not extend the timeout or add demand caps to rescue a failed gate.

## 8. LTP/WBA audit card

- **Window or trigger:** repeated missing-call iteration after HIR growth.
- **Transport corridor:** HIR mutation API -> revision vector -> exact shadow
  comparison -> unchanged legacy queue/process path.
- **Legal move:** guard-only would-reuse classification.
- **Boundary safety:** full scan and occurrence-time admission remain authority.
- **Lexicographic potential:** `(semantic mismatches, false reuse, abort-stub
  obligations, wall time, peak RSS, remaining missing targets)`.
- **Recompute safety:** recompute the complete vector and exact segments after
  every observed mutation window.
- **Dual frame:** per-function demand revision plus global semantic revisions.
- **Local certificate:** unchanged vector and exact segment equality at the
  same iteration boundary.

No Collapse/promotion is admitted until recomputed global potential preserves
semantic zeroes and improves the full B4-F corridor.

## 9. Value-proxy check

- **Intended value:** safe, faster original-to-produced bootstrap.
- **Orientation proxies:** changed segment count, would-reuse count, revision
  invalidation count.
- **Protected qualities:** exact call order, occurrence admission, body
  availability, budget prefix, queue order, produced-compiler runtime behavior.
- **Counter-metrics:** false reuse, mismatch count, wall time, peak RSS,
  remaining missing targets, missing produced artifact.
- **Decision:** revision/reuse counts remain orientation only. B4-F plus semantic
  smokes remain the capability gate.

## 10. Current implementation seal

- **Source/spec:** `hir.cr`, `ast_to_hir.cr`,
  `missing_incremental_shadow_spec.cr`,
  `missing_revision_ledger_spec.cr`.
- **Falsifiers:** F1-F7.
- **Boundary:** default-off guard-only; no production scan skip.
- **Observed staged gate:** 301 HIR examples passed with two existing pending
  examples; source-matched iteration 3 preserved exact full/shadow demand
  vectors with zero false reuse.
- **Adversary verdict:** robust for the bounded observational guard, vulnerable
  for universal mutation ownership or cached-scan authority.
- **Next local track:** isolate scan-side mutation, add an integrated F3
  accessor/union materialization falsifier, and only then seek non-zero stable
  candidates. Cached segments remain non-authoritative.
