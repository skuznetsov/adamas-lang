# Missing-Call Incremental Scan Frontier SDD

Document status: **GUARD-ONLY VERIFIED; PRODUCTION PROMOTION REJECTED.**

Current frontier: `AstToHir#lower_missing_call_targets` retains the legacy full
HIR scan as production authority. The default-off exact shadow can reconstruct
ordered raw and occurrence-admitted demand segments, but it still discovers
segment changes by performing that full scan. Per-function raw-local telemetry
now separates stable HIR demand input from global availability context and is
explicitly non-authoritative. A pre-scan target-state replay model is also
measured and explicitly refuted by occurrence-order side effects. B4-F remains
measured-red.

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
- Raw-local `{body_revision, demand_revision}` equality may be recorded as
  orientation evidence only when the log also states
  `scope=per_function_raw`, `authority=full_scan`, and `promotion=forbidden`.
- Raw-local exact equality and occurrence-availability mismatch are separate
  counters; their coexistence is an expected falsifier, not a contradiction.
- A default-off pre-scan target snapshot may be compared with the authoritative
  occurrence-admitted segment only as a falsifier. Every row must state
  `scope=pre_scan_target_snapshot`, `authority=full_scan`, and
  `promotion=forbidden`.
- A default-off pre-canonical occurrence index may copy ordered
  `(Function#id, Block#id, Call#id, raw_name)` records before the scan and
  compare them with the raw identities observed on entry to the authoritative
  scan. Its scope is occurrence identity/order only; every row states
  `authority=full_scan` and `promotion=forbidden`.
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
- Raw-local stability does not certify function domain/order, target body,
  lowering state, queue membership, definition/type lookup, class/include/enum
  metadata, RTA side state, or public mutable HIR/AST aliases.
- Canonical post-rewrite raw demand plus a pre-scan or final target-state
  snapshot cannot reconstruct occurrence-time availability. A resolver can
  materialize a target between two occurrences during the scan.
- Exact pre-canonical occurrence identity/order does not certify canonical
  target identity, resolver purity, argument/block ABI, target availability, or
  semantic parity. It cannot authorize replay or a skipped scan.
- A sufficient replay transcript would need pre-canonical occurrence identity,
  side-effect position, ordered function/block/instruction domain, resolver
  metadata epochs, target-state transitions, RTA/worklist state, and budget
  order. That is not admitted as a bounded per-segment certificate.
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
12. **Raw/availability separation.** The raw-local comparison can describe
    unchanged per-function HIR input, but it cannot admit an available segment.
    Any cached/current availability difference is counted independently while
    the full scan remains authority.
13. **Occurrence-time causality.** Availability is sampled after each
    canonicalization side effect, not once per target or segment. Two scans can
    end with the same canonical raw names and target body/state while admitting
    different demand because the materializing occurrence moved.
14. **Pre-canonical identity boundary.** An immutable occurrence snapshot copies
    stable function/block/call ids plus the raw call spelling without invoking
    a resolver. Any added, removed, reordered, replaced, or renamed occurrence
    rejects that observation window. Equality proves traversal identity/order
    only; all semantic coordinates remain outside the certificate.

## 5. Execution order

1. Capture the immutable pre-canonical occurrence index without resolving or
   mutating calls.
2. Capture pre-scan target body/state/queue snapshots for the diagnostic model.
3. Capture per-function revision vectors immediately before the legacy HIR
   collection window.
4. Run the unchanged full HIR collection, record raw occurrence identities on
   entry, and collect exact raw/admitted segments.
5. Compare the immutable index with the observed occurrence identity/order;
   any mismatch keeps the diagnostic inconclusive.
6. Replay current canonical raw names against the pre-scan snapshot and compare
   with occurrence-time admission; any mismatch refutes that replay model.
7. Capture vectors immediately after collection, before enqueue/process.
8. Refresh exact cached segments as today.
9. Compare each would-reuse decision with exact segment equality.
10. Emit bounded false-reuse diagnostics.
11. Continue through the unchanged legacy budget/queue/process path.

## 6. Falsifier roster

- **F1 — function replacement:** remove and recreate the same symbol; identity
  and function-set revision must change even when body/state labels match.
- **F2 — call rewrite:** add a call, then rewrite `method_name`; the owning
  demand revision must change and exact raw order must reflect the new name.
- **F3 — same-scan materialization:** a later accessor/union resolution changes
  body/state after an earlier call occurrence; occurrence-admitted parity must
  remain exact and would-reuse must be rejected. Implemented by
  `regression_tests/missing_incremental_same_scan_union_accessor.sh`. The real
  missing-call loop runs both occurrence orders. Both canonicalize to the same
  getter demand, but demand-first admits the getter while materializer-first
  does not; the pre-scan replay model reports a mismatch in both traces.
- **F4 — definition replacement:** replace a `DefNode` under an existing key;
  definition revision must change, while reinstalling the same node is a no-op.
- **F4b — inferred type replacement:** replace an inferred function return type;
  type revision must change, while reinstalling the same type is a no-op.
- **F5 — queue order/duplicate:** append, duplicate, and clear queue entries;
  queue revision and exact snapshot must observe each semantic change.
- **F6 — mutation census:** bounded source search must find no direct admitted
  state/queue/definition/type writes outside the named helpers and no
  production instruction/call mutation that bypasses the body/demand mutator.
  A seeded direct `Call#method_name=` bypass must be detected as raw-local false
  reuse; this qualifies the negative detector without claiming public closure.
- **F7 — staged system gate:** isolated staged snapshot HIR plus same-source
  ON/OFF iteration boundary must preserve exact raw/admitted/budget/queue shape.
- **F8 — pre-canonical identity/order:** direct-first and materializer-first F3
  runs must retain distinct immutable raw occurrence order even though both
  live calls canonicalize to the same getter name. Owned rewrite/insertion must
  leave the old snapshot unchanged, change demand revision, and make a fresh
  index differ.

## 7. Stop rules

- Stop on the first unchanged certificate paired with a changed exact segment.
- Stop if mutation ownership cannot be bounded by source inventory.
- Stop if default-off behavior, HIR output, no-prelude smoke, or staged ON/OFF
  shape diverges.
- Do not extend the timeout or add demand caps to rescue a failed gate.

## 8. LTP/WBA audit card

- **Window or trigger:** repeated missing-call iteration after HIR growth.
- **Transport corridor:** immutable pre-canonical occurrence index -> HIR
  mutation API -> revision vector -> exact shadow comparison -> unchanged
  legacy queue/process path.
- **Legal move:** guard-only would-reuse classification.
- **Boundary safety:** full scan and occurrence-time admission remain authority.
- **Lexicographic potential:** `(semantic mismatches, false reuse, abort-stub
  obligations, wall time, peak RSS, remaining missing targets)`.
- **Recompute safety:** recompute the complete vector and exact segments after
  every observed mutation window.
- **Dual frame:** immutable occurrence identity/order plus per-function demand
  revision and global semantic revisions.
- **Local certificate:** exact occurrence identity/order, unchanged vector, and
  exact segment equality at the same iteration boundary. This remains
  observational because resolver side effects are not replayed.

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
  `missing_revision_ledger_spec.cr`, and the two-order same-scan accessor
  regression.
- **Falsifiers:** F1-F8.
- **Boundary:** default-off guard-only; no production scan skip.
- **Observed focused gate:** the exact-shadow group passes 15 examples; the
  integrated same-scan accessor/union regression and ownership census pass.
- **Source-matched telemetry:** iterations 1-3 observed 603, 1539, and 7471
  raw-local stable segments with zero raw-local false reuse, while 198, 345,
  and 984 of those segments changed occurrence availability. Full/shadow raw
  and available vectors remained exact through iteration 3. The pre-scan replay
  model observed 603, 1539, and 7471 stable segments with zero mismatch on that
  ordinary trace; the two-order F3 counterexample still refutes universal
  sufficiency, so these zeroes are not promotion evidence.
- **Pre-canonical staged telemetry:** a source-matched stop after iteration 3
  observed exact indexed/entered occurrence counts of 7517, 11740, 41080, and
  113005, with identity/order match on all four rows. Full/shadow raw and
  available vectors also matched. The same rows still exposed 253, 621, and
  1801 raw-stable availability mismatches at iterations 1-3; identity/order
  equality is therefore not semantic replay evidence. The diagnostic exited 0
  at the requested boundary after about 105 seconds, before processing
  iteration 3, and is not a B4-F or speed certificate.
- **Adversary verdict:** robust for the bounded observational guard, vulnerable
  for the diagnostic implementation, and broken for bounded canonical
  availability replay as production authority.
- **Next local track:** use the immutable identity/order boundary to classify a
  read-only occurrence transcript of canonicalization side effects, then
  falsify whether any resolver family is actually pure. Do not replay even a
  matching occurrence until argument/block ABI, definition/type/class/include/
  enum/RTA metadata, target-state transitions, and budget order are bounded.
  Public mutable aliases remain a rejected boundary.
