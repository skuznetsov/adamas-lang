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
- A default-off provenance aggregate may correlate occurrence-admitted,
  bodyless demand with the prior and current per-function HIR body/demand
  revisions and the immediately prior post-enqueue target snapshot. It may
  distinguish stable from new-or-changed source input and report scan-window
  invalidation as an orthogonal coordinate. Target classes may overlap when
  different source classes demand the same target; the aggregate is not a
  per-target causal partition.
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
- Stable-source or immediately requeued-target counts do not bound the cost of
  resolving or lowering new demand. A small count cannot authorize a skip, and
  a large count would still require a complete availability certificate.
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
- **Observed focused gate:** the exact-shadow group passes 17 examples; the
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
- **Source-provenance staged telemetry:** a source-matched stop after iteration
  2 observed 7,740 and 8,067 admitted bodyless occurrences at warm iterations
  1 and 2. Only 42 and 225 occurrences came from source functions whose HIR
  body/demand input was stable across the immediately prior iteration; 17 and
  66 of 1,962 and 2,630 unique targets had at least one such source. The
  immediately prior queue contributed only 17 and 65 bodyless targets. The
  authoritative full and exact-shadow demand vectors still matched, while the
  pre-scan availability replay had 24 model mismatches at iteration 2. This
  refutes stable-source rescanning and immediate target retry as the dominant
  sampled cost; it does not prove that changed-source work is intrinsically
  necessary or identify its origin.
- **Force-lowering staged telemetry:** two source-matched CPU samples during
  missing iteration 1 place 312/373 and 364/414 main-thread samples in pending
  function processing. The later sample places 318/414 samples in
  `lower_method`, including a 105-sample synchronous
  `force_pending_call_targets_for_return_type` subtree and a nested 92-sample
  force-lowering subtree. Exact process gates report 1,860 admitted force
  calls over 1,306 names after iteration 0 and 9,409 calls over 5,801 names
  after iteration 1. The warm delta is therefore 7,549 admissions but only
  4,495 newly observed exact names; 3,054 admissions are to an already observed
  name or repeat a new name within the interval. This is an amplification
  certificate, not a redundant-body certificate: the force helper reports an
  admitted invocation even when the lowering implementation later returns
  without materializing a body.
- **Force-lowering outcome telemetry:** a source-matched iteration-1 gate
  partitions all 9,409 admitted calls by request state and visible result.
  Pending requests account for 3,930 calls: 3,624 materialize the requested
  body and 306 have no visible body/function-count effect. NotStarted requests
  account for 5,479 calls: 152 materialize the requested body, 15 materialize
  another symbol, and 5,312 have no visible effect. The dominant no-effect
  names are bare method-family aliases such as `Crystal::Hasher#reference`
  (262 calls), while the useful specialization
  `Crystal::Hasher#reference$Reference` is first admitted through Pending.
  This refutes a global Pending-only guard: 167 admitted NotStarted calls still
  produce visible materialization across the combined force callsites. It does
  not yet attribute those useful calls to the three-name helper, so a
  helper-wide guard is not admitted either. The diagnostic is default-off and
  records no persistent state.
- **Local exact-name dedup:** the three-name return-type helper now skips only
  alternatives whose spelling is exactly equal to an earlier argument in the
  same invocation. It allocates no set, stores no cross-call state, and leaves
  alias/canonical resolution unchanged. At the source-matched iteration-1
  boundary, HIR shape remains exact (`missing=1962`, `pending=0`,
  `funcs=28647`) and unique forced names remain 5,801, while admitted calls
  fall from 9,409 to 8,990. The 419 removed admissions are 4.45% of the
  baseline force corridor. Observed wall time moves from approximately 146 to
  143 seconds, but a single three-second delta is orientation only, not a
  stable performance certificate.
- **Force-origin attribution:** the existing default-off outcome event now
  distinguishes the three-name helper from direct force callsites. After local
  exact-name dedup, the helper contributes 3,836 Pending admissions (3,555
  requested bodies, 281 no-effect) and 4,987 NotStarted admissions (147
  requested bodies, 11 other-symbol materializations, 4,829 no-effect). Direct
  callsites contribute 94 Pending admissions (69 requested bodies, 25
  no-effect) and 73 NotStarted admissions (5 requested bodies, 4 other-symbol
  materializations, 64 no-effect). This directly refutes a helper-wide
  Pending-only guard while locating 4,829 no-effect NotStarted admissions in
  that helper. The origin bit is diagnostic only and stores no history.
- **Helper position/shape attribution:** the outcome event now identifies
  helper alternatives as slots 1-3 while direct callsites retain slot 0. At
  the source-matched iteration-1 boundary, all 4,987 helper `NotStarted`
  admissions are bare. Slot 3 contains 4,941: 147 requested-body
  materializations, 11 other-symbol materializations, and 4,783 no-effect
  outcomes. The other two slots contain 46 no-effect admissions. Slot 3 also
  contains 71 Pending calls, including 16 requested bodies. Thus the useful
  and no-effect `NotStarted` populations share both the late position and bare
  name shape; neither is a legal skip predicate. The diagnostic carries only
  the current call argument and records no history.
- **Earlier-candidate semantic snapshots:** admitted slot-3 candidates now
  record their callsite class plus diagnostic snapshots of the two earlier
  helper alternatives. At the unchanged iteration-1 boundary, 4,783
  `NotStarted` slot-3 calls have no visible effect while 158 materialize a
  requested or other body. An earlier exact candidate in `Completed` state
  with a body and a settled return is the largest no-effect population, but
  the identical observational class also contains 22 useful materializations.
  Completed union, nil, unresolved, and void observations likewise overlap
  useful outcomes. These snapshots are attribution only: state, body presence,
  and return categories do not certify canonical identity or required alias,
  wrapper, inherited-redirect, ABI, keepalive, or inline-yield side effects.
- **Elapsed force-cost attribution:** source-matched iteration-1 telemetry puts
  4,807 root force admissions at approximately 22.36 seconds. The dominant
  no-effect NotStarted slot-3 request-state class contributes 2,516 calls but
  only 132.6 ms (0.59% of root force time). The useful Pending lowering class
  contributes approximately 20.53 seconds. This refutes using outcome count as
  the optimization objective and moves the cost frontier outside no-effect
  force aliases.
- **Pending-phase attribution:** at the unchanged iteration-1 boundary, the
  missing HIR scan/queue take 186.2/2.6 ms while pending processing takes 59.53
  seconds: 47.78 seconds root lowering, 11.53 seconds periodic RTA, 18.7 ms end
  RTA, and 194.1 ms residual. Iteration 0 pending processing takes 33.40 seconds:
  16.91 seconds root lowering and 16.43 seconds periodic RTA. Across both
  iterations, `scan_new_functions_for_live_types` accounts for 25.26 of 27.96
  periodic-RTA seconds; type descriptors account for 1.81 seconds, undefer for
  0.82 seconds, and monomorphized traversal for only 66 ms. The scan is already
  incremental by function index, so this is a cost certificate, not proof of
  redundant work.
- **Virtual-target replay prefix cursor:** a system sample attributes 1,575 of
  1,947 sampled new-function scan frames to live-type virtual-target replay,
  with 734 continuing into real owner lowering. A whole-class replay frontier
  keyed by ancestor names and target counts is rejected because it changed the
  exact gate to `missing=1966`, `funcs=28709`, and force `9017/5819`.
  Resolver/materialization state can change without changing those coordinates.
  The admitted move records only the consumed prefix of each append-only
  `(child, parent)` target bucket and leaves replay, owner lookup, attempted-key
  dedup, and repair active. The 48-example virtual-target family and root replay
  regression pass; the source-matched gate preserves `missing=1962`,
  `pending=0`, `funcs=28647`, and force `8990/5801`. Sampled
  `periodic_functions` time falls from approximately 25.70 to 24.69 seconds
  across iterations 0 and 1. This certificate decays if a target bucket gains
  removal, replacement, or reordering; that mutation must invalidate the pair
  cursor.
- **Missing-call provenance shadow:** the default-off authoritative scan now
  partitions filtered bodyless occurrences by first-missing caller generation,
  existing virtual-target/keepalive/exact-called markers, and direct/virtual
  receiver shape. It stores first-seen target iteration only while enabled and
  emits bounded identities; queue, RTA, replay, and lowering remain unchanged.
  At iteration 1, the `Array` target/caller/receiver filter observes 1,439
  occurrences. Virtual-target bodies supply 656 direct occurrences (45.6%),
  including 517 exact-receiver calls, while prior-iteration missing callers
  supply only 58 (4.0%). The authoritative scan remains 7,740 raw occurrences,
  `funcs=10324`, and force `1714/1306`, preserving the established 1,962-target
  unique queue boundary. This refutes previous-queue regeneration as the main
  early amplifier and locates virtual-target reachability as the next question;
  it does not certify any virtual target as unreachable.
- **Live-transition-only replay falsifier:** filtering the initial AST to
  entry-demanded definitions reduces the parsed definition population from
  96,277 to 23,633 but leaves the first missing-call boundary effectively
  unchanged (`funcs=10324`, `missing=170`, force `1714/1306`), so early AST
  registration is not the sampled amplifier. Replaying a registered class
  only when `mark_live_type` inserts a new live type reduces first-pass work,
  but it also changes the function and force boundaries. A focused regression
  explains the mismatch: `Object` and `Reference` targets recorded outside
  lazy RTA intentionally defer broad replay, so observing an already-live child
  after lazy RTA starts is a required rendezvous. The transition-only guard
  misses that target and is rejected. The 49-example virtual-target family
  passes after restoring unconditional lazy-RTA replay.
- **Retained-source provenance cache:** a late CPU sample and opt-in counters
  locate a concrete linear leak below owner lowering: 98,872 exact provenance
  queries over only 1,233 distinct arena/slice keys perform approximately 485.7
  million retained-buffer checks. The admitted cache stores only the exact
  containment result and reuses it while the primary source storage/size and
  both retained-source list lengths are unchanged. Direct append,
  converter-side append, and same-size primary-source replacement regressions
  prove that stale entries are rescanned. On identical source, the bounded
  `missing_initial` pass-items gate improves from 88.65 to 72.95 seconds while
  preserving `demand=170`, `pending=6218`, `funcs=10372`, `lowered=1972`, and
  `deferred=3551`. The full HIR lowering spec passes 414 examples with zero
  failures and two pending. This certificate relies on the observed repository
  contract that `extra_sources` mutations append; destructive same-length
  mutation must invalidate the cache.
- **Adversary verdict:** robust for the bounded two-axis provenance aggregate,
  robust for the missing-call provenance partition, local exact-name dedup,
  retained-source cache under append-only mutation, position/shape attribution,
  and the snapshot/cost-based falsification at the sampled boundary; vulnerable
  for destructive same-length source-list mutation, causal interpretation of
  live-type scan cost, or virtual-target reachability; and broken for
  stable-source, queued-target, virtual-target, Pending-only, unconditional
  late-slot, bare-name, settled-earlier-candidate, or live-transition-only replay
  skipping as a current production optimization.
- **Next local track:** run the fresh B4-F capability gate under the 300-second
  admission limit. If it remains outside the budget, resume below useful
  virtual-target owner lowering without changing broad-target rendezvous. Do
  not cache an entire class replay, change the RTA interval, add a permanent
  forced-name or live-type cache, create another demand registry, or promote
  availability replay. Bodyful caller existence alone is not a reachability
  certificate. Bodyless completed state can be reopened and the measured
  replay mismatch is a direct safety falsifier. Public mutable aliases remain
  a rejected boundary.
