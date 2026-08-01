# Compiler Architecture SDD

> Status: ACTIVE spec; R0 reconciliation in progress; T1 local typed decision
> guarded but cross-phase consumer absent (amended 2026-08-01).
> Scope: target ownership architecture for the Adamas compiler
> (HIR -> MIR -> LLVM) and the migration contract toward it.
> The 2026-06-25..07-03 execution ledger (145 slices, ~11,600 lines) that
> previously occupied this file is preserved in git:
> `git show 95539f64:docs/compiler_architecture_sdd.md`.
> Rationale and process rules: `docs/sdd_process_review_2026_07_03.md`.

Document contract (hard rules):

- This document contains **no dated work-log entries**. The work log lives in
  `TODO.md` (active board) and git history.
- Section 0 is **replaced in place** on frontier movement, never appended to.
- An owner record is not "consumed" until section 6 describes it and its row
  in the section 0 state table is updated.
- Behavior changes are admitted by falsifiers (`docs/specs/05-falsifier-matrix.md`)
  and the regression gates, never by this document alone.
- Owner migrations are pull-based: extract an owner only when a concrete
  behavior fix needs that boundary. Neutral extractions are batched and do not
  each pay a full bootstrap verification cycle.

## 0. Current State (replace in place)

### 0.1 Frontier

- **B4-H (historical generated artifact): HISTORICAL.** A previously generated
  `s2` passed the downstream full-prelude classifier and printed `42` under
  `scripts/run_safe.sh`. This remains useful compatibility evidence, but it
  does not prove that current source can produce a fresh `s2b`.
- **B4-F (fresh current source): MEASURED RED.** A clean-output `s1 -> s2b`
  build from the reconciled source must finish in at most **180 seconds** on
  the recorded host/cache policy (faster is the stretch target). The output
  directory is new and the manifest records fresh-output/source/output hashes
  plus `cache_policy`, `cache_dir_rel`, and `cache_directory_identity`; no generated stage is reused. Any external host cache is
  recorded and held constant, with cold and warm results reported separately.
  The exact plain/full-prelude and exact no-prelude semantic smokes
  are co-equal release gates; worker-only or emit-only success cannot mask
  either failure. This is a new acceptance target, not a recovered historical
  full-green certificate. The sealed current snapshot reached stage2 timeout
  exit 143 at 182.54 seconds and produced no `cv2_s2`.
- **T8 (offline fresh-s2 decision): EXECUTABLE / NO CURRENT GREEN RECEIPT.**
  `scripts/validate_bootstrap_manifest.sh` rehashes a canonical B6/B7 receipt
  against current source, harness, and an explicitly trusted host, then
  enforces normal no-worker production, numeric resource coverage, both exact
  semantic smokes, and stage2 wall <=180 seconds. The validator exists; the
  measured-red current run has not passed it.
- **T1 (typed call identity): LOCAL GUARD COMPLETE / CONTINUITY RED.** Exact
  r1-r5 explicit-receiver shapes construct and immediately validate one
  private `LocalCallResolution {MethodSymbol, DefInstanceKey}` before legacy
  body inference. Selected Def payload plus receiver visibility/owner
  provenance fail closed for independent roots while canonical re-export
  remains valid. No `ResolutionId`, producer stream, aggregate-to-original arena
  handoff, downstream join, or lowering authority is admitted.
- **B5 (s2 self-build -> s3): BLOCKED BY B4-F / HISTORICAL LOCATOR ONLY.** The
  historical first bad stop was
  `ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED` inside the
  `AstToHir#lower_method` body loop (`body_size=44`) for
  `Adamas::Compiler::CLI#run$IO_IO`, at roughly 4.8 GB peak RSS. The R0
  locator cannot be refreshed until B4-F produces a stage2 artifact.

Current evidence is deliberately revision-scoped:

| Source/artifact | Current classification | Consequence |
|---|---|---|
| `548d29b1` clean baseline | Stage1 and host/no-prelude probes pass; fresh `s1 -> s2` timed out at 900 seconds | Control only; no fresh-s2 certificate. |
| `04b98b04` lineage | Direct `Object`/`Reference` method census 2085 -> 50 | Diagnostic demand-amplifier evidence; not a release certificate. |
| Historical fresh both-smoke green | 231.37 seconds strongest surviving certificate; 251.91/253.42 seconds corroborating | Above the new <=180-second target; not current-source admission. |
| Historical ~178-190-second runs | No-prelude or partial lanes only | Not full-green B4-F certificates. |
| 2026-07-14 fresh run | ~711 seconds; no-prelude green, plain/full-prelude red | Semantic split; release red. |
| G7 snapshot | 1962.79 seconds; both semantic smokes red | Refuted as release candidate. |
| G8 snapshot | 1791.78 seconds; both semantic smokes red | Refuted as release candidate. |
| G9 snapshot | 1768.73 seconds; both semantic smokes red | Diagnostic candidate only; not a release candidate. |
| `91ebe332` T0 | Same 900-second fresh-stage timeout as clean control; HIR provenance ON/OFF byte-identical | Guard-only provenance; no behavior promotion. |
| R0 sealed current-source snapshot | Base `c216b9ef...`, tree `1efb635...`, exactly seven tracked compiler/spec paths, patch `d7ad2cac...`; snapshot diff-check passes | Reproducible current-source certificate; manifest `/private/tmp/adamas_r0_current_c216_manifest.md`. |
| Host preflight and stage1 | Host spawn green; host build 14.13s; plain smoke `42` in 20.29s; exact no-prelude markers in 0.65s; `cv2_s1` SHA-256 `dfe3c0e8...` | Host-infrastructure blocker refuted; stage1 corridor green. |
| Fresh current-source B4-F | Stage2 timeout exit 143, stage wall 182.54s, externally sampled peak RSS 1361.03 MiB; outer chain exit 1 at 219.32s; no `cv2_s2` | Compiler-side performance red. Stage2 semantic smokes unavailable, not red/green. |
| Sealed-current stats-on localization | Only `ADAMAS_PHASE_STATS=1` on sealed `cv2_s1`, safe-run timeout 180s/memory 12288 MB: wall 182.60s, exit 143, no `cv2_s2`; peak RSS unavailable. Completed `process_pending` 218 -> 591 (+373) in 555.2ms and `emit_tracked_sigs` 591 -> 604 (+13) in 235.0ms; open `lower_missing.initial` grew 604 -> 1535 -> 7422 -> 19238 -> 28234 before timeout. Log SHA-256 `1cc025cc...`. | Revalidates/evolves the historical 2026-04-29 locator. No completion/timing/top-prefix for the open phase; definitions differ from the old observation, and stats-on/uninstrumented timing is diagnostic-only. |
| T0 same-source A/B | Not completed on the sealed snapshot | R0 promotion remains blocked independently of B4-F. |

The old `B4 GREEN` wording is therefore split into B4-H and B4-F rather than
silently reused. A diagnostic timeout is not an acceptance budget.

R0 also selected historical G9 only as a typed-materialization diagnostic.
For source `main_arenas << map_arena`, the minimal G9 HIR chooses
`push$AstArena` for the static value but the union target for an explicit
upcast. The upstream Crystal audit establishes both as lawful: concrete flow
through `Array(ArenaLike) << AstArena` specializes `<<`/`push` with `AstArena`,
while explicit `.as(ArenaLike)` and true union flow select union or lawful
reduced-union instances. At the original Crystal oracle boundary, instance
authority is `DefInstanceKey(def.object_id, actual typed args, block/named)`;
that `object_id` detail is not Adamas authority. Adamas requires `DefIdentity`
plus actual typed args, block, and named arguments; the mangled name is later
serialization. The minimal HIR/MIR/LLVM probe preserves two
arguments. Full G9
`s2` LLVM instead contains a union `<<` path calling zero-argument
`push$AstArena()` plus a zero-argument unreachable stub. Late HIR
materialization or a missing selected target is therefore a high-confidence
hypothesis for the malformed body, not yet a proven creation mechanism; T9 is
the current-red selected-Def/instance/coercion/arity/body/symbol continuity
falsifier.

### 0.2 Authority-edge state table

| Edge | Owner record | Guard (script + env) | Status |
|---|---|---|---|
| function-list-inline | LLVMEmissionSession / LLVMEmissionFunctionPlan | `REQUIRE_SESSION=1 scripts/llvm_emission_session_source_shape_guard.sh` | consumed |
| worker-policy-inline | LLVMEmissionSession worker plan | `+ REQUIRE_WORKER_PLAN=1` | consumed |
| side-effect merge | LLVMEmissionSession side-effect contract | `+ REQUIRE_SIDE_EFFECT_CONTRACT=1` | consumed |
| lower_method body scope | MethodBodyLoweringScopeSnapshot | `REQUIRE_METHOD_BODY_SCOPE=1 scripts/method_body_lowering_scope_source_shape_guard.sh` | consumed |
| lower_def body scope | MethodBodyLoweringScopeSnapshot | `+ REQUIRE_LOWER_DEF_BODY_SCOPE=1` | consumed |
| lower_module_method body scope | MethodBodyLoweringScopeSnapshot | `+ REQUIRE_LOWER_MODULE_METHOD_BODY_SCOPE=1` | consumed |
| inline_callee_local_names scan scope | InlineCalleeLocalScanScopeSnapshot | `REQUIRE_INLINE_CALLEE_LOCAL_SCAN_SCOPE=1 scripts/inline_callee_local_scan_scope_source_shape_guard.sh` | consumed |
| LLVM output restore (parallel rescue) | LLVMOutputOwnershipContract | `REQUIRE_OUTPUT_OWNERSHIP=1 scripts/llvm_output_ownership_source_shape_guard.sh` | consumed |
| CLI output commit record | GeneratedStageExecutionOutcome | `REQUIRE_OUTPUT_OUTCOME=1 scripts/generated_stage_outcome_source_shape_guard.sh` | consumed |
| classvar scalar offsetof globals | none (producer behavior fix `ab0747d9`) | `REQUIRE_SELECTED=1 scripts/generated_stage_return_contract_mismatch_report.sh` L19 row | consumed, no owner type |
| non-void call result slots | none (backend behavior fix `aae7c0f8`) | `scripts/generated_stage_return_contract_mismatch_report.sh` (`normal_llc_type_mismatch=0`) | consumed; typed owner residual |
| zero struct sentinels | none (raw value storage `be44b058`) | `REQUIRE_SELECTED=1 scripts/generated_stage_zero_struct_sentinel_report.sh` | consumed |
| GC-aware realloc demand | LLVMEmissionSession `GRH` tag (`31cd6009`) | `scripts/generated_stage_gc_realloc_helper_report.sh` + `regression_tests/gc_aware_realloc_gating_repro.sh` | consumed |
| STABLE6 materialization replay shadow | none on main (`MaterializationReplayShadow` prototype only in `/private/tmp`) | in-process prototype discriminator; no admitted owner | REFUTED IN-PROCESS PROTOTYPE / NOT ADMITTED |

### 0.3 STABLE6 — refuted in-process prototype / not admitted

STABLE6 is **REFUTED IN-PROCESS PROTOTYPE / NOT ADMITTED**. The attempted
`MaterializationReplayShadow` used a typed numeric `CallSiteRef`, explicit
statuses (`Unjoined`, `HIRShapeAgree`, `HIRShapeMismatch`, `StaleCallSite`,
`UntrackedRequiredCallSite`, `StaleTransactionRef`, `AmbiguousHIRShape`, and
`NoMaterializationRequired`), a composite typed HIR request-shape index,
diagnostic logs with a ceiling (not a hard cap), owner-local scratch, and a
final read-only scan. Those local
shapes remain useful evidence, but no in-process owner is admitted and the
prototype has been removed from main code and preserved only in
`/private/tmp`.

Scoped local evidence remains: focused **17/0**, baseline HIR
**286/0 with two existing pending examples**, host build, and simple OFF/ON
HIR/runtime parity. The local adversary is **ROBUST** only for those bounded
parity checks. Full-prelude/union telemetry remains intentionally red/noisy
and separate from the similar plain run (about **2673 registered, 2568 agree,
404 mismatch, 1 stale, 199 untracked required, 225 unjoined, 1 ambiguous, and
11377 calls** in the audit reducer); these counters are proxy orientation only
and do not prove duplicate semantic instances or speed. A strict assertion is
not an admission path.

The system discriminator overrides that local result. On the frozen pre-shadow
base `c216b9ef...` plus patch `d7ad2cac...`, with phase stats as the only
instrumentation, the control timed out at 180 seconds (`run_safe` exit 143),
produced no `s2`, and grew **604 -> 1535 -> 7422 -> 19238 -> 28234
(+27630)** without stack overflow; the repeat-control log prefix is
`e568...`. With the STABLE6 source/executable in the same binary, both runtime
OFF and ON also produced no `s2` and hit exit 11 stack overflow in
`declared_type_match_score`/alias/type-name work during `lower_missing` p0
around item **#800** (ON about **141s**, OFF about **139s**), with identical
completed growth **604 -> 1544 -> 7430 -> 19246 -> 28369 (+27765)**. The ON
and OFF log prefixes are `18603d...` and `51146a...`; RSS was unavailable.
The ON final-scan-i4 orientation counters were
`registered=27363`, `agree=42801`, `mismatch=484`, `unjoined=4459`,
`ambiguous=300`, `no_mat=12864`, `calls=60909`, and `not_yet=1`.

This is not causal proof of the underlying compiler root, but admission is
rejected because runtime-OFF still changes the self-host source/workload and
failure class. Default-off is therefore not zero compile-time cost. The
whole-system Adversary verdict is **BROKEN for admission**, despite the local
parity verdict. T1 remains **MISSING** because HIR `TypeRef`/name shape is not
semantic identity, and B4-F (<=180 seconds) remains red/open with no speed
claim.

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

### 0.4 T1 identity-join boundary (current-red)

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

- exact r1-r5 shapes have a local semantic decision, but semantic analysis owns
  an aggregate reparse arena while `AstToHir` consumes original per-file
  arenas;
- no owned callsite mapping or genuine downstream compiler consumer exists for
  a `ResolutionId`; inference-order ordinals and raw `ExprId` surrogates are
  rejected;
- `IdentityDryRunTracker` remains a definition-annotation/body-infer proxy, not
  the semantic callsite producer.

The ownership precursor and bounded local decision are complete:
`SemanticIdentityRegistry` owns canonical session-local names and types;
`DefInstanceKey` owns ordered positional, block, and `{NameId,
SemanticTypeId}` named components; and the private `LocalCallResolution` is
constructed and immediately revalidated for exact r1-r5 shapes before
unchanged legacy body inference. Parser-owned selected definitions and nominal
receiver symbols from an independent Analyzer/root table fail closed, while
canonical symbol re-export into a file-local table remains valid. Same-arena
class reopenings preserve one receiver identity across distinct selected Defs;
recollecting a shared symbol-table context from a distinct arena rejects stale
receiver and method symbols while admitting the replacement symbol.
Cross-arena admission for declarations retained from another per-file Analyzer
and same-arena stale-`MethodSymbol` admission/duplicate-signature redefinition
ordering remain unresolved. This does not authorize a producer stream, create
a cross-arena consumer, or make T1 green.

The T1 guard is **availability/current-red only**: it can show whether the
current source/configuration emitted a row or exposed the current failing
boundary. It does not prove global absence of another producer, semantic
identity continuity, or equivalence of selected definition, coercion, body,
and emitted symbol. No rewrite, broad in-process owner, or performance claim
is admitted.

Named residuals (explicitly NOT migrated): method-pointer thunks, proc
literals, block-to-proc body lowering scopes (MethodBodyLoweringScopeSnapshot
family); `output-file-owned-by-cli` and `tail-stub-from-mutable-sets`
(LLVMEmissionSession family); `FunctionReturnAvailability` /
`LoweredFunctionReturnContract` as a typed record (paper-only; the L20 edge was
consumed as a behavior fix); `MaterializationAttemptResult` terminal-status
owner type (paper-only); vertical `MethodBodyLoweringContext` /
`SemanticStateScope` slice.
The static-union insertion target/materialization edge is also residual: T9
must join selected HIR target to materialized body and emitted call before an
owner record can be marked consumed.

## 1. Admitted surface

This SDD admits only future architecture work that:

- preserves current language semantics and stdlib compatibility,
- starts with read-only census/probe steps,
- introduces typed facts or facades before behavior changes,
- keeps old behavior behind parity checks until falsifiers pass,
- makes backend lowering consume facts instead of re-inferring source-level
  semantics from names, types, or local helper guesses,
- reduces hidden state coupling between registration, resolution,
  materialization, ABI layout, and backend emission,
- makes AST node identity and arena ownership explicit before HIR lowering
  reads an `ExprId` through a mutable current arena,
- makes semantic state scopes explicit before any decision reads ambient
  mutable maps such as `@type_param_map`,
- enforces that a materialized body and the emitted call agree on the same
  symbol or on an explicit wrapper/forwarder contract,
- reduces code volume by deleting proven-dead paths, not by hiding them behind
  new wrapper layers.

The first implementation tracks should be behavior-neutral extraction and
shadow comparison, not a rewrite.

## 2. Rejected surface

The following are explicitly rejected by this SDD:

- a rewrite-from-scratch compiler effort,
- file splitting that preserves the same stateful class and the same hidden
  cross-phase decisions,
- adding another broad oracle beside the existing ones,
- backend fixes that re-run name resolution, overload selection, layout
  inference, or block materialization heuristics,
- stdlib changes to paper over compiler miscompiles,
- default-on behavior flips without focused falsifiers plus broader bootstrap
  guards,
- fixing only the latest symptom while leaving the ownership boundary
  unnamed,
- local consumer-predicate patches around callsite specialization,
  materialization, or type-param binding that do not name the authoritative
  state scope they are allowed to read,
- forcing materialization to the requested call name without proving that the
  selected definition, argument ABI, and emitted call symbol agree,
- globally ignoring ambient type-param maps in all call-resolution sites when
  some sites are legitimate current-instantiation contexts,
- deleting code because it looks dead without a read/write census and a
  negative-use falsifier,
- consumer patches that replace one raw `@arena[expr_id]` read with another
  heuristic arena scan without proving the `ExprId` owner boundary,
- replacing dead code with equally broad compatibility wrappers that preserve
  the same hidden state contract,
- preserving stale debug gates, one-off probes, or old workaround paths after
  their owning bug frontier has been closed and a regression script exists.

Large files are a symptom. The target is not "shorter files"; the target is
"one owner per semantic decision".

## 3. Guard-only future

The following shapes are allowed as guard-only future work:

- typed facade objects over existing maps (`@function_defs`, `@class_info`,
  `@generic_templates`, pending queues, ABI facts),
- read-only ledgers that record who wrote and who read a semantic decision,
- parity checks that compare old and new routing without changing emitted code,
- durable MIR facts that are populated after optimization and verified before
  LLVM lowering,
- env-gated behavior slices that consume already-verified facts mechanically.

Guard-only means the design may be described and probes may run, but behavior
remains unchanged until the declared falsifiers pass.

## 4. Non-goals

- Do not replace the parser.
- Do not replace the compiler with upstream Crystal internals.
- Do not replace textual LLVM IR with the LLVM C API in this SDD.
- Do not build a full in-memory LLVM module AST unless a later SDD proves that
  MIR plus typed streaming fragments cannot carry the needed checks.
- Do not solve every ABI problem before improving call/materialization
  boundaries. The migration should be sliced.
- Do not make `s2b`/`s3b` stability depend on a broad refactor. Use the
  architecture SDD as the bootstrap control surface: behavior-neutral ledgers
  first, then bounded behavior slices only after the owning boundary is named.

## 5. Design laws

1. One decision, one owner.
   If two phases answer the same semantic question, one is the owner and the
   other must read a fact or facade.

2. Facts over names.
   Mangled names, string prefixes, and function-name substrings are transport
   details, not authorities for semantics.

2a. AST identity is owner-scoped.
   An `ExprId` index is not a globally unique node identity. A lowering path
   that reads an AST node must know the owning arena, carry an explicit
   owner-scoped reference, or emit a ledger row proving why the current arena is
   authoritative. `expr_id.index < arena.size` is a containment heuristic, not
   an ownership proof.

3. No silent fallback across semantic classes.
   A block call must not fall back to a non-block overload of different arity;
   an absolute `::Hash` reopen must not become `Adamas::MIR::Hash`; an unknown
   ABI path must not pretend to be a known inline path.

4. Fail closed.
   If provenance, materialization, layout, escape, or overload ownership is
   unknown, keep legacy lowering or reject the optimization.

5. Behavior-neutral extraction first.
   Introduce read-only facts, ledgers, and shadow comparisons before a behavior
   flip.

6. Every boundary has falsifiers.
   A boundary is not "clean" until at least one positive and one negative
   reducer exercise its ownership.

7. No physical file split before semantic boundary split.
   Moving methods to a new file is useful only after the moved surface has a
   smaller state contract.

8. Backend is mechanical.
   LLVM lowering should consume MIR instructions plus ABI/materialization
   facts. It should not decide overloads, owners, namespaces, block shapes, or
   storage provenance from scratch.

9. Dead code is an evidence claim.
   A path is dead only after static search, runtime census, and bootstrap guards
   agree. Until then it is `suspected_dead`, `legacy_shim`,
   `compatibility_carrier`, or `debug_only`, not dead.

10. Delete after ownership.
    A cleanup slice may delete a path only when its semantic owner exists or
    when the path is proven unreachable under the admitted language surface.

11. Ambient state is not authority.
    Mutable process state such as `@type_param_map`, `@current_class`,
    namespace overrides, pending arg maps, and deferred contexts may be cached
    inputs, but a semantic decision must state which scope owns that state.
    Naming and materialization decisions must not consult ambient maps without
    an explicit `StateScope` / provenance record.

12. Symbol identity is a transaction.
    A call request, selected definition, materialization request, created
    function body, and emitted call must be tied by one identity record. If the
    requested symbol, target symbol, materialized symbol, and emitted call
    symbol differ, the difference must be an admitted wrapper/forwarder with a
    falsifier. Otherwise the slice fails closed.

13. Consumer patches are not architecture fixes.
    Patching the latest predicate, fallback, or backend guard is admissible only
    after a read-only ledger proves that the predicate is the owning boundary.
    If the predicate merely consumes a hidden oracle, the fix belongs at the
    oracle owner or at the boundary that passes the fact.

14. Promotion before proliferation.
    A new shadow ledger is architectural progress only when it has a promotion
    path: one legacy consumer starts reading the owned fact in parity/shadow
    mode, or one old path receives a `CodePathStatus` classification with a
    protecting falsifier. A ledger that only adds rows after the previous ledger
    refuted the local hypothesis is diagnostic debt, not a migration step.

15. Transaction consumers cannot bypass the transaction.
    A `CallMaterializationTransaction` slice is not complete merely because a
    transaction record exists. The selected consumer must read the symbol, state,
    ABI, and wrapper/forwarder facts from that transaction record; direct reads
    from older local records such as `MaterializationSymbolBinding` may remain
    only inside the transaction constructor/helper as parity inputs. If a
    consumer still reads the older record directly, the transaction is a shadow
    observation, not the owner boundary for that decision.

## 6. Target architecture

### 6.1 NameResolution

Owns lexical and absolute name semantics.

Inputs:

- original spelling,
- absolute marker (`::`),
- lexical owner/module,
- local aliases,
- builtin base names,
- generic base and argument names.

Output:

```text
NameRef {
  original_spelling
  absolute
  lexical_owner
  resolved_owner
  canonical_base
  builtin_base
  alias_chain
}
```

Responsibilities:

- preserve absolute-top-level definitions through registration,
- distinguish local nested types from builtin/top-level types,
- expose canonical type names to `TypeIdentity`,
- keep source spelling available for diagnostics.

Non-responsibilities:

- overload choice,
- generic concrete type allocation,
- function materialization,
- ABI layout.

Key falsifiers:

- `class ::Hash(K, V)` reopened inside `module Adamas::MIR` must remain
  top-level `::Hash`, not mint `Adamas::MIR::Hash`;
- alias-derived `Hash(ValueId, BlockId)` must resolve to the same base identity
  as direct `Hash(UInt32, UInt64)`;
- nested local types must still resolve locally when they are genuinely local.

### 6.2 TypeIdentity and TypeRegistry

Owns canonical type identity, generic templates, concrete instantiations, and
class metadata.

Inputs:

- `NameRef`,
- generic arguments,
- declaration identity,
- class/struct/module kind,
- finalized layout metadata from the owning layout step.

Output:

```text
TypeIdentity {
  canonical_name
  declaration_id
  template_id
  concrete_args
  kind
  owner
}
```

Responsibilities:

- prevent phantom generic templates without declarations,
- distinguish declaration identity from display/mangled name,
- make concrete-class registration idempotent,
- provide a stable bridge into MIR `Type`.

Non-responsibilities:

- choosing a method overload,
- deciding storage context,
- emitting allocation code.

Key falsifiers:

- no phantom `Adamas::MIR::Hash`, `Adamas::MIR::Set`, or
  `Adamas::MIR::Array` classes are minted from absolute builtin reopens;
- `hash_dual_typeref_phantom_repro` stays green;
- type aliases do not create a second incompatible base identity.

### 6.2a AstNodeIdentity and ArenaOwnership

Owns the link between parser arenas, expression ids, source spans, and HIR
lowering consumers.

Input:

```text
AstNodeRef {
  arena_owner
  expr_id
  source_path
  span
  origin              # source | macro_expansion | inline_block | reparsed
}
```

Output:

```text
AstNodeIdentity {
  arena_owner
  expr_id
  node_kind
  source_path
  span
  dominance_region    # current lowering region where the reference is valid
}
```

Responsibilities:

- distinguish node id equality from arena ownership,
- make block, macro, inline, and reparsed AST arenas explicit in lowering,
- provide a behavior-neutral ledger for raw `@arena[expr_id]` reads,
- reject or route through an explicit owner when the current arena differs from
  the callsite/block owner,
- prevent fallback scans over `@main_arenas` from silently choosing an arena
  only because the index fits its size.

Non-responsibilities:

- resolving method overloads,
- deciding type identity,
- materializing function bodies,
- choosing ABI layout.

Key falsifiers:

- generated s2->s3 `NodeSlot#node <- AstArena#[] <- AstToHir#lower_call`
  must be classified by a ledger row before any `lower_call` consumer patch;
- a callsite `ExprId` from a block or inline arena must not be read through the
  caller arena merely because the numeric index fits;
- a genuine current-arena local expression should remain readable without
  routing every access through a broad global arena scan.

### 6.2b NodeSlotIntegrity and AstArenaStorage

Owns the producer/read integrity of arena slots after the owning arena has
already been identified.

Input:

```text
NodeSlotRead {
  arena_owner
  expr_id
  read_site
  expected_span
  expected_kind_hint
}
```

Output:

```text
NodeSlotFacts {
  arena_owner
  expr_id
  index_in_range
  slot_initialized
  node_pointer_present
  node_kind
  node_span
  producer_site
}
```

Responsibilities:

- distinguish owner selection bugs from slot storage/producer corruption;
- record whether an `ExprId` points at an initialized slot in its owning arena;
- identify the producer that created or failed to create the slot;
- make `NodeSlot#node` reads reportable without requiring the crashing
  consumer to dereference an invalid node;
- provide a small generated-stage ledger before any consumer reads are routed
  through `AstNodeRef`.

Non-responsibilities:

- selecting the owning arena;
- repairing `lower_call` by scanning other arenas;
- changing parser allocation or macro expansion semantics;
- deciding call resolution, materialization, or ABI layout.

Key falsifiers:

- if lower-call owner parity reports `agree_all_have` for the crash edge, the
  next ledger must show whether the owning arena slot itself is initialized
  and which producer wrote it;
- a valid local node read must still show `index_in_range=true`,
  `slot_initialized=true`, and matching span/kind without requiring broad arena
  fallback;
- if the crash stack moves to an uninstrumented raw read, the ledger must name
  that read site before a consumer patch is allowed.

### 6.3 CallResolution

Owns overload selection and the semantic target of a call.

Input:

```text
CallRequest {
  receiver_type
  method_name
  positional_args
  named_args
  block_presence
  block_signature
  callsite_scope
}
```

Output:

```text
CallResolution {
  selected_def
  selected_owner
  arg_bindings
  named_bindings
  block_binding
  state_scope
  materialization_key
  rejection_reasons
}
```

Responsibilities:

- select between overloads using typed arguments, named arguments, block
  presence, and arity,
- refuse lossy fallback when a more exact overload exists,
- preserve block-bearing calls as block-bearing calls,
- emit a ledger of rejected candidates for debug and reducers.

Non-responsibilities:

- lowering the selected function body,
- scheduling lazy RTA work,
- choosing LLVM symbol names.

Key falsifiers:

- `String#split('/')` must select the separator overload, not the whitespace
  `limit : Int32?` overload through `Char -> Int32`;
- `String#split('/', 2)` and `String#split('/', remove_empty: true)` must not
  collide through a shared block target;
- `Array(UInt32)#join(io, sep) { ... }` must not fall back to a one-argument
  non-block `join`.

The semantic producer for this record is post-resolution, after semantic
literal/autocast normalization if applicable, and before Adamas HIR/value/ABI
coercion, analogous to Crystal `Call#instantiate`. A late
`lower_function_if_needed` or MAT string ledger is therefore a rejected
producer; it may only consume or serialize an already typed resolution.

### 6.4 SemanticStateScope

Owns the authority and lifetime of mutable semantic state used while resolving,
materializing, and lowering compiler functions.

Input:

```text
StateScopeRequest {
  selected_def
  requested_symbol
  target_symbol
  declaring_owner
  declaring_type_params
  callsite_arg_types
  current_lowering_context
}
```

Output:

```text
StateScope {
  authority              # callsite | target_materialization | body_substitution | macro | inline_caller
  type_param_map
  map_source
  allowed_consumers
  forbidden_consumers
  lifetime_region
}
```

Responsibilities:

- distinguish declaring-scope type variables from current-instantiation
  substitutions and leaked caller state,
- state which map a naming/materialization decision is allowed to consult,
- isolate `@type_param_map`-style state before lowering a body, and restore it
  after the declared lifetime region,
- emit a ledger when a naming decision differs under ambient map,
  target-materialization map, or empty map,
- fail closed when the requested decision cannot name the authoritative map.

Non-responsibilities:

- selecting overload candidates,
- choosing the materialized symbol by itself,
- substituting type variables inside an already-admitted body-lowering scope.

Key falsifiers:

- `Hash(UInt64, {class_name: String?, method_name: String?, is_class: Bool})#[]=`
  must not materialize a body under a different symbol from the emitted call
  because unrelated `K`/`V` bindings leaked through `@type_param_map`;
- a current-instantiation site such as `Array(Bool)` remangling must still be
  allowed to use its legitimate `T=Bool` scope;
- `T*` and other declaring-scope short params must still require callsite
  specialization when no admitted current-instantiation scope owns them.

### 6.5 Materialization

Owns turning a `CallResolution.materialization_key` into a concrete lowered
function body and symbol.

Input:

```text
MaterializationRequest {
  selected_def
  requested_symbol
  target_symbol
  state_scope
  receiver_shape
  arg_shapes
  block_shape
  source_def
}
```

Output:

```text
MaterializedFunction {
  symbol
  call_symbol
  identity_status        # exact | wrapper_forwarder | rejected_mismatch
  source_def
  arg_abi
  block_abi
  lowering_state
}
```

Responsibilities:

- keep pending queues keyed by materialization identity, not by lossy arity
  names,
- own lazy RTA scheduling and replay,
- materialize shape-specific block/yield functions as distinct functions when
  the ABI shape differs,
- make call emission use the same target symbol that was materialized, or emit
  an explicit wrapper/forwarder whose contract is recorded,
- reject silent requested-symbol vs target-symbol vs materialized-symbol
  mismatches.

Non-responsibilities:

- selecting the overload,
- deciding type identity,
- backend coercion.

Key falsifiers:

- distinct `String#split$Char_Int32_Bool_block` and
  `String#split$Char_Nil_Bool_block` stay distinct when the block ABI differs;
- no `load i32, ptr %limit` bridge is emitted for a nil `limit`;
- emitted calls target the shape-keyed symbol, not a late canonical
  `$arityN_block` fallback;
- the `@block_owner Hash#[]=` current frontier must either materialize the body
  under the emitted call symbol or emit an explicit wrapper/forwarder; a body
  under only the target symbol is a failing state;
- `main_arenas << map_arena` and its explicit-upcast control may select
  distinct lawful concrete and union instances. Concrete, explicit-cast, and
  true-union flows must each preserve selected `Def`/`DefInstanceKey`,
  coercion/value type, receiver/value arity, materialized body, and emitted
  symbol through HIR/MIR/LLVM, and emit neither an orphan zero-argument
  `push$AstArena()` call nor a malformed zero-argument unreachable stub.

### 6.6 AbiFacts and LayoutContract

Owns representation, storage context, copy/load/store semantics, bulk-copy
semantics, and carrier layout.

Inputs:

- MIR `Type`,
- storage context,
- provenance facts,
- escape facts,
- bulk operation facts,
- finalized HIR/MIR layout data.

Output:

```text
AbiContract {
  type
  storage_context
  slot_repr
  slot_size
  value_size
  access_plan
  copy_plan
  load_plan
  store_plan
  carrier_layout
  provenance
}
```

Responsibilities:

- define field, Array, Slice, StaticArray, Pointer, carrier, arg, return, and
  union storage contexts separately,
- make inline-vs-pointer decisions durable facts,
- provide logical counts and byte strides for bulk operations,
- expose fail-closed rejection reasons.

Non-responsibilities:

- overload resolution,
- namespace resolution,
- function scheduling.

Key falsifiers:

- A-prime inline Array storage reducers keep value/gep/bulk provenance
  C-specific, not global;
- C-narrow store/load reducers show allocation removal only for eligible
  Array element paths;
- `ADAMAS_LAYOUT_ASSERT` and layout probe falsifiers catch slot/access
  disagreements.

### 6.7 BackendEmitter

Owns mechanical LLVM emission from MIR plus facts.

Inputs:

- MIR function body,
- `TypeIdentity` ids already resolved,
- `CallResolution`/`Materialization` target symbols already selected,
- `AbiContract` facts already populated,
- backend-local typed LLVM fragments.

Responsibilities:

- emit LLVM text through typed, validated fragments where possible,
- consume ABI/layout/provenance facts,
- report missing facts as fail-closed diagnostics under gates,
- keep backend debug helpers outside language semantic registration paths.

Non-responsibilities:

- resolving names,
- choosing overloads,
- deciding block shapes,
- deciding whether `Hash` means `::Hash` or a local nested class,
- re-deriving Array buffer provenance from function names.

Key falsifiers:

- backend must not create or depend on phantom language classes for debug
  helpers;
- backend must not silently rewrite call targets after materialization;
- backend must not use string-prefix layout decisions once a typed fact exists.

### 6.8 Code Health and Dead-Code Control

Owns reducing code volume after semantic boundaries are named.

Inputs:

- static references (`rg`, compiler grep, and call graph where available),
- runtime branch counters under focused reducers and bootstrap smoke,
- feature gates and debug gates,
- git history for why a path was introduced,
- replacement boundary or facade ownership.

Output:

```text
CodePathStatus {
  path
  owner_boundary
  status                 # live | suspected_dead | legacy_shim | debug_only | delete_ready
  last_observed_use
  protecting_falsifier
  replacement_boundary
  deletion_plan
}
```

Responsibilities:

- classify large helper clusters before deletion,
- distinguish dead code from bootstrap fallback and compatibility glue,
- quarantine suspected-dead paths behind assertions or counters before removal,
- delete obsolete probes/debug gates after their evidence is captured in docs,
  regression scripts, or landmarks,
- prevent architecture facades from becoming another layer over unused legacy
  paths.

Non-responsibilities:

- deciding language semantics,
- changing overload, name, materialization, or ABI behavior as part of cleanup,
- removing stdlib compatibility paths without Crystal-compat falsifiers.

Classification:

- `live`: observed by source search or runtime census in an admitted path.
- `suspected_dead`: no current evidence of use, but no negative-use proof yet.
- `legacy_shim`: old behavior kept while a new boundary is shadow-tested.
- `debug_only`: probe or trace path gated for investigation.
- `delete_ready`: no observed use, replacement exists or no replacement is
  needed, and deletion falsifiers passed.

Key falsifiers:

- deleting the path does not change HIR/MIR/LLVM for the declared reducer set;
- `s2b`/`s3b` smoke still reaches the same or later frontier;
- grep/census shows no remaining writer/reader of the removed decision;
- debug probes removed from production code have their evidence preserved in an
  SDD, regression script, or landmark.

### 6.9 Built owner records (verified in code, 2026-07-03)

The records below exist in the codebase and are consumed by production paths.
Each entry names its defining location, the authority edge(s) it consumed, and
its guard. A record listed here and absent from the section 0 state table is a
documentation bug.

#### 6.9.1 LLVMEmissionSession (mir/llvm_backend.cr:648)

Owns the per-`generate` LLVM emission plan: which functions are emitted, under
what worker policy, and through which side-effect channel tags.

Fields: `function_plan : LLVMEmissionFunctionPlan` (original_count,
reachable_count?, skipped_ids, deduped_mangled_names, functions_to_emit;
derived final_count/pruned_count), `requested_worker_count`,
`effective_worker_count`, `worker_sequential_reason_code`, plus owned
side-effect tag constants (`STR/ZSG/EXT/CCF/EMF/ERT/MSG/GRH/DGF/SCN`).

Responsibilities: built once by `build_llvm_emission_session` before emission;
worker emission serializes side effects through
`write_worker_side_effects_with_contract` and the parent merges via
`merge_worker_side_effects_with_contract`; records sequential-fallback reason
as evidence, never silently.

Non-responsibilities: function body semantics, output/file ownership
(LLVMOutputOwnershipContract), tail-stub body-presence contract (residual),
resource acceptance gates.

Guard: `REQUIRE_SESSION=1 REQUIRE_WORKER_PLAN=1 REQUIRE_SIDE_EFFECT_CONTRACT=1
scripts/llvm_emission_session_source_shape_guard.sh`.
Edges consumed: `function-list-inline`, `worker-policy-inline`,
side-effect merge, GC-realloc helper demand (`GRH`).

#### 6.9.2 MethodBodyLoweringScopeSnapshot (hir/ast_to_hir.cr:2973)

Owns the method-body lowering scope for the three method-like seams:
`lower_method`, `lower_def`, `lower_module_method`. Replaces the raw
inline-yield/infer-body/current-return save-clear-restore blocks.

Fields (snapshot of ambient AstToHir state): `inline_yield_block_stack`,
`inline_yield_block_arena_stack`, `inline_yield_block_param_types_stack`,
`inline_yield_block_return_stack`, `inline_yield_name_stack`,
`inline_arenas?`, `infer_body_context?`, `current_def_return_type`.

Responsibilities: `enter_method_body_lowering_scope(return_type)` snapshots
all eight facts, resets the five inline-yield stacks, nils `inline_arenas`,
installs the callee return type; `restore_method_body_lowering_scope` restores
all eight. Exactly one enter/restore pair per owned seam.

Non-responsibilities: method lookup, materialization naming, parameter/self
binding, callee-local scanning (6.9.3), method-pointer thunks, proc literals,
block-to-proc body scopes (explicitly NOT migrated).

Guard: `scripts/method_body_lowering_scope_source_shape_guard.sh` with
`REQUIRE_METHOD_BODY_SCOPE=1 REQUIRE_LOWER_DEF_BODY_SCOPE=1
REQUIRE_LOWER_MODULE_METHOD_BODY_SCOPE=1`.

#### 6.9.3 InlineCalleeLocalScanScopeSnapshot (hir/ast_to_hir.cr:3017)

Owns the scanner/provenance scope of `AstToHir#inline_callee_local_names`:
the temporary switch from caller arena to callee arena plus inline-yield stack
clearing while collecting assigned and block-local names.

Fields: `arena`, `inline_yield_block_stack`, `inline_yield_block_arena_stack`,
`inline_yield_block_param_types_stack`.

Responsibilities: `enter_inline_callee_local_scan_scope(callee_arena)`
snapshots four facts, installs the callee arena, clears the three stacks;
`restore_inline_callee_local_scan_scope` restores stacks then arena.

Non-responsibilities: body lowering scope (6.9.2), name-collection semantics,
arena lifetime.

Guard: `REQUIRE_INLINE_CALLEE_LOCAL_SCAN_SCOPE=1
scripts/inline_callee_local_scan_scope_source_shape_guard.sh`.

#### 6.9.4 LLVMOutputOwnershipContract (mir/llvm_backend.cr:724)

Owns which IO the LLVM backend writes to: primary output vs parallel
parent/worker temporary outputs, and rescue-path restore. Consumed the
frontier where the parallel rescue restored a stale `saved_output` with
`pos=0`, nulling the final output.

Fields: `primary_output : IO`, `current_output : IO`. Operations:
`capture_primary_output`, `enter_temporary_output`, `restore_output`,
`restore_primary_output`.

Responsibilities: sole authority for the parallel save/restore-output pattern.

Non-responsibilities: finalization/`to_s` semantics, `.ll` file writing (CLI
owns the file; `output-file-owned-by-cli` residual), IO::Memory internals.

Guard: `REQUIRE_OUTPUT_OWNERSHIP=1
scripts/llvm_output_ownership_source_shape_guard.sh`.

#### 6.9.5 BlockCallReturnContract (hir/ast_to_hir.cr:919)

HIR-owned contract making the callsite block-return fact part of wrapper
identity for untyped `&` helpers whose method result is the yielded value
carried through an assigned tail local (`result = yield; ...; result`).
Deliberately narrower than all yield-containing helpers (a census refuted
global return-shape specialization: 208 multi-shape keys).

Fields: `block_return_name : String`, `block_return_type : TypeRef`. The
producer returns `BlockCallReturnContract?` — nil for ordinary iterators and
scoped helpers, protecting nil/non-returning callsites from
over-specialization.

Responsibilities: prevents a shared `$String_block` wrapper first lowered at a
void callsite from freezing `yield : Void` for later value-demanding
callsites.

Guard: `REQUIRE_CURRENT_CU_CONTRACT=1
scripts/hir_block_return_shape_census.sh`.

#### 6.9.6 GeneratedStageExecutionOutcome (cli.cr:615)

Owns the CLI output commit record: LLVM IR start/written and binary
compile-result rows for generated-stage transaction ledgers.

Fields: `ll_file`, `output_path`, `emit_mode`; mutable `llvm_ir_bytes`,
`binary_compile_result`. Serialized through the default-off `GSETX` ledger
(`ADAMAS_GSETX_ID` / `ADAMAS_GSETX_LEDGER`); rows must never affect compiler
semantics.

Guard: `REQUIRE_OUTPUT_OUTCOME=1
scripts/generated_stage_outcome_source_shape_guard.sh`.

#### 6.9.7 LLVMFunctionEmissionOutcome (mir/llvm_backend.cr:757)

Env-gated per-function emission transaction row connecting planned function
emission to output/side-effect growth. Produced when
`ADAMAS_GSETX_FUNCTION_EMISSION_OUTCOMES` is on plus GSETX ledger vars;
evidence only, never acceptance.

Fields: function/mangled name, mode, status (incl. `started`), index, totals,
`out_pos_before/after`, emitted/called/undefined before/after and deltas.

Consumers: `scripts/generated_stage_execution_transaction_report.sh`,
`scripts/generated_stage_mode_resource_lane_classifier.sh`,
`scripts/generated_stage_function_emission_attempt_classifier.sh`.

#### 6.9.8 CallMaterializationTransaction (hir/ast_to_hir.cr:2171)

Owner record for the vertical materialization spine in
`lower_function_if_needed_impl`: one transaction carrying request-through-body
identity instead of split locals/ambient maps.

Fields (24) include: `phase`, `requested_name`, `target_name`, `state_key`,
`body_symbol`, `call_symbol_hint`, `override_symbol?`, `lookup_branch`,
`ambient_map`, `target_map`, `call_arg_types`, `selected_def`,
`selected_owner`, `state_scope`, `materialization_action`,
`body_function_present`, `body_has_body`, `body_state`, `abi_shape`,
`wrapper_forwarder_contract`, `rejection_reason`. Derived: `identity_status`
(`exact` iff body_symbol == call_symbol_hint), `symbol_relation`, `debug_id`.

Responsibilities: answers "did requested, selected, target, body, and emitted
call agree under one transaction id"; feeds the `[MAT_TX]`/`[MAT_DONE]`
ledger.

Non-responsibilities: requested-name forcing, backend forwarders, ambient-map
policy, `BlockOwner` carrier changes.

Guards: `REQUIRE_PROMOTED=1
scripts/call_materialization_transaction_admission_report.sh`;
`scripts/materialization_transaction_report.sh`;
`scripts/call_materialization_transaction_consumer_selection_report.sh`;
`scripts/block_owner_materialization_transaction_availability_report.sh`.

#### 6.9.9 MaterializationSymbolBinding (hir/ast_to_hir.cr:2254)

Owns the symbol-binding seam of `lower_function_if_needed`:
requested/target/body/call symbol identity plus override decision, replacing
inline `materialized_name = if ...` / `override = if ...` branches.

Fields: `requested_name`, `target_name`, `state_key`, `body_symbol`,
`call_symbol_hint`, `override_symbol?`, `override_reason`.

Responsibilities: sole source for materialization keepalive candidates and the
identity-ledger symbol fields; wrapper/forwarder contract derivation.

Non-responsibilities: body lowering, state-scope selection, emitted-symbol
behavior changes (shadow/parity: emitted symbols remain legacy-equivalent).

Guard: `REQUIRE_PROMOTED=1
scripts/materialization_symbol_binding_admission_report.sh`.

#### 6.9.10 InvocationContext (hir/ast_to_hir.cr:670)

Owns the invocation frame for the `lower_super` / `previous_def` seam:
consumers read one owned frame instead of ambient `@current_class` /
`@current_method` / `@current_method_is_class` /
`@current_super_source_module` / forward-arg fields.

Fields: `class_name?`, `method_name?`, `method_is_class`,
`super_source_module?`, `function_name`, `forward_arg_ids`. Constructor:
`invocation_context_for_current_method(ctx)`; `with_invocation_super_source`
scopes nested module-super lowering with legacy save/restore semantics.

Guard: `REQUIRE_PROMOTED=1 scripts/invocation_context_admission_report.sh`.

#### 6.9.11 MaterializationCompletion ledger (methods, not a type)

Post-lowering completion authority for a materialization attempt. Not a
record: a default-off `[MAT_DONE]` row (`log_materialization_completion_ledger`,
hir/ast_to_hir.cr:2654) under `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER`.

Row fields: requested/target/materialized symbols, `has_function`,
`has_body`, final lowering `state`, owned terminal `status` and `reason`,
`created_function_count`, `producer_path`, `created_symbol_relation`,
`created_symbols`.

Responsibilities: distinguishes missing completion facts, completed attempts
without HIR functions/bodies, and MIR/backend visibility loss;
`created_body` / pre-lowering `InProgress` state is NOT body-present evidence.

Cautions: a `MaterializationAttemptResult` owner type remains a named future
slice (paper-only). Do not thread a trace object through production
`lower_method` (refuted: regressed generated-stage runs).

Guards: `scripts/generated_stage_created_body_visibility_classifier.sh`;
`scripts/generated_stage_lower_method_terminal_classifier.sh`.

#### 6.9.12 Shadow decision records (parity only)

`MaterializationDecisionRecord` (hir/ast_to_hir.cr:2856),
`SemanticStateScopeDecision` (:2901), `KeepRequestedNameDecision` (:2938) are
shadow/parity decision records; they must not become behavior authorities
without a would-change census. `DominanceInfo`
(mir/optimizations.cr:1681) is the lazy-dominance perf subowner for
CopyPropagation, not a contract record.

## 7. Execution order

### Phase 0: Bootstrap stabilization freeze

Do not start broad refactor while current `s2b`/`s3b` bug frontiers are moving.
Only add SDDs, probes, and small tactical fixes needed to restore the bootstrap
corridor. The active performance objective is fresh `s1 -> s2b` in <=180s
(with a faster stretch target), not merely a downstream run of an old generated
artifact.

Additional stop-rule after the 2026-07-01 checkpoint: a tactical fix is allowed
only when it names the owning semantic boundary and either consumes an existing
ledger row or adds a new behavior-neutral ledger/falsifier that will survive the
fix. If a slice only moves the crash/RSS frontier without adding an owner
boundary, stop and route the work to Phase 1 census.

Exit signal:

- fresh B4-F `s1 -> s2b` reaches the <=180s budget and both exact
  plain/full-prelude and no-prelude smokes pass;
- `s3b` status is known;
- active frontiers have problem cards and reducers or smoke scripts.

### Phase 0a: R0 frontier reconciliation

R0 is the mandatory join before Slice 1B or any default-path semantic
promotion. It must be run from a disposable snapshot of the current dirty
frontier and must not stage, clean, or rewrite the user's main worktree.

1. Build an A/B pair from the same source snapshot: A without T0 provenance
   and B with `91ebe332` T0. Record revision, flags, cache policy, workers,
   wall time, peak RSS, and generated-artifact provenance. Use a new output
   directory, verify fresh-output/source/output hashes, and record
   `cache_policy`, `cache_dir_rel`, and `cache_directory_identity`; record any external host cache separately and hold it
   constant.
2. Run host/unit guards plus exact plain/full-prelude and exact no-prelude
   semantic smokes on both A and B under `scripts/run_safe.sh`. Both modes are
   co-equal gates; a timeout is non-discriminating rather than proof that T0 is
   the cause.
3. Run a fresh `s1 -> s2b` classifier with a diagnostic cap sufficient to
   leave an attributable artifact, then apply the B4-F acceptance budget of
   <=180s. Compare materialization requests, duplicate bodies, forced lowers,
   queue peaks, phase times, and RSS; no single function count or timeout is a
   value proxy.
4. Write an evidence manifest naming the first divergent owner or declaring
   the result non-discriminating. Only after this seal may Slice 1B introduce a
   real `ResolutionId`/materialization consumer.

The disposable snapshot/source-guard subgate and host preflight are complete.
The sealed current-source run classifies B4-F as compiler-side performance red:
stage2 timed out at 182.54 seconds with exit 143 and no `cv2_s2`. Stage2
semantic smokes are unavailable because no artifact exists; they are not
semantic red or green. B5 remains historical/unrefreshed, and G9 remains only a
diagnostic candidate.

R0 as a promotion seal remains open until the same sealed source passes B4-F,
produces explicit stage2 semantic smoke results, and completes the fresh T0
A/B. Neither B4-H, G9, nor the manifest substitutes for those gates.

### Phase 0a.1: Reliability/architecture two-track join

The reliability track owns the <=180s fresh-stage budget, generated-stage
provenance, exact plain/no-prelude smokes, and rollback. The architecture track
owns T0 -> typed `ResolutionId`/`CallResolution`/materialization contracts and
the active typed resolution-to-materialization queue payload/transaction guard
at final HIR emission plus `lower_missing` replay. Evidence currently supports
a high-confidence string-keyed replay/materialization amplification hypothesis,
not causal proof. Its falsifier is a bounded typed payload/shadow that reduces
duplicate shape expansion while preserving exact semantics. Architecture work
must remain guard/shadow-only while reliability is red; the default-path
consumer stays blocked. Neither track may delete a queue/shim or claim a
speedup until the same source snapshot passes B4-F and both semantic gates.
Reliability fixes must name an owner boundary; architecture slices must retain
a legacy kill switch.

### Phase 0b: Architecture transition gate

Purpose: prevent the bootstrap loop from becoming a tail-chase while still
allowing evidence-producing fixes.

Admitted work:

- read-only or docs-only owner ledgers;
- scripts that census semantic decision sites without changing compiler output;
- focused reducers that prove a boundary before a behavior change;
- the bounded typed resolution-to-materialization queue payload/transaction
  guard and legacy shadow at final HIR emission plus `lower_missing` replay,
  with no default-path consumer;
- emergency bootstrap fixes only when they update the owner ledger or falsifier
  roster in the same logical change.

Rejected work:

- another local predicate/backend guard whose owner is only "the current stack";
- broad canonicalization or wrapper patches that pass one reducer but do not
  state requested, selected, materialized, and emitted identity;
- deleting "dead" branches before `CodePathStatus` marks them `delete_ready`;
- continuing a behavior patch after its focused DoD moves only memory/time but
  not the intended semantic boundary.
- another `lower_call` raw-read routing patch after generated-stage owner
  parity has already shown current/ref/heuristic owner agreement at the crash
  edge. The next slice must inspect `NodeSlot` / arena storage producer/read
  integrity or name an uninstrumented raw read first.
- extending a frontier with a second or third diagnostic ledger by inertia. If
  a ledger refutes the current local hypothesis without naming a fix owner, the
  next move is an SDD checkpoint or sealing plan unless a new diagnostic slice
  has its own falsifier roster, generated-stage evidence requirement, and
  cleanup rule.

Exit signal:

- Phase 1 census command exists and is committed;
- at least one active frontier is represented as a row in the semantic owner
  map;
- `TODO.md` points at the architecture-first next slice rather than only the
  latest crash stack.

### Phase 1: Architecture census

Read-only census of semantic writers/readers:

- who writes `@function_defs`, `@class_info`, `@generic_templates`,
  pending-lower queues, and method-resolution caches;
- who writes and reads `@type_param_map`, function type-param maps, namespace
  overrides, pending arg maps, and deferred contexts;
- where `mangled_method_name` is rewritten;
- where requested, target, materialized, and emitted call symbols can diverge;
- where block/yield function names are canonicalized;
- where `Hash`, `Array`, `Set`, and other builtin base names are qualified;
- where `ExprId` values are read through raw `@arena[...]`, where current arena
  can differ from the owning call/block/macro arena, and where `arena_for_expr?`
  uses index containment as a fallback;
- where layout/ABI/storage decisions are made or inferred.

Exit signal:

- a table of writers/readers per semantic decision;
- a list of hidden fallback sites;
- no production behavior changes.

Executable entry point:

```bash
scripts/semantic_decision_census.sh
```

This command is static grep only. It is allowed to produce broad candidate
sets, but no candidate becomes `live`, `dead`, or `owner` without a follow-up
dynamic ledger or reducer.

### Phase 1b: Dead-code and bloat census

Run after or alongside Phase 1, before physical extraction.

Work items:

- classify debug/probe gates, one-off workaround branches, old fallback paths,
  duplicate helper families, and source comments marked as temporary;
- build a `CodePathStatus` ledger for large clusters in `ast_to_hir.cr`,
  `hir_to_mir.cr`, and `llvm_backend.cr`;
- identify paths that can be shadow-disabled behind a guard without changing
  behavior;
- identify compatibility shims that must survive until their owner boundary is
  sealed.

Exit signal:

- every delete candidate has a status and protecting falsifier;
- no production behavior changes;
- cleanup candidates are ordered by risk and blast radius.

Executable entry point:

```bash
scripts/codepath_status_census.sh
```

This command is static grep only. It may identify candidate debug gates,
workarounds, fallback paths, compatibility shims, and broad semantic scans, but
it must not classify a candidate as live, dead, or `delete_ready` without a
follow-up runtime census plus protecting falsifier.

### Phase 2: Typed facades over existing state

Introduce small wrapper types that read/write the old maps but record owner,
callsite, and decision provenance.

Examples:

- `NameRegistry` facade over name qualification and class registration,
- `CallResolver` facade over overload selection,
- `StateScope` facade over type-param and namespace authority,
- `AstNodeIdentity` facade over parser arenas and owner-scoped `ExprId`
  references,
- `NodeSlotIntegrity` facade over arena slot producer/read facts after owner
  selection is already known,
- `MaterializationRegistry` facade over pending/lazy/block-shape functions,
- `AbiFacts` facade over layout/provenance facts.

Exit signal:

- old and new ledgers match on focused reducers;
- no behavior change at default gates.

### Phase 2a: Seal semantic state scopes for naming decisions

Before any behavior patch that changes callsite specialization,
`lower_function_if_needed_impl` override selection, or call-target remangling,
add a read-only ledger that records:

- requested symbol,
- resolved target symbol,
- selected definition identity,
- materialized symbol,
- emitted call symbol,
- ambient type-param map,
- target-materialization map,
- callsite arg types,
- selected state authority.

Exit signal:

- the `@block_owner Hash#[]=` frontier is classified as
  `call_symbol != materialized_symbol` with a named map-authority cause;
- current-instantiation cases such as `Array(Bool)` remangling are classified
  as legitimate ambient scopes, not false positives;
- a proposed behavior patch proves, before implementation, which symbol it will
  materialize and why.

### Phase 2b: Materialization identity transaction record

Before any behavior patch that changes pending-function replay,
requested/target/body/call symbol selection, wrapper/forwarder emission, or
backend undefined-extern recovery, introduce an explicit transaction record:

- call request symbol,
- selected definition identity,
- target materialization symbol,
- created body symbol,
- emitted call symbol,
- wrapper/forwarder contract when symbols differ,
- state-scope authority used to derive the names,
- ABI shape used by the emitted call.

Exit signal:

- a body created under one symbol while the emitted call names another symbol is
  represented as `exact`, `wrapper_forwarder`, or `rejected_mismatch`; there is
  no silent fourth state;
- known `Hash(UInt64, NamedTuple)#[]=` evidence is classified by this record
  before any forwarder or producer-side fix is attempted;
- backend undefined-extern stubs cannot be used as the first place where this
  semantic transaction is discovered.

### Phase 3: Seal CallResolution first

This should be the first major boundary because recent failures repeatedly
cross overload, block, super, state-scope, and materialization behavior.

Work items:

- introduce `CallRequest` and `CallResolution` structs,
- centralize candidate rejection reasons,
- forbid fallback from block call to non-block overload of incompatible arity,
- shadow-log old vs new selected targets before changing behavior.

Exit falsifiers:

- split overload misdispatch,
- split nilable-limit collision,
- Array join block-overload/super recursion,
- class-arg overload dispatch,
- block-call mega-union return leakage.

### Phase 3a: T1 identity-join guard and first vertical slice

Keep this phase behavior-neutral and follow the canonical five-step slice in
`docs/specs/07-compiler-decomposition-and-semantic-replacement.md` section
13.3. Ownership/`NameId` and the exact r1-r5 local typed decision are complete.
Next prove a bounded aggregate-to-original callsite/arena handoff to one named
downstream compiler consumer; only then mint `ResolutionId` and stream the
producer record. Keep boundedness diagnostic until a guard hard-caps it and
the external join pending until downstream `resolution_id` enrichment exists.
Its first DoD is identity continuity with zero HIR/MIR/LLVM delta, not queue
reduction or a speed claim.

### Phase 4: Seal NameResolution and TypeIdentity

Work items:

- preserve absolute-name markers through definition registration,
- separate declaration identity from display name and mangled name,
- stop phantom generic-template creation,
- add a typed path for builtin-base names.

Exit falsifiers:

- phantom `Adamas::MIR::Hash` underallocation family,
- hash dual typeref family,
- local nested class/module resolution cases,
- alias-derived generic base cases.

### Phase 5: Seal Materialization

Work items:

- make materialization keyed by selected definition plus ABI shape,
- unify deferred lowering, lazy RTA, and block/yield function replay under a
  single materialization registry,
- ensure emitted call target equals materialized symbol or an explicit
  wrapper/forwarder symbol.

Exit falsifiers:

- distinct block-shape split functions are emitted and called,
- concrete `main_arenas << map_arena`, explicit `.as(ArenaLike)`, and true
  union flow preserve their lawful selected `Def`/instance, coercion/value
  type, receiver/value arity, matching body/symbol, and no orphan malformed
  stub,
- `@block_owner Hash#[]=` does not leave a body only under the target symbol
  while the emitted call uses the requested symbol,
- pending queue does not drop shape-specific requests,
- no late emission site collapses a shape-specific symbol back to an arity
  symbol.

### Phase 6: Seal AbiFacts and LayoutContract

Work items:

- move remaining phase-local layout helpers behind context-specific facts,
- keep field, Array, Pointer, Slice, StaticArray, union, arg, return, and
  carrier layouts distinct,
- remove backend string-prefix decisions after equivalent facts exist.

Exit falsifiers:

- A-prime and C-narrow reducers stay green,
- layout probe has no unexplained slot/access conflict in admitted contexts,
- unknown contexts fail closed.

### Phase 7: Physical file split

Only after the above boundaries have typed contracts:

- move services into smaller files/modules,
- keep compatibility shims briefly,
- delete old backdoors after parity windows pass.

Exit signal:

- each moved module has a bounded state contract;
- no module reaches back into the old monolithic object for unrelated maps.

### Phase 8: Dead-code deletion and shim retirement

Only after the owning boundary is sealed or the path is proven unreachable:

- delete `delete_ready` paths from the `CodePathStatus` ledger;
- retire compatibility shims whose replacement boundary has passed parity;
- remove stale debug gates and probes once their evidence has moved to docs,
  regression scripts, or landmarks;
- keep a short deletion note naming the falsifier that made the removal safe.

Exit signal:

- the codebase shrinks without changing admitted behavior;
- no replacement shim reintroduces the old hidden state contract;
- broader bootstrap and regression guards pass.

## 8. Falsifier roster

Keep this roster executable where possible. It is the minimum adversary set for
future architecture work:

- `string_split_int32_nil_limit_collision_repro.sh` - block-shape collision.
- `string_split_default_nil_limit_repro.sh` - overload misdispatch.
- `s2b_value_def_block_phantom_hash_probe.sh` or successor - phantom builtin
  base registration.
- `hash_dual_typeref_phantom_repro.sh` - dual typeref phantom regression.
- `BlockOwner` owner-cache materialization successor - the current
  `Hash(UInt64, BlockOwner)#[]=` carrier must not emit a call to a symbol whose
  body was materialized only under a different target symbol. The old
  `hash_named_tuple_index_assign_materialization_repro.sh` was retired because
  it targeted the obsolete `Hash(UInt64, NamedTuple)#[]=` shape.
- `type_param_scope_authority_probe.sh` or successor - distinguishes leaked
  ambient `@type_param_map` from legitimate current-instantiation maps in
  naming/materialization decisions.
- Array join super-chain smoke - block-overload materialization/super
  dispatch.
- A-prime inline Array storage reducers - storage context and provenance.
- C-narrow placement/load reducers - store/load residual removal without
  carrier leaks.
- layout probe / `ADAMAS_LAYOUT_ASSERT` - slot/access divergence.
- super-chain module/class collision reducers.
- block-call mega-union and class-arg overload dispatch reducers.
- typed union-container insertion target/materialization reducer (T9): join
  selected `Def`/`DefInstanceKey`, coercion/value type, receiver/value arity,
  materialized body, and emitted symbol for lawful concrete, explicit-cast,
  and true-union flows. The
  [reducer](../regression_tests/union_static_generic_materialization_guard.cr)
  and [guard](../regression_tests/union_static_generic_materialization_guard.sh)
  are current-red: focused HIR reports signature/conversion discontinuities,
  and optional full-G9 mode classifies the orphan zero-argument call/stub as
  `MEASURED_RED`.
- dead-code deletion smoke - targeted reducer set plus `s2b`/`s3b` frontier
  comparison for removed paths in compiler hot code.

If a refactor slice cannot name which roster items it might affect, it is not
ready to start.

## 9. Stop rules

Stop and return to census/design when any of these occurs:

- a facade needs to re-infer a fact instead of reading the owning boundary;
- two hidden consumers of the same semantic decision appear;
- a consumer predicate patch is proposed without naming the authoritative
  state scope that feeds the predicate;
- `with_isolated_type_param_map` or a similar scoping helper changes which map
  is read but does not prove the requested, target, materialized, and emitted
  symbols agree;
- a body is created under one symbol while the emitted call names another
  symbol and there is no explicit wrapper/forwarder contract;
- a union-container flow loses selected `Def`/instance, coercion/value type,
  receiver/value arity, body/emitted-symbol continuity, or creates/emits an
  orphan malformed zero-argument call/body/stub;
- an AST-node consumer patch is proposed before the raw `@arena[expr_id]` read
  has been classified as current-arena-owned, call-arena-owned, block-owned,
  macro-owned, reparsed-owned, or stale/corrupt;
- a behavior-neutral extraction changes emitted HIR/MIR/LLVM under default
  gates;
- a backend patch needs source-level knowledge to decide a call, owner, block
  shape, or storage context;
- one build/falsifier cycle does not change the targeted wrong edge;
- three attempts repeat the same observation level;
- `s2b` moves to a new crash frontier that is not explained by the active
  slice;
- a cleanup patch deletes code before proving the path is `delete_ready`;
- a cleanup patch replaces deleted code with a new broad shim that preserves
  the same hidden oracle.
- a downstream ledger is proposed only because the previous ledger did not
  produce a fix owner. The new ledger must either complete an existing
  transaction contract or be admitted as its own SDD slice with generated-stage
  evidence, residual boundary, and cleanup rule.
- a backend reconciliation/forwarder path needs knowledge that exists only
  after HIR/MIR materialization has already dropped the target body. That is an
  architecture ordering failure, not permission to re-run HIR lowering from the
  backend.

## 10. Ledger sync

This document carries no dated entries. The division of truth:

- `TODO.md`: active working backlog and per-slice evidence (the work log).
- `LANDMARKS.md`: durable verified anchors and refuted branches.
- git history: everything else, including the retired 2026-06/07 execution
  ledger (`git show 95539f64:docs/compiler_architecture_sdd.md`).
- This file: target architecture, built owner records (section 6.9), the
  authority-edge state table and current frontier (section 0, replaced in
  place).

Sync rule: a slice that builds or extends an owner record updates section 6.9
and the section 0 table in the same commit. A slice that moves the frontier
rewrites section 0.1 in the same commit.

## 11. Migration slice boundaries

The four root migration slices. Each defines a boundary, not a schedule.

### Slice A: CallResolution boundary

Source/spec:

- `ast_to_hir.cr` call resolution paths,
- overload and block lookup helpers,
- pending function and block target rewriting sites.

Falsifiers:

- split overload misdispatch,
- split nilable-limit collision,
- Array join block-overload dispatch,
- block-call and class-arg overload reducers.

Evidence:

- old vs new target ledger for each falsifier,
- default-gate byte-identical output before behavior flip.

Boundary:

- no ABI/layout/backend behavior changes.

Next local track:

- materialization registry after CallResolution emits stable
  `materialization_key` values.

### Slice B: NameResolution and TypeIdentity boundary

Source/spec:

- definition name extraction,
- namespace qualification,
- generic template registration,
- concrete class registration,
- alias-derived generic base handling.

Falsifiers:

- phantom builtin base underallocation,
- hash dual typeref,
- absolute reopen inside module,
- local nested class positive cases.

Evidence:

- no phantom builtin-base class symbols,
- canonical type identity ledger matches direct and alias-derived references.

Boundary:

- no overload or backend changes.

Next local track:

- Materialization and pending/lazy replay.

### Slice C: AbiFacts/LayoutContract boundary

Source/spec:

- MIR type/fact model,
- HIR field/layout helpers,
- MIR lowering layout readers,
- LLVM storage, copy, and carrier helpers.

Falsifiers:

- A-prime reducers,
- C-narrow reducers,
- layout probe conflicts,
- Pointer/Slice/StaticArray non-Array guards.

Evidence:

- LLVM consumes facts without re-deriving provenance,
- unknown storage contexts fail closed.

Boundary:

- no call/name resolution changes.

Next local track:

- typed LLVM writer after ABI facts are stable enough to be consumed
  mechanically.

### Slice D: Dead-code census and deletion ledger

Source/spec:

- `scripts/codepath_status_census.sh`;
- large helper clusters and fallback branches in `ast_to_hir.cr`,
  `hir_to_mir.cr`, and `llvm_backend.cr`;
- debug/probe gates left from bootstrap investigations;
- compatibility shims introduced by boundary slices.

Falsifiers:

- static reader/writer census for each delete candidate;
- runtime branch counters on focused reducers and bootstrap smoke;
- HIR/MIR/LLVM parity for behavior-neutral deletions;
- no-cache and cache-off bootstrap smoke when the path touches hot compiler
  control flow.

Evidence:

- static Phase 1b census output grouped by debug gates, workaround comments,
  fallback/recovery paths, legacy naming shims, broad scans, backend semantic
  leakage, and layout/ABI workaround candidates;
- `CodePathStatus` ledger with `suspected_dead` -> `delete_ready` transitions;
- before/after diffstat and removed-symbol list;
- regression script or documented reason for each removed compatibility path.

Boundary:

- the census itself is read-only and never proves deletion safety alone;
- no semantic behavior changes in the same commit as a deletion unless the
  deletion is the behavior change and has its own falsifier.

Next local track:

- physical file split only after the deleted paths are no longer part of the
  old hidden state contract.

## 12. Status and admission

Status: ACTIVE. This document admits architecture-shape decisions (ownership
boundaries, record shapes, migration order). It does not admit behavior
changes by itself: behavior changes are admitted by the falsifier matrix
(`docs/specs/05-falsifier-matrix.md`), the regression gates, and the B4/B5
classifiers.

Retired process machinery (do not resurrect): `SliceReceipt`,
`BootstrapPotential`, per-slice admission checkpoints, dated board
refinements. Rationale: `docs/sdd_process_review_2026_07_03.md`.
