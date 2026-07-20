# Compiler Decomposition and Semantic Replacement — Frontier SDD

> Status: DESIGN-SEALED; R0 CURRENT-SOURCE SNAPSHOT SEALED,
> B4-F PERFORMANCE RED; STAGE2 SEMANTIC SMOKES UNAVAILABLE
> (implementation/SDD amendment, 2026-07-19).
> Live T1a/T1b producer and Crystal-oracle audit amendment: 2026-07-19;
> bounded local T1a producer, T1b0 same-owner carrier, the default-off T1b1a
> canonical parsed-owner candidate, the T1b1b1 owner-tagged macro-result
> boundary, and T1b1b2a exact call-tail/block admission are implemented;
> T1b1b2b, T1b2, and the full production handoff remain current-red/open.
> Resource evidence is scoped below and is not a fresh-s2 or <=180-second
> compile-speed claim.
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
| T0 same-source fresh A/B | `NOT COMPLETED` | R0 promotion remains blocked independently of B4-F; T8 also remains missing until an executable validator is committed. |

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
  the manifest records fresh-output/source/output hashes and `cache_mode`; no generated
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

Current blockers and candidate-only substrate status are explicit:

- The isolated candidate now owns named-argument identity with `NameId` and
  owns generic/tuple/named sequences through immutable value carriers. `NameId`
  and `SemanticTypeId` are 16B handles whose equality/hash authority is the
  `(owner interner reference, ordinal)` pair; each owner validates issued
  ordinals, and equal ordinals from different tables are unequal. No separate
  `IdentityScope` token is used. This closes those substrate blockers only in
  the candidate; it is not production callsite evidence or a promoted
  consumer, and residual performance measurement is still required.
- There is still no production semantic callsite type interner that can
  authoritatively populate receiver and argument semantic type IDs, no
  production `resolution_id` producer, and no downstream correlation through
  inline, materialization, body, and emission-terminal states.
- `IdentityDryRunTracker` and its source file are removed from the isolated
  candidate. The retired path was a definition-annotation/body-infer proxy,
  not the semantic callsite producer; its historical counts are archival only.
- Fresh current-source B4-F remains **MEASURED RED** at the <=180-second
  target; no fresh `s2` semantic smoke or T1 admission follows from the
  candidate substrate.

The T1 guard is **availability/current-red only**: it can show whether the
current source/configuration emitted a row or exposed the current failing
boundary. It does not prove global absence of another producer, semantic
identity continuity, or equivalence of selected definition, coercion, body,
and emitted symbol. No rewrite, broad in-process owner, or performance claim
is admitted.

### 2.7 T1a/T1b producer and handoff split

The live audit fixes the producer boundary before the HIR boundary. **T1a is
the semantic producer seam:** `Adamas::Compiler::Semantic::TypeInferenceEngine`
is the canonical place to capture one call decision, at `infer_call`
(`src/compiler/semantic/type_inference_engine.cr:6846-7367`) after
receiver/argument/block/named types are known and at `lookup_method`
(`:8507-8574`) after overload filtering and specificity selection. This names
the seam, not an admission of the current monolith or its transitional caches
as a finished authority. The bounded T1a implementation now returns an
immutable `CallResolution`, mints one owner-scoped `ResolutionId`, preserves
the selected `DefIdentity`, and retains semantic receiver, positional,
typed-block, and source-ordered named-argument facts before HIR/value or ABI
coercion. Its admitted scope is explicit-receiver, single-target, source-backed
ordinary overloads; typed blocks with a complete declared signature and known
actual result; concretely typed generic calls whose carried receiver/argument/
block/named facts contain no unresolved `TypeParameter`; and ordinary named
calls without a block. Receiverless calls,
constructors/type applications, unions/virtual target sets, named-block calls,
default/splat expansion, unresolved type parameters, synthetic methods, and
body-key normalization remain outside T1a. Such shapes fail this read-only
sidecar closed and leave inference on the legacy path; the legacy builtin
`ExprId(0)` placeholder is never admitted as a `DefIdentity`.
Capture is an explicit typed `TypeInferenceEngine` constructor capability and
is default-off. Until T1b names a consumer and a matched resource gate measures
the carrier, the legacy compile path allocates no `CallResolutionContext`,
resolution map, or semantic identity interner.
Nominal semantic IDs additionally carry a source-backed
`TypeDeclarationIdentity(arena_id, expr_index)`: the short `NameId` remains
diagnostic spelling, so equal local names in different namespaces cannot
coalesce. Legacy name-only `TypeParameter` values fail closed until their
declaration owner is represented.
`ResolutionScope` retains the actual `AstArena` and semantic interner owners,
not only their numeric IDs, and permits each issued ordinal to be claimed once
in order. A rejected carrier construction cancels its pending issue so a
foreign semantic table cannot poison the next valid issue. The rejected
ordinal is burned rather than reused: gaps are legal, while stale-token ABA is
not.
`CallResolutionContext` derives its arena ID from that retained owner
and verifies source-backed `CallNode`/`DefNode` coordinates before publication.

The current `MethodSymbol#type_parameters` is not an admitted identity or
generic-provenance source. `DefNode` does not retain typed signature nodes or
`forall/free_vars`, and the collector derives this field by walking annotation
strings; for example, without a source declaration it can mistake `Object` in
`Int32 -> Object` for a method type parameter. T1a therefore keys only the
actual semantic call types and lets the typed encoder reject a surviving
`TypeParameter`. A later signature refactor must retain `TypeExpr` plus explicit
free-variable identity in the frontend before declaration-level generic policy
can be enforced without string heuristics.

The `AstToHir` M1/M2 records are rejected as the producer. `CallShape`,
`MethodInstanceKey`, and `Resolution` are explicitly inert scaffolding
(`src/compiler/hir/ast_to_hir.cr:771-847`); `resolution_from_selected_name`
(`:38880-38908`) splits a selected string and carries its suffix verbatim. It
is a string/HIR identity sidecar, not semantic resolution. The downstream
`lower_call`/`lookup_function_def_for_call` path may collapse aliases, lose
per-call facts, or reconstitute identity from a requested name, so it cannot
retroactively become the producer.

**T1b is the explicit downstream handoff and remains current-red.** A
versioned, read-only handoff
must carry `ResolutionId`, selected `DefIdentity`, owner/state scope, and the
immutable `MethodInstanceKey` inputs through HIR, MAT, body, and emission
terminal records. The existing MAT/HIR path is a consumer of T1a facts; it
must not re-resolve or infer a missing callsite identity. Because the current
MAT/HIR streams collapse or drop per-call identity, T1b remains pending and
cannot be replaced by a join on `materialized_name`.

The 2026-07-19 T1b owner audit found an earlier production boundary that must
be removed rather than bridged heuristically. `run_semantic_compile_prepass`
re-parses every active unit into one new `CompileShadowAggregate` arena, while
the normal HIR path lowers the original per-file `ParsedUnit` arenas. The
semantic engine is then discarded before `AstToHir` is constructed. Therefore
the producer `CallsiteIdentity(arena_id, expr_index)` and selected
`DefIdentity` do not name nodes in the HIR owner, even when a simple source
happens to receive the same local expression ordinals in both parses.

Path, source spelling, span, node text, and local-expression ordinal parity are
rejected as production identity joins. Macro/generated nodes, conditional
selection, require ordering, and future AST-cache behavior can invalidate such
a join while leaving its strings or simple ordinals apparently equal. A typed
`SourceUnitId + local ordinal` parity probe may exist only as a default-off,
fail-closed transition diagnostic with explicit graph-parity evidence; it may
not mint `CallsiteIdentity`, `DefIdentity`, or a body key and may not authorize
materialization.

T1b is therefore split without weakening its final DoD:

- **T1b0 — same-owner carrier plumbing.** On a deliberately same-arena test
  path, carry an immutable `CallResolutionHandoff` from the T1a resolution into
  HIR and MIR. Two distinct source callsites selecting the same typed def must
  retain distinct owner-scoped `ResolutionId` values while comparing equal by
  one `DefInstanceKey`. The carrier is default-off, changes no selection or
  emission behavior, and performs no string re-resolution. It may retain only
  the existing compile-scoped arena lease already required to prevent numeric
  `arena_id` reuse/ABA; it must not inject or retain the whole
  `CallResolutionContext`, `TypeInferenceEngine`, or semantic graph. Payload
  production is default-off, but the nullable HIR/MIR pointer slots exist on
  every call instruction and are therefore not zero-footprint. Detaching
  that lease requires a unique compile-session/arena token first and is not
  part of this smallest plumbing slice. T1b0 is partial transport evidence,
  not a production T1b terminal.
- **T1b1a — canonical parsed syntax ownership.** Remove the compile-path dual-parse
  identity split: semantic resolution and HIR lowering must consume one
  canonical syntax owner (or an explicitly shared typed syntax identity issued
  before either consumer). The shadow reparse remains diagnostic and cannot be
  the production handoff source. This sub-slice covers the initial parsed graph,
  not independent HIR reparse arenas.
- **T1b1b1 — macro-result ownership boundary.** The result of macro expansion
  must cross into HIR as one owner-tagged reference minted around the trusted
  producer call. The capture API owns the append floor and supplies the exact
  owner to that producer, so the bare ID cannot cross the boundary separately.
  The consumer must dereference only that retained owner and must not recover
  ownership from a bare numeric ID, size/span scan, source text, or scan order.
- **T1b1b2 — remaining generated/reparse ownership closure.** Every inline,
  repair, nested-macro, body-inference, source-helper, or reparse `ExprId` that
  crosses arena context must carry an owner token or an equivalent typed
  reference. Unowned generated provenance fails closed, and source-text helpers
  must select the owning view before reading.
  - **T1b1b2a — exact call-tail/block child admission (implemented).** `lower_call`
    captures the `CallNode` owner before semantic child classification or any
    fast-return path. Admission validates direct `node.block`, the final
    positional expression, and a trailing `&` operand through that exact owner;
    every downstream block/proc/inline-yield reader uses the retained
    `call_arena` and safe `[]?` lookup. Missing, out-of-range, or foreign
    canonical-generated/unregistered IDs fail with a stable `LoweringError`
    before ordinary argument lowering or unsafe/global recovery. Shared parsed
    prefix IDs remain intentionally readable by canonical views. This sub-slice
    introduces no ownership-only AST copy, no per-read owner allocation, and
    keeps existing block-pass synthesis writes in the retained owner. It is
    contract hardening, not evidence that a foreign-child production edge
    currently exists and not a compile-speed, bootstrap, or body-deduplication
    claim.
  - **T1b1b2b — remaining raw recovery (open).** Nested macro/inline repair,
    body inference, main-root repair, general `lower_expr`, and semantic source-
    text helpers still require their own owner-tagged boundaries and falsifiers.
- **T1b2 — materialization/emission terminal.** Only after T1b1b may the
  production path carry the original `ResolutionId` and equal typed body key
  through demand, cache-hit/materialized/inline classification, MIR, and the
  versioned terminal record. The existing name-keyed MAT ledger is observation
  data, not the join authority.

The admitted T1b1a candidate is one parse-time `AstArena` shared by every
active source parser before either semantic analysis or HIR lowering begins.
Its `ExprId` sequence is therefore globally unique inside that compile
session, including child IDs stored inside AST nodes; no node clone, ID rewrite,
path lookup, or source-coordinate join is needed. Semantic analysis consumes
that exact arena directly. HIR keeps its existing per-file path/source context
through one lightweight view per parsed unit. Every view can dereference the
whole frozen parsed-ID prefix so embedded global child IDs remain valid, but it
claims source provenance only for its unit's explicit `[start, end)` parse
range. Generated nodes appended through a canonical view are allocated
monotonically in the shared owner so they cannot collide between those views;
each view keeps only a sorted compact list of the IDs it issued. A shared node
that no view registered is rejected by ID-aware view access and HIR owner
recovery. This guarantee does not cover an equal numeric ID from an independent
arena; that is T1b1b. HIR owner recovery must prefer the unique unit range or
registered generated owner before its legacy size heuristic. `AstArena` and
canonical views lazily retain every parser `StringPool` written into them, and
parsed units/semantic aggregates retain the source-parse pools as well.
VirtualArena/PageArena pool leases are outside this slice. Retaining only source
text or installing an unrelated fresh pool is not a lifetime proof. Replacing
or reparsing the canonical arena
invalidates every resolution and view derived from it; the owner is
compile-session local and is not a cross-run cache key.

The candidate is default-off outside `ADAMAS_SEMANTIC_COMPILE`. The legacy
per-file parse topology and the diagnostic `ADAMAS_SEMANTIC_SHADOW` reparse
remain unchanged; both legacy and canonical aggregates now explicitly retain
their parser pools because that is a lifetime correction, not candidate
authority. The candidate route must bypass AST-cache load/save until cached
trees can be imported with a typed owner-preserving relocation contract; local
IDs from independently cached arenas cannot enter the shared owner. Semantic
macro expansion may add nodes to the canonical arena, but those generated IDs
do not automatically become source-backed HIR identities. They require an
explicit generated provenance mapping in a later slice or fail closed.

Rejected T1b1a alternatives are: a `VirtualArena` over independently parsed
files, because embedded child IDs are not rewritten to its global offsets;
per-file semantic analyzers sharing one context, because symbols still carry
bare `ExprId` values; cloning/importing trees into an aggregate arena, because
every embedded ID would need a proven deep relocation; one aggregate HIR arena
without per-file views, because current `__FILE__`, diagnostic, and source maps
are arena-scoped; and any path/span/text/local-ordinal join. Original Crystal's
`Def#object_id` and `DefInstanceContainer` support the same owner-scoped
principle, not a source-stable identity claim.

The executable T1b1a falsifier parses identical source/path pairs under two
independent owners and requires their equal spans and local ordinals to remain
different identities and fail cross-owner admission. Its positive half parses
multiple units into one owner and requires globally distinct IDs, exact node
address continuity through each unit view, correct per-unit source/path
projection, and fail-closed generated/view-local IDs. Promotion additionally
requires semantic compile/no-prelude parity, a production assertion that no
second compile aggregate parse occurred, unchanged default-route semantics/
parse topology, and matched allocation/RSS evidence. This slice creates no
T1b0 handoff payload and
authorizes no MAT, body-cache, MIR, or LLVM consumer.

The implemented candidate selects the shared arena before recursive parsing,
captures each unit's parsed range, binds the per-unit views only after the final
parsed limit is known, and constructs the semantic aggregate from the original
roots and diagnostics without invoking the diagnostic reparse builder. AST
cache load/save is disabled only on this candidate route. The legacy per-file
route and `ADAMAS_SEMANTIC_SHADOW` retain their prior builders; their aggregates
now retain the pools that already own their interned slices. Focused owner
specs pass 8/0; the targeted semantic/HIR/CLI set passes 456/0; the full
`spec/semantic` directory passes 958/0; and the host compiler builds. A
cross-file candidate no-prelude compile reports `syntax_owner=canonical`, and
an arithmetic no-prelude artifact compiles and exits successfully; the legacy
no-prelude `puts 7` compile still prints `7`.

Full-prelude semantic compile is not green on either the candidate or its
`eae05ff3` parent: both stop in the existing generated-macro resolution family
with 140 diagnostics. A single matched safe-run measurement to that same
failure boundary reports the final hardened candidate at 1628.6 ms and
118,603,776-byte peak RSS versus parent 2460.4 ms and 178,176,000 bytes. The
candidate retains 800 more
parsed nodes because inactive/skipped units remain in the shared owner, while
the active root, analysis-root, generated-node, identifier, file, and
diagnostic counts stay matched. This is evidence that removing the duplicate
aggregate parse improves this bounded failing lane; it is not a completed
full-prelude parity result, a stable benchmark, a body-deduplication result, or
evidence for B4-F. This seals T1b1a only for the canonical parsed graph.

T1b1b1 migrates the first demonstrated cross-arena generated boundary. A
compile-scoped `OwnedExprRef` retains the exact dynamic `AstArena` or
`CanonicalSyntaxView`, the 4-byte `ExprId`, and an `OwnedExprOrigin : UInt8`
enum. `capture_macro_expansion(owner) { |exact_owner| producer(exact_owner) }`
is the only factory admitted for macro results: it captures the append floor
itself, supplies the exact retained owner to the producer, and tags the result
before the bare `ExprId` can escape. Null/invalid macro output becomes no
reference; a stale/pre-existing or out-of-bounds ID, foreign canonical-view ID,
shrinking owner, or unsupported `VirtualArena`/`PageArena` owner fails closed.
The typed `lower_expanded_macro_result` consumer calls `fetch?` on that retained
owner and never invokes `arena_for_expr?`, scans paths/spans/sizes, or searches
other arenas. Retaining the exact canonical view preserves its registered-
generated-ID provenance; collapsing it to its shared source arena would lose
that proof. This changes neither `ExprId` layout nor parser/LLVM ABI and
introduces no ownership-only AST copy at this boundary. It does allocate one
short-lived reference object for each
non-null macro result on the two migrated expansion call paths, so this is not
a zero-allocation or compile-speed claim.

A plain append-only `AstArena` has no per-node provenance ledger and therefore
cannot authenticate a deliberately dishonest producer that ignores the owner
supplied by the capture block and returns an equal-index ID from another plain
arena. T1b1b1 removes that separable pair from the migrated production API and
source-checks that both producers use the supplied owner; it does not claim
cryptographic or type-level proof against a malicious closure. Canonical views
add the stronger generated-ID ledger check. Any future API that again accepts
`(plain owner, bare generated ExprId)` from separate sources is rejected and
belongs to T1b1b2 unless plain arenas gain an owner-issued generation token.

The T1b1b1 falsifier constructs independent owners and an exact canonical view
with colliding numeric IDs, rejects foreign-view/stale/pre-floor IDs, exercises
a fresh positive generated ID through the capture block, retains interned
slices through GC churn, pins `sizeof(ExprId) == 4`, and source-checks that both
producers use the supplied owner while the consumer has no old
`ArenaLike + ExprId` signature. Focused evidence is 6/0; the targeted owner,
macro, semantic-CLI, and HIR set is 334/0; full `spec/semantic` is 958/0; the
host compiler builds; and a no-prelude macro artifact compiles and exits 0.
The same-target guard deliberately remains `MEASURED_RED` with two source
calls, one legacy MAT transaction/completion, two emits, and zero terminal
rows. That result is a boundary certificate, not a regression.

T1b1b2b remains open. `arena_for_expr?` and several nested macro, inline,
repair, body-inference, and source-text helpers still accept bare `ExprId` or
use size/span/full-node recovery; an equal numeric ID from an independent arena
can still collide there. The proposed packed-main-root seam was not selected:
all current generated `program.arena` calls to `collect_top_level_nodes` pass
`collect_main_exprs=false`, so no generated root escape through `main_exprs`
was demonstrated. That observation does not prove the broader helper graph
safe. Bulk `nodes` remains traversal/debug data rather than identity authority.
The scoped verdict is **ROBUST** for T1b1a, the migrated T1b1b1 boundary, and
implemented T1b1b2a; it remains **VULNERABLE/OPEN** for full T1b1 because
T1b1b2b must still remove the remaining raw owner recovery before default
promotion or T1b2.

T1b1b2a exact call-tail/block child admission is implemented as the first
bounded fail-open contract at the `lower_call` boundary, without claiming an
observed foreign-child production bug. The complete call shape is admitted
before type-like and `is_a?` fast returns. Direct blocks, final positional
expressions, trailing `&` operands, and all downstream block/proc/inline-yield
readers use the exact captured `call_arena`; missing, out-of-range, or foreign
canonical-generated/unregistered children raise stable `LoweringError`
diagnostics before ordinary lowering or global recovery. The dedicated
`spec/hir/call_child_owner_spec.cr` covers 21/0: plain and canonical collision
negatives, exact-owner positives, block-pass helper rejection, direct/trailing
fast-return negatives, and source-shape guards for every call-child reader. The
six-file target is 355/0; full `spec/semantic/` is green at 958/0 across
86/86 files. The host build is rc=0;
the corrected no-prelude three-shape smoke (ordinary block, macro-expanded
block, and trailing `&proc`) compiles rc=0 and safe-runs rc=0 with exit-only
oracle outputs `42`, `41`, and `42`.

The source contract follows original Crystal's direct `Call` child-object
ownership: a shared parsed prefix is intentionally readable by canonical
views, while a plain `AstArena` cannot authenticate a deliberately forged
equal-index ID without a generated-node ledger. No ownership-only AST copy is
introduced and no per-read owner object is allocated; existing block-pass
synthesis writes into the retained owner. Nested/non-last argument recovery,
copied nested `CallNode` child IDs, general `lower_expr`, body inference, source
helpers, and main-root repair remain T1b1b2b.

The bounded T1b0 implementation satisfies only the first bullet on a manually
bound test path. Its focused same-owner spec proves distinct callsites retain
distinct `ResolutionId` and `CallsiteIdentity` values, same-def/same-type calls
share one immutable `DefInstanceKey`, different overload definitions remain
distinct despite equal display spelling, source call/def coordinates are
revalidated through the retained owner, and one ordinary non-virtual,
non-stack-promoted HIR-to-MIR route plus one copy-propagation clone retain the
exact carrier. Named calls are rejected by the handoff factory; default/splat
expansions remain rejected upstream by T1a and produce no carrier input. HIR
call-recreation postpasses, virtual dispatch, and stack-promotion replacement
remain outside T1b0. No production adapter/attach API exists because current
HIR cannot prove source-owner association; no production CLI path constructs
or consumes this carrier. Matched `instance_sizeof` measurement
against parent `a74172f7` records `HIR::Call` 56 -> 64 bytes and `MIR::Call`
128 -> 136 bytes: +8 bytes per instruction in each layer. The carrier is a
shared reference across the tested HIR/MIR/clone corridor, so that corridor
does not copy its semantic argument sequence or 88-byte `DefInstanceKey`.
However, each allocated `CallResolutionHandoff` object is 128 bytes. Production
allocates none today; a future one-payload-per-source-call route is rejected
unless body keys are interned/shared (or another compact typed owner is proven)
and the matched allocation/retention/RSS gate passes. This is explicit T1b0
resource debt and prevents any zero-cost, memory, or speed claim.

The first targeted diagnostic is an **identity explosion ledger**, not a speed
benchmark. For each resolution, preserve the tuple
`(resolution_id, selected_def, owner, semantic_args, block_shape, named_args)`
and compare its cardinality with `materialized_name`. A one-to-many mapping is
not automatically a bug: it must first be classified as an explicit wrapper /
forwarder, dynamic-dispatch branch, or a duplicate body. The ledger must keep
named arguments in source order; sorting is a later hypothesis, not a producer
normalization. No compile-time or memory improvement claim follows from this
diagnostic alone.

### 2.8 Original Crystal oracle (comparison only)

The pinned Crystal source is a behavior and phase oracle, not an ownership or
performance template:

- `syntax/ast.cr:849-869,900-915` stores `Call` receiver, arguments, block,
  block argument, and named arguments as direct child `ASTNode` references,
  records the exact `block.call` back-reference, traverses those exact objects,
  and deep-clones the child graph. There is no local numeric child ID and no
  cross-tree fallback. `semantic/main_visitor.cr:1341-1369` and
  `semantic/bindings.cr:179-269` retain exact object identity when binding and
  propagating an enclosing call. The faithful arena translation is therefore
  an exact owner-bound child lookup that fails closed, not a global arena scan.
- `syntax/ast.cr:80-86` clones AST nodes into fresh objects while preserving
  their locations; identity is the live node object, not `(path, span)`.
  `semantic/ast.cr:139-190` keeps `owner`, `original_owner`, and `macro_owner`
  as semantic provenance on `Def`; those fields do not search an arena from a
  local numeric node ID. `types.cr:883-902` keys typed def instances with the
  selected `Def#object_id` plus typed arguments, block type, and named facts.
  Adamas cannot copy that heap-object representation directly, but its arena
  equivalent must preserve `(exact owner, ExprId)` and mint a fresh identity
  when a node is cloned/reparsed.
- `semantic/call.cr:37-137` waits for operand types, performs exact lookup then
  autocast retry; `semantic/method_lookup.cr:192-377` fixes the selected `Def`
  and restriction-normalized positional/named types in `Match`.
- `semantic/call.cr:365-403` removes literal wrappers, chooses the owner,
  builds `DefInstanceKey`, inserts the typed definition before recursive body
  walking, and skips the walk on a cache hit. `types.cr:865-902` defines the
  per-owner cache; `semantic/match.cr:1-38` records the known inherited-owner
  duplication trade-off.
- `codegen/codegen.cr:1704-1711` does not emit a regular method body when
  visiting `Def`. `codegen/call.cr:433-491` emits only when a call reaches
  `target_def_fun`, while simple literals/self/ivar/primitive bodies inline;
  `codegen/fun.cr:20-25,64-220` turns the typed body into an LLVM function.
  `codegen/call.cr:332-431` intentionally materializes each virtual-dispatch
  branch.

Crystal's source-order named-argument arrays are part of its forwarding and
  default-expansion behavior (`semantic/default_arguments.cr:4-113,180-250`),
  even though exact-match comparison sorts names
  (`semantic/method_lookup.cr:379-395`). Adamas therefore preserves source
  order in `CallResolution`; any canonical sort in `DefInstanceKey` stays
  guard-only until a forwarding-equivalence proof covers defaults, splats,
  double splats, and expansion identity. This oracle section makes no speed
  claim.

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
| `DefIdentity`, `TypeDeclarationIdentity`, `SemanticTypeId`, `DefInstanceKey`, and `SemanticToHIRAdapter` in `src/compiler/semantic/identity/` | Extend these as the canonical identity substrate; keep `ResolutionId` owner-scoped beside them and preserve the one-way HIR adapter. | Do not create parallel `*Key2`, duplicate type interners, or a second semantic-to-HIR bridge. |
| `DefInstanceKey` named-argument component | The isolated candidate now owns canonical `NameId` pairs through an immutable value carrier; each `NameId` is authoritative only as `(owner interner reference, ordinal)`, and production callsite plumbing/downstream correlation remain pending. | Do not treat isolated candidate handles as cross-run authority or as a promoted semantic producer. |
| Current `AstToHir` maps, queues, and owner records | Keep as a legacy compatibility carrier behind facades and differential ledgers. | Do not remove queues or rewrite all lowerers in the first slice. |
| `TypeInferenceEngine` (13,201 lines, 464 `def` lines) | Treat its existing `infer_call` -> `lookup_method` -> `infer_method_call_result` seam as the canonical T1a producer boundary; reuse the rest as a leaf/legacy differential oracle where needed. | Do not promote the class unchanged as the new declaration, resolution, or body-cache authority; it must be decomposed behind the budgets below. |
| `AstToHir` M1/M2 resolution scaffolding (`CallShape`, `Resolution`, string-derived `MethodInstanceKey`) | Keep only as a diagnostic/HIR compatibility carrier while T1a facts are handed off explicitly. | Reject it as a semantic producer: its selected-name suffix carrier and `lower_call`/MAT path can collapse or drop per-call identity. |
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

#### Context bridge: resolution versus body identity

| Field | Semantic-resolution context | Body/materialization context |
|---|---|---|
| Term | `ResolutionId` | `MethodInstanceKey` |
| Sense | One call/name-resolution decision, including rejection or a selected target set. | One immutable typed body-demand identity, independent of callsite spelling. |
| Relation | One resolution may produce zero, one, or many instance keys (for example, virtual dispatch). | Many resolutions may coalesce to one instance key when declaration, owner scope, receiver, argument, block, and named facts are equal. |
| Allowed transfer | Carry the ID and selected facts downstream as an explicit handoff. | Use only the typed key for body cache/materialization; retain the source `ResolutionId` for correlation. |
| Loss/fit note | A resolution is not a body; a rejected resolution has no instance. | A key cannot reconstruct the original callsite or justify overload selection. |
| Decay trigger | Resolver contract, semantic type interner, or owner scope changes. | Key schema, forwarding semantics, ABI shape, or declaration fixed point changes. |
| Evidence | T1a producer record at the semantic seam. | T1b handoff and body/emission join; no name-only reconstruction. |

This is a lossy bridge in both directions and must be treated as such. In
particular, `CallResolution` preserves source-order named arguments. A sorted
or otherwise canonicalized named component in `DefInstanceKey` is not admitted
until a forwarding-equivalence proof demonstrates that reordered defaults,
splats, double splats, and generated forwarding definitions preserve the same
selected body and ABI.

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
| `CallResolver` | receiver/argument types, source-ordered named arguments, block shape, callsite scope, `DeclarationIndex` | `ResolutionId`, `CallResolution`, selected `DefIdentity`, rejection reasons, `MethodInstanceKey` inputs | body lowering, pending-queue mutation, LLVM symbol construction, backend fallback |
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
   `cache_mode`; report any external host cache separately and hold it
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
must remain behavior-neutral and proceed in two separately falsifiable
sub-slices: **T1a (semantic producer)** and **T1b (explicit downstream
handoff)**. T1b cannot be admitted by a late MAT/HIR join if T1a did not carry
the per-call identity.

The 2026-07-19 bounded candidate now includes the T1a substrate/local producer
and T1b0 same-owner carrier plumbing. `NameId` replaces named-argument strings,
generic/tuple/named
sequences are owned by immutable value carriers, and nominal semantic keys use
source-backed `TypeDeclarationIdentity` rather than short-name equality.
`NameId` and `SemanticTypeId` remain owner-scoped handles; cross-table equal
ordinals are unequal. The producer stores only the latest resolution per
callsite for diagnostic lookup and returns each newly minted resolution from
its context; it does not retain a replay history. T1b0 can derive one immutable
`DefInstanceKey` and carry the exact handoff through manually bound same-owner
HIR and direct MIR, but no streaming identity record, production CLI binding,
MAT/body/emission consumer, or downstream terminal is admitted. Residual
resource measurement records +8 bytes for every HIR and MIR call instruction;
no speed claim is made, and the fresh B4-F <=180-second frontier remains red.
Capture is a typed
constructor capability and default-off; normal legacy inference does not
allocate the context or identity tables. Capture-on resource measurement
remains required before T1b promotion.

1. **Ownership and `NameId` invariant.** Seal explicit owners for canonical
   names, source-backed nominal declarations, resolution ordinals, and callsite
   semantic types. Replace named-argument strings with owned/interned `NameId`
   components before candidate promotion; make generic/tuple `SemanticTypeKey`
   components immutable owned arrays rather than aliases to caller arrays.
   Falsifiers include a raw-string semantic branch, short-name nominal
   collision, unowned type parameter, forged call/def coordinate, replayed
   resolution, foreign semantic interner, post-insertion key mutation,
   generic/tuple order collision, or mixed owner scope.
2. **T1a — local typed decision.** At the existing semantic
   `TypeInferenceEngine` call-resolution seam, return a typed `CallResolution`
   carrying selected definition, actual semantic receiver/argument types,
   known block result, and source-ordered named facts before Adamas
   HIR/value/ABI coercion or inline materialization. This slice does not claim
   Crystal-style restriction-normalized `Match` facts, virtual target sets,
   owner/state selection, or a constructed `MethodInstanceKey`; those remain
   explicit future inputs. Do not add a new `AstToHir` ivar, broad context
   owner, parallel interner, or default-path consumer; keep the legacy route
   authoritative.
3. **T1a — optional diagnostic serialization (pending, not authority).** If an
   external diagnosis needs it, emit the exact `t1_identity_join_v1` record at
   the owner boundary and serialize typed IDs for telemetry only. This is not a
   T1a DoD and cannot replace the typed T1b handoff; the current producer emits
   no telemetry. `lower_function_if_needed` and the MAT string ledger remain
   rejected producers. Any current log ceiling is diagnostic unless a guard
   hard-caps it, so no bounded-memory or backpressure claim is admitted yet.
4. **T1b0 — same-owner carrier plumbing (completed, partial only).** A
   read-only typed handoff now exists on a manually bound same-arena test path.
   It preserves
   two distinct
   source-call `ResolutionId` values through HIR and MIR while both handoffs
   compare equal by one immutable `DefInstanceKey`. No string-derived lookup,
   behavior change, backend row, production attach API, or production CLI join
   is admitted by this sub-slice. HIR postpass reconstruction, virtual dispatch,
   and stack promotion are explicitly outside it. The carrier preserves the existing compile-scoped owner lease
   through its IDs but does not retain or inject the whole semantic context.
   It adds one nullable pointer slot to every HIR and MIR call (+8 bytes each
   in the matched parent/candidate measurement). The shared payload is 128
   bytes with an inline 88-byte body key; production allocates none, and a raw
   one-payload-per-call route is not admitted. Owner retention, body-key
   interning/compact ownership, and aggregate call-count cost remain promotion
   gates.
5. **T1b1a — canonical parsed syntax owner (implemented, candidate route only).** The
   default-off semantic compile route parses all units into one shared owner,
   gives HIR per-unit source views, and builds the semantic aggregate from the
   original nodes without reparsing. Path/span/text/local-index joins remain
   rejected; a parity probe is diagnostic only. Generated nodes without typed
   provenance fail closed. Full-prelude semantic compile still stops at the
   parent's existing generated-macro frontier, so this is not a promotion or a
   full semantic-parity claim.
6. **T1b1b1 — owner-tagged macro-result boundary (implemented).** The two
   production macro-expansion result paths now mint `OwnedExprRef` inside a
   capture block that owns the pre-expansion floor and passes the exact owner to
   the producer. The consumer fetches directly through the retained exact
   owner/view. Equal numeric IDs, stale/pre-existing IDs, foreign canonical-view
   IDs, unsupported owner kinds, and owner lifetime are executable falsifiers.
   Plain arenas rely on the trusted producer using the supplied owner because
   they have no generated-node ledger; reintroducing a separable plain-owner/
   bare-ID API is rejected. `ExprId` remains 4 bytes and no ownership-only AST
   copy is introduced; one short-lived reference allocation per non-null result
   remains measured resource debt.
7. **T1b1b2 — remaining owner-tagged generated/reparse transport (open).**
   T1b1b2a exact call-tail/block admission is implemented: every `lower_call`
   block-child classification now
   uses the exact captured call owner and safe `[]?`, with independent-arena
   and canonical-generated-owner collision negatives plus same-owner positives.
   It introduces no ownership-only AST copy or per-read reference allocation
   and makes no observed-production-bug or speed claim. T1b1b2b remains the
   next slice: replace bare
   cross-arena IDs and raw size/span recovery in nested macro/inline repair,
   body-inference, main-root, general lowering, and source-text helpers. Audit
   each route against equal numeric IDs from independent arenas; the bulk view
   `nodes` array is never identity authority.
8. **T1b2 — explicit downstream terminal and one consumer.** After T1b1b2,
   define and emit the versioned correlation enrichment carrying the original
   `resolution_id` through inline, materialization, body, and emission-terminal
   states. Add exactly one default-off consumer correlating resolution to typed
   body/call symbol. Its falsifiers are missing rows, duplicate IDs, changed
   selected definition, receiver/value arity loss, body/symbol mismatch, and
   any legacy queue or backend reconstruction. Keep all other consumers on the
   legacy path.

The T1a DoD is ownership/NameId and selected-definition continuity with zero
HIR/MIR/LLVM behavior delta. T1b0 closes only same-owner HIR/MIR carrier
continuity; it does not satisfy T1b. The full T1b DoD remains an explicit
production per-call handoff with no dropped or reminted `ResolutionId` through
the downstream terminal after canonical syntax ownership is sealed. Neither
DoD is a queue reduction, compile-speed claim, or rewrite authorization. The
demand-driven body cache remains later until declaration fixed-point parity is
demonstrated.

T9 is a prerequisite for promoting this slice on the union-container path.
The upstream audit admits the distinct concrete and union instances. The
remaining defect is continuity: the zero-arg call/stub in full G9 LLVM must
remain a late-materialization/missing-target hypothesis until one reducer joins
selected `Def`/`DefInstanceKey`, coercion/value type, receiver/value arity,
materialized body, and emitted symbol for all three lawful flows.

### 13.4 Future body-dedup LTP/WBA audit (guard-only)

Body deduplication is a candidate local move, not an automatic optimization.
The promotion card is:

```text
Window or trigger:
  The T1 explosion ledger finds one equal semantic instance tuple mapped to
  multiple materialized names, after explicit wrapper/forwarder and dispatch
  cases have been classified.
Transport corridor:
  T1a CallResolution -> T1b handoff -> DemandGraph/BodyCache ->
  MaterializationRegistry -> body/emission terminal.
Legal move:
  Coalesce only equal immutable MethodInstanceKey values; preserve an explicit
  wrapper_forwarder or dispatch branch and derive, never parse, the emit name.
Boundary safety:
  DefIdentity, owner/state scope, receiver type, ordered argument types, full
  block shape, ordered named arguments, ABI facts, and declaration fixed point
  must all match. Unknown or missing facts fail closed.
Lexicographic potential:
  (normalized semantic mismatches, unjoined/dropped identity rows,
   duplicate body instances, peak RSS, compile wall time).
  The first two components must remain zero/non-increasing; only then may a
  duplicate-body reduction be considered. No speed claim is implied.
Recompute safety:
  Replay the raw resolution->body->emit rows, re-run plain/no-prelude positive
  and negative reducers, and re-evaluate recursive, default/named, and virtual
  dispatch edges after coalescing.
Dual frame:
  Semantic demand identity and emitted LLVM symbol/ABI identity are compared
  as normalized facts; equal strings alone are not a bridge.
Local certificate:
  Before/after ledger cardinalities plus an exact key-equality witness, an
  explicit wrapper/forwarder classification, zero dropped rows, and bounded
  log/resource evidence.
Fail policy:
  Reject promotion and keep the legacy path on any collision, owner loss,
  order-dependent forwarding difference, unresolved ABI, missing join row,
  log-cap breach, or resource regression. Do not repair the mismatch in LLVM.
```

This card remains `guard-only` until T1a and T1b records exist and the
recomputed potential descends. It is an LTP/WBA audit boundary, not a license
to add another cache, retry loop, or string-based deduplication pass.

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
