# Compiler Decomposition and Semantic Replacement — Frontier SDD

> Status: DESIGN-SEALED; R0 CURRENT-SOURCE SNAPSHOT SEALED,
> B4-F PERFORMANCE RED; STAGE2 SEMANTIC SMOKES UNAVAILABLE
> (documentation-only amendment, 2026-07-18).
> Audit snapshot: source-shape counts remain scoped to checkout `05954794`.
> Current R0 evidence is the seven-path dirty-source snapshot sealed at base
> `c216b9ef...`, tree `1efb635...`, patch `d7ad2cac...`; measured evidence and
> remaining promotion gates are recorded below.
> Bounded context: Adamas compile semantics from parser arenas through HIR,
> MIR, and LLVM emission.

This SDD defines the architecture transition from the current stateful
compiler to explicit semantic owners. It is a transition contract, not an
authorization to rewrite source files. It complements, and does not replace,
the [Compiler Architecture SDD](../compiler_architecture_sdd.md), the deferred
[Refactor Architecture Plan](../compiler_refactor_architecture_plan.md), and
the [Demand-Driven Rewrite RFC](../../PLAN_DEMAND_DRIVEN_REWRITE_RFC.md).
Their execution history and current owner records remain authoritative in
those documents, `TODO.md`, `LANDMARKS.md`, and git history. This document
narrows the next architecture decision: selective semantic replacement with
typed identity and shadow gates.

## 1. Live audit and ProblemCard

### 1.1 Quantified monolith and coupling facts

The following are source-shape counts taken from the audit checkout. They are
not runtime allocation or performance measurements. Method counts are the
result of a `def`-line search (including nested helper types), and ivar counts
are lexical symbol counts.

| Surface | Lines | `def` lines | Unique ivar names | Ivar references | Selected coupling indicators |
|---|---:|---:|---:|---:|---|
| `src/compiler/hir/ast_to_hir.cr` | 108,700 | 2,222 | 695 | 9,624 | `@arena` 1,425; `@current_class` 701; `@function_defs` 348; `@class_info` 257; `@type_param_map` 190; 25 `@pending*` names / 234 references; `@main_arenas` 52 |
| `src/compiler/mir/hir_to_mir.cr` | 11,325 | 299 | 60 | 799 | HIR/MIR value, block, phi, dispatch, alias, and storage state coexist in one lowering object |
| `src/compiler/mir/llvm_backend.cr` | 29,889 | 499 | 602 | 4,083 | type mapping, scheduling, textual emission, worker output, runtime shims, and layout decisions share one backend surface |
| `src/compiler/semantic/type_inference_engine.cr` | 13,201 | 464 | 52 | 1,113 | existing semantic inference is another monolith; it may be reused behind adapters, but cannot become the new authority unchanged |

These numbers establish a coupling problem, not a conclusion that every line
or helper must move. In particular, `AstToHir` has enough mutable semantic
state that a name, arena, overload, pending-demand, and materialization bug
can appear at a later phase. The existing SDD records the ownership response
and already-consumed edges; this table records why another physical split
without a semantic boundary would be cosmetic.

### 1.2 ProblemCard

```text
signal:   semantic decisions are repeated or transported as mutable maps,
          rendered names, pending queues, and arena-local numeric indices;
          the current B4-F self-build bottleneck remains inside AstToHir,
          while the old B5 lower-method locator is historical only.
why_now:  the active bootstrap loop is red, while both the architecture SDD
          and demand-driven RFC are otherwise easy to misread as permission
          for a broad rewrite.
bounded_context: compile semantics, HIR/MIR lowering, and LLVM emission;
                 Crystal stdlib and parser compatibility remain in scope.
scope:    name/type identity, call resolution, state scope, materialization,
          ABI facts, backend consumption, and the migration gates between them.
not_merely: a line-count cleanup, a new file layout, a queue optimization,
            or a slogan that the compiler should be demand-driven.
improvement_probe: replace one semantic decision with an immutable typed fact,
                   shadow it against the legacy path, and measure both
                   normalized equivalence and resource use.
unknowns:  the complete writer/reader census, arena retention cost, the exact
           compile-path declaration fixed point, and which legacy helpers are
           genuinely leaf-only.
freshness: source shape remains scoped to 05954794; runtime frontier is
           refreshed by the sealed c216b9ef current-source manifest and decays
           when the base, seven-path patch, host/cache policy, or command moves.
safe_next_move: typed resolution-to-materialization queue payload/transaction
                guard plus legacy shadow at final HIR emission and
                lower_missing replay; no default-path consumer.
validation_boundary: the first vertical ResolutionId/MethodInstanceKey slice
                     must preserve old behavior and prove identity continuity.
```

The single next move is a behavior-neutral identity slice with a normalized
shadow comparison; its evidence requirement is a typed identity ledger plus
positive and negative reducers, not a successful host build alone.

## 2. Current frontier and transition decision

The old architecture SDD recorded B4 as green because a previously generated
`s2` artifact passed a downstream full-prelude smoke. That is useful historical
evidence, but it is not proof that the current source can produce a fresh
`s2b`. The following table is the R0 reconciliation input; it deliberately
keeps source revisions, generated artifacts, and the dirty worktree distinct.

### 2.1 R0 evidence state

| Evidence | State | Interpretation for the plan |
|---|---|---|
| Clean `548d29b1` baseline | `IN_PROGRESS / NON-DISCRIMINATING` | Stage1 and host/no-prelude probes pass, but fresh `s1 -> s2` timed out at the 900-second diagnostic cap without producing a new `s2`. It is a control, not a release certificate. |
| `04b98b04` demand-amplifier lineage | `DIAGNOSTIC` | Direct `Object`/`Reference` method census fell from 2085 to 50. This explains one cross-product, but the branch is not a speed or semantic release certificate by itself. |
| Historical fresh both-smoke green runs | `HISTORICAL GREEN / ABOVE TARGET` | The strongest surviving fresh certificate is 231.37 seconds; 251.91 and 253.42 seconds corroborate that both smoke modes have been green, but none satisfies the new <=180-second B4-F target. |
| Historical ~178-190-second records | `PARTIAL ONLY` | These are no-prelude or otherwise partial records. They are not recovered full-green certificates and cannot satisfy B4-F. |
| 2026-07-14 fresh run | `SEMANTIC SPLIT / RED` | Roughly 711 seconds; no-prelude was green while the plain/full-prelude smoke was red. |
| G7 snapshot | `REFUTED AS RELEASE CANDIDATE` | Produced `s2` after 1962.79 seconds; both semantic smoke modes were red. |
| G8 snapshot | `REFUTED AS RELEASE CANDIDATE` | Produced `s2` after 1791.78 seconds; both semantic smoke modes were red. |
| G9 snapshot | `DIAGNOSTIC CANDIDATE ONLY` | Produced `s2` after 1768.73 seconds; both semantic smoke modes were red. Its retained HIR/MIR/LLVM artifacts may localize typed materialization divergence, but cannot certify current source. |
| `91ebe332` Slice 1A | `T0 COMPLETED / GUARD-ONLY` | Stage1 passes; fresh `s1 -> s2` reaches the same 900-second timeout as the clean control. HIR provenance ON/OFF is byte-identical, but no `ResolutionId`/materialization consumer is present. |
| R0 sealed current-source snapshot | `COMPLETED / NON-PROMOTING` | Base `c216b9ef...`, tree `1efb635...`, exactly seven tracked compiler/spec paths, patch SHA-256 `d7ad2cac...`; snapshot diff-check passes. Manifest: `/private/tmp/adamas_r0_current_c216_manifest.md`. |
| Host preflight and stage1 | `GREEN` | Host spawn green; host build 14.13s; plain smoke `42` in 20.29s; exact no-prelude markers in 0.65s; `cv2_s1` SHA-256 `dfe3c0e8...`. |
| Fresh current-source B4-F | `MEASURED RED` | Stage2 timeout exit 143 at 182.54s, externally sampled peak RSS 1361.03 MiB; outer chain exit 1 at 219.32s; no `cv2_s2`. Compiler-side performance red; stage2 semantic smokes unavailable, not red/green. |
| Sealed-current stats-on localization | `DIAGNOSTIC / OPEN PHASE` | With only `ADAMAS_PHASE_STATS=1` on sealed `cv2_s1` under timeout 180s/memory 12288 MB, the run ended at wall 182.60s, exit 143, without `cv2_s2`; peak RSS is unavailable. `process_pending` completed 218 -> 591 (+373) in 555.2ms and `emit_tracked_sigs` 591 -> 604 (+13) in 235.0ms. The first open phase was `lower_missing.initial`; internal growth was 604 -> 1535 -> 7422 -> 19238 -> 28234 (+27,630 from 604) before timeout, with no completion/timing/normalized top-prefix. Log SHA-256 `1cc025cc5930ebd0513382e68dbb400e763002186f227288683d6bc710f79ecd`. This revalidates/evolves the 2026-04-29 localization; observation definitions differ, and stats-on/uninstrumented timing is diagnostic-only. |
| T0 same-source fresh A/B | `NOT COMPLETED` | R0 promotion remains blocked independently of B4-F. |
| T8 offline readiness validator | `COMPLETED / NO CURRENT GREEN RECEIPT` | The committed validator rehashes B6/B7 evidence and enforces trusted host, normal no-worker build, numeric resource coverage, both exact stage2 smokes, and the inclusive <=180-second budget. B4-F remains red until a fresh current receipt passes it. |
| T1 ownership/NameId substrate | `COMPLETED / T1 STILL RED` | One `SemanticIdentityRegistry` owns canonical session-local names and the existing semantic type table; `DefInstanceKey` named arguments are typed `NameId` pairs, and retained semantic key arrays are mutation-safe. Expired HIR-only identity sidecars were pruned instead of promoted; `SelectedCallTarget` is explicitly legacy symbol/DefNode compatibility. No live semantic `CallResolution`, producer row, downstream join, or lowering behavior change is claimed. |

These states supersede an unqualified `B4 GREEN` label. They do not discard
the historical artifact; they prevent it from being used as evidence for fresh
source readiness.

### 2.2 B4 split and the performance/semantic release target

The bootstrap contract now has two explicitly different rows:

- **B4-H (historical artifact):** an already generated `s2` may be used for
  downstream diagnosis and compatibility archaeology. Its smoke result is
  retained as historical evidence and cannot promote a source change.
- **B4-F (fresh current source):** a clean-output `s1 -> s2b` build from the
  reconciled source must finish in **at most 180 seconds** on the recorded host
  and explicit cache policy. The output directory must be new and
  the manifest records fresh-output/source/output hashes plus `cache_policy`,
  `cache_dir_rel`, and `cache_directory_identity`; no generated
  stage may be reused. Cold and warm results are reported separately, and a
  warm run cannot satisfy a missing cold/fresh result.
  Faster is the stretch target. A longer diagnostic timeout may be used to
  obtain a failure artifact, but it never relaxes this acceptance budget.

B4-F has two co-equal semantic gates: the exact plain/full-prelude smoke and
the exact no-prelude smoke must both compile and run under the safe runner,
with the expected behavior/oracle output. Worker count, cached old artifacts,
or emit-only success cannot mask a failure in either mode. A candidate is not
fresh-s2 ready unless the 180-second budget and both semantic gates pass.

The <=180-second threshold is a new acceptance target, not a recovered
historical full-green certificate. The strongest surviving fresh both-smoke
green result is 231.37 seconds (with 251.91 and 253.42 second corroborating
runs); the ~178-190-second records cover only no-prelude or partial lanes.

### 2.3 Transition decision

The declared B5 frontier remains useful as a historical locator: the first bad
stop was the `AstToHir#lower_method` body loop for
`Adamas::Compiler::CLI#run$IO_IO`, at roughly 4.8 GB peak RSS, under
`ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED`; the pre-body
gates were recorded clean. It is not a current green claim. The sealed R0 run
now classifies B4-F as performance red; B5 remains unavailable without `cv2_s2`.

Decision:

1. The demand-driven pipeline in the RFC is the strategic destination.
2. The immediate route is a selective strangler: introduce a typed
   resolution-to-materialization queue payload/transaction guard at final HIR
   emission and `lower_missing` replay, then shadow it against the legacy
   string-keyed route. The current amplification classification is a
   high-confidence hypothesis, not causal proof; its falsifier is reduced
   duplicate shape expansion with selected target, call shape, body/symbol
   continuity, and exact semantics preserved. Keep the default-path consumer
   blocked; guard/shadow only.
3. A blank-slate compiler rewrite is not admitted while B4-F is red and B5 is
   unreachable from the current source.
4. Physical file splitting is delayed until semantic contracts reduce the
   state surface of the moved code.
5. The R0 reconciliation seal is mandatory before Slice 1B: the active dirty
   frontier is snapshotted, a same-source A/B control is run with and without
   T0, and the fresh-s2 plus plain/no-prelude gates are classified together.

### 2.4 Typed union materialization diagnostic

R0 also exposed a narrower semantic boundary in the historical G9 artifacts.
The source call is `main_arenas << map_arena`, where the container expects the
union element type. In the minimal G9 probe, static-value insertion selects
`push$AstArena`, while an explicit upcast selects the union target. The upstream
Crystal audit establishes that both are lawful, distinct generic instances:
concrete flow through `Array(ArenaLike) << AstArena` specializes `<<`/`push`
with `AstArena`, while explicit `.as(ArenaLike)` and true union flow specialize
with the union or a lawful reduced union.

At the original Crystal oracle boundary, instance authority is the selected
definition plus actual typed arguments, block shape, and named arguments
(`DefInstanceKey` uses `def.object_id` there). That `object_id` detail is not
Adamas authority: Adamas requires `DefIdentity`. The mangled name is only the
later serialization of that identity; equal display families do not require
equal instances.

The minimal probe preserves both call arguments through HIR, MIR, and LLVM, so
it does not reproduce argument loss. The full G9 `s2` LLVM artifact instead
contains a union `<<` path that calls zero-argument `push$AstArena()` and a
zero-argument unreachable stub. That makes late HIR materialization or a
missing selected target a high-confidence hypothesis for zero-argument body
creation, but it is not yet proven. G9 is therefore retained only as a
diagnostic candidate. T9 permits the lawful concrete and union instances and
requires one reducer to join selected definition/instance, coercion and value
type, receiver/value arity, materialized body, and emitted symbol before any
fix or promotion.

### 2.5 STABLE6 — refuted in-process prototype / not admitted

The attempted `MaterializationReplayShadow` is **REFUTED IN-PROCESS
PROTOTYPE / NOT ADMITTED**. Its local shape used a typed numeric `CallSiteRef`,
explicit replay statuses, a composite typed HIR request-shape index, diagnostic
logs with a ceiling (not a hard cap), owner-local scratch, and a final
read-only scan, with no `HIR::Call`
field and no fixed-point, queue, lowering, or routing change. The prototype is
preserved only in `/private/tmp` and removed from main code; default-OFF is not
itself zero compile-time cost.

Scoped local evidence remains: OFF/ON no-prelude and plain HIR/runtime parity,
focused **17/0**, baseline HIR **286/0 plus two existing pending examples**,
and host build. The local adversary is **ROBUST** only for those simple parity
checks. Full-prelude/union telemetry remains red/noisy and separate from the
similar plain run (about 2673 registered, 2568 agree, 404 mismatch, 1 stale,
199 untracked required, 225 unjoined, 1 ambiguous, and 11377 calls in the
audit reducer); the counters are orientation-only and do not prove duplicate
semantic instances or speed. The context bridge remains explicit:
`StaleCallSite`, `UntrackedRequiredCallSite`, and `StaleTransactionRef` are
distinct meanings.

The system discriminator overrides local admission. On frozen pre-shadow
`c216b9ef...` plus `d7ad2cac...`, phase-stats only timed out at 180 seconds
(`run_safe` exit 143), produced no `s2`, and grew 604 -> 1535 -> 7422 ->
19238 -> 28234 (+27630) without stack overflow; repeat-control log prefix
`e568...`. With the same binary's STABLE6 ON and OFF, both produced no `s2`
and hit exit 11 stack overflow in `declared_type_match_score`/alias/type-name
work during `lower_missing` p0 around #800 (about 141s/139s), with identical
growth 604 -> 1544 -> 7430 -> 19246 -> 28369 (+27765); ON/OFF log prefixes
are `18603d...`/`51146a...`, and RSS is unavailable. ON final-scan-i4
orientation was `registered=27363`, `agree=42801`, `mismatch=484`,
`unjoined=4459`, `ambiguous=300`, `no_mat=12864`, `calls=60909`,
`not_yet=1`.

This does not prove causality, but admission is rejected because runtime-OFF
changes the self-host source/workload and failure class. Whole-system
Adversary verdict: **BROKEN for admission**. T1 remains **MISSING** because
HIR `TypeRef`/name shape is not semantic identity, and B4-F (<=180 seconds)
remains red/open with no speed claim.

Pivot: do not add another large in-process callsite owner or new `AstToHir`
ivars. Reuse the existing materialization ledger and semantic
`DefIdentity`/`DefInstanceKey` only as a later join input; it lacks
`resolution_id`, so it cannot be joined deterministically today. The full path
requires a second versioned downstream correlation record/enrichment carrying
`resolution_id` through inline, materialization, body, and emission-terminal
states. Until that record exists, the external join remains pending and this
document does not claim that existing streams suffice. A future analyzer may
stream its inputs, but the current log ceiling is diagnostic unless a guard
hard-caps it; no bounded-memory or backpressure claim is admitted.

### 2.6 T1 identity-join boundary (current-red)

T1 rejects the late `lower_function_if_needed` / MAT string ledger as the
semantic producer. That point is downstream of resolution and can also be
after semantic literal/autocast normalization, Adamas HIR/value/ABI coercion,
or inline materialization, so it cannot establish which semantic callsite
identity was selected. The authoritative producer boundary is **post-resolution,
after semantic literal/autocast normalization if applicable, before Adamas
HIR/value/ABI coercion**, analogous to the original Crystal
`Call#instantiate` boundary. This is an ownership placement, not a behavior
or performance claim.

The first admitted semantic-producer handoff is this versioned,
telemetry-only record shape:

```text
[T1_IDENTITY_JOIN] schema=t1_identity_join_v1 case_id=<opaque-case-id> resolution_id=<u64> def_arena_id=<u64> def_expr_index=<i32> receiver_semantic_type_id=<u32|none> arg_semantic_type_ids=<ordered-u32-list|none> block_semantic_type_id=<u32|none> named_semantic_args=<ordered-NameId:SemanticTypeId-list|none> producer_phase=post_resolution_pre_hir_coercion
```

The producer and join operate on typed IDs and ordered fields. Strings are
serialization only: `case_id/correlation` is an opaque external correlation
token, and any rendered name is diagnostic/ABI text, never a semantic key or
owner decision. The record is not an in-process authority and must not be
used to silently route the legacy path. The existing MAT ledger cannot be
joined deterministically because it lacks `resolution_id`. Full correlation
therefore requires a second versioned downstream record/enrichment carrying
that ID through inline, materialization, body, and emission-terminal states;
until it exists, the external join is pending.

Current blockers are explicit and remain red:

- there is no actual semantic callsite type interner that can authoritatively
  populate the receiver and argument semantic type IDs;
- `IdentityDryRunTracker` is a definition-annotation/body-infer proxy and is
  in-process, not the semantic callsite producer.

The ownership precursor is now implemented: `SemanticIdentityRegistry` owns
canonical session-local names alongside the existing type table,
`DefInstanceKey` uses ordered `{NameId, SemanticTypeId}` named components, and
`SemanticTypeKey`/`DefInstanceKey` retain owned arrays without exposing their
mutable storage. This closes only step 1 of section 13.3; it does not create a
live resolution owner or make T1 green.

The T1 guard is **availability/current-red only**: it can show whether the
current source/configuration emitted a row or exposed the current failing
boundary. It does not prove global absence of another producer, semantic
identity continuity, or equivalence of selected definition, coercion, body,
and emitted symbol. No rewrite, broad in-process owner, or performance claim
is admitted.

## 3. Surface policy

### 3.1 Admitted

- Immutable, domain-specific identity records for names, declarations,
  resolutions, method instances, arenas, and ABI facts.
- Explicit owner-scoped arena references and lifetime evidence for `ExprId`.
- Behavior-neutral facades over existing maps and queues.
- One-way data flow from source facts to HIR, MIR, and LLVM consumers.
- Normalized shadow comparison of legacy and candidate semantic results.
- A demand-driven body cache keyed by semantic identity once declaration and
  compile-graph parity are established.
- Narrow, measured zero-copy paths that retain their owner/lifetime contract.

### 3.2 Rejected

- A rewrite-from-scratch compile path while B5 is red.
- A file split that preserves the same ambient state and hidden fallback
  decisions.
- Semantic cache keys based on mangled/display strings, object addresses, or
  unstable HIR/MIR numbering.
- A backend that resolves names, selects overloads, reconstructs block shape,
  or infers layout from strings after HIR/MIR has emitted facts.
- A global queue removal before the semantic pipeline has a fixed declaration
  point and an explicit recursive in-progress state.
- A new owner that accepts the whole `AstToHir`/`TypeInferenceEngine` context
  instead of a narrow typed contract; this only relocates ambient authority.
- Stdlib edits, parser replacement, or a broad ABI representation change as a
  side effect of this architecture transition.
- The STABLE6 in-process callsite-owner prototype: it is not an admitted
  default-off guard, and must not be replaced by another large owner or new
  `AstToHir` ivars. Only a minimal producer record, serialized as telemetry
  rather than authority, may be reconsidered after an external streaming
  composite census; current log ceilings do not establish bounded memory or
  backpressure unless a guard hard-caps them.

### 3.3 Guard-only future

- `ADAMAS_SEMANTIC_COMPILE=1` as a kill-switched candidate compile path.
- `ADAMAS_SEMANTIC_SHADOW=1` normalized legacy/candidate comparison.
- `ADAMAS_SEMANTIC_ASSERT_NO_LEGACY_QUEUE=1` assertions that reject
  `emit_all_tracked_signatures`, `process_pending_lower_functions`,
  `force_lower_function_for_return_type`, or non-zero legacy pending demand
  under the candidate path.
- T0 provenance/arena guard records, including `ArenaId` and fail-closed owner
  checks. T0 remains diagnostic until a real typed consumer reads the record.
  If two subsequent architecture slices finish without such a consumer, the
  guard-only slice expires: its flag, ledger, and unused registry retention
  are removed or explicitly re-admitted with a new owner and falsifier.
- Typed facades over `@function_defs`, `@class_info`, generic templates,
  arena storage, materialization, and ABI/layout facts.
- A typed streaming LLVM writer and an allocation census. The current textual
  writer remains the behavior authority until the backend seal is met.
- Runtime behavior changes, queue deletion, default-path switching, and
  physical module extraction. These remain rejected until their seals and
  falsifiers are complete.

### 3.4 Non-goals

- Replacing the parser or the Crystal standard library.
- Copying upstream Crystal compiler internals into Adamas.
- Replacing textual LLVM IR with the LLVM C API or constructing a full-module
  LLVM AST.
- Solving every B5 crash or memory frontier through a decomposition document.
- Making HIR, MIR, or LLVM IDs stable across compiler runs.
- Treating source LOC, queue length, or allocation count as the user value;
  semantic compatibility and safe resource use are the protected outcomes.

## 4. Blank-slate rewrite versus selective strangler replacement

These are different programs and must not share a readiness label.

| Model | Meaning | Current decision |
|---|---|---|
| Blank-slate rewrite | Replace the compile path wholesale, usually with a new semantic/type stack, then re-establish parser, prelude, macro, HIR, MIR, LLVM, and bootstrap parity. | Rejected at B5. It combines too many unknowns and makes a moved crash impossible to attribute. |
| Selective strangler semantic replacement | Keep the legacy path as a compatibility carrier; introduce one typed owner at an existing boundary; compare old/new results; route one consumer; retain a kill switch; delete only after negative-use and bootstrap falsifiers. | Admitted and is the only immediate implementation route. |

### 4.1 Reuse versus rewrite now

| Existing asset/context | Reuse now | Rewrite now |
|---|---|---|
| `DefIdentity`, `SemanticTypeId`, `DefInstanceKey`, and `SemanticToHIRAdapter` in `src/compiler/semantic/identity/` | Extend these as the canonical identity substrate; add the missing `ResolutionId` beside them and keep the one-way HIR adapter. | Do not create parallel `*Key2`, duplicate type interners, or a second semantic-to-HIR bridge. |
| `DefInstanceKey` named-argument component | Reuse the current ordered `Array({NameId, SemanticTypeId})` field from the shared registry owner. | Do not reconstruct it from raw strings downstream or add a parallel compatibility key. |
| Current `AstToHir` maps, queues, and owner records | Keep as a legacy compatibility carrier behind facades and differential ledgers. | Do not remove queues or rewrite all lowerers in the first slice. |
| `TypeInferenceEngine` (13,201 lines, 464 `def` lines) | Reuse as a leaf/legacy differential oracle where its result is already needed. | Do not promote the class unchanged as the new declaration, resolution, or body-cache authority; it must be decomposed behind the budgets below. |
| Existing LLVM text/output path | Reuse output and ownership contracts while semantic facts are sealed. | Do not start with a backend rewrite or let backend code repair missing semantic facts. |
| Original Crystal compiler | Reuse for behavior and phase invariants at an explicit comparison boundary. | Do not copy upstream implementation classes, ownership, queues, or backend internals. |

The RFC's demand-driven semantic pipeline can therefore be implemented as a
series of strangler slices. It is not a license to route the entire compile
path through the new pipeline before declaration fixed-point and normalized
shadow gates exist. A physical extraction is progress only when the extracted
surface has fewer authorities and a smaller state contract.

## 5. One-owner design laws

1. **One decision, one owner.** A consumer reads a typed fact; it does not
   answer the same question again.
2. **Identity is structural.** A declaration, arena node, resolution, and
   method instance have domain identities distinct from their display names.
3. **Strings carry spelling, not authority.** A rendered/mangled name may be a
   diagnostic or ABI transport value, never the semantic cache key.
4. **Enums classify; IDs identify.** Finite state/status enums may reject an
   unknown state, but an enum ordinal is not a declaration or method identity.
5. **No silent semantic-class fallback.** Unknown owner, overload, block shape,
   ABI, or lifetime is rejected or remains on the legacy path.
6. **Facts cross boundaries one way.** Name/type facts precede resolution;
   resolution precedes materialization; ABI facts precede backend emission.
7. **AST identity is arena-scoped.** `ExprId` equality or index containment is
   not proof that two nodes have the same owner.
8. **Zero-copy is a contract.** Borrowed data names its owner and lifetime;
   retained data is interned or explicitly owned. Eliminating a copy cannot
   introduce an alias to mutable or expired state.
9. **Shadow before promotion.** A typed record is diagnostic until one legacy
   consumer reads it under normalized parity.
10. **Backend is mechanical.** Backend code consumes MIR plus ABI/materialization
    facts and never reconstructs source semantics.
11. **Dead code is an evidence claim.** Delete only after static census,
    dynamic census, negative-use proof, and replacement ownership agree.
12. **Rollback is a feature.** Every candidate path has a kill switch and the
    legacy path remains runnable until the declared soak window ends.
13. **No whole-context injection.** A new owner may not receive `AstToHir`,
    `TypeInferenceEngine`, or another monolithic context as an implicit service
    locator. It receives only a narrow typed input/facade whose reads and
    lifetime are part of the owner contract.

## 6. String, enum, and domain-ID taxonomy

The same lexical token may occur in several bounded contexts. The following
bridge prevents string equality from being mistaken for semantic equality.

| Kind | Owns | Allowed uses | Forbidden uses |
|---|---|---|---|
| Source `String` | Original spelling, source paths, diagnostics, user-facing names, and explicit serialization. | Error text, source maps, display, ABI spelling at the final emission boundary. | Semantic cache keys, owner selection, overload choice, lifetime proof. |
| Interned `NameId` / `TypeId` | Canonical compile-session name/type identity. | Hash/map keys, typed facts, normalized comparison. | Assuming the integer is stable across compiler runs or source edits. |
| Enum (`ResolutionKind`, `StorageContext`, `IdentityStatus`, `CodePathStatus`) | A closed classifier or state machine. | Exhaustive branching, fail-closed status, telemetry labels. | Encoding an open-ended declaration/method identity or silently adding an unknown ordinal. |
| `DefIdentity` | Structural declaration identity, including arena/source owner and expression index (or an equivalent source identity). | Declaration maps and provenance. | Replacing it with a mangled name or a bare `ExprId`. |
| `ResolutionId` | Identity of one call/name-resolution decision in one compilation. | Joining producer, selected definition, state scope, and shadow rows. | Treating it as a method identity or as a stable cross-run ID. |
| `MethodInstanceKey` | Immutable typed body/materialization identity: declaration identity, receiver type, argument types, block shape, named-argument types, and owning state scope. | Demand cache, materialization registry, normalized shadow. | Building it from rendered names, mutable arrays, ambient maps, or backend guesses. |
| `FunctionId` / `ValueId` / `BlockId` | Local HIR/MIR graph identity. | Def-use and CFG references within the owning module/function. | Raw cross-run equality or direct shadow comparison without normalization. |

`ResolutionId` and `MethodInstanceKey` are related but not interchangeable:
many resolutions can request one method instance, and one resolution can be
rejected without producing a method instance. The bridge from source spelling
to IDs must record the owner, scope, and decay trigger; a later phase may not
silently remint a second identity from the same string.

In the current tree, `DefInstanceKey` is the existing scaffolding for the
target `MethodInstanceKey` contract. The migration may evolve or rename that
implementation in place, or expose one compatibility adapter, but it must not
create two caches with different meanings.

## 7. Zero-copy ownership and lifetime contracts

Zero-copy is admitted only where the producer's owner outlives every consumer.
The non-negotiable rule is: **no borrow without a lifetime proof; no copy
without a named boundary reason**. A copy is an explicit ownership transfer,
not an accidental workaround, and a borrow is never justified by an index or
an apparent current-arena coincidence.

1. **Parser arena.** The parser owns AST nodes. An `AstNodeRef` carries the
   owning arena, `ExprId`, source span, and origin. HIR may borrow it only while
   the arena is alive; a retained reference is either interned into a durable
   declaration identity or rejected as stale. `expr_id.index < arena.size` is a
   containment check, not an ownership proof.
2. **Semantic identity.** Interners own canonical names/types and return compact
   IDs. `MethodInstanceKey` owns or interns its component IDs; mutable input
   arrays cannot remain aliases after insertion into a cache.
3. **HIR/MIR facts.** Facts own IDs and immutable descriptors, not copied source
   trees. A fact that borrows a source span or arena must carry the lifetime
   token needed by its consumer and must fail closed after the token expires.
4. **LLVM emission.** Typed fragments stream to an explicit output sink. The
   writer must not build an unbounded `Array(String)`/join/reparse buffer for a
   function, and worker shards must identify their owner and merge contract.
   Output ownership remains with the existing `LLVMOutputOwnershipContract`
   until a later writer seal.
5. **Boundary accounting.** Each slice records borrowed bytes, owned bytes,
   arena-retained bytes, temporary string bytes, and allocations. A lower copy
   count is not a win if retention or peak RSS grows.

The first zero-copy implementation is therefore an ownership/lifetime proof
plus an allocation census, not a blanket replacement of `String` with slices.

## 8. Target one-way subsystem graph

```text
Parser/Arena + source spans
        |
        v
NameResolution -----> TypeIdentity/Interners -----> DeclarationIndex
        |                         |                       |
        +-------------------------+-----------------------+
                                  v
                           CallResolution
                                  |
                                  v
                       SemanticStateScope
                                  |
                                  v
                    Materialization/MethodCache
                                  |
                                  v
                              HIRBuilder
                                  |
                                  v
                            HIR -> MIR
                                  |
                                  v
                      AbiFacts/LayoutContract
                                  |
                                  v
                           BackendEmitter
                                  |
                                  v
                         LLVM text/output sink
```

Read-only evidence ledgers may observe every edge, but they do not become a
second semantic authority. The following reverse edges are prohibited:

- Backend -> name resolution, overload selection, materialization, or source
  arena recovery.
- MIR -> mutation of HIR semantic registries or ambient type-parameter maps.
- HIRBuilder -> backend layout guesses or LLVM symbol repair.
- Materialization -> a late backend decision about the selected definition.
- Oracle Crystal -> Adamas runtime state. The oracle is an external comparison
  boundary, not a pipeline dependency.

### 8.1 Target subsystem contracts

Each row is one semantic owner. The inputs and outputs are typed facts or
owner-scoped references; strings are retained only for spelling/diagnostics.

| Owner | Input | Output | Forbidden dependency |
|---|---|---|---|
| `DeclarationIndex` | parser declarations, `DefIdentity`, source/arena provenance | immutable declaration records, owner/name/type membership, declaration fixed-point status | backend emission, overload choice, ambient `@type_param_map`, rendered-name identity |
| `NameTypeIdentity` | source spelling, absolute marker, lexical owner, generic arguments, declaration identity | `NameRef`, canonical `NameId`/`SemanticTypeId`, alias chain, type-kind facts | call resolution, materialization, LLVM layout, bare `ExprId` ownership |
| `CallResolver` | receiver/argument types, named arguments, block shape, callsite scope, `DeclarationIndex` | `ResolutionId`, `CallResolution`, selected `DefIdentity`, rejection reasons, `MethodInstanceKey` inputs | body lowering, pending-queue mutation, LLVM symbol construction, backend fallback |
| `DemandGraph` + `BodyCache` | `MethodInstanceKey`, call edges, declaration fixed point, recursion state | demand nodes, in-progress/completed body states, cache hits/misses, bounded worklist | rendered/mangled cache keys, ad-hoc source scans, backend requests, unbounded legacy queue |
| `MaterializationRegistry` | `ResolutionId`, selected definition, `MethodInstanceKey`, state scope, ABI shape | materialized body identity, requested/target/body/call symbols, explicit wrapper/forwarder contract | overload selection, name re-resolution, ambient-map guesses, backend reconstruction |
| `HIRBuilder` | typed semantic facts, `SemanticToHIRAdapter`, materialization results, owner-scoped AST refs | HIR functions/instructions, normalized semantic metadata, source provenance | direct backend calls, semantic cache mutation, arena scans by index, string-based overload choice |
| `AbiFacts` | HIR/MIR types, storage context, escape/provenance, finalized layout inputs | immutable `AbiContract`, representation/storage/copy/load/store facts | name resolution, method selection, demand scheduling, source-string prefixes |
| `BackendEmitter` | MIR, materialization facts, `AbiFacts`, typed LLVM fragments, explicit output sink | LLVM text/shards, emission outcomes, fail-closed missing-fact diagnostics | Name/CallResolver, `TypeInferenceEngine`, AST arena recovery, source semantic reconstruction |

The table is a structural guard against a second monolith: a new owner may
depend on upstream facts, but it may not reach sideways into another owner's
mutable store. A coordinator can sequence these owners; it cannot own their
semantic state.

### 8.2 Candidate-path structural tripwires

These are enforceable shape budgets, not value metrics. They apply to new
candidate files and owners; an exception is allowed only with a written reason,
named owner, measured correctness/resource impact, expiry date, replacement
plan, and protecting falsifier in the same slice.

| Surface | Default tripwire | Hard failure |
|---|---|---|
| Coordinator | ≤600 source lines, ≤25 method definitions, ≤16 mutable fields | A coordinator over budget becomes a new monolith unless the exception record is complete. |
| Method | ≤120 logical lines and ≤6 direct semantic-state reads/writes | A longer method must be split by owner or carry the explicit exception record. |
| File | ≤1,500 source lines and ≤80 method definitions for a new owner file | Copying a legacy monolith into a new file is rejected even if behavior is unchanged. |
| Public API | ≤12 exported types/functions per owner boundary | Extra surface requires a consumer/falsifier map; convenience re-exports do not count as ownership. |
| State surface | ≤16 mutable fields, ≤4 mutable collections, zero ambient authority reads across owners | A field/map crossing the boundary must be an immutable input or a named owner facade. |

The current 13,201-line, 464-method `TypeInferenceEngine` is explicitly not an
exception: it may remain a legacy/leaf differential oracle, but candidate
authority must be decomposed behind these tripwires. A coordinator may exceed a
budget only temporarily to carry an existing compatibility seam; it must name
the seam and a delete-ready successor rather than normalize the excess.

### 8.3 Three distinct oracle contexts

Three authorities must remain distinct:

| Context | Role | Allowed use | Not allowed |
|---|---|---|---|
| Original Crystal at its pinned source revision | Behavior/phase oracle | Establish language invariants, diagnostics, and negative cases for normalized comparison. | Copying its compiler classes, parser-arena ownership, queue policy, or backend internals into Adamas. |
| Current Adamas legacy path | Differential oracle | Produce the incumbent HIR/MIR/LLVM and runtime result against which a candidate slice is shadowed. | Treating a legacy workaround or stringly fallback as the new design authority. |
| New typed records and owner contracts | Design authority | Define admitted identity, ownership, lifetime, and one-way dependencies after their seals pass. | Using a record merely because it exists, or letting it silently override legacy behavior before parity. |

When a language-visible result is uncertain, inspect the original Crystal
compiler to establish the semantic invariant and a negative case, then compare
current Adamas and candidate output through normalized gates. The compatibility
promise is Crystal behavior and stdlib compatibility, not source or object
layout identity with upstream. Record the oracle revision and adapter at the
boundary so an upstream update is an explicit evidence-decay event rather than
a silent implementation dependency.

## 9. Migration order

The order reconciles the current architecture SDD's owner-first phases with the
RFC's demand-driven phases:

### 9.1 R0 reconciliation gate (before Slice 1B)

R0 is a required evidence seal, not another semantic owner. It prevents a
dirty worktree, an old generated artifact, and a new identity guard from being
compared as if they were one compiler.

1. Snapshot the current dirty frontier into a disposable worktree without
   changing, staging, or cleaning the user's main worktree.
2. Produce an A/B pair from the same snapshot: A without T0 and B with
   `91ebe332` T0 provenance. Record source revision, flags, cache policy,
   worker count, wall time, peak RSS, and generated-artifact provenance. Use a
   new output directory, verify fresh-output/source/output hashes, and record
   `cache_policy`, `cache_dir_rel`, and `cache_directory_identity`; report any external host cache separately and hold it
   constant.
3. Run host/unit guards, plain/full-prelude smoke, and no-prelude smoke on
   both A and B. A/B must be semantically equal before any architecture
   consumer is promoted; a timeout is classified as non-discriminating, not
   as evidence that B caused the slowdown.
4. Run the fresh `s1 -> s2b` classifier with a diagnostic cap sufficient to
   leave an attributable artifact, then apply the actual B4-F budget of 180
   seconds. Compare function/materialization demand, duplicate bodies, queue
   peaks, phase times, and RSS; do not use a single timeout or function count
   as a value proxy.
5. Write a compact evidence manifest naming the first divergent owner or
   declaring the result non-discriminating. Only then may Slice 1B introduce a
   real `ResolutionId`/materialization consumer.

The current-source snapshot/source-guard portion and host preflight are
complete. The fresh chain classifies B4-F as compiler-side performance red:
stage2 timed out at 182.54 seconds with exit 143 and no `cv2_s2`. Stage2
semantic smokes are unavailable because no artifact exists; they are not
semantic red or green. Historical G9 remains diagnostic-only.

R0 as a promotion seal remains open until the same sealed source passes B4-F,
produces explicit stage2 semantic smoke results, and completes the fresh T0
A/B. Neither B4-H, G9, nor the manifest substitutes for those gates.

### 9.2 Reliability/architecture two-track join

The work proceeds on two coordinated tracks:

- **Reliability track:** restore a fresh B4-F build at or below 180 seconds
  (with a faster stretch target), then keep exact plain and no-prelude smokes
  green across every promoted slice. It owns source snapshots, generated
  stage provenance, resource budgets, and bootstrap rollback.
- **Architecture track:** move from T0 guard-only provenance to typed
  `ResolutionId`, `CallResolution`, and a typed
  resolution-to-materialization queue payload/transaction guard at final HIR
  emission plus `lower_missing` replay without injecting whole compiler
  contexts. It owns identity/lifetime contracts, normalized shadow, and
  structural tripwires; the default-path consumer remains blocked.

The **join** is a release gate: an architecture slice may run in guard/shadow
mode while reliability is red, but it cannot change the default path, delete a
queue/shim, or claim a performance win until the same source snapshot passes
B4-F plus both semantic smoke modes. Conversely, a reliability fix cannot
enter the architecture track without naming the owner boundary and preserving
the typed shadow ledger. A lower queue count or faster host build cannot
compensate for a semantic mismatch, and a semantic parity result cannot hide a
10x fresh-stage slowdown.

0. **Bootstrap freeze.** Keep B4-F/B5 evidence current and label B4-H as
   historical only. Permit docs, census,
   reducers, and emergency fixes that add an owner ledger; stop broad refactor
   while the frontier moves.
1. **Decision and dead-code census.** Enumerate semantic writers/readers,
   string rewrites, ambient maps, arena reads, pending queues, and candidate
   shims. No behavior change.
2. **Identity substrate.** Seal `DefIdentity`, `NameId`, `TypeId`,
   `ResolutionId`, and `MethodInstanceKey`; bridge to existing string/HIR
   records without changing selected targets.
3. **CallResolution.** Make overload, named-argument, receiver, and block
   presence one typed decision. Shadow candidate rejection and target identity.
4. **State scope and materialization.** Carry requested, selected, target,
   body, and emitted identities through one transaction; make type-parameter
   authority explicit; retain legacy queue behavior under parity.
5. **Compile-path substrate and declaration fixed point.** Extend the semantic
   stack to the complete prelude/require/macro graph before demand-driven body
   typing. No later phase may discover declarations ad hoc.
6. **Demand-driven body cache and HIR bridge.** Analyze each
   `MethodInstanceKey` once, use explicit in-progress states for recursion, and
   allow only leaf HIR emission helpers. The semantic path must not invoke the
   legacy supply-driven queue.
7. **Normalized shadow rollout.** Compare legacy/candidate HIR, MIR, LLVM, and
   runtime behavior, then enable the candidate behind a kill switch.
8. **AbiFacts and mechanical backend.** Move representation/layout facts to
   their owners; only after semantic identity is stable, introduce the typed
   streaming writer and zero-copy allocation seal.
9. **Physical split and deletion.** Move files/modules only after state
   contracts are smaller; retire shims and queues only after negative-use and
   bootstrap falsifiers pass.

The existing backend-writer plan remains a later backend-local slice. It must
not become a way to hide unresolved name, arena, or materialization ownership.

## 10. Normalized shadow gates

Raw HIR equality is invalid because `FunctionId`, `ValueId`, `BlockId`, and
`TypeId` numbering is order-sensitive. A candidate/legacy comparison is green
only when all of the following hold:

1. Normalize IDs and compare function name/signature sets, return types,
   instruction shape, normalized callee/operand shape, effects, hierarchy,
   module includers, extern tables, and type descriptors.
2. Both paths build MIR successfully.
3. Both paths emit LLVM successfully; worker count and output ownership do not
   alter normalized semantics.
4. Selected runtime reducers behave identically, including negative cases.
5. Under `ADAMAS_SEMANTIC_COMPILE=1`, no legacy queue/safety-net path executes;
   any execution is a hard failure, not a warning.
6. A mismatch names the first differing owner and keeps the legacy path active;
   it does not trigger a backend repair or a broad fallback.

The gate is a vector, not a single score. A lower queue count cannot compensate
for an identity mismatch, a peak-RSS regression, or a runtime difference.

## 11. Falsifier roster

This roster extends the [falsifier matrix](05-falsifier-matrix.md); it does not
retire existing B4/B5, name-resolution, materialization, or layout rows.

| Claim | Smallest falsifier | Expected decision |
|---|---|---|
| `ResolutionId` preserves typed identity continuity. | Direct versus alias-derived generic calls, named arguments, block calls, absolute `::Hash`, and two distinct declarations with the same display spelling. | Any collision, remint, or owner loss stops the slice. |
| `MethodInstanceKey` is injective for body/materialization demand. | Same declaration with different receiver/arg/block/named-arg types; same rendered name with different `DefIdentity`. | A key collision or mutable-key change rejects cache promotion. |
| Lawful concrete and union generic instances preserve identity and body continuity through materialization. | [Reducer](../../regression_tests/union_static_generic_materialization_guard.cr) and [guard](../../regression_tests/union_static_generic_materialization_guard.sh) compare concrete `main_arenas << map_arena`, explicit `.as(ArenaLike)`, and true union flow; they join selected instance, coercion/value type, receiver/value arity, HIR body, and optional full-stage LLVM symbol/stub shape. | Concrete flow may select the `AstArena` instance; explicit and true union flow may select union/reduced-union instances. Any owner/key discontinuity, lost receiver/value argument, unmatched body/symbol, or orphan zero-argument call/stub fails T9. Current focused HIR and full-G9 artifact modes are both measured red, so T9 is falsifiable but unsatisfied. |
| No semantic string keys remain on the candidate route. | Source-shape scan plus runtime ledger for mangled-name cache/owner decisions and late string rewrites. | Any semantic branch driven by a string remains guard-only. |
| Arena identity is preserved. | Block, macro, inline, reparsed, and current-arena `ExprId` reducers with equal numeric indices. | Index-only fallback or stale dereference fails closed. |
| No legacy queue is required. | `ADAMAS_SEMANTIC_ASSERT_NO_LEGACY_QUEUE=1` on hello, generic, macro, block, recursive, and stage2/3 reducers. | Any legacy queue/safety-net execution blocks promotion. |
| Normalized shadow is equivalent. | Legacy/candidate compare across declaration, HIR, MIR, LLVM, and runtime negative cases. | First normalized mismatch identifies the owning boundary; no backend patch. |
| Zero-copy lowers resource cost without lifetime damage. | Allocation/retention census on parser-to-HIR, HIR-to-MIR, and MIR-to-LLVM paths, plus arena-expiry negatives and peak RSS. | Unknown lifetime, use-after-expiry, or worse protected metric rejects the optimization. |
| Backend remains semantic-free. | Source-shape guard and IR probe showing backend consumes typed symbols/facts and never calls resolver, mangle, overload, or arena recovery. | Any reconstruction reopens the upstream owner slice. |
| Original Crystal compatibility is retained. | Original-vs-stage semantic oracle for type identity, overloads, blocks, aliases, enums, and runtime output. | Divergence is a semantic failure even if Adamas LLVM is valid. |
| Bootstrap frontier remains attributable. | B4/B5 classifiers and safe-stage smoke after each promoted slice. | Earlier frontier, unexplained RSS jump, or worker-only success stops the slice. |

Rows without an executable guard are `[MISSING-FALSIFIER]` in the companion
matrix until a script or reducer is added. A source-shape guard proves routing;
it does not prove runtime equivalence.

## 12. Performance and resource metrics

Record a before/after vector for every slice. Units and scope must remain
explicit; these metrics orient decisions and do not replace semantic value.

- **Correctness:** normalized HIR/MIR/LLVM mismatch count, runtime reducer
  divergences, B4/B5 classification, and legacy-queue assertion count.
- **Demand:** forced lowers, duplicate body analyses, pending queue peak and
  total enqueues, distinct `MethodInstanceKey` count, and cache hit rate.
- **Memory:** peak RSS, arena-retained bytes, live identity-record bytes,
  temporary string bytes, LLVM shard bytes, and worker merge buffers.
- **Allocation/copy:** allocation count and bytes by parser→HIR, HIR→MIR,
  MIR→LLVM, number of retained borrowed spans, string joins/reparses, and
  copy-elision opportunities accepted or rejected by the lifetime proof.
- **Time:** compile wall time split by declaration, resolution, materialization,
  MIR, and LLVM emission; include worker-count and cache-mode labels.

The protected value is compatible, attributable compilation under bounded
resources. A smaller file, fewer queue entries, or fewer allocations is only a
proxy. Counter-metrics (normalized equivalence, runtime output, arena safety,
and peak RSS) remain release-blocking.

## 13. Implementation seals and first vertical slice

### 13.1 Required seals

1. **Identity seal:** one registry constructs domain IDs; IDs carry their
   bounded context and cannot be fabricated from display strings downstream.
2. **Resolution seal:** `CallResolution` produces one `ResolutionId`, selected
   definition, state scope, and immutable `MethodInstanceKey` inputs.
3. **Materialization seal:** one transaction connects requested, selected,
   target, body, and emitted symbols. A difference is `exact`, an explicit
   `wrapper_forwarder`, or `rejected_mismatch`—never an implicit fallback.
4. **Arena/lifetime seal:** every retained AST reference names an owner arena;
   source spans and interned names outlive their consumers.
5. **Shadow seal:** old and candidate outputs are normalized before any default
   switch; the first mismatch is attributed to an owner boundary.
6. **Backend seal:** MIR/ABI facts provide all semantic choices required by
   LLVM emission; no backend resolver/mangler/layout oracle remains on the
   candidate route.
7. **Resource seal:** allocation and retention census has a baseline, a
   negative lifetime case, and an owner-approved budget before zero-copy
   promotion.

### 13.2 T0 provenance guard classification

Slice 1A (`91ebe332`) is **T0: guard-only provenance**, not the first vertical
semantic replacement. It adds compile-scoped `ArenaId` provenance and a
fail-closed registry under an assertion flag; the default route remains
behavior-neutral and lazy. Its evidence is useful for owner diagnostics, but
it does not yet construct `ResolutionId`, feed `CallResolution`, or reduce
materialization demand. T0 is therefore `COMPLETED` as a guard slice and
`UNADMITTED` as a behavior/architecture authority until R0 produces the same
source A/B result and a real consumer is named.

### 13.3 T1 identity-join guard and first vertical slice

T1 is a guard-only, current-red diagnostic. It is not a global absence proof,
an identity-continuity proof, or a performance measurement. The first slice
must remain behavior-neutral and proceed in this order:

1. **Ownership and `NameId` invariant.** Seal one owner for canonical names,
   declaration identity, and callsite semantic types. Replace named-argument
   strings with owned/interned `NameId` components before candidate promotion;
   make generic/tuple `SemanticTypeKey` components immutable copies or owned
   IDs rather than aliases to caller arrays. Falsifiers include a raw-string
   semantic branch, a post-insertion mutation that changes a key/hash, a
   generic/tuple order collision, or two owners minting different IDs for the
   same canonical name.
2. **Local typed decision.** Return a typed `CallResolution` and
   `MethodInstanceKey` locally from the existing resolution owner, at the
   post-resolution boundary after semantic literal/autocast normalization if
   applicable, and before Adamas HIR/value/ABI coercion or inline
   materialization. Do not add a new `AstToHir` ivar, broad context owner,
   parallel interner, or default-path consumer; keep the legacy route
   authoritative.
3. **Streaming producer (boundedness pending).** Emit the exact
   `t1_identity_join_v1` record at that owner boundary. The producer
   serializes typed IDs for telemetry only; `lower_function_if_needed` and the
   MAT string ledger remain rejected producers. Any current log ceiling is
   diagnostic unless a guard hard-caps it, so no bounded-memory or backpressure
   claim is admitted yet.
4. **External join (pending downstream enrichment).** The existing MAT ledger
   lacks `resolution_id` and cannot be joined deterministically. Define and
   emit a second versioned downstream correlation record/enrichment carrying
   `resolution_id` through inline, materialization, body, and emission-terminal
   states; until that exists, keep the external join pending rather than
   claiming that the existing streams suffice.
5. **One downstream correlation consumer.** After the second record exists,
   add exactly one read-only, default-off consumer that correlates selected
   resolution to materialized body/call symbol. Its falsifiers are missing
   rows, duplicate IDs, changed selected definition, receiver/value arity loss,
   body/symbol mismatch, and any legacy queue or backend reconstruction. Keep
   all other consumers on the legacy path.

The first DoD is ownership/NameId and selected-definition continuity with zero
HIR/MIR/LLVM behavior delta. It is not a queue reduction, compile-speed claim,
or rewrite authorization. The demand-driven body cache remains later until
declaration fixed-point parity is demonstrated.

T9 is a prerequisite for promoting this slice on the union-container path.
The upstream audit admits the distinct concrete and union instances. The
remaining defect is continuity: the zero-arg call/stub in full G9 LLVM must
remain a late-materialization/missing-target hypothesis until one reducer joins
selected `Def`/`DefInstanceKey`, coercion/value type, receiver/value arity,
materialized body, and emitted symbol for all three lawful flows.

## 14. Stop, dirty-worktree, and rollback rules

Stop and return to census/design when:

- a new facade re-infers a semantic fact or reads a rendered name as authority;
- two owners answer the same question or a consumer patch hides the owner;
- a key can be reminted, mutated after insertion, or read without its owner
  context;
- a shadow mismatch, legacy queue execution, arena-expiry failure, or backend
  reconstruction appears;
- a union insertion loses selected `Def`/instance identity, coercion/value
  type, receiver/value arity, body/symbol continuity, or becomes an orphan
  malformed/zero-argument body/call;
- a zero-copy change improves an allocation proxy while worsening normalized
  semantics, peak RSS, or retention;
- a fresh `s1 -> s2b` build exceeds the 180-second B4-F budget, or either
  exact plain/full-prelude or no-prelude smoke diverges;
- a B4/B5 run moves to an earlier or unexplained frontier;
- an architecture slice is promoted without the reliability/architecture join
  on the same source snapshot;
- three attempts operate at the same observation level without changing the
  targeted edge;
- a deletion is proposed before `CodePathStatus=delete_ready` and its negative
  use proof.

The audit worktree already contains unrelated modified compiler/spec files and
untracked probes. This SDD, its README index row, and the falsifier-matrix
section are the only owned paths for the documentation slice. Do not stage,
format, revert, or commit unrelated work. Before implementation, use an
isolated branch/worktree or an equivalent ownership checkpoint and stage exact
paths only. If parallel work creates another
numeric-slot-07 document (for example `07-inherited-virtual-demand.md`), keep
`07-compiler-decomposition-and-semantic-replacement.md` as the canonical
architecture-transition SDD and keep one README index row for slot 07. Do not
rename a user-owned file in this slice; at the next docs merge, assign the
other bounded contract the next unused numeric slot and update its links,
preserving its git history. Never admit two different SDDs under numeric slot
07.

Rollback is by disabling the candidate flag and returning consumers to the
legacy path. Do not delete queues, old registries, or compatibility shims until
the shadow soak and bootstrap gates pass. If source or frontier evidence moves,
mark this audit stale and refresh the counts and B4/B5 declaration before
continuing.

## 15. Ledger sync and residual decisions

- This document: transition boundary, identity/lifetime taxonomy, migration
  order, seals, and residual rejected surface.
- `docs/compiler_architecture_sdd.md`: current owner records, the split B4-H /
  B4-F frontier, architecture phases, and authority-edge table. It remains
  the main SDD; its section 0 and execution gate are updated with this R0
  amendment in the same documentation change.
- `docs/compiler_refactor_architecture_plan.md`: deferred physical/backend
  refactor options; revisit after semantic ownership is sealed.
- `PLAN_DEMAND_DRIVEN_REWRITE_RFC.md`: strategic semantic pipeline, canonical
  identity requirements, kill switches, and normalized shadow contract.
- `docs/specs/05-falsifier-matrix.md`: executable claim-to-falsifier rows,
  including the Architecture Transition section added with this document.
- `TODO.md`/`LANDMARKS.md`: active work and durable evidence. No entries are
  changed here.

Residual decisions deliberately left open:

1. The exact interner representation and arena-retention budget for IDs.
2. The complete declaration fixed-point inventory for compile-path macros and
   multi-file `require` graphs.
3. The first runtime implementation of `MethodInstanceKey` in Crystal source.
4. The zero-copy writer's sink/shard API and its allocation census script.
5. The threshold for default promotion after normalized shadow and B4/B5
   evidence; no scalar readiness score is defined by this SDD.
