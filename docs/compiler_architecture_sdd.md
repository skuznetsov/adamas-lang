# Compiler Architecture Frontier SDD

Document status: PROPOSED, design-only. This is a post-bootstrap
architecture target, not approval to start a broad refactor while the current
`s2b`/`s3b` bug frontiers are still moving.

Current frontier: the compiler can make progress through bounded bug slices,
but many semantic decisions are still inferred repeatedly across HIR, MIR, and
LLVM lowering. This creates hidden oracles, string-name coupling, phase-local
fallbacks, and hard-to-localize bootstrap failures.

Current hostile-review frontier: the latest `s2b` stub family exposed a
materialization identity failure, not a backend stub bug. A call to
`Hash(UInt64, {class_name: String?, method_name: String?, is_class: Bool})#[]=`
can be emitted under the requested call symbol while the body is materialized
under a different target symbol. The proximate cause is an ambient
`@type_param_map` leak into a naming/materialization decision
(`def_has_untyped_regular_param?` at the `lower_function_if_needed_impl`
override seam). The deeper architectural issue is that symbol identity,
type-param authority, and materialization ownership are still inferred from
mutable process state and rendered strings.

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
- Do not make `s2b`/`s3b` stability depend on this architecture work. First
  stabilize bootstrap; then widen the architecture frontier.

## 5. Design laws

1. One decision, one owner.
   If two phases answer the same semantic question, one is the owner and the
   other must read a fact or facade.

2. Facts over names.
   Mangled names, string prefixes, and function-name substrings are transport
   details, not authorities for semantics.

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

Exit signal:

- `s2b` reaches a stable smoke target;
- `s3b` status is known;
- active frontiers have problem cards and reducers or smoke scripts.

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
- where layout/ABI/storage decisions are made or inferred.

Exit signal:

- a table of writers/readers per semantic decision;
- a list of hidden fallback sites;
- no production behavior changes.

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

### Phase 2: Typed facades over existing state

Introduce small wrapper types that read/write the old maps but record owner,
callsite, and decision provenance.

Examples:

- `NameRegistry` facade over name qualification and class registration,
- `CallResolver` facade over overload selection,
- `StateScope` facade over type-param and namespace authority,
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

- `CodePathStatus` ledger with `suspected_dead` -> `delete_ready` transitions;
- before/after diffstat and removed-symbol list;
- regression script or documented reason for each removed compatibility path.

Boundary:

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
  call/materialization frontier;
- the first boundary slice has a falsifier matrix and a behavior-neutral
  facade plan;
- owner explicitly chooses the first slice.

No behavior-changing refactor is admitted by this document alone.
