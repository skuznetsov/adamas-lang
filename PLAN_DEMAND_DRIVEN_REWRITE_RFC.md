# RFC: Demand-Driven Semantic Rewrite for Compile Path

Status: Draft; R0 sealed current-source evidence reconciled 2026-07-18
Audience: Claude Opus implementation track, architecture review  
Scope: Compiler compile path only; check path unification is part of rollout, not day 1  
Supersedes: high-level direction in `PLAN_DEMAND_DRIVEN_REWRITE.md`

## 1. Purpose

This RFC turns the current rewrite idea into a migration contract.

The goal is not "rewrite AstToHir because it is large".
The goal is to replace the current supply-driven compile path with a
demand-driven semantic pipeline that:

- removes queue-explosion architecture from compile
- makes body analysis cacheable by semantic identity
- preserves current HIR and downstream contracts during rollout
- keeps self-hosted bootstrap risk bounded with feature flags and shadow mode

This is a strategic architecture track. It is not justified as the immediate
fix for the current runtime-stability frontier.

## 2. Current Constraints

The current tree has two worlds:

- compile path: `Parse -> AstToHir -> HIR -> MIR -> LLVM`
- check path: `Parse -> Analyzer -> SymbolCollector -> resolve_names -> infer_types`

Important constraint: these worlds do not share one type identity model today.

- semantic stack uses `Semantic::Type` in `TypeContext`
- HIR explicitly uses `HIR::TypeRef` and avoids coupling to `Semantic::Type`

Important compile-path constraint: compile does not operate on one small parser
program. It loads prelude and `require` graph into multiple parsed units and
source maps.

Important rollout constraint: raw HIR equality is not a valid shadow gate.
Function ids, value ids, block ids, and type ids are order-sensitive.

### 2.1 R0 readiness boundary

Fresh-source readiness is a performance and semantic vector, not a recovered
historical label. B4-F requires a new-output `s1 -> s2b` build in <=300 seconds
plus exact green plain/full-prelude and no-prelude smokes. Historical fresh
both-smoke certificates at 231.37, 251.91, and 253.42 seconds fit that numeric
budget but remain stale and cannot certify current source. Historical
~178-190-second records are no-prelude or partial only. A 2026-07-14 fresh run
took roughly 711 seconds with no-prelude green/plain red; G7, G8, and G9 took
1962.79, 1791.78, and 1768.73 seconds and both smoke modes were red.

R0 now has a sealed current-source snapshot: base `c216b9ef...`, tree
`1efb635...`, exactly seven tracked compiler/spec paths, patch SHA-256
`d7ad2cacb1472d07daf6cc5793bce52a1940ed967bfce2a2322d67a291a967fc`, and
passing snapshot diff-check. The manifest is
`/private/tmp/adamas_r0_current_c216_manifest.md`; host spawn preflight is
green. With fresh cache/output, `s1` built in 14.13s and passed exact plain
(`42`) and no-prelude (`hello world`, `n=42`, `noprelude_interp_ok`) smokes.
The `s2` self-host build timed out with exit 143 at 182.54s and 1361.03 MiB
externally sampled peak RSS; the outer chain exited 1 at 219.32s and produced
no `cv2_s2`. That receipt is red under the former 180-second cap but does not
measure the current 300-second policy. Stage2 semantic smokes are unavailable,
not semantic red or green. The host-infrastructure blocker is refuted; R0
promotion remains blocked by B4-F and the missing same-source fresh T0 A/B.
Historical G9 remains diagnostic-only; T8 is executable, but no fresh current
receipt has passed it.

A bounded stats-on repeat used the sealed `cv2_s1` with only
`ADAMAS_PHASE_STATS=1` under the same 180-second/12288-MB safe-run envelope.
It timed out with exit 143 at 182.60s, produced no `cv2_s2`, and did not capture
peak RSS. Completed phase counters were `process_pending` 218 -> 591 (+373) in
555.2ms and `emit_tracked_sigs` 591 -> 604 (+13) in 235.0ms. The first open
phase, `lower_missing.initial`, grew internally 604 -> 1535 -> 7422 -> 19238 ->
28234 (+27,630 from 604) before timeout; no completion, phase timing, or
normalized top-prefix exists. The log SHA-256 is
`1cc025cc5930ebd0513382e68dbb400e763002186f227288683d6bc710f79ecd`.
This is sealed-current revalidation/evolution of the historical 2026-04-29
localization, not a normalized before/after result: observation definitions
differ, and stats-on versus uninstrumented timing is diagnostic-only.

### 2.2 Typed materialization diagnostic boundary

For source `main_arenas << map_arena`, the minimal G9 HIR selects
`push$AstArena` for the static value and the union target for an explicit
upcast. The upstream Crystal audit establishes both as lawful, distinct generic
instances: concrete flow through `Array(ArenaLike) << AstArena` specializes
`<<`/`push` with `AstArena`, while explicit `.as(ArenaLike)` and true union
flow specialize with a union or lawful reduced union. The same minimal probe
preserves both arguments through HIR, MIR, and LLVM. Full G9
`s2` LLVM instead contains a union `<<` call to zero-argument
`push$AstArena()` and a zero-argument unreachable stub.

The exact zero-argument creation mechanism is not proven. Late HIR
materialization or a missing selected target is a high-confidence hypothesis,
and must remain one until T9 joins selected `Def`/`DefInstanceKey`,
coercion/value type, receiver/value arity, materialized body, and emitted symbol
on one reducer.

The identity authority for this boundary is
`DefInstanceKey(def.object_id, actual typed args, block/named)`. The mangled
name is only its later serialized form and must not replace the typed key.

The active bounded target is therefore a typed resolution-to-materialization
queue payload/transaction guard at final HIR emission and `lower_missing`
replay. Current evidence supports a high-confidence hypothesis of string-keyed
replay/materialization amplification, not causal proof. The falsifier is a
bounded typed payload/shadow that reduces duplicate shape expansion while
preserving selected target, call shape, body/symbol continuity, and exact
semantics. It remains guard/shadow-only; no default-path consumer is admitted.

## 3. Non-Negotiable Invariants

These are hard requirements for the rewrite.

### 3.1 Semantic identity is canonical

The new semantic layer must define one canonical type identity model for:

- cache keys
- invalidation
- typed-def identity
- conversion into HIR `TypeRef`

The compile path must not mix `Semantic::Type` and `HIR::TypeRef` in the same
cache key without a canonical adapter.

Required artifact:

- `SemanticTypeId` or equivalent canonicalization layer
- stable mapping:
  - semantic type -> canonical semantic id
  - canonical semantic id -> HIR `TypeRef` at emission boundary

### 3.2 Bridge to AstToHir is leaf-only

The new pipeline may temporarily delegate only to leaf emission helpers.

It must never depend on legacy supply-driven control flow:

- `emit_all_tracked_signatures`
- `process_pending_lower_functions`
- `force_lower_function_for_return_type`
- legacy pending-function safety nets

Required runtime assertion under the new feature flag:

- if any of the above paths execute, compilation fails loudly

### 3.3 Declaration phase reaches a full fixed point

The declaration phase must produce all compile-visible metadata required by
later phases, including:

- classes, modules, structs, enums, libs
- aliases and alias chains
- macros relevant to compile path
- enum constant resolution
- C struct sizes and alignment-relevant info
- module includers/extenders
- class hierarchy
- generic template declarations
- method effect annotations
- extern function/global registration

No later phase may depend on ad hoc discovery of these declarations.

### 3.4 Shadow mode compares normalized equivalence, not raw dumps

The rollout gate is semantic equivalence after normalization, not byte-identical
HIR text.

Required normalized comparison includes:

- function name and signature set
- return types
- instruction shape per function
- call target set
- method effect summaries
- class hierarchy and module includer metadata
- extern tables
- type descriptor set after normalization
- MIR generation success
- LLVM generation success
- reducer runtime behavior on selected smoke cases

### 3.5 Typed target identity survives materialization

A call's selected `Def`/`DefInstanceKey`, coercion/value type, receiver/value
arity, body, and emitted symbol must remain continuous through materialization
and emission unless an explicit typed conversion or wrapper/forwarder contract
says otherwise. Concrete insertion may select the concrete `AstArena` instance;
explicit-cast and true-union flows may select union/reduced-union instances.
HIR, MIR, LLVM, and the materialized body must preserve the receiver/value call
shape; an orphan malformed zero-argument call or unreachable stub fails closed.

## 4. Feature Flags

### 4.1 Primary flag

`ADAMAS_SEMANTIC_COMPILE=1`

- `0` or unset: legacy compile path
- `1`: new semantic compile path

### 4.2 Validation flags

Recommended auxiliary flags:

- `ADAMAS_SEMANTIC_SHADOW=1`
- `ADAMAS_SEMANTIC_ASSERT_NO_LEGACY_QUEUE=1`
- `ADAMAS_SEMANTIC_DUMP_NORMALIZED=1`

## 5. Phases

### Phase 0: Contracts and Instrumentation

Purpose:
- define what must be preserved before changing architecture

Must produce:
- contract doc for HIR inputs required by MIR and LLVM
- normalized shadow comparator spec
- a B4-F evidence manifest that distinguishes the <=300-second acceptance
  target from historical full-green, no-prelude-only, partial, and both-red
  records
- the T9 [reducer](regression_tests/union_static_generic_materialization_guard.cr)
  and [guard](regression_tests/union_static_generic_materialization_guard.sh),
  joining static union insertion target selection to
  selected definition/instance, coercion/value type, receiver/value arity,
  materialization, and emission for concrete, explicit-cast, and true-union
  flows; focused HIR and optional full-G9 modes are current-red falsifiers
- counters for legacy supply-driven behavior:
  - forced lowers
  - pending queue growth
  - safety-net pass count
  - duplicate body analysis count if measurable

Exit criteria:
- normalized comparison format is implemented or fully specified
- legacy-path metrics are observable in CI/local runs
- kill-switch assertions are defined for new flag
- same-source fresh T0 A/B and B4-F must pass before promotion; the prior
  sealed attempt is red only under the former 180-second cap, the current
  300-second policy is unmeasured, and manifest evidence does not replace the
  committed T8 decision

### Phase 1: Canonical Semantic Identity Layer

Purpose:
- remove ambiguity between semantic types and HIR types

Must produce:
- canonical semantic type id
- typed-def identity model
- canonical `DefInstanceKey`

Required shapes (implemented in `src/compiler/semantic/identity/`):

```crystal
# Canonical semantic type identity — interned UInt32, NOT hash
struct SemanticTypeId
  getter id : UInt32
end

# Structured def identity — injective by construction
struct DefIdentity
  getter arena_id : UInt64
  getter expr_index : Int32
end

# Semantic cache key — NO mangled names, NO HIR::TypeRef
struct DefInstanceKey
  getter def_identity : DefIdentity
  getter receiver_type : SemanticTypeId?
  getter arg_types : Array(SemanticTypeId)
  getter block_type : SemanticTypeId?
  getter named_arg_types : Array({String, SemanticTypeId})?
end
```

Rules:
- no mangled names in semantic cache keys
- no `HIR::TypeRef` in semantic cache keys
- no cache keyed by unstable object graph unless object identity is the intended
  semantic identity and lifecycle is controlled

Exit criteria:
- one adapter exists from semantic id to `HIR::TypeRef`
- one adapter exists from semantic id to printable normalized type name
- cache invalidation rules are documented

### Phase 2: Compile-Path Integration Substrate

Purpose:
- make existing semantic stack compile-capable before demand-driven rewrite

This is the missing migration phase between current check path and compile path.

Must cover:
- multi-file aggregation
- prelude loading behavior
- require graph handling
- source-map parity
- macro expansion parity for compile path
- arena strategy that does not assume only one parser-built `AstArena`

Required changes:
- `Analyzer` can consume compile-path program graph, not only check-path unit
- `TypeInferenceEngine` no longer assumes one parser-built `AstArena`
- symbol collection and macro expansion preserve file/source provenance needed by
  compile diagnostics and later lowering

Exit criteria:
- semantic pipeline can analyze a compile-path aggregate program without going
  through AstToHir
- file/line provenance matches current compile diagnostics on a smoke suite

### Phase 3: Full Declaration Fixed Point

Purpose:
- move all declaration and registration logic required for compile into the
  semantic pipeline

Must produce:
- all declaration metadata listed in invariant 3.3

Must not rely on:
- later fallback registration from AstToHir
- runtime discovery of types during emission

Exit criteria:
- declaration output can seed HIR builder without extra AstToHir registration
- legacy declaration pass and new declaration pass are normalized-equivalent on
  selected stdlib and repo inputs

### Phase 4: Demand-Driven Body Typing

Purpose:
- type-check bodies on demand and cache by semantic identity

Core rules:
- bodies are analyzed only when reached from top-level demand
- each typed def is analyzed once per unique `DefInstanceKey`
- generic instantiation is on-demand
- typed target identity retains selected `Def`/`DefInstanceKey`,
  coercion/value type, receiver/value arity, body, and emitted-symbol continuity
  from resolution through body cache and materialization; concrete and union
  flows may retain distinct lawful instances
- recursive and cyclic cases use explicit in-progress states, not fallback queue
  growth

Must produce:
- demand-driven call resolver
- typed-def cache
- duplicate body analysis counter

Exit criteria:
- repeated calls with identical semantic signature hit cache
- legacy forced-return-type lowering is not used
- body-analysis count drops on benchmark reducers

### Phase 5: HIR Builder Replacement

Purpose:
- emit current HIR contracts from typed semantic results

Allowed bridge:
- leaf helpers only

Forbidden bridge:
- any delegation that can invoke legacy queue/safety-net architecture

Must emit:
- HIR instructions compatible with current `hir_to_mir`
- typed selected/materialized target identity and call arity sufficient to
  reject a malformed or zero-argument late materialization
- method effect summaries
- lifetime and taint seeds required downstream
- class hierarchy and module includers
- extern tables
- type descriptors and generic metadata needed downstream

Exit criteria:
- new HIR builder passes normalized shadow compare against legacy path on
  reducer suite
- `ADAMAS_SEMANTIC_ASSERT_NO_LEGACY_QUEUE=1` stays green

### Phase 6: Shadow Rollout

Purpose:
- validate semantics before switching default

Stages:
1. build both pipelines
2. normalize both outputs
3. compare equivalence
4. run MIR/LLVM generation on both
5. run runtime smoke suite on both

Required shadow suite:
- hello world
- no-prelude tiny carrier
- representative block/proc case
- generic container reducer
- macro-heavy reducer
- enum/lib/alias reducer
- current stage2/stage3 compile reducers
- static union-container insertion versus explicit upcast (T9)

Exit criteria:
- normalized comparator green on agreed suite
- downstream MIR/LLVM green
- no regressions in runtime smoke behavior
- no legacy queue assertions fired
- fresh B4-F reaches <=300 seconds and both exact semantic smoke modes are
  green on the same manifested source/artifact; historical G9 cannot satisfy
  this gate

### Phase 7: Default Switch and Deletion

Purpose:
- switch compile default only after shadow confidence is high

Order:
1. default-on behind escape hatch
2. soak period
3. remove legacy compile-path dependency
4. unify check and compile semantic paths where appropriate

Exit criteria:
- default-on is stable on reducer suite and bootstrap suite
- rollback flag still works during soak
- dead code deletion does not remove still-used leaf helpers prematurely

## 6. Normalized Shadow Comparison Spec

The comparator must ignore unstable ids and emission order where order is not
semantically meaningful.

Normalization rules:

- normalize `FunctionId`, `ValueId`, `BlockId`, `TypeId`
- compare functions by name + signature
- compare calls by normalized callee + normalized operand shape
- compare type descriptors by normalized name/kind/params
- compare metadata maps by normalized keys
- compare instruction streams after id renaming

A shadow run is green only if:

- normalized HIR equivalent
- MIR build succeeds
- LLVM build succeeds
- selected runtime smokes behave the same

## 7. Kill-Switch Rules

Under `ADAMAS_SEMANTIC_COMPILE=1`, fail immediately if:

- `emit_all_tracked_signatures` executes
- `process_pending_lower_functions` executes
- `force_lower_function_for_return_type` executes
- legacy pending-function queue exceeds zero after semantic typing is active
- new semantic cache falls back to mangled-name identity

## 8. Metrics

Primary metrics:

- forced lowers per compile
- safety-net pass count
- pending queue growth
- duplicate typed-body analysis count
- compile wall time
- peak RSS on selected reducers
- B4-F certificate class: fresh both-smoke, no-prelude-only, partial, or red

Secondary metrics:

- normalized HIR mismatches
- MIR mismatches
- LLVM mismatches
- bootstrap stage success rate

## 9. Out of Scope for Initial Rollout

- redesigning MIR
- redesigning LLVM backend
- changing HIR semantics unless required by contract gap
- solving every current runtime correctness bug through this RFC

## 10. Definition of Done

This RFC is complete when:

- compile path is demand-driven by semantic identity
- legacy supply-driven queue machinery is not required under the new flag
- normalized shadow suite is green
- bootstrap and reducer suite are green enough to justify default switch
- B4-F has a fresh <=300-second both-smoke green certificate and T9 proves
  concrete, explicit-cast, and true-union insertion preserve selected
  definition/instance, coercion/value type, receiver/value arity, body/symbol
  continuity, and non-stub materialization
- semantic and HIR type identity boundary is explicit and stable
