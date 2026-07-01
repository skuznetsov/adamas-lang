# Compiler Architecture Frontier SDD

Document status: ACTIVE FRONTIER SDD. Behavior-neutral architecture slices are
landing as bootstrap control gates. This is not approval to start a broad
refactor while the current `s2b`/`s3b` bug frontiers are still moving.

Current frontier: the compiler can make progress through bounded bug slices,
but many semantic decisions are still inferred repeatedly across HIR, MIR, and
LLVM lowering. This creates hidden oracles, string-name coupling, phase-local
fallbacks, and hard-to-localize bootstrap failures.

Current hostile-review frontier: the latest bootstrap work keeps exposing the
same ownership class under different symptoms, but the active implementation
track is no longer the old crash-edge diagnostic ladder. The earlier `s2b`
stub family showed a materialization identity failure, not a backend stub bug:
a call could be emitted under the requested symbol while the body was
materialized under a different target symbol because ambient `@type_param_map`
leaked into a naming/materialization decision. Later generated-stage ledgers
then refuted current-arena drift, out-of-range `ExprId`, and missing
`NodeSlot` for the instrumented `lower_call` edge. That evidence remains
valuable, but it is not the current next implementation track. Slice 0k-A
added default-off correlation between HIR materialization transactions and
backend emitted-call facts; Slice 0k-B added selected-definition and
state-scope owner fields. Those focused slices are not enough to authorize a
behavior patch, because the full generated-stage run still does not reach the
emitted-call seam. The deeper architectural issue is still that symbol
identity, type-param authority, AST node ownership, type identity,
materialization ownership, and field/layout facts are inferred from mutable
process state and rendered/index-only values instead of from owned typed facts.

Current next-slice decision after 0k-B: do not start a call/materialization
behavior patch from focused transaction success alone. The full generated-s2
transaction report does not reach `[MAT_EMIT]`, so the next admitted slice is
either generated-stage seam reachability as an owner-boundary problem or the
`SemanticStateScope` shadow facade. The default preferred direction is the
facade, because the repeated verified roots involve ambient semantic state
being treated as authority.

Current next-slice decision after the first `SemanticStateScope` shadow ledger:
do not turn the fresh generated-stage `NodeSlot#node` crash back into a
consumer patch. A full generated-s2 `SemanticStateScope` report now reaches the
HIR materialization seam and emits owned `[STATE_SCOPE]` rows, but it still
crashes before `[MAT_EMIT]`. A fresh `NodeSlotIntegrity` report on the same
full corridor reports only healthy slots for the instrumented lower-call edge.
That means the next executable work is not another `lower_call` guard, arena
scan, backend forwarder, or materialization-name tweak. The next work is an
architecture migration contract: state which legacy consumers must become
`StateScope`, `MaterializationRegistry`, `AstNodeRef`, or `CodePathStatus`
consumers before a behavior-changing fix is allowed.

Current next-slice decision after the Slice 0k-E hostile self-review: the
preferred `StateScopeConsumerCensus` is admissible only as a migration gate,
not as another diagnostic ladder. The report must classify every known
naming/materialization consumer by the authority it is allowed to read and must
emit a migration decision for that consumer. A report that only prints rows,
ambient maps, or suspicious examples remains diagnostic-only and authorizes no
behavior change.

Bounded context: Crystal V2 compiler architecture:

- HIR lowering and semantic registration (`src/compiler/hir/ast_to_hir.cr`)
- MIR construction and fact annotation (`src/compiler/mir/hir_to_mir.cr`)
- MIR type/fact model (`src/compiler/mir/mir.cr`)
- LLVM lowering (`src/compiler/mir/llvm_backend.cr`)

ProblemCardRef: reduce compiler cludginess after the current correctness
frontiers are closed. The goal is not to split large files because they are
large. The goal is to move each semantic decision to one owning boundary and
make later phases mechanical consumers of typed facts. Dead-code cleanup is
part of that goal, but only when the path is proven not to be a live semantic
carrier, bootstrap fallback, compatibility shim, or intentionally gated debug
surface.

2026-07-01 execution checkpoint: do not continue the bootstrap frontier as an
unbounded sequence of local consumer fixes. The latest read-only parse frontier
evidence showed generated s2 loading 138 raw `Loading:` paths that canonicalize
to 75 real files, while stage1 loads 75 raw / 75 canonical paths. A local
canonical-loaded-path WIP reduced the generated s2 registration graph
(`modules=224`, `classes=146`) but did not pass the bootstrap DoD: the fresh
s2 build still timed out after `pass3 after lower_main call` around allocator
flush. Treat that WIP as evidence for a `NameResolution/file identity` boundary,
not as a shipped fix. The transition gate now includes
`scripts/parse_path_identity_probe.sh`: stage1 is expected to pass raw/canonical
path parity, while the current generated s2 is expected to fail with duplicate
raw paths. The next behavior-changing bootstrap slice must either make this
probe pass for generated s2 or explicitly refute file identity as the active
frontier with fresher evidence.

2026-07-01 architecture-execution checkpoint after Slice 0f: the
`NodeSlotIntegrity` ledger refuted owner drift, out-of-range `ExprId`, and
missing/uninitialized slot for the instrumented `lower_call` edge, but it did
not yet name a behavior fix. That is the intended point to stop the diagnostic
ladder and update the architecture plan, not to automatically add another
probe. A payload/vtable/deep-read ledger remains an allowed falsifier only if
it is admitted as a named SDD slice with generated-stage evidence and a
cleanup plan. The default next track is architecture sealing:
`SemanticStateScope` / `MaterializationIdentity` identity records plus
`CodePathStatus` runtime census, so future behavior fixes consume owned facts
instead of chasing the latest crash stack.

2026-07-01 architecture-pause checkpoint after Slice 0h: the pre-call
`MaterializationIdentityTransaction` ledger is useful but not sufficient to
justify a behavior fix. It records `call_symbol_hint`, not the backend-proven
emitted call. A downstream emitted-call ledger remains admissible only if it is
framed as completing the transaction contract from Phase 2b. It is not
admissible as a backend undefined-extern rescue, a forwarder shortcut, or a
way to keep chasing the latest stub. Before the next production behavior
change, the plan must choose one of two architecture tracks: complete the
transaction identity contract, or build runtime `CodePathStatus` evidence for
cleanup and bloat reduction. Both tracks must preserve the same rule: no
compiler behavior changes until the owning semantic fact is named.

2026-07-01 runtime `CodePathStatus` checkpoint after Slice 0i: the first
runtime status ledger is deliberately limited to coarse CLI/compiler-driver
branches. It proves that `CodePathStatus` can collect observed branch status
without changing default compiler behavior, but it does not classify any
`ast_to_hir`, `hir_to_mir`, or backend semantic path as dead or
`delete_ready`. This slice chooses the cleanup/bloat evidence track for one
small executable step. It does not replace the transaction-completeness track
needed before call/materialization behavior patches.

2026-07-01 architecture checkpoint after Slice 0k-B: focused transaction
reports now carry selected-definition, state-scope, map-source, materialization
action, and emitted-call correlation fields. That does not yet make the full
generated-stage frontier transaction-complete. A fresh generated s2 compiling
full `src/adamas.cr` emitted HIR-side `[MAT_ID]` / `[MAT_TX]` rows through
`Adamas::Compiler::CLI#run$IO_IO`, then failed the transaction report with
`FAIL: no [MAT_EMIT] materialization emitted-call rows emitted` and
`compiler_rc=139`. This is a stop signal, not a backend fix invitation: the
full generated-stage run does not reach the emitted-call seam, so no
call/materialization behavior patch may consume backend/stub facts from this
probe. The next admitted work must either name the full-stage seam reachability
owner or start the `SemanticStateScope` shadow facade that replaces ambient
state reads with explicit authority records.

2026-07-01 architecture checkpoint after the `SemanticStateScope` shadow
ledger: the facade exists and self-applies in focused and generated-s2
no-prelude corridors, but the full generated-stage corridor still does not
reach backend emitted-call correlation. A full generated-s2 state-scope report
on `src/adamas.cr` emitted `11` valid owned rows and then exited `139` before
`[MAT_EMIT]`. An lldb run with the same ledger pinned the crash stack to
`NodeSlot#node <- AstArena#[] <- AstToHir#lower_call` while draining pending
lower functions. A fresh 8GB `NodeSlotIntegrity` report on the same corridor
emitted `639` rows with `healthy_present=639` and zero
`missing_node_payload`, `missing_slot`, `out_of_range`, `invalid_expr`, or
`null_expr` buckets. This refutes the next tempting consumer fixes for the
instrumented edge. The next admitted work is Slice 0k-E: an architecture
migration contract that names which existing state/name/AST/materialization
consumers will be migrated to typed owner facts, and which symptom fixes remain
rejected until that migration contract has executable gates.

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
  under only the target symbol is a failing state.

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

## 7. Execution order

### Phase 0: Bootstrap stabilization freeze

Do not start broad refactor while current `s2b`/`s3b` bug frontiers are moving.
Only add SDDs, probes, and small tactical fixes needed to restore the bootstrap
corridor.

Additional stop-rule after the 2026-07-01 checkpoint: a tactical fix is allowed
only when it names the owning semantic boundary and either consumes an existing
ledger row or adds a new behavior-neutral ledger/falsifier that will survive the
fix. If a slice only moves the crash/RSS frontier without adding an owner
boundary, stop and route the work to Phase 1 census.

Exit signal:

- `s2b` reaches a stable smoke target;
- `s3b` status is known;
- active frontiers have problem cards and reducers or smoke scripts.

### Phase 0b: Architecture transition gate

Purpose: prevent the bootstrap loop from becoming a tail-chase while still
allowing evidence-producing fixes.

Admitted work:

- read-only or docs-only owner ledgers;
- scripts that census semantic decision sites without changing compiler output;
- focused reducers that prove a boundary before a behavior change;
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
- `hash_named_tuple_index_assign_materialization_repro.sh` or successor -
  `Hash(UInt64, NamedTuple)#[]=` must not emit a call to a symbol whose body was
  materialized only under a different target symbol.
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

- task ledger: `TODO.md`
- existing architecture plan: `docs/compiler_refactor_architecture_plan.md`
- ABI frontier: `docs/abi_struct_value_sdd.md`,
  `docs/abi_struct_value_c_packet.md`, `docs/abi_cnarrow_a_placement_brief.md`,
  `docs/abi_cnarrow_b_load_brief.md`
- active code surfaces:
  - `src/compiler/hir/ast_to_hir.cr`
  - `src/compiler/mir/hir_to_mir.cr`
  - `src/compiler/mir/mir.cr`
  - `src/compiler/mir/llvm_backend.cr`
- falsifier matrix: `regression_tests/*_repro.sh`,
  `regression_tests/*_probe.sh`

## 11. Implementation seals

### Slice 0: StateScope and materialization identity ledger

Source/spec:

- `ast_to_hir.cr` type-param scope helpers (`with_type_param_map`,
  `with_isolated_type_param_map`, `function_type_param_map_for`),
- naming predicates such as `def_has_untyped_regular_param?`,
- `lower_function_if_needed_impl` requested/target/override seam,
- HIR/MIR call emission paths that can fall back to `ExternCall`.

Falsifiers:

- `Hash(UInt64, NamedTuple)#[]=` requested-symbol/body-symbol mismatch,
- mixed ambient-map census: leaked `K`/`V` rows vs legitimate
  current-instantiation rows,
- `T*` and short-type-param specialization controls.

Evidence:

- a ledger row per affected callsite containing requested symbol, target
  symbol, materialized symbol, emitted call symbol, selected definition,
  ambient map, target map, and selected state authority;
- preflight proves a proposed behavior patch's chosen symbol before code
  changes.

Boundary:

- no overload selection, ABI/layout, or backend emission changes;
- no force-`override=name` patch without ABI and symbol-identity evidence.

Next local track:

- CallResolution can consume `state_scope` once the ledger is stable.

### Slice 0a: Static semantic decision census

Source/spec:

- `scripts/semantic_decision_census.sh`
- this SDD's Phase 1/1b owner-map requirements

Falsifiers:

- the script must be read-only and must not require generated compiler
  artifacts;
- broad output is acceptable, but each section must point to concrete source
  paths and patterns;
- the script must not classify a path as dead or live by itself.

Evidence:

- checked-in script output can be captured in review logs;
- source sections cover `NameResolution`, `TypeIdentity`,
  `SemanticStateScope`, `CallResolution`, `Materialization`,
  `AbiFacts/LayoutContract`, backend semantic leakage, and debug/workaround
  gates.

Boundary:

- no compiler behavior changes;
- no deletion or refactor decisions from static grep alone.

Next local track:

- convert high-signal rows into dynamic ledgers, starting with
  `StateScope/materialization identity` or `NameResolution/file identity`.

### Slice 0b: Materialization identity dynamic ledger

Source/spec:

- `src/compiler/hir/ast_to_hir.cr` `lower_function_if_needed_impl`
  materialization seam;
- `scripts/materialization_identity_ledger_smoke.sh`.

Falsifiers:

- with `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1`, a small compile emits
  `[MAT_ID]` rows;
- each row contains requested symbol, target symbol, materialization state key,
  body symbol, call-symbol hint, override reason, lookup branch, ambient map,
  target map, and call arg types;
- with the env var off, this slice changes no compiler behavior.

Evidence:

- `scripts/materialization_identity_ledger_smoke.sh <compiler>` proves the
  ledger can be enabled without generated compiler artifacts;
- future bootstrap probes can filter `[MAT_ID]` rows for mismatches such as
  `state_key != body_symbol` or stale ambient-map authority.

Boundary:

- no call resolution, overload selection, ABI/layout, or backend emission
  changes;
- this ledger does not fix symbol mismatches by itself.

Next local track:

- run the ledger on the active s2b/s3b frontier and classify the first
  mismatch as `StateScope`, `Materialization`, `CallResolution`, or
  `NameResolution` before any behavior-changing fix.

### Slice 0c: Parse path identity dynamic probe

Source/spec:

- `scripts/parse_path_identity_probe.sh`;
- `parse_file_recursive` and require-path loading in `src/compiler/cli.cr`;
- the `NameResolution/file identity` owner boundary.

Falsifiers:

- a fresh stage1 compiler must report identical raw and canonical `Loading:`
  counts for `src/adamas.cr --no-prelude --verbose` under
  `ADAMAS_STOP_AFTER_PARSE=1`;
- a generated s2 compiler that parses the same source with duplicate raw paths
  must fail this probe and print representative raw aliases for the same
  canonical file;
- the probe must be read-only and must clean its own temporary directory.

Evidence:

- current stage1: `raw=75 canonical=75`, `PASS parse_path_identity`;
- pre-fix generated s2: `raw=138 canonical=75`,
  `DUPLICATE_PATH_IDENTITY`, including duplicate aliases such as
  `frontend/parser/../ast.cr`, `semantic/../frontend/ast.cr`, and
  `hir/../frontend/ast.cr` for the same canonical file;
- fixed generated s2: `raw=75 canonical=75`, `PASS parse_path_identity`.

Boundary:

- the probe itself does not canonicalize paths and does not change compiler
  behavior;
- the behavior slice owns only the loaded-source-file identity key. It does not
  change overload resolution, type identity, materialization, or backend
  emission;
- no later materialization or backend frontier may be claimed from this slice
  unless the generated compiler first passes raw/canonical path parity.

Next local track:

- use the now-green path-identity gate as the required precondition for the
  next owner-ledger step. The current residual generated-s2 frontier reaches
  materialization and then crashes in
  `NodeSlot#node <- AstArena#[] <- AstToHir#lower_call` while draining missing
  call targets.

### Slice 0d: AstNodeIdentity / ArenaOwnership census

Source/spec:

- `scripts/arena_ownership_census.sh`;
- `scripts/lower_call_arena_ledger_smoke.sh`;
- `src/compiler/hir/ast_to_hir.cr` arena helpers (`with_arena`,
  `arena_for_expr?`, `node_for_expr`, `node_for_call_expr`);
- raw `@arena[expr_id]` read sites in `lower_call` and related HIR lowering
  helpers.

Falsifiers:

- the census is read-only, grep/awk-based, and does not require generated
  compiler artifacts;
- output separately lists owner helpers, global raw arena reads, lower-call raw
  arena reads, and containment-heuristic sites;
- the census does not classify a raw read as safe or unsafe by itself.
- with `ADAMAS_LOWER_CALL_ARENA_LEDGER=1`, a small no-prelude call compile
  emits `[LC_ARENA]` phase and expr rows without dereferencing the logged node
  slots.

Evidence:

- `scripts/arena_ownership_census.sh` reports the static raw-read surface and
  identifies `lower_call` as the active residual frontier surface after the
  parse-path identity fix;
- `scripts/lower_call_arena_ledger_smoke.sh <compiler>` proves the dynamic
  ledger channel is available without generated compiler artifacts;
- the next dynamic ledger must bind a crashing/generated `ExprId` to a
  preferred arena and current arena without dereferencing the node slot.
- current generated-s2 evidence produced `475` `[LC_ARENA]` rows and `11`
  `[MAT_ID]` rows before `EXIT 139`; the final observed lower-call row had
  current, preferred, and heuristic owner all on the same `src/compiler/cli.cr`
  arena with `*_has=1`, which refutes a simple current-arena-drift explanation
  for that last observed edge but does not yet prove the producer root.

Boundary:

- no HIR behavior changes;
- no replacement of raw reads with broad `arena_for_expr?` scans from this
  slice alone;
- no claim that `NodeSlot#node` corruption is an arena-ownership bug until a
  dynamic ledger proves the first bad transition.

Next local track:

- consume the dynamic `lower_call` arena ledger to classify the first bad
  transition as current-arena drift, stale/corrupt `ExprId`, `NodeSlot`/arena
  storage corruption, or an uninstrumented raw read;
- if the ledger continues to show current/preferred/owner agreement, introduce
  a behavior-neutral `AstNodeRef` / `ArenaOwnership` facade instead of patching
  another `lower_call` consumer.

### Slice 0e: AstNodeRef shadow facade

Source/spec:

- `src/compiler/hir/ast_to_hir.cr` `AstNodeRef`;
- `ADAMAS_LOWER_CALL_ARENA_LEDGER=1` lower-call arena ledger;
- `scripts/lower_call_arena_ledger_smoke.sh`;
- `scripts/lower_call_arena_parity_report.sh`.

Falsifiers:

- `AstNodeRef` is a reference type, not a struct carrying `ArenaLike`, because
  generated-stage binaries have shown fragile copies of ArenaLike-bearing
  structs;
- the facade is allocated only under the env-gated ledger path and is not
  consumed by lowering decisions;
- ledger rows contain explicit ref origin/span/path data in addition to current
  arena and heuristic owner data;
- default env-off compile emits no `[LC_ARENA]` rows;
- the parity report must treat compiler nonzero exit as reportable data when
  `[LC_ARENA]` rows exist, so generated-stage crashes can still produce owner
  classification evidence.

Evidence:

- the lower-call ledger now records explicit owner-scoped references before raw
  AST reads, while preserving the legacy raw reads untouched;
- focused smoke requires `[LC_ARENA]` expr/phase rows plus `ref_origin=` and
  `ref_span=`;
- `scripts/lower_call_arena_parity_report.sh <compiler>` summarizes
  `current`, explicit `AstNodeRef` owner, and heuristic owner parity into
  `agree_all_have`, missing-has, and divergence buckets;
- fresh generated s2->s3 evidence with the parity report produced
  `compiler_rc=139`, `phase_rows=265`, `expr_rows=210`,
  `agree_all_have=210`, and zero divergence buckets. The last expr row before
  the crash was `Adamas::Compiler::CLI#run$IO_IO`
  `before.member_object_read`, with current arena, explicit ref owner, and
  heuristic owner all equal to the same `src/compiler/cli.cr` arena and all
  `*_has=1`.

Boundary:

- no HIR behavior changes;
- no routing through `AstNodeRef` yet;
- no replacement of raw reads until a follow-up ledger classifies the first bad
  transition and a parity check proves the replacement is not another
  containment heuristic.

Next local track:

- use the facade to add a shadow parity report for lower-call raw reads:
  `current`, explicit `AstNodeRef` owner, and heuristic owner must be compared
  before any consumer read is routed through the facade;
- run the parity report on the generated s2->s3 frontier before any raw-read
  routing change; the report should classify whether the crash-edge rows show
  owner agreement, current-vs-ref divergence, heuristic divergence, or missing
  ownership evidence;
- because parity shows owner agreement at the crash edge, move the next
  read-only investigation to `NodeSlot` / arena storage producer corruption or
  an uninstrumented raw read, not to another arena-selection consumer patch.

### Slice 0f: NodeSlotIntegrity / AstArenaStorage ledger

Source/spec:

- `src/compiler/frontend/ast_arena.cr` and related `NodeSlot`/arena storage
  definitions;
- `src/compiler/hir/ast_to_hir.cr` raw AST-read callsites that already have
  current/ref/heuristic owner parity;
- generated-stage crash corridor
  `NodeSlot#node <- AstArena#[] <- AstToHir#lower_call`.
- `scripts/node_slot_integrity_report.sh`.

Falsifiers:

- the ledger must be env-gated and behavior-neutral when disabled;
- it must log slot facts before the crashing read dereferences the node:
  arena owner, `ExprId`, index range, slot initialization/presence, safe
  node-kind/span facts when available, and read site;
- it must distinguish "owner selected correctly but slot is corrupt/missing"
  from "read site was never instrumented";
- it must not scan all arenas as a substitute for naming the producer.

Evidence required before any behavior change:

- a no-prelude stage1 smoke proves the ledger channel without generated
  compiler artifacts;
- generated s2->s3 report names the first bad transition as one of:
  stale/corrupt `ExprId`, missing/uninitialized `NodeSlot`, node payload
  corruption, or uninstrumented raw read;
- if all slot facts are healthy at the crash edge, the next slice must move
  upstream to the producer of the `ExprId` or downstream to the exact
  uninstrumented consumer, not add a lower-call arena routing patch.

Boundary:

- no HIR behavior changes;
- no parser or arena allocation rewrite;
- no `lower_call` consumer route through `AstNodeRef` until this ledger names
  the first bad transition.

Next local track:

- implement the env-gated ledger and report script, then rerun the generated
  s2->s3 crash corridor under `scripts/run_safe.sh`;
- only after the ledger names a producer boundary may a bounded behavior slice
  be designed.

Current evidence:

- `scripts/node_slot_integrity_report.sh /private/tmp/adamas_nodeslot_stage1`
  on a no-prelude call reports `rows=9`, `healthy_present=9`, and zero
  non-healthy buckets;
- with no env gate, the same no-prelude compile emits no `[NODE_SLOT]` rows;
- a fresh generated s2 built by the stage1 with this ledger exits 0 under
  `scripts/run_safe.sh`;
- generated s2->s3 with `ADAMAS_NODE_SLOT_LEDGER=1` returns
  `compiler_rc=139`, `rows=630`, `healthy_present=630`, and zero
  `missing_node_payload`, `missing_slot`, `out_of_range`, `invalid_expr`, or
  `null_expr` buckets. The last row before the crash is the same
  `Adamas::Compiler::CLI#run$IO_IO` `before.member_object_read` edge,
  `expr=2828`, with `in_range=1`, `slot_present=1`, and `node_present=1`.

Interpretation:

- this refutes missing/uninitialized slot and out-of-range `ExprId` for the
  currently instrumented crash edge;
- it does not prove the payload/vtable/node-kind read is healthy, because the
  default ledger intentionally avoids dereferencing the node payload;
- payload/vtable/deep node read integrity or the exact uninstrumented consumer
  after `NodeSlot#node` remains the allowed local falsifier for this crash
  corridor, but it is no longer an automatic next step. After this diagnostic
  ladder refuted three local hypotheses, the default next step is an
  architecture-sealing checkpoint unless the payload/deep-read work is promoted
  into a named SDD slice with generated-stage evidence, residual boundary, and
  cleanup rule.

### Slice 0g: Architecture execution checkpoint after diagnostic ladders

Source/spec:

- this SDD's Phase 0b stop rules;
- `TODO.md` active backlog;
- `LANDMARKS.md` active bootstrap gate;
- any uncommitted diagnostic WIP that exists when a checkpoint starts.

Falsifiers:

- `git status --short --branch` must be checked before planning;
- uncommitted probe code is either committed as a named SDD slice with evidence
  or removed before architecture planning continues;
- the plan must name whether the next work is a local falsifier, a typed facade,
  a runtime dead-code census, or a behavior slice;
- behavior slices remain rejected unless they consume an existing owner ledger
  or add one in the same logical change.

Evidence:

- the first application removed an uncommitted `ADAMAS_NODE_PAYLOAD_LEDGER` WIP
  because it had no SDD slice, no completed generated-stage evidence, and no
  cleanup rule;
- the committed Slice 0f evidence remains the last verified crash-edge ledger:
  `compiler_rc=139`, `rows=630`, `healthy_present=630`, and zero non-healthy
  `NodeSlot` buckets.

Boundary:

- this slice does not change compiler behavior;
- it does not declare `s2b`/`s3b` green;
- it does not forbid future payload/deep-read probes, but requires them to be
  explicit SDD slices instead of tail-chase continuation.

Next local track:

- seal the `SemanticStateScope` / `MaterializationIdentity` transaction record
  enough that future call/materialization fixes consume a single identity fact;
- add a runtime `CodePathStatus` census before deleting stale workarounds or
  debug gates;
- only then pick the next bounded behavior slice or local payload/deep-read
  falsifier.

### Slice 0h: Materialization pre-call transaction ledger

Source/spec:

- `src/compiler/hir/ast_to_hir.cr` `lower_function_if_needed_impl`
  materialization seam;
- `MaterializationIdentityTransaction` debug record;
- `scripts/materialization_identity_ledger_smoke.sh`;
- `scripts/materialization_transaction_report.sh`.

Falsifiers:

- before the slice exists, the transaction report must fail closed with
  `FAIL: no [MAT_TX] materialization transaction rows emitted`;
- with `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1`, a small compile emits both
  the legacy `[MAT_ID]` row and the structured `[MAT_TX]` row;
- each `[MAT_TX]` row has parseable `identity_status`, `symbol_relation`, and
  `required_contract` fields;
- with the env var off, the compiler emits no `[MAT_TX]` rows and default
  behavior is unchanged.

Evidence:

- the first stage1 report classified `2513` materialization transactions:
  `2504` exact rows and `9` `body_eq_target_call_eq_requested` rows requiring
  `wrapper_or_call_remap`;
- the report found `0` malformed rows and grouped rows by phase, identity
  status, symbol relation, and required contract;
- full stage1 regression suites passed after the ledger change:
  `152/152` original tests and `36/36` combined tests.
- a fresh generated s2 compiled a no-prelude report repro with `1` exact
  `[MAT_TX]` row and `0` malformed rows.

Boundary:

- this is a pre-call materialization transaction ledger. It records
  `call_symbol_hint`, not a backend-proven final emitted call symbol;
- it does not emit wrappers, remap calls, change pending-function replay, or
  fix any `s2b`/`s3b` frontier by itself;
- a future behavior patch that changes requested/target/body/call symbol
  selection must either upgrade this transaction to include the final emitted
  call symbol or consume a downstream ledger that proves the emitted call
  contract.

Next local track:

- connect the transaction record to final call emission, or add a sibling
  emitted-call ledger at the HIR/MIR boundary, only when the slice is explicitly
  framed as transaction-completeness evidence from Phase 2b;
- do not use backend undefined-extern stubs as the first authority for
  requested/target/body/call identity. If backend visibility is required, the
  slice must also prove that the target body still exists before backend
  emission and that the backend is not re-running source-level resolution;
- add runtime `CodePathStatus` evidence before deleting stale workarounds or
  old debug gates;
- do not continue to the next crash stack unless the new slice consumes an
  owned transaction row or explicitly adds an owner ledger/falsifier that
  survives the fix.

### Slice 0i: Architecture pause and next-track selection

Source/spec:

- this SDD's Phase 0b stop rules;
- `TODO.md` active backlog;
- `LANDMARKS.md` active bootstrap gate;
- static census scripts:
  `scripts/semantic_decision_census.sh` and
  `scripts/codepath_status_census.sh`.

Falsifiers:

- `git status --short --branch` must be checked before choosing the next
  implementation slice;
- stale uncommitted probes must be removed or promoted to a named SDD slice
  before planning continues;
- static census scripts must still run successfully and must not classify
  anything as live/dead/delete-ready by themselves;
- the plan must name whether the next work is transaction-completeness,
  runtime `CodePathStatus`, a local falsifier, or a behavior slice.

Evidence:

- current static census scale is broad enough to reject ad hoc cleanup:
  `SemanticStateScope` rows are counted separately from
  `Materialization`, `CallResolution`, backend semantic leakage, and
  debug/workaround surfaces;
- current `CodePathStatus` census reports large env/debug, fallback/recovery,
  legacy/shim, semantic-scan, backend-leakage, and layout/ABI candidate
  surfaces, but remains static-only.

Boundary:

- this slice is docs/plan-only and changes no compiler behavior;
- it does not declare `s2b`/`s3b` green;
- it does not forbid final-call linkage, payload/deep-read probes, or
  behavior fixes. It requires each of those to be selected as an architecture
  track, not as a reaction to the latest crash/stub.

Next local track:

1. Prefer runtime `CodePathStatus` if the next goal is reducing bloat,
   deleting stale gates, or retiring workarounds.
2. Prefer transaction-completeness if the next goal is a call/materialization
   behavior fix. The slice must prove requested, selected, target, body,
   emitted call, state-scope authority, and ABI shape as one owned fact.
3. Prefer a local falsifier only if a fresh generated-stage frontier invalidates
   the current owner ledgers or exposes a new uninstrumented boundary.

### Slice 0j: Runtime CodePathStatus CLI ledger

Source/spec:

- `src/compiler/cli.cr` coarse compiler-driver control flow;
- `scripts/codepath_status_runtime_report.sh`;
- static Phase 1b census script `scripts/codepath_status_census.sh`.

Falsifiers:

- before the runtime ledger exists, the report script must fail closed with
  `FAIL: no [CODEPATH_STATUS] runtime rows emitted`;
- with `ADAMAS_CODEPATH_STATUS_LEDGER=1`, a no-prelude compile must emit
  parseable `[CODEPATH_STATUS]` rows with no malformed rows;
- without `ADAMAS_CODEPATH_STATUS_LEDGER`, the same compile must emit no
  `[CODEPATH_STATUS]` rows;
- broad stage1 regression suites must remain green, because this is
  behavior-neutral instrumentation.

Evidence:

- a fresh stage1 build with this slice passed;
- the focused runtime report on a no-prelude `x = 1` compile produced
  `rows=26`, `malformed=0`, `taken=8`, and `not_taken=18`;
- the default env-off no-prelude compile emitted no `[CODEPATH_STATUS]` rows;
- static semantic and CodePathStatus census scripts still run;
- full stage1 suites passed: `152/152` original regression tests plus `36/36`
  combined tests;
- a fresh generated s2 build exited `0`, and the generated s2 emitted the same
  focused no-prelude runtime report shape: `rows=26`, `malformed=0`.

Boundary:

- this slice records runtime status only for coarse CLI/compiler-driver
  branches such as parser mode, semantic gates, HIR/MIR driver gates, metrics,
  cache, and stop-after gates;
- it is not delete-ready proof and must not drive code removal by itself;
- it does not change overload, materialization, ABI, backend, or AST ownership
  behavior;
- it does not declare `s2b`/`s3b` green.

Next local track:

- if continuing cleanup/bloat work, extend runtime `CodePathStatus` only for a
  named cluster from the static census and pair every `suspected_dead` row with
  a protecting falsifier before deletion;
- if continuing bootstrap correctness work, return to
  `SemanticStateScope` / `MaterializationIdentity` transaction-completeness:
  requested symbol, selected definition, target symbol, created body, emitted
  call, state-scope authority, and ABI shape must be one owned fact before the
  next behavior-changing call/materialization patch.

### Slice 0k: Transaction-completeness execution plan

Status:

- Slice 0k-A default-off transaction-correlation channel implemented;
- no production behavior change is admitted by this slice;
- behavior-changing call/materialization fixes remain blocked until a targeted
  row is classified by the completed transaction contract.

Source/spec:

- `MaterializationIdentityTransaction` rows from Slice 0h;
- `src/compiler/hir/ast_to_hir.cr` call resolution, pending lowering, and
  materialization sites;
- `src/compiler/mir/hir_to_mir.cr` HIR call to MIR call lowering;
- `src/compiler/mir/llvm_backend.cr` final call/extern-call emission;
- `scripts/materialization_transaction_report.sh`.

Problem:

- Slice 0h records a pre-call `call_symbol_hint`, but not the final backend
  callee that is actually emitted;
- without the emitted callee and ABI shape, a behavior patch can still confuse
  requested symbol, target symbol, body symbol, backend call symbol, and
  wrapper/keepalive policy;
- backend undefined-extern stubs are too late to discover this semantic
  mismatch, because target HIR/MIR bodies may already have been pruned.

Required transaction fields before a behavior patch:

- request symbol;
- selected definition identity;
- target materialization symbol;
- created body symbol;
- emitted call symbol;
- state-scope authority used for naming and type-param maps;
- target-materialization map;
- callsite arg types;
- ABI shape used at the emitted call;
- admitted contract: `exact`, `materialization_keepalive`,
  `wrapper_forwarder`, or `rejected_mismatch`.

Falsifiers:

- the transaction report must fail closed when it cannot link a requested
  symbol to a final emitted call symbol for a call/materialization candidate;
- the known `Hash(UInt64, NamedTuple)#[]=` corridor must classify as an
  explicit contract, not as a backend stub surprise;
- current-instantiation remangle cases must remain distinct from leaked
  ambient state-scope cases;
- stage1 and generated-s2 no-prelude reports must emit parseable transaction
  rows with zero malformed rows;
- no behavior change is allowed until this report can name the contract for the
  targeted behavior slice.

Rejected implementation moves:

- emitting backend forwarders from `@undefined_externs` as the first point of
  semantic discovery;
- forcing materialization to the requested name without proving ABI agreement;
- globally ignoring ambient `@type_param_map` in naming decisions;
- relying on `CodePathStatus` runtime liveness rows as a substitute for
  transaction identity.

Next local implementation step:

- upgrade the existing materialization transaction report, or add a sibling
  emitted-call transaction report, so one report can join requested, target,
  body, emitted call, state-scope authority, and ABI shape for focused stage1
  and generated-s2 runs;
- only after that, choose the first behavior slice that consumes the completed
  transaction as its owner fact.

Hostile self-review of the next step:

- continuing Slice 0k is architecture work only if the emitted-call evidence
  is joined to a HIR-owned transaction identity. It is tail-chasing if it is a
  standalone backend log keyed by `@undefined_externs`, `@func_by_name`, or
  "whatever crashed next";
- the backend is allowed to report the final callee and ABI shape, but it must
  not create or repair the semantic transaction. The transaction owner is
  materialization/state-scope, not LLVM undefined-extern recovery;
- a report row that cannot tie emitted call back to request, selected def,
  target symbol, body symbol, and state-scope authority is evidence of an
  incomplete transaction, not a reason to emit a backend wrapper;
- broad emitted-call rows are acceptable only as diagnostics. The contract
  gate is the subset whose transaction id links every required field and
  classifies the row as `exact`, `materialization_keepalive`,
  `wrapper_forwarder`, or `rejected_mismatch`;
- if implementing the report requires reconstructing source-level facts in
  the backend, the slice fails the architecture gate and must pivot back to
  `SemanticStateScope` / `MaterializationRegistry`.

Implementation guard for the first code slice:

- introduce a default-off transaction-correlation channel, not a behavior
  change;
- give each HIR materialization transaction a stable debug identity that can be
  carried or re-emitted at HIR/MIR/backend seams;
- make HIR/MIR call lowering preserve the transaction identity when it lowers a
  transaction-bound call, and mark non-transaction calls explicitly rather than
  inferring ownership from a mangled string;
- make backend emission log only mechanical facts: emitted callee, return/arg
  ABI shape, extern-vs-crystal call kind, and whether the callee body is present
  in the backend function table;
- update the report to fail closed on missing joins, malformed rows, or any
  silent requested/target/body/emitted mismatch without an admitted contract;
- keep env-off output and behavior unchanged.

Slice 0k-A preflight plan:

- `transaction-bound call` means a HIR-owned materialization transaction already
  exists for the request, and the call lowering path can carry or re-emit that
  transaction identity without deriving ownership from a backend string table.
  Broad backend call rows are allowed as diagnostics, but they are not the gate.
- `non-transaction call` must be reported explicitly as outside the contract
  (`tx=none` or equivalent). It must not be silently promoted into a
  transaction by matching only the mangled callee name.
- The first code slice must be red before it is green: the report is upgraded
  first so a compiler that emits only Slice 0h `[MAT_TX]` rows fails with a
  missing emitted-call correlation signal. Only then may the code add
  default-off correlation rows.
- The intended first implementation shape is:
  1. add a stable debug id to `MaterializationIdentityTransaction`;
  2. expose a HIR-owned transaction lookup/attachment point for call lowering;
  3. carry the id through HIR-to-MIR call/extern-call lowering where the call is
     transaction-bound;
  4. let backend emission log only mechanical `[MAT_EMIT]` facts:
     transaction id or `none`, emitted callee, call kind, return/arg ABI shape,
     and body-present status;
  5. make `scripts/materialization_transaction_report.sh` join `[MAT_TX]` and
     `[MAT_EMIT]` rows and fail closed on malformed transaction-bound joins.
- Minimal green evidence for Slice 0k-A is deliberately narrower than green
  `s2b`/`s3b`: focused stage1 and generated-s2 no-prelude reports must contain
  parseable `[MAT_TX]` rows, parseable `[MAT_EMIT]` rows, at least one joined
  transaction-bound emitted call, zero malformed transaction rows, and no
  default-env output change.
- The resulting report may classify many calls as non-transaction diagnostics.
  That is acceptable only if the contract gate remains the joined
  transaction-bound subset and if a targeted behavior slice later consumes a
  joined row rather than a backend-only row.

Stop conditions for the first code slice:

- more than a small focused set of rows requires a wrapper/forwarder contract
  before the report can classify them;
- the only way to identify real stub rows is to wait until backend
  `@undefined_externs` after HIR/MIR has already pruned target bodies;
- the implementation would preserve target bodies by marking broad candidate
  sets live without proving they are transaction-bound;
- the report can observe emitted calls but cannot name selected definition or
  state-scope authority for the same transaction.
- carrying the transaction id requires reconstructing source-level request,
  overload, or state-scope facts in `llvm_backend.cr`;
- the upgraded report's only useful failure signal is "backend emitted a dead
  stub" rather than "a HIR-owned transaction failed to link to emitted-call
  facts";
- the joined transaction-bound subset is empty for focused stage1 or
  generated-s2 no-prelude runs after the implementation.

Slice 0k-A evidence:

- red gate: after upgrading `scripts/materialization_transaction_report.sh`, a
  Slice 0h-only compiler built as `/private/tmp/adamas_txcorr_red` fails with
  `FAIL: no [MAT_EMIT] materialization emitted-call rows emitted` while still
  emitting `[MAT_TX]` rows;
- implementation: `MaterializationIdentityTransaction` now emits a stable
  `tx=` id, `HIR::Module` records the HIR-owned call-symbol to transaction-id
  lookup, MIR `Call` / `ExternCall` carry an optional
  `materialization_tx_id`, HIR-to-MIR call lowering preserves that id for
  direct transaction-bound calls, and backend call emission emits default-off
  `[MAT_EMIT]` mechanical rows under
  `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1`;
- focused stage1 report:
  `scripts/materialization_transaction_report.sh
  /private/tmp/adamas_txcorr_stage1` reports `rows=2513`,
  `malformed=0`, `emit_rows=16995`, `malformed_emit=0`,
  `transaction_bound_emit_rows=5332`, `non_transaction_emit_rows=11663`,
  `joined_transactions=1349`, and `unjoined_emit_rows=0`;
- default-env check: compiling a focused Box reducer with the same stage1
  compiler and no ledger env emits no `[MAT_ID]`, `[MAT_TX]`, or `[MAT_EMIT]`
  rows;
- generated-s2 no-prelude report:
  `scripts/materialization_transaction_report.sh /private/tmp/adamas_txcorr_s2
  /private/tmp/adamas_txcorr_np.cr --no-prelude -o
  /private/tmp/adamas_txcorr_np.bin` reports `rows=1`, `emit_rows=2`,
  `transaction_bound_emit_rows=1`, `joined_transactions=1`, and
  `unjoined_emit_rows=0`;
- broad guard: `regression_tests/run_all_suites.sh
  /private/tmp/adamas_txcorr_stage1 4` passes `152/152` original and `36/36`
  combined tests.

Residual boundary after Slice 0k-A:

- broad `[MAT_EMIT] tx=none` rows are diagnostics only; they must not drive a
  behavior patch;
- the report now proves correlation is possible, but it does not by itself fix
  `Hash(UInt64, NamedTuple)#[]=`, `@type_param_map` authority, or any current
  generated-stage crash;
- the next behavior slice must choose a targeted transaction-bound row or add a
  `SemanticStateScope` / `MaterializationRegistry` owner record if the row still
  lacks selected-definition or state-authority evidence.

### Slice 0k-B: StateScope-authorized materialization transaction plan

Status:

- Slice 0k-B default-off selected-definition and state-scope owner fields
  implemented;
- no compiler behavior change is admitted by this slice.

Problem:

- Slice 0k-A links a HIR-owned transaction id to emitted backend call facts, but
  the id is still attached by call symbol and does not itself prove which
  selected definition, state-scope authority, or materialized body owner
  created the row;
- using a joined `[MAT_TX]` / `[MAT_EMIT]` row alone would still allow a
  consumer patch to treat a symptom as root when the real boundary is ambient
  state authority or materialization registry ownership;
- the known `Hash(UInt64, NamedTuple)#[]=` corridor requires distinguishing
  three facts in one record: selected stdlib `Hash#[]=` definition,
  requested/call symbol, and target/body symbol chosen under a state-scope
  decision.

Required owner fields before behavior changes:

- selected definition identity: source file, line/column when available,
  declaring owner, method name, and declared parameter annotations;
- state-scope authority used by the naming/materialization decision:
  `callsite`, `target_materialization`, `body_substitution`,
  `current_instantiation`, or `ambient_rejected`;
- map source and map keys: ambient map snapshot, target-materialization map,
  callsite arg types, and the reason one map was authoritative;
- materialization registry action: created body, reused body, keepalive-only,
  pending/deferred, or rejected mismatch;
- final emitted call facts from Slice 0k-A: call kind, emitted symbol, return
  type, arg ABI shape, and backend body-present bit.

Implementation preflight for the next code slice:

1. extend the existing materialization transaction report, or add a sibling
   state-scope transaction report, so a single transaction id can print the
   fields above without deriving source-level semantics in `llvm_backend.cr`;
2. make the report classify each targeted transaction as one of:
   `exact`, `materialization_keepalive`, `wrapper_forwarder`,
   `state_scope_rejected`, or `rejected_mismatch`;
3. run the report first on focused stage1 and generated-s2 no-prelude cases,
   then on the known `@block_owner Hash#[]=` frontier if the generated-stage
   run reaches that seam;
4. require a negative control where current-instantiation remangle is
   legitimate, such as an `Array(Bool)`/`Array(Int32)` style generic method
   call, so the slice does not globally reject ambient maps that are actually
   owned by the current instantiation.

Stop conditions:

- the only available discriminator is backend `@undefined_externs`,
  `@func_by_name`, or final stub emission;
- the proposed fix would force `override=name` or force materialization to the
  requested symbol without selected-definition and ABI evidence;
- the proposed fix globally ignores `@type_param_map` or globally treats short
  type parameters as unbound;
- the owner fields require source-level reconstruction in backend code;
- the first would-change census for a behavior patch is wider than the
  targeted row set and cannot classify unrelated rows as legitimate.

Minimal evidence before the first behavior slice:

- focused stage1 transaction report includes selected-definition and
  state-scope fields with zero malformed owner rows;
- generated-s2 no-prelude report includes at least one joined transaction with
  selected-definition and state-scope fields;
- static semantic and CodePathStatus censuses still pass;
- the SDD/TODO/LANDMARKS ledger names the exact first behavior row to consume,
  or explicitly states why the next slice remains behavior-neutral.

Slice 0k-B evidence:

- red gate: a Slice 0k-A compiler built as `/private/tmp/adamas_0kb_red`
  already emitted joined `[MAT_TX]` / `[MAT_EMIT]` rows, but the upgraded
  report failed with `owner_malformed=2513`;
- implementation: `[MAT_TX]` rows now include `selected_def`, `state_scope`,
  `map_source`, and `materialization_action`, all produced at the HIR
  materialization seam; backend `[MAT_EMIT]` rows remain mechanical and do not
  reconstruct source-level owner facts;
- focused stage1 report:
  `scripts/materialization_transaction_report.sh /private/tmp/adamas_0kb_stage1`
  reports `rows=2513`, `emit_rows=16995`, `owner_malformed=0`,
  `joined_transactions=1349`, and `unjoined_emit_rows=0`;
- focused stage1 owner buckets: `state_scope` reports `callsite=871` and
  `target_materialization=1642`; `map_source` reports
  `callsite_arg_types=871`, `target_map=1165`,
  `ambient_snapshot_rejected=238`, and `empty_map=239`;
- default-env check: compiling a focused Box reducer with no ledger env emits
  no `[MAT_ID]`, `[MAT_TX]`, or `[MAT_EMIT]` rows;
- generated-s2 no-prelude report:
  `scripts/materialization_transaction_report.sh /private/tmp/adamas_0kb_s2
  /private/tmp/adamas_0kb_np.cr --no-prelude -o
  /private/tmp/adamas_0kb_np.bin` reports `rows=1`, `emit_rows=2`,
  `owner_malformed=0`, `joined_transactions=1`, and `unjoined_emit_rows=0`;
- static guards: `scripts/semantic_decision_census.sh` and
  `scripts/codepath_status_census.sh` still pass.
- broad guard: `regression_tests/run_all_suites.sh
  /private/tmp/adamas_0kb_stage1 4` passes `152/152` original and `36/36`
  combined tests.

Residual boundary after Slice 0k-B:

- owner fields are diagnostic and default-off; they do not change
  materialization, state-scope isolation, or backend emission;
- `ambient_snapshot_rejected` means ambient state was observed as a rejected
  snapshot, not accepted as authority;
- the next behavior slice is still blocked until it chooses a targeted
  transaction row and proves the first would-change set is not wider than the
  classified row set;
- this does not make `Hash(UInt64, NamedTuple)#[]=` fixed and does not make
  `s2b`/`s3b` green.

### Slice 0k-C: Post-0k-B generated-stage checkpoint and next-slice selection

Status:

- docs-only stop/checkpoint slice;
- no compiler behavior change is admitted by this slice;
- current decision: do not continue 0k as another backend or forwarder
  diagnostic ladder.

Source/spec:

- Slice 0k-A/0k-B transaction reports;
- full generated-s2 run compiling `src/adamas.cr`;
- this SDD's stop rules for backend-only semantic discovery;
- `TODO.md` and `LANDMARKS.md` active bootstrap ledgers.

Fresh evidence:

- a fresh stage1 built a fresh generated s2 with the 0k-B owner fields;
- the generated s2 full transaction report returned `compiler_rc=139`;
- the report failed with
  `FAIL: no [MAT_EMIT] materialization emitted-call rows emitted`;
- the run emitted HIR-side `[MAT_ID]` / `[MAT_TX]` rows through
  `Adamas::Compiler::CLI#run$IO_IO`;
- the crash happened before backend emitted-call correlation was available.

Interpretation:

- focused stage1 and generated-s2 no-prelude transaction reports prove the
  transaction machinery is present and default-off, but only in those focused
  corridors;
- the full generated-stage frontier currently stops before the emitted-call
  seam, so the completed transaction contract is not yet available for a
  full-stage behavior slice;
- a backend `@undefined_externs`, `@func_by_name`, stub, keepalive, or
  forwarder patch would be a symptom fix unless a HIR-owned transaction row
  reaches and classifies that seam first.

Next allowed architecture moves:

1. `SemanticStateScope` shadow facade:
   introduce an explicit behavior-neutral record for naming/materialization
   authority decisions, compare it against current ambient-map decisions, and
   fail closed on unowned ambient reads. This is the preferred next correctness
   architecture slice because repeated frontiers trace back to mutable ambient
   state being treated as authority.
2. Full-stage seam-reachability owner slice:
   if the next step targets the current `compiler_rc=139`, it must name the
   first owner boundary that prevents generated s2 from reaching `[MAT_EMIT]`.
   It must not use backend stubs as the first semantic discovery point.
3. Runtime `CodePathStatus` extension:
   admissible only for cleanup/bloat work on a named cluster. It must not be
   used as a substitute for semantic transaction identity.

Stop conditions:

- another report slice is proposed without saying which semantic owner it will
  make explicit;
- the proposed fix consumes only backend emitted/stub facts from a run that did
  not reach a joined HIR-owned transaction;
- the would-change census is wider than the classified owner row set;
- the patch touches `@block_owner`, changes it back to a tuple/namedtuple
  carrier, or relies on NamedTuple/Tuple string normalization as the root fix.

Minimal evidence before resuming behavior fixes:

- a named owner boundary for the next behavior row;
- a red/green focused falsifier for that boundary;
- a would-change census with unrelated rows classified as legitimate or
  rejected before code changes;
- static semantic and CodePathStatus censuses still pass;
- generated-s2 evidence either reaches a joined transaction row for the target
  or explicitly names why the next slice is still behavior-neutral.

### Slice 0k-D: SemanticStateScope shadow ledger

Status:

- default-off behavior-neutral shadow ledger implemented;
- no state-scope behavior, materialization behavior, backend behavior, or
  type-param-map lifetime is changed by this slice.

Source/spec:

- `src/compiler/hir/ast_to_hir.cr` materialization seam;
- `scripts/semantic_state_scope_report.sh`;
- `SemanticStateScope` target architecture in section 6.4;
- Slice 0k-C stop rule: make semantic authority explicit before behavior
  fixes.

Red gate:

- before the slice, `scripts/semantic_state_scope_report.sh <compiler>` fails
  with `FAIL: no [STATE_SCOPE] semantic state-scope rows emitted`.

Implementation:

- `ADAMAS_SEMANTIC_STATE_SCOPE_LEDGER=1` emits `[STATE_SCOPE]` rows at the HIR
  materialization seam;
- each row carries transaction id, phase, requested symbol, target symbol,
  selected definition identity, explicit authority, map source,
  allowed/forbidden consumers, lifetime region, validation status, ambient map,
  target map, callsite arg types, override reason, and lookup branch;
- the new ledger env is independent from
  `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER`. Enabling only the state-scope ledger
  does not remember backend transaction ids and does not emit `[MAT_ID]`,
  `[MAT_TX]`, or `[MAT_EMIT]`;
- the existing materialization transaction report remains compatible when only
  `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1` is enabled.

Focused evidence:

- fresh stage1 build passes;
- focused state-scope report emits `rows=2513`, `malformed=0`,
  `invalid_validation=0`, and `rejected_without_ambient=0`;
- authority buckets match the current owner classification:
  `callsite=871` and `target_materialization=1642`;
- map-source buckets are `callsite_arg_types=871`, `target_map=1165`,
  `ambient_snapshot_rejected=238`, and `empty_map=239`;
- default env-off focused compile emits no `[STATE_SCOPE]` or materialization
  ledger rows;
- the existing materialization transaction report still emits joined
  `[MAT_TX]` / `[MAT_EMIT]` rows with `owner_malformed=0`;
- full stage1 suites pass `152/152` original tests and `36/36` combined tests;
- fresh stage1 builds fresh generated s2, and generated-s2 no-prelude
  state-scope report emits `rows=1`, `malformed=0`,
  `invalid_validation=0`, and `rejected_without_ambient=0`.

Boundary:

- this is an observability/facade slice only. It does not isolate
  `@type_param_map`, does not change naming/materialization, and does not fix
  `Hash(UInt64, NamedTuple)#[]=`;
- `target_materialization` rows without a target map are diagnostic, not
  malformed, because non-generic target materialization can be authoritative
  without a type-param map;
- `ambient_snapshot_rejected` rows identify places where ambient mutable state
  was observed as a rejected snapshot, not accepted as authority.

Next local track:

- run the state-scope report on generated-s2 no-prelude and, if the full
  generated-stage run reaches this seam, on the full frontier;
- before any behavior change, add a would-change census that names which
  `[STATE_SCOPE]` rows would change and classifies unrelated rows as legitimate
  current-instantiation or rejected ambient snapshots;
- if the full generated-stage run still fails before `[MAT_EMIT]`, keep the
  next behavior work blocked and choose a named seam-reachability owner slice
  instead of a backend rescue.

### Slice 0k-E: Architecture migration contract after StateScope shadowing

Status:

- design-sealed, docs-only checkpoint;
- no compiler behavior, state-scope behavior, materialization behavior, AST
  read behavior, or backend behavior is changed by this slice.

Problem:

- the active ledgers now refute the immediate symptom-level fixes for the
  generated-stage crash corridor, but the codebase still allows the same
  semantic question to be answered from ambient maps, rendered symbols, backend
  lookup state, and raw `ExprId` indexes;
- adding another probe or local guard without a migration contract would keep
  the architecture in tail-chase mode.

Source/spec:

- `SemanticStateScope` section 6.4;
- `Materialization` section 6.5;
- `AstNodeIdentity / ArenaOwnership` sections 6.2a and 6.2b;
- `Code Health and Dead-Code Control` section 6.8;
- `TODO.md` active architecture backlog;
- `LANDMARKS.md` active bootstrap gate.

Migration contract:

1. `StateScope` authority becomes the only admissible owner for type-param and
   naming state used by materialization/naming decisions.
   - First migration target: callsite-specialization and materialization naming
     consumers around `def_has_untyped_regular_param?`,
     `raw_annotation_needs_callsite_specialization?`,
     `with_type_param_map`, `with_isolated_type_param_map`, and
     `function_type_param_map_for`.
   - Each consumer must be classified as `callsite`, `target_materialization`,
     `body_substitution`, `legacy_shim`, or `rejected_ambient` before behavior
     changes.
2. `MaterializationRegistry` becomes the owner for requested, selected, target,
   body, emitted-call, and wrapper/forwarder identity.
   - First migration target: pending function replay and call emission paths
     that currently join by rendered symbol or backend function presence.
   - Each mismatch must classify as `exact`, `materialization_keepalive`,
     `wrapper_forwarder`, or `rejected_mismatch` before a fix can emit or retarget
     calls.
3. `AstNodeRef` becomes the owner-scoped AST read contract.
   - First migration target: raw `@arena[expr_id]` reads in lower-call and
     semantic hot paths that currently rely on current arena or containment
     heuristics.
   - Each consumer must state whether it is `owner_ref`, `current_arena_owned`,
     `legacy_shim`, or `rejected_raw_read`.
4. `CodePathStatus` becomes the deletion authority for debug/probe/fallback
   code.
   - Static grep output is not enough. A path can become `delete_ready` only
     after runtime evidence plus a protecting falsifier.

Stop rules:

- stop if a proposed code change changes behavior before one of the four
  contracts above names its owner and DoD;
- stop if a behavior patch consumes only crash stack, backend
  `@undefined_externs`, `@func_by_name`, slot presence, arena containment, or
  broad `tx=none` diagnostics;
- stop if the proposed fix globally changes ambient `@type_param_map`, globally
  forces requested-name materialization, normalizes `NamedTuple`/`Tuple` strings
  as a symptom fix, or routes raw AST reads through a broad arena scan;
- stop if `@block_owner` is converted back to tuple/namedtuple owner metadata.
  `BlockOwner` remains the admitted owner-metadata boundary.

DoD for the next executable slice:

- update one of the four contracts above from design-sealed to shadow/ledger
  implementation;
- add or upgrade a report script that fails closed when the owner row is absent;
- run the report on a focused stage1 corridor, generated-s2 no-prelude where
  applicable, and the full generated-stage corridor when the seam is reachable;
- run the static `semantic_decision_census.sh` and `codepath_status_census.sh`
  gates to prove the slice did not silently broaden cleanup or semantic
  ownership claims;
- record the residual rejected surface in `TODO.md` and `LANDMARKS.md` before
  any behavior-changing patch.

Rejected immediate moves:

- `lower_call` consumer guards around `NodeSlot#node`;
- arena-wide searches to repair an `ExprId` read;
- backend forwarder or undefined-extern rescue;
- target keepalive driven by backend body presence;
- forced requested-name materialization;
- global ambient-map ignore/clear;
- `NamedTuple`/`Tuple` display-string normalization as the root fix;
- another diagnostic ledger without a named owner, cleanup rule, and
  generated-stage evidence requirement.

Next local track:

- implement the first real migration slice against `SemanticStateScope` or
  `MaterializationRegistry`, not another crash-edge local fix. The preferred
  first slice is a `StateScopeConsumerCensus`/shadow report that classifies the
  known naming/materialization consumers by allowed state authority and proves
  which legacy consumers can be changed without over-firing legitimate
  current-instantiation sites.

### Slice 0k-F: StateScope consumer migration gate

Status:

- implemented behavior-neutral follow-up to Slice 0k-E;
- default-off migration ledger/report, not a behavior patch;
- no compiler behavior, state-scope behavior, materialization behavior, AST
  read behavior, or backend behavior is changed by this slice.

Problem:

- `SemanticStateScope` rows currently describe the materialization seam, but
  legacy consumers still call predicates and helpers that can read ambient
  `@type_param_map` or rendered symbols directly;
- if the next report merely logs those calls, it becomes another diagnostic
  ladder. The report must instead classify each consumer into a migration
  status that can block or permit later behavior work.

Source/spec:

- `SemanticStateScope` section 6.4;
- `Materialization` section 6.5;
- `lower_function_if_needed_impl` callsite-args, suffix-types, and override
  naming decisions;
- `prefer_callsite_specialization` and `lower_call` remangling decisions;
- `def_has_untyped_regular_param?`,
  `raw_annotation_needs_callsite_specialization?`, and the type-param map
  helpers they currently consult.

Required consumer set:

The first executable report must cover at least these legacy consumers:

1. `prefer_callsite_specialization` deciding whether to preserve or remangle a
   callsite-specialized symbol.
2. `lower_function_if_needed_impl` `callsite_args` `keep_requested_name`.
3. `lower_function_if_needed_impl` `suffix_types` `keep_requested_name`.
4. `lower_function_if_needed_impl` materialization `override`.
5. `lower_call` call-target remangling / entry-name suffix preservation.
6. Direct predicate helpers used by those decisions:
   `def_has_untyped_regular_param?` and
   `raw_annotation_needs_callsite_specialization?`.

Required row shape:

Each row must carry enough information to make the consumer decision auditable:

- `consumer` and `decision`;
- requested symbol and target/materialized symbol when available;
- selected definition identity;
- current ambient map snapshot;
- target-materialization map when available;
- callsite arg types when available;
- selected authority:
  `callsite`, `target_materialization`, `body_substitution`,
  `legacy_shim`, or `rejected_ambient`;
- migration decision:
  `migrate_to_state_scope`, `migrate_to_materialization_registry`,
  `keep_legacy_shim`, `blocked_unknown`, or `rejected_ambient`;
- validation:
  `owned`, `ambient_rejected`, or `diagnostic_only`.

Acceptance gate:

- the report script fails closed when no consumer rows are emitted;
- malformed rows are failures, not warnings;
- every required consumer appears at least once in a focused stage1 corridor or
  is explicitly recorded as `not_reached` with a reason;
- every reached consumer has a migration decision;
- any `diagnostic_only` or `blocked_unknown` row blocks behavior patches that
  consume that decision surface;
- a would-change census is required before any later behavior patch changes a
  consumer decision. The would-change set must be no wider than the classified
  owner row set and must preserve legitimate current-instantiation cases.

Rejected shortcuts:

- treating row count as evidence that the migration is safe;
- changing `def_has_untyped_regular_param?` globally before the consumer
  authority split is classified;
- adding a boolean `ignore_ambient` mode passed through arbitrary callers;
- forcing requested-name materialization from this report alone;
- using backend `@undefined_externs` or `@func_by_name` as the first place to
  decide the consumer status;
- using `NamedTuple`/`Tuple` string normalization as the discriminator;
- converting `BlockOwner` back to tuple/namedtuple metadata.

DoD for implementation:

- add or upgrade one report script, likely
  `scripts/state_scope_consumer_report.sh`, that enforces the acceptance gate;
- prove the red state against a pre-slice compiler or with the missing-row
  failure mode before adding instrumentation;
- keep the compiler env-off behavior unchanged;
- run the focused report on a fresh stage1 compiler;
- run generated-s2 no-prelude when applicable;
- run the existing static gates:
  `scripts/semantic_decision_census.sh` and
  `scripts/codepath_status_census.sh`;
- run the existing materialization/state-scope reports to prove row formats
  still compose;
- update `TODO.md` and `LANDMARKS.md` with residual `blocked_unknown` and
  `diagnostic_only` surfaces before any behavior-changing patch.

Current evidence:

- red gate: a pre-slice compiler built from `4d0965e2` as
  `/private/tmp/adamas_ssc_red` compiles the focused repro but
  `scripts/state_scope_consumer_report.sh /private/tmp/adamas_ssc_red` fails
  closed with `FAIL: no [STATE_SCOPE_CONSUMER] consumer rows emitted` and
  `compiler_rc=0`;
- fresh stage1 build:
  `crystal build src/adamas.cr -o /private/tmp/adamas_ssc_stage1
  --error-trace`;
- focused stage1 report:
  `scripts/state_scope_consumer_report.sh /private/tmp/adamas_ssc_stage1`
  emits `rows=42224`, `malformed=0`, `invalid_authority=0`,
  `invalid_migration=0`, `invalid_validation=0`,
  `rejected_without_ambient=0`, and covers all required consumers:
  `prefer_callsite_specialization`,
  `lower_function_if_needed.callsite_args`,
  `lower_function_if_needed.suffix_types`,
  `lower_function_if_needed.override`, `lower_call.remangle`,
  `def_has_untyped_regular_param`, and
  `raw_annotation_needs_callsite_specialization`;
- the same report records migration blockers rather than hiding them:
  `diagnostic_only=5935`, `keep_legacy_shim=5935`,
  `rejected_ambient=2767`, `migrate_to_state_scope=25978`, and
  `migrate_to_materialization_registry=7544`;
- env-off focused compile emits `0` `[STATE_SCOPE_CONSUMER]` rows and the
  compiled `basic_sanity` binary exits `0`;
- static gates still run:
  `scripts/semantic_decision_census.sh` and
  `scripts/codepath_status_census.sh`;
- existing state/materialization reports still compose with the new ledger:
  `scripts/semantic_state_scope_report.sh /private/tmp/adamas_ssc_stage1`
  emits `rows=2513`, `malformed=0`, and
  `scripts/materialization_transaction_report.sh
  /private/tmp/adamas_ssc_stage1` emits `rows=2513`,
  `owner_malformed=0`, `joined_transactions=1349`, and
  `unjoined_emit_rows=0`;
- focused regressions remain green:
  `regression_tests/string_split_default_nil_limit_repro.sh`,
  `regression_tests/string_split_int32_nil_limit_collision_repro.sh`, and
  `regression_tests/proc_nilable_union_arg_indirect_call_repro.sh` against
  `/private/tmp/adamas_ssc_stage1`;
- broader bounded guard:
  `regression_tests/run_combined.sh /private/tmp/adamas_ssc_stage1` passes
  `36` / `36` combined tests;
- generated s2 self-build succeeds under `scripts/run_safe.sh`
  (`EXIT: 0` after about 179s), but
  `TIMEOUT=240 MEM_MB=8192 scripts/state_scope_consumer_report.sh
  /private/tmp/adamas_ssc_s2` fails closed with `compiler_rc=139`,
  `rows=17`, `malformed=0`, and missing
  `lower_function_if_needed.callsite_args` /
  `lower_function_if_needed.suffix_types` because generated s2 crashes before
  those consumer sites are reached.

Interpretation:

- Slice 0k-F is a migration gate. It proves the known consumer set is
  reportable in a focused stage1 corridor and that generated s2 reaches the
  ledger but not the full required consumer set;
- the `diagnostic_only` / `keep_legacy_shim` rows are blockers for behavior
  patches on those surfaces, not invitations to patch
  `def_has_untyped_regular_param?` or `lower_call` locally;
- the generated-s2 `compiler_rc=139` residual is a stage frontier and must not
  be converted into a consumer predicate fix without a later owned
  StateScope/MaterializationRegistry migration row plus would-change census.

Next local track:

- classify the `diagnostic_only` / `keep_legacy_shim` rows into explicit
  `StateScope` or `MaterializationRegistry` migration candidates before any
  behavior patch. Do not modify naming/materialization semantics until a later
  would-change census proves the changed set is bounded and preserves
  legitimate current-instantiation behavior.

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

## 12. Promotion criteria

This SDD moves from PROPOSED to DESIGN-SEALED only after:

- `s2b`/`s3b` bootstrap status is stable enough that architecture work will not
  chase a moving crash frontier;
- Phase 1 architecture census exists;
- Phase 2a state-scope/materialization-identity ledger exists for the active
  call/materialization frontier, and Phase 2b has at least a pre-call
  transaction record plus a named route to final emitted-call proof;
- the first boundary slice has a falsifier matrix and a behavior-neutral
  facade plan;
- owner explicitly chooses the first slice.

No behavior-changing refactor is admitted by this document alone.
