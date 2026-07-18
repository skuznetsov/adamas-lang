# Compiler Decomposition and Semantic Replacement — Frontier SDD

> Status: DESIGN-SEALED, documentation-only (2026-07-18).
> Audit snapshot: checkout `05954794`, with a dirty worktree. No compiler
> build, generated-stage run, or runtime claim is made by this document.
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
          the current B5 self-build frontier remains inside AstToHir.
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
freshness: fresh for source shape at 05954794; runtime frontier evidence is
           inherited from the current architecture SDD and must be refreshed.
safe_next_move: P2W-ready for a docs/ledger slice; implementation remains
                guard-only until the first identity falsifiers exist.
validation_boundary: the first vertical ResolutionId/MethodInstanceKey slice
                     must preserve old behavior and prove identity continuity.
```

The single next move is a behavior-neutral identity slice with a normalized
shadow comparison; its evidence requirement is a typed identity ledger plus
positive and negative reducers, not a successful host build alone.

## 2. Current frontier and transition decision

The declared bootstrap frontier in the current architecture SDD is:

- B4 (produced s2 compiles a full-prelude tiny source) is recorded GREEN.
- B5 (s2 self-build to s3) is recorded RED. The first bad stop is the
  `AstToHir#lower_method` body loop for
  `Adamas::Compiler::CLI#run$IO_IO`, at roughly 4.8 GB peak RSS, under
  `ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED`; the
  pre-body gates are recorded clean.

This is a declared frontier, not a fresh build result: this docs-only change
does not rerun the classifiers. A later source or evidence change invalidates
the statement and requires the B4/B5 gates in
`docs/compiler_architecture_sdd.md` and `docs/specs/05-falsifier-matrix.md`
to be refreshed.

Decision:

1. The demand-driven pipeline in the RFC is the strategic destination.
2. The immediate route is a selective strangler: introduce an owner record,
   shadow it, route one consumer, then retire the old path only after its
   falsifiers pass.
3. A blank-slate compiler rewrite is not admitted at the current B5 frontier.
4. Physical file splitting is delayed until semantic contracts reduce the
   state surface of the moved code.

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
- Stdlib edits, parser replacement, or a broad ABI representation change as a
  side effect of this architecture transition.

### 3.3 Guard-only future

- `ADAMAS_SEMANTIC_COMPILE=1` as a kill-switched candidate compile path.
- `ADAMAS_SEMANTIC_SHADOW=1` normalized legacy/candidate comparison.
- `ADAMAS_SEMANTIC_ASSERT_NO_LEGACY_QUEUE=1` assertions that reject
  `emit_all_tracked_signatures`, `process_pending_lower_functions`,
  `force_lower_function_for_return_type`, or non-zero legacy pending demand
  under the candidate path.
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
| `DefInstanceKey` named-argument component | Reuse through a compatibility adapter while its `String` names are canonicalized to `NameId`/typed argument-name IDs before candidate promotion. | Do not treat the current `Array({String, SemanticTypeId})` field as the final no-semantic-string contract. |
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

0. **Bootstrap freeze.** Keep B4/B5 evidence current. Permit docs, census,
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

### 13.2 First vertical `ResolutionId` / `MethodInstanceKey` slice

The first implementation slice is intentionally narrow and behavior-neutral;
it evolves existing scaffolding rather than duplicating it:

1. Extend `src/compiler/semantic/identity/def_identity.cr`,
   `semantic_type_id.cr`, `def_instance_key.cr`, and `hir_adapter.cr`. Add
   immutable `ResolutionId` beside those records, and evolve the current
   `DefInstanceKey` named-argument field from rendered `String` names to
   canonical `NameId`/typed argument-name IDs through a compatibility adapter.
   Do not add a parallel key or interner; do not put mangled strings or
   mutable arrays in the candidate key.
2. At one existing call-resolution owner, emit the evolved records alongside
   the legacy selected name and pending request. Keep the old route
   authoritative.
3. Join the records through materialization and emit a default-off ledger that
   reports selected definition, scope authority, target/body/call symbols, and
   key components.
4. Run positive/negative identity reducers and normalized shadow comparison.
   The candidate record must not alter HIR/MIR/LLVM, queue behavior, or backend
   calls. A mismatch remains on the legacy route and names the first owner.
5. Promote exactly one legacy consumer to read the typed record in parity mode;
   do not add a second diagnostic ledger unless it completes this transaction.

The slice is design-sealed, not implemented by this document. Its first DoD is
identity continuity and zero behavior delta, not a queue reduction or a new
compile path. The next local track is the state-scope/materialization seal;
the demand-driven body cache remains later until declaration fixed-point parity
is demonstrated.

## 14. Stop, dirty-worktree, and rollback rules

Stop and return to census/design when:

- a new facade re-infers a semantic fact or reads a rendered name as authority;
- two owners answer the same question or a consumer patch hides the owner;
- a key can be reminted, mutated after insertion, or read without its owner
  context;
- a shadow mismatch, legacy queue execution, arena-expiry failure, or backend
  reconstruction appears;
- a zero-copy change improves an allocation proxy while worsening normalized
  semantics, peak RSS, or retention;
- a B4/B5 run moves to an earlier or unexplained frontier;
- three attempts operate at the same observation level without changing the
  targeted edge;
- a deletion is proposed before `CodePathStatus=delete_ready` and its negative
  use proof.

The audit worktree already contains unrelated modified compiler/spec files and
untracked probes. This SDD, its README index row, and the falsifier-matrix
section are the only owned paths for the documentation slice. Do not stage,
format, revert, or commit unrelated work. Before implementation, use an
isolated branch/worktree or an equivalent ownership checkpoint and stage exact
paths only.

Rollback is by disabling the candidate flag and returning consumers to the
legacy path. Do not delete queues, old registries, or compatibility shims until
the shadow soak and bootstrap gates pass. If source or frontier evidence moves,
mark this audit stale and refresh the counts and B4/B5 declaration before
continuing.

## 15. Ledger sync and residual decisions

- This document: transition boundary, identity/lifetime taxonomy, migration
  order, seals, and residual rejected surface.
- `docs/compiler_architecture_sdd.md`: current owner records, B4/B5 frontier,
  architecture phases, and authority-edge table. It remains the main SDD and
  is intentionally not edited in this docs-only slice.
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
