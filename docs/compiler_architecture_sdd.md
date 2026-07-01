# Compiler Architecture Frontier SDD

Document status: ACTIVE FRONTIER SDD. Behavior-neutral architecture slices are
landing as bootstrap control gates. This is not approval to start a broad
refactor while the current `s2b`/`s3b` bug frontiers are still moving.
The authoritative current decision surface is the "Active Architecture Board"
below. The older "Current next-slice decision after ..." paragraphs are kept as
historical ledger entries and must not override the board.

Current frontier: the compiler can make progress through bounded bug slices,
but many semantic decisions are still inferred repeatedly across HIR, MIR, and
LLVM lowering. This creates hidden oracles, string-name coupling, phase-local
fallbacks, and hard-to-localize bootstrap failures.

## Active Architecture Board

Status: design-sealed execution board after Slice 0k-Y. This board exists to
prevent the next step from being selected by the latest generated-stage crash
stack. A next slice is admitted only if it moves one board row by replacing or
shadowing a named authority edge, producing `CodePathStatus` evidence for a
named path, or refuting a row with fresher generated-stage evidence.

| Owner boundary | Current status | Next admitted movement | Forbidden repeat |
| --- | --- | --- | --- |
| `SemanticStateScope` | `prefer_callsite_specialization` is promoted in shadow/parity mode; emitted behavior still returns the legacy result. | Select a different root-sized consumer with a red/green source-shape gate, or explicitly leave this lane paused. | Reselecting `prefer_callsite_specialization`; wrapping `def_has_untyped_regular_param?` without a separate owner result; changing emitted behavior from the shadow row. |
| `MaterializationIdentity` / `MaterializationRegistry` | Transaction and decision ledgers exist, but focused generated-stage runs still do not authorize a behavior patch. Slice 0k-X selects the next implementation receipt and Slice 0k-Y adds the red source-shape gate for it: `scripts/materialization_symbol_binding_admission_report.sh` reports `legacy_split_edge` until the helper lands. | Implement the selected `MaterializationSymbolBinding` shadow seam: one helper owns requested, target, materialized body, override/call hint, keepalive, state-scope, target-map, call-arg, and ABI facts while emitted behavior remains legacy. Turn `REQUIRE_PROMOTED=1 scripts/materialization_symbol_binding_admission_report.sh` green. | Backend undefined-extern rescue; target keepalive as a standalone patch; requested-name forcing; `NamedTuple`/`Tuple` display normalization; global ambient-map predicate changes; adding another report before consuming the symbol-binding source-shape gate. |
| `NameResolution` / `MethodNameCodec` | File identity was fixed; method/symbol identity is still partly rendered-string driven. Slice 0k-V promotes the selected `lower_function_if_needed.exact_lookup_keep_requested_name` seam through `method_name_codec_exact_lookup_keep_requested_name?` in shadow/parity mode; emitted behavior still returns the legacy result. Slice 0k-W pauses standalone promotion-report proliferation. | Either select the next root-sized codec seam with a red/green source-shape gate, or define a generated-stage classification slice that consumes the existing promotion ledger to answer one blocking yes/no decision before changing emitted naming behavior. | String-slice parsing patches at individual callsites; treating rendered names as canonical identity; broad normalization without a falsifier; selecting lower-level helpers before a materialization seam; flipping owner-result behavior from shadow rows; committing another report surface that does not reduce or select an authority edge. |
| `AstNodeRef` / `ArenaOwnership` | Explicit-owner lower-call rows and `NodeSlotIntegrity` refuted owner drift, out-of-range ids, and missing slots for the instrumented edge. | Resume only with a named payload/deep-read or uninstrumented-consumer falsifier, including cleanup rules for its ledger. | Lower-call arena routing, broad arena scans, parser allocation rewrites, or another unbounded crash-edge probe. |
| `CodePathStatus` | `cli.metrics.identity_dry_run` is classified as `debug_only`, not `delete_ready`. | Classify another named path, or run a separate `delete_ready` slice with default-behavior, HIR/MIR/LLVM, bootstrap, and evidence-preservation guards. | Deleting debug/probe/fallback paths from static grep output; using runtime liveness as semantic ownership evidence. |

Default next track: plan the next correctness architecture slice around
`NameResolution` / `MethodNameCodec` plus `MaterializationIdentity`, because
the repeated high-cost frontiers are symbol/owner identity failures. A cleanup
slice remains admitted, but only when the goal is explicitly bloat reduction
and the selected path has its own `CodePathStatus` falsifier.

Current selected implementation receipt and gate: `MaterializationIdentity /
MaterializationRegistry`, `lower_function_if_needed.symbol_binding`,
`scripts/materialization_symbol_binding_admission_report.sh`. The next
production code slice should be a behavior-neutral helper/record extraction for
the inline materialization symbol-binding seam, not a behavior flip. It must
make requested/target/body/call-symbol identity one owned fact before any
forwarder, keepalive, remangle, or requested-name behavior patch is admissible.
Acceptance is not "a record exists": downstream materialization consumers must
read the body/call/keepalive symbols from that binding record, and any legacy
branching that remains must be enclosed inside the helper as a parity oracle,
not re-derived at each consumer. The source-shape gate is intentionally red
today under `REQUIRE_PROMOTED=1`.

Mini-Quadrumvirate gate for every future slice:

1. `VERIFY`: name the live board row and cite the current source/report that
   proves its status.
2. `CRITICIZE`: state the strongest symptom-fix interpretation and why the
   proposed move avoids it.
3. `BUILD`: name the old authority edge, the owned fact replacing or shadowing
   it, and the DoD command that proves the movement.
4. `ADVERSARY`: before claiming progress, check whether the slice merely added
   another row/report without consumer migration, deletion classification, or a
   refuted owner hypothesis.

Immediate stop rule after Slice 0k-W: a new script, ledger wrapper, or
generated-stage report is not architecture progress unless the SDD names the
decision it answers and the authority edge it reduces, selects, or blocks. If a
report only makes existing rows easier to print, keep it as local scratch and
delete it before handoff.

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

Current next-slice decision after Slice 0k-F: pause behavior fixes and turn
the mixed `MaterializationRegistry` result surface into a contract slice. The
consumer report has already refuted the simple replacements: consumer name,
target-map presence, call-arg count, and migration class are all mixed. The
next executable implementation must therefore create a typed
`MaterializationDecision` / `MaterializationRegistry` facade or equivalent
contract record before any naming, remangling, keepalive, or forwarder
behavior changes. That record must explain the decision from
`requested_symbol`, `selected_def`, `target_symbol`, `callsite_arg_types`,
`target_map`, `state_scope`, and ABI shape. Another local patch to
`def_has_untyped_regular_param?`, materialization override selection,
`lower_call` remangling, backend undefined extern handling, or
`NamedTuple`/`Tuple` display strings is explicitly rejected until it consumes
that owner record and passes a bounded would-change census.

Current next-slice decision after Slice 0k-G implementation: the
`MaterializationDecision` shadow record now exists for the focused stage1
MaterializationRegistry surface, but it is still behavior-neutral. It does not
authorize a consumer patch by itself, because generated-s2 still does not reach
the full focused decision seam before its existing crash. The next behavior
work must choose a bounded owned `MaterializationDecision` row and run a
would-change census; otherwise continue architecture work by improving
generated-stage seam reachability or by extending `CodePathStatus` cleanup
evidence. Do not treat the all-zero focused `would_change_rows` count as proof
that materialization behavior is correct globally.

Current next-slice decision after the 0k-G hostile promotion review: pause
behavior fixes and pause new diagnostic-ledger proliferation. Slice 0k-G is
useful only if it becomes an authority boundary for at least one legacy
consumer, or if it retires a legacy/debug path through `CodePathStatus`. The
next admitted slice is therefore Slice 0k-H: a docs-first promotion gate that
turns `MaterializationDecision` from a row-producing shadow ledger into the
next behavior-neutral owner/facade contract. No new local crash probe is
admitted unless it either promotes an existing owner fact into a consumer seam,
marks an existing path with a `CodePathStatus` status, or refutes the current
owner evidence with fresher generated-stage data.

Current next-slice decision after the 0k-H implementation preflight: do not
start by adding a new promotion ledger or by hard-coding the first promoted
consumer. A local preflight showed that a naive
`ADAMAS_MATERIALIZATION_PROMOTION_LEDGER` report can fail before proving any
architectural ownership: it can target `lower_function_if_needed.override`
without first proving that this is the right reached seam for the focused
report, and it can introduce another row format before selecting a behavior
owner. That WIP was removed instead of patched. Slice 0k-H remains a design
gate; the next admitted slice is 0k-I, a promotion-target selection gate that
uses the existing `StateScopeConsumerCensus` and `MaterializationDecision`
rows to choose exactly one legacy consumer or to explicitly switch to
`CodePathStatus` cleanup. No promotion helper, forwarder, remangle change, or
backend reconciliation is admitted until that selection gate is green.

Current next-slice decision after Slice 0k-I implementation: the promotion
target selection gate now exists and is behavior-neutral. The focused stage1
report selected exactly one eligible promotion consumer from existing
`[MAT_DECISION]` rows: `lower_function_if_needed.override`. Direct predicate
consumers remain rejected as requiring their own oracle, `lower_call.remangle`
is rejected as too late/backend-adjacent for the first promotion, and
`lower_function_if_needed.callsite_args` / `.suffix_types` are unreached for
the focused MaterializationRegistry row set. Generated s2 still crashes before
`[MAT_DECISION]` on the focused full-prelude repro, and the report records
that as `not_reached_named_residual`, not as a green generated-stage promotion.
The next admitted step is not "add another promotion report". It is Slice
0k-J, a promotion-definition gate: define the exact consumption effect that
turns `MaterializationDecision` from a row-producing ledger into an owned
facade at the selected override seam. A narrow helper is admitted only if the
legacy consumer starts obtaining its parity/shadow input from the owned
`MaterializationDecision` record, the old emitted behavior remains unchanged,
and a source-shape check proves the seam no longer reaches directly for the
ambient predicate as its only authority. A local unfinished 0k-J WIP that added
`[MAT_PROMOTION]` rows before this definition gate is classified as stale and
non-admitted.

Current next-slice decision after the architecture pause: do not start the
0k-J helper until the implementation plan proves an authority-edge
replacement, not only a row/report addition. Slice 0k-K is a docs-only
anti-tail-chase gate: the next code slice must name the old authority edge it
removes or shadows, the owned decision record that replaces it, the
source-shape check that proves the consumer no longer depends on the old direct
authority path, and the generated-stage residual if the focused seam is not
reached. If that receipt cannot be produced, the next track must switch to
`CodePathStatus` cleanup or to a generated-stage reachability owner boundary
instead of adding another materialization diagnostic.

Current next-slice decision after the Slice 0k-P hostile self-review: pause
code edits before accepting the first `SemanticStateScope` helper. The selected
candidate, `prefer_callsite_specialization`, remains the right first seam only
if the next implementation replaces a named authority edge, not if it merely
wraps the old ambient predicate with a new row format. A local
`SemanticStateScopeSnapshot` / `[STATE_SCOPE_PROMOTION]` WIP was removed as
non-admitted because it did not yet prove that the old
`def_has_untyped_regular_param?` oracle had become parity-only rather than the
hidden authority. The next admitted step is Slice 0k-Q, a docs-only ownership
contract: define what counts as a real `SemanticStateScope` migration, what
remains wrapper theater, and which source-shape/report gates must be red
before code and green after code.

Current next-slice decision after Slice 0k-R implementation: the first
`SemanticStateScope` owner-consumption seam is now promoted in shadow/parity
mode, but it is not a behavior fix. `prefer_callsite_specialization` no longer
calls the old state-scope consumer helper directly; it calls a named
`SemanticStateScopeDecision` helper that evaluates the legacy predicate only as
parity, emits an owner-result classification, and returns the legacy result as
the emitted result. The admission report now marks the seam
`already_promoted_shadow`. The generated-s2 full-prelude smoke still exits 139
after `pass3 after lower_main call`, so this slice is not green `s2b`/`s3b`
evidence. The next work must not reselect this same seam; either add a
no-repeat state-scope selection gate for a genuinely different consumer, or
switch to runtime `CodePathStatus` cleanup selection if no root-sized
state-scope consumer is admitted.

Current next-slice decision after Slice 0k-S implementation: the architecture
track has explicitly switched to runtime `CodePathStatus` cleanup selection
for one small cluster instead of adding another state-scope helper. The first
cleanup selection report classifies `cli.metrics.identity_dry_run` as
`debug_only` with a protecting falsifier: default runtime status is
`not_taken`, and `ADAMAS_IDENTITY_DRY_RUN=1` makes the same path `taken`.
This is not delete-ready proof and does not remove code; it is the first
cleanup/bloat control record. The next cleanup step must either add a second
runtime-observed status for a named path or propose a deletion only after
`CodePathStatus` says `delete_ready` with HIR/MIR/LLVM and bootstrap guards.

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

14. Promotion before proliferation.
    A new shadow ledger is architectural progress only when it has a promotion
    path: one legacy consumer starts reading the owned fact in parity/shadow
    mode, or one old path receives a `CodePathStatus` classification with a
    protecting falsifier. A ledger that only adds rows after the previous ledger
    refuted the local hypothesis is diagnostic debt, not a migration step.

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
- blocker classification is now explicit and fail-closed:
  `unclassified_blocked=0`, with `legacy_shim.concrete_typed_params=4481`,
  `legacy_shim.skipped_untyped_params=924`,
  `legacy_shim.no_regular_params=530`, and zero
  `legacy_shim.regular_untyped_param_review` rows. The report also prints
  bounded samples for each non-empty blocker class. The skipped-untyped bucket
  contains splat, double-splat, or block untyped annotations and is not proof
  that the old predicate is wrong for a regular parameter;
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

Post-0k-F owner-result preflight:

- `scripts/state_scope_consumer_report.sh` now includes an owned-candidate
  census and a proposed owner-result probe. It keeps malformed/unknown owner
  rows as failures, but treats result mismatches as measured-red evidence
  rather than malformed report output. Bounded samples are truncated so large
  `call_arg_types` rows do not turn the report into an artifact-size hazard;
- focused stage1 report against `/private/tmp/adamas_ssc_owned_stage1`
  exits `0` and reports `owned_candidate_rows=36289`,
  `owner_result_unknown=0`, and `owned_would_change=3779`;
- owned candidate classes are `state_scope=25978`,
  `materialization_registry=7544`, and `ambient_rejected=2767`;
- the proposed owner-result probe is parity-clean for
  `state_scope.legacy_result_1=25978`, `state_scope.legacy_result_0=0`,
  `ambient_rejected.legacy_result_1=0`, and
  `ambient_rejected.legacy_result_0=2767`;
- it is explicitly mixed for MaterializationRegistry rows:
  `materialization_registry.legacy_result_1=3779` and
  `materialization_registry.legacy_result_0=3765`.

Post-0k-F MaterializationRegistry attribution:

- the report now breaks the mixed MaterializationRegistry rows down by
  consumer, decision, selected-definition parameter class, target-map
  presence, and callsite-arg shape;
- focused stage1 evidence still reports
  `materialization_registry_rows=7544`, split as
  `legacy_result_1=3779` and `legacy_result_0=3765`;
- the split is not owned by one consumer: all reached consumers are mixed
  (`def_has_untyped_regular_param` 1775/1355,
  `prefer_callsite_specialization` 580/483,
  `raw_annotation_needs_callsite_specialization` 229/1055,
  `lower_function_if_needed.override` 566/496, and
  `lower_call.remangle` 629/376 for result 1/0 respectively);
- the strongest observed separator is selected-definition parameter class:
  `regular_untyped_params` is mostly result 1 (`3362/3`), while
  `concrete_typed_params` is mostly result 0 (`2/2033`) and
  `no_regular_params` is mostly result 0 (`4/572`). `short_type_params`
  (`273/895`) and `skipped_untyped_params` (`138/262`) remain mixed;
- all MaterializationRegistry rows have `target_map_present`
  (`3779/3765`). Callsite-arg shape is also mixed:
  `call_args_none` (`507/599`), `call_args_1` (`1864/2363`),
  `call_args_2_4` (`1202/801`), `call_args_5_16` (`194/2`), and
  `call_args_17_plus` (`12/0`), result 1/0 respectively.

Interpretation:

- Slice 0k-F is a migration gate. It proves the known consumer set is
  reportable in a focused stage1 corridor and that generated s2 reaches the
  ledger but not the full required consumer set;
- the `diagnostic_only` / `keep_legacy_shim` rows are blockers for behavior
  patches on those surfaces, not invitations to patch
  `def_has_untyped_regular_param?` or `lower_call` locally;
- the largest blocker class is concrete typed parameters and should not drive a
  callsite-specialization behavior change. The `skipped_untyped_params` bucket
  also does not justify a StateScope predicate patch; it explains why those
  rows remain legacy shims under the current predicate. This closes the
  diagnostic blocker surface as non-behavior evidence unless a future run
  produces nonzero `regular_untyped_param_review` or `blocked_unknown` rows;
- the generated-s2 `compiler_rc=139` residual is a stage frontier and must not
  be converted into a consumer predicate fix without a later owned
  StateScope/MaterializationRegistry migration row plus would-change census.
- the owner-result preflight refutes a naive behavior rule such as
  `migrate_to_materialization_registry => result=false`. The
  MaterializationRegistry migration class is a mixed owner surface, not a
  boolean replacement rule. It needs per-consumer/per-decision classification
  before any behavior patch changes naming or materialization decisions.
- the MaterializationRegistry attribution further refutes a single-consumer
  fix. The next behavior design has to model the selected-definition parameter
  contract and its exceptions; using consumer name, target-map presence, or
  callsite-arg count alone would over-fire.

Next local track:

- treat the current `diagnostic_only` / `keep_legacy_shim` rows as classified
  legacy-shim blockers, not behavior candidates. The next migration step should
  target already-owned rows (`migrate_to_state_scope`,
  `migrate_to_materialization_registry`, or `rejected_ambient`) with a
  bounded would-change census, while preserving legitimate
  current-instantiation behavior;
- because `migrate_to_materialization_registry` is measured-red under the
  proposed owner-result probe, the next MaterializationRegistry slice must
  classify rows by consumer, decision, selected definition, target map, and
  callsite arg shape before it proposes any replacement rule;
- the next design candidate is a MaterializationRegistry contract for
  selected-definition parameter classes: regular untyped params, skipped
  untyped params, short type params, concrete typed params, and no-param
  definitions must each state whether callsite specialization, target
  materialization, or legacy shim owns the symbol decision.

### Slice 0k-G: MaterializationRegistry contract checkpoint

Status:

- implemented behavior-neutral contract checkpoint after Slice 0k-F;
- no compiler behavior, state-scope behavior, materialization behavior,
  remangling behavior, backend behavior, or cleanup behavior is changed by
  this slice.

Problem:

- Slice 0k-F made the known naming/materialization consumers visible, but its
  owner-result probe is measured-red for `MaterializationRegistry`: the same
  migration class splits `3779/3765` against the legacy result;
- each tempting local discriminator is also mixed or too broad. Consumer name,
  target-map presence, and callsite-arg count do not isolate the behavior
  decision. Selected-definition parameter class is stronger but still has
  exceptions, especially `short_type_params` and `skipped_untyped_params`;
- continuing directly to a consumer patch would repeat the previous failure
  pattern: a locally plausible fix would encode one symptom into one consumer
  while leaving symbol identity spread across ambient maps, rendered strings,
  pending queues, and backend function presence.

Source/spec:

- `SemanticStateScope` section 6.4;
- `Materialization` section 6.5;
- Slice 0k-F `StateScopeConsumerCensus`;
- `scripts/state_scope_consumer_report.sh` attribution output;
- `TODO.md` active architecture backlog;
- `LANDMARKS.md` active bootstrap gate.

Required MaterializationRegistry contract:

`MaterializationRegistry` must become the owner of a typed decision record for
symbol identity. The record must be explicit enough that later phases do not
reconstruct the answer from ambient state or rendered name strings.

Minimum input fields:

- `requested_symbol`: the symbol emitted or requested by the callsite;
- `selected_def`: the resolved source definition and its regular parameter
  annotations;
- `target_symbol`: the symbol produced by target/materialization naming;
- `state_scope`: the authoritative `SemanticStateScope` decision for this
  materialization;
- `callsite_arg_types`: callsite argument types, including whether the row has
  no args, one arg, bounded multi-arg shape, or large arg shape;
- `target_map`: the selected target-materialization type-param map, including
  empty-map and missing-map cases;
- `arg_abi` / `block_abi`: the ABI shape required by the emitted call and the
  materialized body.

Minimum output fields:

- `decision`:
  `exact`, `callsite_specialized`, `target_materialized`,
  `wrapper_required`, `legacy_shim`, or `rejected_mismatch`;
- `owner`:
  `materialization_registry`, `semantic_state_scope`,
  `call_resolution`, `backend_mechanical`, or `rejected`;
- `reason`: a non-stringly reason such as
  `regular_untyped_param_requires_callsite_symbol`,
  `concrete_typed_param_uses_target_symbol`,
  `short_type_param_requires_scope_disambiguation`,
  `skipped_untyped_param_requires_legacy_shim`,
  `no_regular_param_requires_target_symbol`,
  `abi_shape_requires_wrapper`, or `insufficient_owner_evidence`;
- `legacy_result`: the current decision result, carried only for parity and
  would-change reporting, not as an authority;
- `would_change`: whether consuming the record would alter the current result.

Admitted next implementation slice:

- add a behavior-neutral `MaterializationDecision` shadow record or facade at
  the materialization/naming seam;
- populate it from the existing `StateScopeConsumerCensus`,
  `MaterializationIdentityTransaction`, and `SemanticStateScope` facts without
  changing the chosen symbol;
- fail closed when a reached row lacks one of the required inputs or cannot
  name an owner/reason;
- report the same focused stage1 corridor and, where reachable, generated-s2
  no-prelude/full-stage corridors;
- print bounded would-change buckets by decision, reason, owner, consumer,
  selected-definition parameter class, target-map class, call-arg shape, and
  ABI shape.

Rejected moves:

- patching `def_has_untyped_regular_param?`,
  `raw_annotation_needs_callsite_specialization?`, materialization override,
  or `lower_call` remangling directly from the Slice 0k-F attribution;
- treating `migrate_to_materialization_registry` as a replacement boolean;
- forcing requested-name materialization globally or per `Hash#[]=`;
- adding backend keepalive, backend forwarder, or undefined-extern rescue as
  the first behavior mechanism;
- normalizing `NamedTuple`/`Tuple` display strings as the root fix;
- converting `BlockOwner` back to tuple/namedtuple owner metadata;
- adding another diagnostic-only report that does not define a contract owner,
  accepted/rejected decisions, and cleanup/falsifier requirements.

DoD for implementation:

- red gate: the pre-slice compiler/report must fail closed because no
  `MaterializationDecision` rows are emitted or required fields are missing;
- green focused gate: fresh stage1 report emits decision rows for all reached
  `MaterializationRegistry` candidates with malformed/unknown owner counts at
  zero;
- generated-stage gate: generated-s2 no-prelude runs the report where
  reachable, and full generated-stage evidence is recorded as either valid
  rows or a named seam-reachability failure;
- over-fire gate: any proposed behavior consumer must run a would-change
  census and must not exceed the owned decision set. A broad would-change set
  is measured-red, not permission to patch;
- compatibility gate: static `semantic_decision_census.sh` and
  `codepath_status_census.sh` still run, and existing
  `semantic_state_scope_report.sh` / `materialization_transaction_report.sh`
  row formats still compose;
- ledger sync: update `TODO.md` and `LANDMARKS.md` with accepted, rejected, and
  residual surfaces before any behavior-changing patch.

Slice 0k-G evidence:

- red gate: after adding `scripts/materialization_decision_report.sh` but before
  compiler instrumentation, a fresh compiler
  `/private/tmp/adamas_matdec_red` failed the report with
  `FAIL: no [MAT_DECISION] materialization decision rows emitted` and
  `compiler_rc=0`;
- implementation: `ADAMAS_MATERIALIZATION_DECISION_LEDGER=1` now emits
  `[MAT_DECISION]` rows from the existing naming/materialization consumer seam
  only for `migrate_to_materialization_registry` candidates. Env-off behavior
  is unchanged;
- focused stage1 report:
  `scripts/materialization_decision_report.sh
  /private/tmp/adamas_matdec_stage1` reports `rows=7544`,
  `malformed=0`, `invalid_decision=0`, `invalid_owner=0`,
  `invalid_reason=0`, `invalid_legacy_result=0`,
  `invalid_would_change=0`, `would_change_rows=0`,
  `legacy_shim_rows=891`, and `rejected_rows=0`;
- focused decision buckets:
  `exact=2311`, `callsite_specialized=2245`,
  `target_materialized=2097`, and `legacy_shim=891`;
- focused parameter buckets:
  `regular_untyped_params=3365`, `concrete_typed_params=2495`,
  `short_type_params=708`, `no_regular_params=576`, and
  `skipped_untyped_params=400`;
- existing reports still compose:
  `scripts/state_scope_consumer_report.sh /private/tmp/adamas_matdec_stage1`
  reports `rows=42224`, `malformed=0`, `owned_candidate_rows=36289`,
  `owner_result_unknown=0`, `owned_would_change=3779`, and
  `materialization_registry_rows=7544`; `scripts/semantic_state_scope_report.sh`
  reports `rows=2513`, `malformed=0`; and
  `scripts/materialization_transaction_report.sh` reports `rows=2513`,
  `owner_malformed=0`, `joined_transactions=1349`, and
  `unjoined_emit_rows=0`;
- env-off check: compiling and running a tiny `puts 7` program with the same
  stage1 emits `0` `[MAT_DECISION]` rows and the binary exits `0` under
  `scripts/run_safe.sh`;
- static guards still run:
  `scripts/semantic_decision_census.sh` and
  `scripts/codepath_status_census.sh`;
- broad guard:
  `regression_tests/run_all_suites.sh /private/tmp/adamas_matdec_stage1 4`
  passes `152/152` original tests and `36/36` combined tests;
- generated-stage evidence: fresh stage1 builds fresh generated s2
  `/private/tmp/adamas_matdec_s2` (`EXIT: 0` after about 178s). The generated
  compiler does not yet reach this decision seam on the focused full-prelude
  report: `scripts/materialization_decision_report.sh
  /private/tmp/adamas_matdec_s2` fails with no `[MAT_DECISION]` rows and
  `compiler_rc=139`. A tiny no-prelude source compiles with `compiler_rc=0`
  but emits no rows because that corridor does not reach
  `MaterializationRegistry` candidates. This is a named seam-reachability
  residual, not an invalid row-format failure.

Hostile self-review:

- strongest objection: this slice can become one more ledger instead of a
  simplification. The guard is that a `MaterializationDecision` row must name a
  behavior owner and accepted/rejected decision. Rows that only restate
  ambient maps or string differences remain diagnostic-only and block behavior
  work;
- second objection: the record can accidentally encode the old legacy result
  as truth. The guard is that `legacy_result` is carried only for parity and
  would-change reporting, while `decision` and `reason` must be derived from
  owner facts;
- third objection: the current `Hash(UInt64, NamedTuple)#[]=` frontier may
  tempt a special-case wrapper. The guard is that any wrapper or keepalive is
  admitted only after the registry row says `wrapper_required`, proves ABI
  compatibility, and survives a root-sized would-change census.

Next local track:

- superseded by Slice 0k-H. The `MaterializationDecision` record/report exists;
  the next architecture step is promotion of that owner fact into one
  behavior-neutral consumer seam, or an explicit switch to `CodePathStatus`
  cleanup work. Do not resume behavior fixes from the `Hash#[]=`,
  `@type_param_map`, `NamedTuple`/`Tuple`, or backend stub corridor until a
  promoted owner row selects a bounded behavior change.

### Slice 0k-H: MaterializationDecision promotion gate

Status:

- design-sealed, docs-only checkpoint after Slice 0k-G;
- no compiler behavior, state-scope behavior, materialization behavior,
  remangling behavior, backend behavior, AST-read behavior, or cleanup behavior
  is changed by this slice.

Problem:

- Slice 0k-G created a useful `MaterializationDecision` shadow record, but a
  shadow record by itself does not reduce architectural coupling;
- the failure pattern across the recent frontier is not "missing one more
  observation". It is repeated semantic ownership leakage: a later phase or a
  local consumer reconstructs a decision from ambient state, rendered names,
  backend function presence, or raw indexes instead of consuming an owned fact;
- continuing with another payload/deep-read/local crash probe before promoting
  an existing owner fact would keep the architecture in diagnostic tail-chase
  mode.

Source/spec:

- Slice 0k-E migration contract;
- Slice 0k-F `StateScopeConsumerCensus`;
- Slice 0k-G `MaterializationDecision` shadow ledger;
- `CodePathStatus` section 6.8;
- `TODO.md` active architecture backlog;
- `LANDMARKS.md` active bootstrap gate.

Promotion rule:

1. A new ledger is admitted only if it has one of these outcomes:
   - `promote_owner`: one legacy consumer starts reading the typed owner record
     in parity/shadow mode, while emitted behavior remains unchanged;
   - `classify_codepath`: one old debug/probe/fallback/shim path receives a
     `CodePathStatus` status plus a protecting falsifier;
   - `refute_current_owner`: fresh generated-stage evidence contradicts the
     current owner evidence and names the new boundary.
2. If none of those outcomes is available, the next step is design work or
   cleanup planning, not another diagnostic probe.
3. A promoted owner record must preserve the old result as `legacy_result`
   only for parity reporting. The old result is not authority.
4. A consumer may move from legacy logic to an owner record only after a
   would-change census proves the row set is bounded and classified by owner,
   decision, reason, selected-definition parameter class, state-scope authority,
   target-map class, callsite-arg shape, and ABI shape.

Admitted next implementation slice:

- add a behavior-neutral `MaterializationDecision` promotion helper/facade that
  computes the existing Slice 0k-G decision object in one place and exposes it
  to exactly one naming/materialization consumer in shadow/parity mode;
- the first candidate consumer should be one already covered by
  `StateScopeConsumerCensus` and `MaterializationDecision`, preferably the
  materialization naming/override seam rather than backend undefined-extern
  handling;
- keep legacy behavior as the emitted result until the would-change census is
  root-sized and the SDD admits the behavior flip;
- fail closed if the consumer cannot obtain a complete owner record.

Rejected moves:

- adding a fresh crash-edge ledger without a promotion/classification/refutation
  outcome;
- using generated-stage `compiler_rc=139` alone as the reason for another
  `lower_call`, backend, arena, `NodeSlot`, or payload consumer patch;
- using all-zero focused `would_change_rows` from Slice 0k-G as proof that
  materialization is globally correct;
- using `CodePathStatus` branch liveness as a substitute for semantic ownership;
- backend undefined-extern rescue, target keepalive, or forwarder emission
  before a `MaterializationDecision` row says `wrapper_required` and a
  root-sized would-change census exists;
- rolling `BlockOwner` back to tuple/namedtuple metadata.

DoD for implementation:

- red gate: the pre-slice report must fail because no promoted
  `MaterializationDecision` consumer rows are emitted;
- green focused gate: fresh stage1 report emits promoted consumer rows with
  malformed/unknown owner counts at zero and legacy/parity result preserved;
- generated-stage gate: generated-s2 no-prelude runs the report where
  reachable, and full generated-stage evidence is recorded as either promoted
  rows or a named seam-reachability residual;
- over-fire gate: the report prints would-change buckets and treats broad or
  mixed would-change sets as measured-red;
- cleanup gate: if the slice discovers stale debug/probe/fallback paths, it
  marks them only as `suspected_dead`, `legacy_shim`, or `debug_only` until a
  protecting falsifier can prove `delete_ready`;
- compatibility gate: static `semantic_decision_census.sh` and
  `codepath_status_census.sh` still run, existing state/materialization reports
  still compose, and env-off compiler behavior is unchanged;
- ledger sync: update `TODO.md` and `LANDMARKS.md` with promoted, rejected, and
  residual surfaces before any behavior-changing patch.

Current evidence:

- focused generated-s2 seam recheck after Slice 0k-G still fails before
  `[MAT_DECISION]`: the materialization decision report has no rows and
  `compiler_rc=139`;
- a fresh `NodeSlotIntegrity` report on the same focused corridor reports only
  healthy rows (`rows=105`, `healthy_present=105`, and zero missing/out-of-range
  buckets);
- a fresh lower-call arena parity report on the same focused corridor reports
  `compiler_rc=139`, `expr_rows=35`, `agree_all_have=35`, and zero owner
  divergence buckets;
- this reinforces the stop rule: do not spend the next slice on arena owner,
  slot existence, or lower-call consumer routing. Those are not currently the
  promoted owner boundary.

Hostile self-review:

- strongest objection: this promotion gate can become more process text without
  changing code. The guard is that the next implementation must expose a real
  owner object/helper to one legacy consumer in shadow/parity mode, not merely
  print a new report line;
- second objection: a parity consumer can hide old behavior under a new facade.
  The guard is that every row carries owner, decision, reason, legacy result,
  and would-change classification, and broad/mixed would-change remains red;
- third objection: generated-stage still fails before the full seam, so a
  focused stage1 promotion might not help bootstrap immediately. The guard is
  to keep the claim narrow: promotion reduces architectural coupling and is a
  prerequisite for behavior flips; it is not a green `s2b`/`s3b` claim.

Next local track:

- superseded by Slice 0k-I. Do not implement a promotion helper directly from
  Slice 0k-H. First run a promotion-target selection gate that proves which
  legacy consumer is eligible for shadow/parity promotion, or explicitly choose
  `CodePathStatus` cleanup if no consumer is eligible. Do not add another local
  crash probe unless fresh evidence invalidates the current owner ledgers.

### Slice 0k-I: Promotion target selection gate

Status:

- implemented behavior-neutral report after the failed 0k-H implementation
  preflight;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, AST-read behavior, or cleanup behavior is changed by this slice.

Problem:

- Slice 0k-H correctly says that ledgers must be promoted before more ledgers
  are added, but it did not specify how to choose the first promoted consumer;
- choosing a consumer by intuition, by the latest crash story, or by a
  preferred seam such as `lower_function_if_needed.override` repeats the same
  hidden-oracle problem at the planning layer;
- adding a new promotion env/report before the consumer is selected can become
  diagnostic proliferation even if the row format looks architectural.

Source/spec:

- Slice 0k-F `StateScopeConsumerCensus`;
- Slice 0k-G `MaterializationDecision` shadow ledger;
- Slice 0k-H promotion rule;
- Design law 14, promotion before proliferation;
- Stop rules for backend reconciliation, requested-name forcing, global
  ambient-map changes, and `BlockOwner` rollback.

Selection rule:

1. Candidate consumers come only from already-reached rows in the existing
   `StateScopeConsumerCensus` / `MaterializationDecision` reports.
2. A candidate is eligible only if the report can show:
   - nonzero focused stage1 rows for that consumer;
   - complete owner fields: requested symbol, target symbol, selected
     definition, state-scope authority, target map, callsite arg shape, and
     ABI shape;
   - bounded decision/reason buckets;
   - legacy/parity result preservation under shadow consumption;
   - a generated-stage status: reached, not reached with a named seam
     residual, or explicitly not applicable to that generated-stage corridor.
3. A candidate is rejected if selecting it requires a new compiler env solely
   to make rows appear, backend `@undefined_externs` as the first semantic
   signal, target keepalive, requested-name forcing, global ambient-map
   ignore/clear, or `NamedTuple`/`Tuple` string normalization.
4. If no candidate is eligible, the next local track is not another
   materialization probe. It is either `CodePathStatus` cleanup selection or a
   revision of the SDD contract.

Admitted next implementation slice:

- upgrade an existing report or add a report that consumes existing
  `[STATE_SCOPE_CONSUMER]` / `[MAT_DECISION]` rows and prints a
  promotion-selection table;
- do not add new compiler instrumentation for this selection slice unless the
  report proves an existing required field is absent from all current rows;
- output for each candidate:
  `consumer`, `row_count`, decision buckets, reason buckets, param-class
  buckets, state-scope buckets, ABI buckets, legacy-result buckets,
  would-change buckets, generated-stage reachability, and `selection_status`;
- `selection_status` must be one of:
  `eligible_promote_owner`, `rejected_unreached`,
  `rejected_broad_would_change`, `rejected_missing_owner_fields`,
  `rejected_backend_only`, `rejected_requires_new_oracle`, or
  `defer_to_codepath_status`.

Rejected moves:

- implementing `ADAMAS_MATERIALIZATION_PROMOTION_LEDGER` or a new promotion
  row format before the selection report chooses one eligible consumer;
- using `lower_function_if_needed.override` as the first target merely because
  Slice 0k-H called it preferable;
- patching direct predicates, remangling, target keepalive, requested-name
  materialization, backend undefined-extern handling, or `NamedTuple`/`Tuple`
  rendering from this slice;
- treating a failed generated-stage report with `compiler_rc=139` as proof
  that the selected consumer is wrong unless the owner rows show the wrong
  boundary.

DoD for implementation:

- red gate: the pre-slice selection report fails closed because no
  promotion-selection table exists or because required fields are missing;
- green focused gate: fresh stage1 report lists all reached
  `MaterializationDecision` consumers and selects at most one
  `eligible_promote_owner` consumer;
- generated-stage gate: generated-s2 no-prelude or full-stage report records
  either the selected consumer rows or a named seam-reachability residual;
- compatibility gate: existing `state_scope_consumer_report.sh`,
  `materialization_decision_report.sh`, `semantic_decision_census.sh`, and
  `codepath_status_census.sh` still run;
- cleanup gate: any rejected candidate is classified as a semantic rejection,
  seam residual, or cleanup candidate, not silently ignored;
- ledger sync: update `TODO.md` and `LANDMARKS.md` before any promotion helper
  or behavior-changing patch.

Current evidence:

- the Slice 0k-G `MaterializationDecision` report already exposes multiple
  candidate consumers and mixed materialization surfaces;
- a local 0k-H WIP that tried to add a dedicated promotion ledger was removed
  before commit because it did not first prove the selected consumer seam;
- this is a planning/refutation result, not a compiler behavior result and not
  a green `s2b`/`s3b` claim.

Implementation evidence:

- red gate: before the report existed,
  `scripts/materialization_promotion_selection_report.sh` failed closed with
  `FAIL: no materialization promotion selection report exists`;
- implementation:
  `scripts/materialization_promotion_selection_report.sh` consumes the existing
  `ADAMAS_MATERIALIZATION_DECISION_LEDGER=1` rows and does not add a compiler
  env, source instrumentation, backend hook, or behavior change;
- focused stage1 report:
  `scripts/materialization_promotion_selection_report.sh
  /private/tmp/adamas_0ki_stage1` reports `rows=7544`, `malformed=0`,
  `invalid_owner=0`, `invalid_legacy_result=0`,
  `invalid_would_change=0`, `eligible_count=1`, and `selected_count=1`;
- selected consumer:
  `lower_function_if_needed.override` has `row_count=1062`,
  `missing_owner_fields=0`, `invalid_owner_fields=0`,
  `would_change_rows=0`, and
  `selection_status=eligible_promote_owner`;
- rejected consumers:
  `prefer_callsite_specialization`, `def_has_untyped_regular_param`, and
  `raw_annotation_needs_callsite_specialization` are
  `rejected_requires_new_oracle`; `lower_call.remangle` is
  `rejected_backend_only`; `lower_function_if_needed.callsite_args` and
  `.suffix_types` are `rejected_unreached`;
- compatibility gates:
  `scripts/materialization_decision_report.sh
  /private/tmp/adamas_0ki_stage1`,
  `scripts/state_scope_consumer_report.sh /private/tmp/adamas_0ki_stage1`,
  `scripts/semantic_decision_census.sh`, and
  `scripts/codepath_status_census.sh` all exit `0`;
- generated-stage gate: fresh stage1 builds fresh generated s2
  `/private/tmp/adamas_0ki_s2` (`EXIT: 0` after about 178s). Running the
  focused selection report with generated s2 still fails before
  `[MAT_DECISION]` with `compiler_rc=139`; explicit residual mode reports
  `rows=0`, `eligible_count=0`, `selected_count=0`,
  `generated_stage_status=not_reached_named_residual`, and
  `no_row_reason=generated_s2_crashes_before_materialization_decision`.

Hostile self-review:

- strongest objection: this selection gate can become another report instead
  of a migration step. The guard is that it must select at most one eligible
  consumer or explicitly route to `CodePathStatus` cleanup; a table with no
  decision fails the slice;
- second objection: using existing rows may hide a missing field. The guard is
  fail-closed `rejected_missing_owner_fields`, not best-effort inference;
- third objection: generated-stage does not reach many focused seams. The guard
  is to record generated-stage seam residuals explicitly and keep the claim at
  architecture-selection level, not bootstrap-green level.

Next local track:

- Slice 0k-J: define and then implement promotion as a consumption effect, not
  as a new diagnostic row surface. The selected
  `lower_function_if_needed.override` seam may get a behavior-neutral helper
  only after the SDD states what old direct read is replaced by the owned
  `MaterializationDecision` record, which source-shape check proves that
  boundary, and which reports prove legacy behavior is preserved.

### Slice 0k-J: Promotion-definition gate for override seam

Status:

- design-sealed docs-only checkpoint after Slice 0k-I;
- current unfinished 0k-J code/report WIP is stale and non-admitted;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, AST-read behavior, or cleanup behavior is changed by this slice.

Problem:

- Slice 0k-I selected `lower_function_if_needed.override`, but selecting a
  consumer is not the same as promoting an owner fact;
- a report that only emits `[MAT_PROMOTION]` rows can recreate the same failure
  pattern as the rejected 0k-H WIP: more evidence surface without a smaller
  state contract;
- the architecture objective is to reduce hidden authority, so 0k-J must prove
  that the selected legacy seam starts consuming an owned decision object in
  shadow/parity mode, not merely that the seam can print another row.

Promotion definition:

1. The promoted consumer is exactly `lower_function_if_needed.override`.
2. The promoted owner is the existing `MaterializationDecision` /
   `MaterializationRegistry` record from Slice 0k-G/0k-I.
3. The first implementation remains behavior-neutral: emitted behavior must use
   the legacy result, but parity/shadow computation must flow through the owner
   record.
4. The old direct predicate call at the override seam must be replaced by a
   named helper whose contract is "owner decision plus legacy parity", not by a
   wrapper that simply logs around the old predicate.
5. The helper must fail closed to legacy behavior if it cannot construct a
   complete owner record.
6. The slice is not allowed to promote direct predicates,
   `prefer_callsite_specialization`, `lower_call.remangle`, backend
   undefined-extern handling, target keepalive, requested-name materialization,
   global ambient-map changes, or `NamedTuple`/`Tuple` display normalization.

Required source-shape gate:

- before implementation, `lower_function_if_needed.override` reaches
  `state_scope_consumer_def_has_untyped_regular_param?` directly;
- after implementation, that seam reaches a named promotion helper instead;
- direct callers of `state_scope_consumer_def_has_untyped_regular_param?` must
  remain limited to their existing non-promoted consumers and must not be
  silently widened or globally changed;
- the helper must return the legacy result in this slice, so env-off behavior
  is unchanged.

Required report gate:

- red gate: a pre-implementation compiler must fail the override promotion
  report because no promoted override rows exist;
- green focused gate: a fresh stage1 report must emit rows only for
  `lower_function_if_needed.override`, with complete owner fields, zero
  malformed rows, and `emitted_result == legacy_result`;
- source-shape gate: static `rg` checks must prove the selected seam no longer
  calls the ambient predicate directly;
- compatibility gate: existing materialization decision, state-scope consumer,
  semantic decision, and CodePathStatus reports still pass;
- generated-stage gate: generated s2 must either emit promoted rows where the
  seam is reached or preserve the explicit
  `not_reached_named_residual` boundary. This remains a residual, not a green
  `s2b`/`s3b` claim.

Rejected 0k-J shapes:

- adding a new compiler env/report without replacing the selected seam's
  authority path;
- logging `[MAT_PROMOTION]` rows while the override seam still calls the old
  predicate directly;
- using owner-result for emitted behavior in this slice;
- making any backend, remangle, keepalive, requested-name, tuple rendering, or
  `BlockOwner` carrier change in the same slice.

Next local track:

- implement the behavior-neutral helper only after this gate is in place, or
  switch to `CodePathStatus` cleanup if the source-shape/report gates show that
  the helper would not reduce the selected seam's state contract.

### Slice 0k-K: Architecture pivot and anti-tail-chase gate

Status:

- design-sealed docs-only checkpoint after the 0k-J definition gate and the
  explicit architecture pause;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, AST-read behavior, cleanup behavior, or `BlockOwner` carrier is
  changed by this slice.

ProblemCard:

- signal: repeated successful ledger/report slices still leave generated s2
  crashing before the full `MaterializationDecision` seam;
- why now: the selected 0k-J helper is locally plausible, but a locally
  plausible helper is the same pattern that produced prior symptom loops unless
  it proves a smaller state contract;
- bounded context: HIR semantic ownership and materialization naming;
- not merely: another report, crash probe, or helper wrapper;
- improvement probe: require an authority-edge replacement receipt before any
  code implementation;
- unknowns: whether generated s2 reaches the promoted seam after the helper,
  and whether the selected override seam is enough to move the full bootstrap;
- safe next move: P2W-ready only for a docs-backed edge replacement plan;
- validation boundary: source-shape evidence plus existing report
  compatibility, not a green `s2b`/`s3b` claim.

Architecture progress definition:

1. A slice is architecture progress only if it does at least one of:
   - replaces or shadows a named legacy authority edge with an owned record;
   - classifies one stale/debug/fallback path with `CodePathStatus` and a
     protecting falsifier;
   - refutes the current owner evidence with fresher generated-stage data and
     names the new owner boundary.
2. A new report or env var is not progress unless it enables one of those
   outcomes in the same slice.
3. A helper is not progress if the selected consumer still obtains its decision
   from the same direct predicate, ambient map, rendered-name comparison,
   backend function presence, or raw index after the helper lands.
4. A generated-stage crash movement is not progress unless the fixed invariant
   has a guard and the new residual boundary is named in `TODO.md` /
   `LANDMARKS.md`.

Required receipt before any 0k-J code implementation:

- `old_edge`: exact source seam and direct authority path to be replaced;
- `owned_edge`: exact `MaterializationDecision` / `MaterializationRegistry`
  record fields that the helper consumes;
- `legacy_parity`: proof that emitted behavior still returns the legacy result
  in this slice;
- `source_shape`: static check proving the promoted seam no longer calls the
  old direct authority path as its only authority;
- `report_shape`: focused report fields proving complete owner fields, zero
  malformed rows, and `emitted_result == legacy_result`;
- `generated_stage_boundary`: either promoted generated-s2 rows or the explicit
  `not_reached_named_residual` reason;
- `cleanup_impact`: whether the slice marks any old debug/probe/fallback path
  for later `CodePathStatus`, without deleting it in the same commit.

Admitted next implementation choices:

1. `0k-J owner-consumption helper`: behavior-neutral helper for exactly
   `lower_function_if_needed.override`, admitted only with the receipt above.
2. `CodePathStatus cleanup selection`: no semantic behavior change; choose one
   stale/debug/fallback cluster and classify it as `live`, `legacy_shim`,
   `debug_only`, `suspected_dead`, or `delete_blocked` with a protecting
   falsifier.
3. `Generated-stage reachability owner boundary`: behavior-neutral slice that
   names why generated s2 does not reach the selected materialization seam,
   without using backend stubs or undefined externs as the first semantic
   discovery point.

Rejected next moves:

- implementing a 0k-J helper whose only effect is to print `[MAT_PROMOTION]`
  rows;
- direct patches to `def_has_untyped_regular_param?`,
  `raw_annotation_needs_callsite_specialization?`,
  `prefer_callsite_specialization`, `lower_call.remangle`, backend
  undefined-extern handling, target keepalive, or requested-name materialization;
- global ambient-map clearing, global short-type-param rebinding, or
  `NamedTuple`/`Tuple` display normalization;
- rolling `BlockOwner` back to tuple/namedtuple metadata;
- deleting workaround/debug paths without runtime `CodePathStatus` evidence and
  a protecting falsifier.

Hostile self-review:

- strongest objection: this slice can become another docs-only delay. The guard
  is that it narrows the next code slice acceptance test to an edge-replacement
  receipt; if the receipt is missing, code is not admitted;
- second objection: selected `lower_function_if_needed.override` may be a
  focused-stage artifact because generated s2 still does not reach the seam.
  The guard is to keep generated-stage reachability as a first-class residual
  rather than claiming bootstrap movement from a stage1 helper;
- third objection: cleanup can distract from correctness. The guard is that
  `CodePathStatus` cleanup is admitted only when owner-consumption cannot
  produce the receipt, and cleanup must not substitute for semantic ownership.

Next local track:

- write the 0k-J implementation plan in terms of the required receipt above, or
  explicitly switch to `CodePathStatus` cleanup / generated-stage reachability
  if the receipt cannot be made concrete.

### Slice 0k-L: 0k-J override owner-consumption receipt

Status:

- design-sealed docs-only receipt after Slice 0k-K;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, AST-read behavior, cleanup behavior, or `BlockOwner` carrier is
  changed by this slice;
- the next code slice is admitted only if it implements this receipt
  behavior-neutrally.

Receipt:

- `old_edge`:
  `src/compiler/hir/ast_to_hir.cr` in `lower_function_if_needed_impl`, at the
  materialization override seam, currently computes
  `has_untyped_regular_param` by calling
  `state_scope_consumer_def_has_untyped_regular_param?` directly with
  consumer `lower_function_if_needed.override`, source decision
  `materialization_override`, requested name `name`, target `target_name`,
  selected `resolved_func_def`, and `call_arg_types`. That boolean directly
  decides whether the materialized function name is the requested call symbol
  (`name`) or the resolved target symbol (`target_name`).
- `owned_edge`:
  extract the existing `[MAT_DECISION]` computation into an owned
  `MaterializationDecisionRecord` (or equivalently named internal owner object)
  built from the same facts already printed by
  `log_materialization_decision`: `consumer`, `source_decision`, `requested`,
  `target`, `selected_def`, `param_class`, `state_scope`, `owner`, `decision`,
  `reason`, `legacy_result`, `would_change`, `target_map`, `call_arg_types`,
  `arg_abi`, `block_abi`, and `validation`. The helper must use this record as
  its parity/shadow input; it must not recompute authority from backend function
  presence, rendered-name normalization, or a new ambient-map rule.
- `legacy_parity`:
  the first helper returns exactly the legacy boolean used today. The owner
  record may compute and report an `owner_result`, but emitted behavior must be
  `legacy_result` until a later behavior slice has a root-sized would-change
  census admitted by this SDD.
- `source_shape`:
  after implementation, the override seam's assignment to
  `has_untyped_regular_param` must call a named promotion helper such as
  `materialization_override_shadow_untyped_regular_param?`, not
  `state_scope_consumer_def_has_untyped_regular_param?` directly. Existing
  non-promoted consumers may keep their direct calls.
- `report_shape`:
  add a focused override promotion report that is red on the pre-slice compiler
  because no promoted override rows exist, then green with rows only for
  `lower_function_if_needed.override`. Required row fields are the owned record
  fields plus `owner_result`, `emitted_result`, and `promotion`. The green gate
  requires complete owner fields, zero malformed rows, `promotion=shadow_parity`,
  and `emitted_result == legacy_result`.
- `generated_stage_boundary`:
  generated s2 must either emit promoted override rows where the seam is
  reached or preserve the explicit
  `generated_stage_status=not_reached_named_residual` /
  `no_row_reason=generated_s2_crashes_before_materialization_decision`
  boundary. This remains a residual, not a green bootstrap claim.
- `cleanup_impact`:
  this slice does not delete debug/probe/fallback paths. If it discovers stale
  helper/report paths, it may only mark them as candidates for the
  `CodePathStatus` track.

Implementation outline for the next code slice:

1. Add an internal `MaterializationDecisionRecord` builder next to the existing
   `materialization_decision_*` helpers. Reuse it from
   `log_state_scope_consumer_decision` so existing `[MAT_DECISION]` output stays
   byte-shape compatible.
2. Add a named override helper that:
   - computes `legacy_result = def_has_untyped_regular_param?(resolved_func_def)`;
   - builds the owner record for
     `consumer=lower_function_if_needed.override` /
     `source_decision=materialization_override`;
   - emits existing state-scope/materialization decision rows through the shared
     record path when those ledgers are enabled;
   - emits promotion rows only under the new promotion-report env;
   - returns `legacy_result` in all cases, including incomplete owner record
     fallback.
3. Replace only the override seam's direct call with that helper. Do not change
   `prefer_callsite_specialization`, `lower_function_if_needed.callsite_args`,
   `lower_function_if_needed.suffix_types`, `lower_call.remangle`, direct
   predicate behavior, remangling, target keepalive, requested-name
   materialization, or backend behavior.
4. Add `scripts/materialization_override_promotion_report.sh` as the executable
   red/green gate and source-shape check for this receipt.

DoD for the next code slice:

- red first:
  `CHECK_SOURCE_SHAPE=0 scripts/materialization_override_promotion_report.sh
  <pre-slice-compiler>` fails with no `[MAT_PROMOTION]` override rows;
- focused green:
  `scripts/materialization_override_promotion_report.sh <fresh-stage1>` exits
  `0` with rows only for `lower_function_if_needed.override`,
  `promotion=shadow_parity`, malformed/invalid counts at zero, and
  `emitted_result == legacy_result`;
- source-shape:
  the report or a paired static check proves the override seam calls the named
  helper and no longer calls
  `state_scope_consumer_def_has_untyped_regular_param?` directly;
- compatibility:
  `scripts/materialization_decision_report.sh <fresh-stage1>`,
  `scripts/materialization_promotion_selection_report.sh <fresh-stage1>`,
  `scripts/state_scope_consumer_report.sh <fresh-stage1>`,
  `scripts/semantic_decision_census.sh`, and
  `scripts/codepath_status_census.sh` all exit `0`;
- generated-stage residual:
  generated s2 either emits promoted rows on the focused report or reports the
  named `not_reached_named_residual` boundary with `ALLOW_NO_ROWS=1`;
- broad guard:
  run the existing focused regression suite appropriate to a behavior-neutral
  HIR helper refactor. If the helper touches only reporting/shape, `git diff
  --check` plus the report suite above is the minimum; if any compiler semantic
  path changes beyond returning the legacy boolean, run the full combined suite.

Rejected implementation shortcuts:

- returning the owner result from the helper in this slice;
- changing the old predicate globally or passing a broad boolean flag through it;
- adding a promotion row while leaving the override seam's authority path
  unchanged;
- adding backend reconciliation, keepalive, forwarder, requested-name
  materialization, remangle, or tuple-rendering changes to make the report
  greener;
- treating generated-stage `compiler_rc=139` as failure of the selected
  receipt unless the generated-stage rows reach and contradict the promoted
  seam.

Implementation evidence for the 0k-L code slice:

- `MaterializationDecisionRecord` now exists inside `AstToHir` and is reused by
  the existing `[MAT_DECISION]` report path, preserving the prior report shape.
- The selected override seam now assigns `has_untyped_regular_param` through
  `materialization_override_shadow_untyped_regular_param?`; that helper builds
  the owner record for `lower_function_if_needed.override` /
  `materialization_override`, emits `[MAT_PROMOTION]` only under
  `ADAMAS_MATERIALIZATION_OVERRIDE_PROMOTION_LEDGER=1`, and returns the legacy
  boolean.
- Red gate:
  `CHECK_SOURCE_SHAPE=0 scripts/materialization_override_promotion_report.sh
  bin/adamas` exits `1` with
  `FAIL: no [MAT_PROMOTION] override promotion rows emitted` while the compiler
  itself exits `0`.
- Focused green:
  `scripts/materialization_override_promotion_report.sh
  /private/tmp/adamas_0km_stage1` exits `0` with `rows=1062`, all malformed /
  invalid counts at `0`, consumer limited to
  `lower_function_if_needed.override`, `promotion=shadow_parity`, and
  `emitted_mismatch=0`.
- Compatibility gates:
  `scripts/materialization_decision_report.sh
  /private/tmp/adamas_0km_stage1` exits `0` with `rows=7544`,
  `malformed=0`, and `would_change_rows=0`;
  `scripts/materialization_promotion_selection_report.sh
  /private/tmp/adamas_0km_stage1` exits `0` with exactly one selected eligible
  consumer, `lower_function_if_needed.override`;
  `scripts/state_scope_consumer_report.sh /private/tmp/adamas_0km_stage1`
  exits `0` with `rows=42224`, `malformed=0`,
  `unclassified_blocked=0`, and `materialization_registry_rows=7544`;
  `scripts/semantic_decision_census.sh`, `scripts/codepath_status_census.sh`,
  and `git diff --check` all exit `0`.
- Broad guard:
  `regression_tests/run_combined.sh /private/tmp/adamas_0km_stage1` passes
  `36/36`.
- Generated-stage residual:
  fresh `/private/tmp/adamas_0km_stage1` builds fresh
  `/private/tmp/adamas_0km_s2` under `scripts/run_safe.sh` with `EXIT: 0`;
  `TIMEOUT=180 MEM_MB=8192 ALLOW_NO_ROWS=1
  scripts/materialization_override_promotion_report.sh
  /private/tmp/adamas_0km_s2 src/adamas.cr -o /private/tmp/adamas_0km_s3`
  exits `0` with `compiler_rc=139`, `rows=3`, all malformed / invalid counts
  at `0`, consumer limited to `lower_function_if_needed.override`, and
  `promotion=shadow_parity`.

Boundary after implementation:

- this is an authority-edge shadow/promotion checkpoint, not a behavior change;
- it does not claim `s2b`/`s3b` green;
- generated s2 still reaches a later `compiler_rc=139` frontier after emitting
  valid promotion rows;
- the next step remains Slice 0k-M: choose one architecture lane before any
  new behavior or generated-stage crash work.

Next local track:

- commit/close this behavior-neutral receipt slice, then choose exactly one
  Slice 0k-M architecture lane before any further behavior or generated-stage
  crash work.

### Slice 0k-M: Architecture implementation pivot after 0k-L

Status:

- design-sealed planning checkpoint for the work immediately after the 0k-L
  owner-consumption helper;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, AST-read behavior, cleanup behavior, or `BlockOwner` carrier is
  changed by this slice;
- the purpose is to prevent the project from returning to local frontier fixes
  as soon as the selected override seam has a behavior-neutral owner record.

Problem:

- the recent bootstrap history repeatedly exposed the same architecture class
  through different symptoms: ambient `@type_param_map`, requested/target/body
  symbol drift, raw AST index ownership, file identity, and backend-discovered
  stubs;
- a successful 0k-L helper would reduce one authority edge, but it would not by
  itself extract the owning services or make `s2b`/`s3b` green;
- continuing from 0k-L directly into the next crash or stub would recreate the
  same tail-chase pattern under a better diagnostic vocabulary.

Standing mini-Quadrumvirate gate for every next slice:

1. `VERIFY`: name the current owner fact already available in code, docs, or a
   report. If no owner fact exists, the slice is a census/facade slice, not a
   behavior patch.
2. `CRITICIZE`: ask whether the planned change only moves a symptom from one
   consumer to another. If yes, reject it unless it also replaces an authority
   edge or deletes a path with `CodePathStatus` evidence.
3. `BUILD`: choose one of the admitted architecture lanes below and state the
   exact old edge, new owner, source-shape guard, and falsifier.
4. `ADVERSARY`: before claiming progress, prove the slice did not widen
   behavior by accident and did not create a new ledger without a promotion or
   deletion path.

Admitted architecture lanes after 0k-L:

1. `MaterializationDecision owner extraction`
   - Goal: turn the current internal record/helpers into a side-effect-bounded
     owner surface for requested, selected, target, materialized, and emitted
     symbol identity.
   - First slice: keep behavior unchanged, but make one additional legacy
     materialization consumer obtain its parity input through the owner record
     or explicitly classify why it cannot.
   - Rejected shortcut: force requested-name materialization, target keepalive,
     backend forwarders, or remangle changes before the transaction owner can
     classify the row as `exact`, `materialization_keepalive`,
     `wrapper_forwarder`, or `rejected_mismatch`.

2. `SemanticStateScope facade`
   - Goal: make ambient state such as `@type_param_map`, current class/method,
     namespace owner, and pending arg maps readable only through an explicit
     scope snapshot at naming/materialization seams.
   - First slice: add a behavior-neutral scope snapshot at one selected seam and
     prove parity against the legacy ambient reads.
   - Rejected shortcut: globally clear or ignore ambient maps, or add a boolean
     mode to old predicates that lets consumers choose semantics ad hoc.

3. `NameResolution / MethodNameCodec boundary`
   - Goal: make parsing, suffix interpretation, owner extraction, and mangled
     name normalization a typed service rather than repeated string slicing.
   - First slice: shadow-parse the names used by one materialization or overload
     report and prove byte-equivalent legacy output for the regression corpus.
   - Rejected shortcut: normalize `NamedTuple`/`Tuple`, owner strings, or
     builtin names only at the failing consumer.

4. `AstNodeRef / ArenaOwnership boundary`
   - Goal: make AST reads use owner-scoped references instead of raw `ExprId`
     indexes plus current-arena assumptions.
   - First slice: route one read-only ledger or one non-behavioral helper
     through `AstNodeRef` after owner parity is proven, without changing raw
     read behavior.
   - Rejected shortcut: broad arena scans, current-arena fallbacks, or
     containment heuristics as authority.

5. `Runtime CodePathStatus cleanup`
   - Goal: reduce codebase bloat without deleting semantic carriers.
   - First slice: choose one cluster from `scripts/codepath_status_census.sh`,
     add runtime status rows if needed, and mark it `live`, `debug_only`,
     `legacy_shim`, `suspected_dead`, or `delete_blocked` with a protecting
     falsifier.
   - Rejected shortcut: deleting debug/workaround/fallback paths because they
     look old or because a newer owner facade exists nearby.

Next local track:

- close the 0k-L helper/report slice as behavior-neutral or revert it; then
  choose exactly one admitted lane above for the next code slice;
- do not resume generated-stage crash localization, backend stub work, or
  materialization behavior changes until the chosen lane states its owner fact
  and source-shape/falsifier gates.

### Slice 0k-N: Post-promotion selection no-repeat gate

Status:

- implemented behavior-neutral report hardening after Slice 0k-L;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, AST-read behavior, cleanup behavior, or `BlockOwner` carrier is
  changed by this slice.

Problem:

- Slice 0k-I selected `lower_function_if_needed.override` as the first
  eligible `MaterializationDecision` promotion consumer;
- Slice 0k-L promoted that seam in shadow/parity mode;
- without a no-repeat gate, the promotion-selection report still selects the
  already promoted seam as `eligible_promote_owner`, which would send the next
  architecture step back through the same local lane and recreate the
  tail-chase pattern this SDD is trying to prevent.

Implementation:

- `scripts/materialization_promotion_selection_report.sh` now accepts
  `PROMOTED_CONSUMERS=<comma-list>` and, by default,
  `AUTO_DETECT_PROMOTED=1`;
- the report auto-detects the 0k-L source shape:
  `materialization_override_shadow_untyped_regular_param?` exists, the
  override seam assigns `has_untyped_regular_param` through that helper, and
  the same assignment window no longer calls
  `state_scope_consumer_def_has_untyped_regular_param?` directly;
- detected promoted consumers receive
  `selection_status=already_promoted_shadow`;
- when the preferred consumer is already promoted, `selected_count=0` is the
  expected green result and the report prints
  `preferred_already_promoted=1`.

Falsifiers:

- `AUTO_DETECT_PROMOTED=0
  scripts/materialization_promotion_selection_report.sh
  /private/tmp/adamas_0kn_stage1` preserves the old baseline:
  `lower_function_if_needed.override` has
  `selection_status=eligible_promote_owner`, `eligible_count=1`,
  `selected_count=1`, and `preferred_already_promoted=0`;
- default
  `scripts/materialization_promotion_selection_report.sh
  /private/tmp/adamas_0kn_stage1` now reports
  `promoted_consumers=lower_function_if_needed.override`, the override row has
  `selection_status=already_promoted_shadow`, `eligible_count=0`,
  `selected_count=0`, and `preferred_already_promoted=1`.

Boundary:

- this is a report/gate correction only;
- it does not delete old consumers, change any compiler semantic decision, or
  claim `s2b`/`s3b` progress;
- it deliberately classifies the focused post-0k-L `MaterializationDecision`
  lane as having no second eligible consumer in the current report surface.

Next local track:

- switch the next implementation lane to `SemanticStateScope facade` unless a
  fresh report with a different focused repro names another unpromoted
  `MaterializationDecision` consumer with complete owner fields and a
  root-sized would-change census;
- the next code slice should add a behavior-neutral scope snapshot at a naming
  or materialization seam and prove parity against legacy ambient reads.

### Slice 0k-O: SemanticStateScope admission gate

Status:

- design-sealed planning checkpoint after Slice 0k-N;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, AST-read behavior, cleanup behavior, or `BlockOwner` carrier is
  changed by this slice;
- the purpose is to prevent the `SemanticStateScope` lane from becoming another
  sequence of shadow ledgers that do not reduce authority edges.

Problem:

- Slice 0k-N correctly routes the next near-term architecture lane to
  `SemanticStateScope`, because the focused post-0k-L
  `MaterializationDecision` surface has no second eligible consumer;
- the current wording still admits a weak next move: add a behavior-neutral
  scope snapshot and a report, but leave every consumer reading ambient state
  through the same legacy helper;
- that weak shape would repeat the old failure mode under a new vocabulary:
  evidence grows, but the old authority edge remains live and the next frontier
  can still be patched at a consumer.

Mini-Quadrumvirate receipt for the next code slice:

1. `VERIFY`: name the exact legacy ambient-state edge and the existing owner
   fact it already exposes. For the preferred first seam this is expected to be
   `prefer_callsite_specialization` reading
   `state_scope_consumer_def_has_untyped_regular_param?` directly, with owner
   facts already present in `[STATE_SCOPE_CONSUMER]` rows.
2. `CRITICIZE`: prove that the proposed slice does not merely add a new report.
   A new ledger is admitted only if a source-shape guard proves the selected
   consumer no longer calls the legacy edge directly.
3. `BUILD`: introduce a named `SemanticStateScopeSnapshot` or equivalently
   named internal owner object for exactly one selected seam. The snapshot may
   observe the legacy result for parity, but emitted behavior must still return
   the legacy result until a later would-change slice is admitted.
4. `ADVERSARY`: run a no-repeat/source-shape report that rejects already
   promoted seams, rejects broad or multi-consumer migrations, and proves
   `emitted_result == legacy_result`.

Admitted next code slice:

- choose exactly one `SemanticStateScope` consumer seam before implementation;
- record the receipt fields:
  - `old_edge`: direct ambient-state read or legacy helper call at the selected
    consumer;
  - `owned_edge`: `SemanticStateScopeSnapshot` fields used by that consumer;
  - `legacy_parity`: the helper returns the same boolean/value the old edge
    returned;
  - `source_shape`: the selected consumer no longer calls the old helper
    directly;
  - `report_shape`: rows are limited to the selected consumer, include complete
    authority/lifetime/map fields, and fail closed on malformed rows;
  - `generated_stage_boundary`: a generated-stage run may stop at the current
    residual frontier, but any claim must state where the new seam was or was
    not reached;
  - `cleanup_impact`: whether the old direct call is eliminated only at the
    selected seam, remains elsewhere, or becomes a delete candidate.

Rejected next moves:

- adding a `SemanticStateScope` report whose only effect is to print new rows;
- adding a boolean mode to `def_has_untyped_regular_param?`,
  `raw_annotation_needs_callsite_specialization?`, or related helpers;
- globally clearing, ignoring, or trusting `@type_param_map`;
- migrating multiple state-scope consumers in one slice;
- treating `diagnostic_only`, `keep_legacy_shim`, or `blocked_unknown` rows as
  behavior authority;
- backend undefined-extern rescue, target keepalive, requested-name
  materialization, remangling, `NamedTuple`/`Tuple` display normalization, or
  rolling `BlockOwner` back to tuple/namedtuple metadata.

Stop rules:

- if the selected seam cannot name `old_edge`, `owned_edge`, source-shape guard,
  and falsifier before code, stop and switch to `CodePathStatus` cleanup
  selection instead of adding another scope ledger;
- if a would-change census for the selected seam is broader than the named seam
  or contains unrelated behavior classes, stop and classify before patching;
- if the source-shape report cannot distinguish already promoted seams from
  unpromoted ones, stop before adding the helper.

DoD for the next code slice:

- red gate: the new SemanticStateScope promotion/admission report fails on a
  pre-slice compiler with no promoted state-scope rows or with the old direct
  source shape still present;
- green source-shape gate: the selected consumer obtains parity input through
  the owned snapshot and no longer calls the old helper directly;
- green report gate: rows are limited to the selected consumer, malformed and
  invalid counts are zero, authority/lifetime/map fields are complete, and
  `emitted_result == legacy_result`;
- compatibility gates: existing `state_scope_consumer_report`,
  `materialization_promotion_selection_report`, `semantic_decision_census`, and
  `codepath_status_census` still pass;
- behavior gate for code changes: focused regression suite and a fresh
  generated-s2 smoke must be run, with any residual generated-stage boundary
  named explicitly in `TODO.md` / `LANDMARKS.md`.

Boundary:

- this is an admission gate, not an implementation;
- it does not claim `s2b`/`s3b` progress;
- it narrows the next `SemanticStateScope` code slice from "add a snapshot" to
  "replace one named ambient-state authority edge in shadow/parity mode."

Next local track:

- implement the first `SemanticStateScope` owner-consumption slice only after a
  concrete receipt names the selected seam. The current preferred candidate is
  `prefer_callsite_specialization`, but that preference must be rechecked
  against the live `StateScopeConsumer` report before code;
- if that receipt cannot be made root-sized, switch to runtime
  `CodePathStatus` cleanup selection rather than continuing diagnostic
  expansion.

### Slice 0k-P: SemanticStateScope admission selection report

Status:

- implemented behavior-neutral report after Slice 0k-O;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, AST-read behavior, cleanup behavior, or `BlockOwner` carrier is
  changed by this slice.

Problem:

- Slice 0k-O says that the next `SemanticStateScope` code slice must replace
  one named ambient-state edge, but it deliberately does not choose that edge
  from memory or source inspection alone;
- the broad `StateScopeConsumer` report is useful but too wide to directly
  authorize code: it reports tens of thousands of consumer rows and thousands of
  owner-result would-change rows across unrelated consumers;
- the next code slice therefore needs a selection/admission gate that consumes
  the existing state-scope evidence, rejects broad or late seams, and exposes a
  red mode for the future owner-consumption helper.

Implementation:

- added `scripts/semantic_state_scope_admission_report.sh`;
- the report runs the existing compiler under
  `ADAMAS_STATE_SCOPE_CONSUMER_LEDGER=1`, parses `[STATE_SCOPE_CONSUMER]` rows,
  and emits `[STATE_SCOPE_ADMISSION]` candidate rows;
- source-shape detection currently focuses on the expected first seam,
  `prefer_callsite_specialization`:
  - `legacy_direct_edge` means the method still calls
    `state_scope_consumer_def_has_untyped_regular_param?` directly;
  - `already_promoted_shadow` means a future
    `semantic_state_scope_prefer_callsite_specialization_shadow_untyped_regular_param?`
    helper is called and the legacy helper is no longer called directly;
  - `missing_old_edge` fails selection because neither shape is admissible.
- default mode selects exactly one `eligible_scope_owner`;
- `REQUIRE_PROMOTED=1` is the red gate for the next code slice: it must fail
  until the selected consumer is actually routed through the promoted
  `SemanticStateScope` owner in shadow/parity mode.

Fresh evidence:

- fresh stage1 build:
  `crystal build src/adamas.cr -o /private/tmp/adamas_0kp_stage1 --error-trace`;
- default report:
  `TIMEOUT=180 MEM_MB=4096 SAMPLES=3
  scripts/semantic_state_scope_admission_report.sh
  /private/tmp/adamas_0kp_stage1`;
- observed selection:
  - `rows=42224`;
  - `malformed=0`;
  - `preferred_consumer=prefer_callsite_specialization`;
  - `preferred_source_shape=legacy_direct_edge`;
  - `preferred_rows=3448`;
  - migration buckets for the preferred seam:
    `migrate_to_state_scope=1256`,
    `migrate_to_materialization_registry=1063`,
    `rejected_ambient=269`, `keep_legacy_shim=860`;
  - `[STATE_SCOPE_ADMISSION] consumer=prefer_callsite_specialization ...
    selection_status=eligible_scope_owner`;
  - all other current consumers are rejected as later/too late/direct predicate
    helpers/already materialization-promoted;
  - `eligible_count=1`, `selected_count=1`, `already_promoted_count=0`.
- red mode:
  `REQUIRE_PROMOTED=1 ... semantic_state_scope_admission_report.sh ...`
  exits `9` with `preferred_source_shape=legacy_direct_edge` and
  `already_promoted_count=0`, proving the next code slice has a real red gate.

Boundary:

- this is a selection/report slice only;
- it does not implement `SemanticStateScopeSnapshot` and does not change
  emitted semantics;
- the preferred seam is now selected for a future shadow/parity helper, but the
  report also exposes why behavior changes remain blocked: the preferred seam
  spans multiple migration classes and has `keep_legacy_shim` /
  `rejected_ambient` rows that are not behavior authority.

Next local track:

- implement a `SemanticStateScope` owner-consumption helper for
  `prefer_callsite_specialization` only if it satisfies the 0k-O receipt:
  old edge removed from that seam, owned snapshot fields complete,
  `emitted_result == legacy_result`, and the new report's
  `REQUIRE_PROMOTED=1` mode turns green;
- do not migrate `lower_call.remangle`, `lower_function_if_needed.*`, direct
  predicate helper rows, or any behavior result in the same slice.

### Slice 0k-Q: SemanticStateScope ownership contract before helper code

Status:

- design-sealed docs-only checkpoint after Slice 0k-P hostile self-review;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, AST-read behavior, cleanup behavior, or `BlockOwner` carrier is
  changed by this slice;
- a local uncommitted helper/report WIP for `SemanticStateScopeSnapshot` was
  removed before commit because it risked becoming another diagnostic wrapper
  around the old ambient predicate instead of an authority-edge migration.

Problem:

- Slice 0k-P selected exactly one first `SemanticStateScope` seam:
  `prefer_callsite_specialization`;
- the tempting next move is to introduce a helper that logs a
  `SemanticStateScopeSnapshot` and returns the legacy boolean;
- that shape is admitted only if it proves that the selected consumer no longer
  obtains its semantic authority from the old ambient-state path;
- if the helper still treats `def_has_untyped_regular_param?` or
  `raw_annotation_needs_callsite_specialization?` as the authority rather than
  a parity source, the slice has not improved architecture. It has only moved
  the same oracle behind a new name.

Ownership contract:

1. `decision`: the single semantic question owned by this slice is whether a
   callsite-specialized symbol should be preferred for the selected definition.
2. `selected_consumer`: exactly `prefer_callsite_specialization`.
3. `old_authority_edge`: direct use of
   `state_scope_consumer_def_has_untyped_regular_param?` /
   `def_has_untyped_regular_param?` from the selected consumer.
4. `owned_record`: a `SemanticStateScopeDecision` or equivalently named object
   that records requested symbol, target symbol, selected definition, target
   map, ambient map snapshot, callsite arg types, lifetime, authority class,
   migration class, legacy parity result, owner result, and emitted result.
5. `parity_only_source`: the legacy predicate may still be evaluated in the
   helper, but only as `legacy_result` for parity. It is not allowed to be the
   only named authority in the row/report.
6. `owner_result`: the owned record must compute and print the owner decision
   separately from `legacy_result`. While behavior remains unchanged,
   `emitted_result` must equal `legacy_result`; a later would-change slice is
   required before emitted behavior may equal `owner_result`.
7. `source_shape`: the selected consumer must call the named owner helper and
   must not call `state_scope_consumer_def_has_untyped_regular_param?`
   directly. Other legacy consumers may remain unchanged and must be counted as
   residual surface, not silently considered migrated.

Wrapper-theater rejection test:

- If the new helper only logs fields and returns
  `def_has_untyped_regular_param?` without a separately named owner result, the
  slice is diagnostic-only and must not be committed as architecture progress.
- If the report cannot prove rows are limited to
  `prefer_callsite_specialization`, the slice is too broad.
- If `owner_result` is just a stringified copy of `legacy_result` for every
  row without an owner computation and a mismatch bucket, the slice is not an
  ownership contract.
- If the helper requires a boolean mode on
  `def_has_untyped_regular_param?` or
  `raw_annotation_needs_callsite_specialization?`, stop; that repeats the
  rejected consumer-predicate patch family.

DoD for the future code slice:

- pre-slice red gate: `REQUIRE_PROMOTED=1
  scripts/semantic_state_scope_admission_report.sh <compiler>` fails because
  the selected seam is still `legacy_direct_edge`;
- green source-shape gate: the report identifies
  `prefer_callsite_specialization` as `already_promoted_shadow`, and no other
  consumer is counted as promoted;
- green ownership gate: every promoted row has complete requested/target/
  selected-def/map/lifetime fields, a nonempty owner-result field, and zero
  malformed rows;
- parity gate: `emitted_result == legacy_result` for all promoted rows;
- mismatch census: if `owner_result != legacy_result` appears, it is reported
  as would-change evidence only and does not change behavior in the same
  commit;
- compatibility gates: existing `state_scope_consumer_report`,
  `materialization_promotion_selection_report`, `semantic_decision_census`,
  and `codepath_status_census` still pass;
- bootstrap guard: a fresh generated-s2 smoke is run or the residual boundary
  is stated explicitly if the focused seam is not reached.

Rejected next moves:

- committing a helper/report whose only effect is new
  `[STATE_SCOPE_PROMOTION]` rows;
- treating the legacy predicate result as the owned state-scope result without
  a separately named owner computation;
- migrating `lower_call.remangle`, `lower_function_if_needed.*`, direct
  predicate helper rows, or behavior results in the same commit;
- resuming backend forwarder, requested-name materialization, target keepalive,
  `NamedTuple`/`Tuple` normalization, or `BlockOwner` rollback work from this
  seam;
- deleting the old helper globally before all remaining consumers are
  classified.

Next local track:

- implement the `prefer_callsite_specialization` owner helper only after this
  contract is satisfied in the patch plan;
- otherwise switch to runtime `CodePathStatus` cleanup selection rather than
  adding more state-scope diagnostics.

### Slice 0k-R: prefer_callsite SemanticStateScope owner helper

Status:

- implemented behavior-neutral owner-consumption helper after Slice 0k-Q;
- one selected consumer, `prefer_callsite_specialization`, now routes through
  a named `SemanticStateScopeDecision` helper;
- compiler behavior remains unchanged because the helper returns
  `legacy_result` as `emitted_result`;
- no materialization behavior, remangling behavior, backend behavior,
  AST-read behavior, cleanup behavior, or `BlockOwner` carrier changed.

Implementation:

- added default-off `ADAMAS_SEMANTIC_STATE_SCOPE_PROMOTION_LEDGER`;
- added an internal `SemanticStateScopeDecision` record with requested symbol,
  target symbol, selected definition, authority, migration, validation, legacy
  result, owner result, emitted result, ambient map snapshot, target map,
  callsite arg types, and lifetime;
- `owner_result` is an owner classification
  (`state_scope`, `materialization_registry`, `rejected_ambient`,
  `legacy_shim`), not a behavior result;
- `prefer_callsite_specialization` now calls
  `semantic_state_scope_prefer_callsite_specialization_shadow_untyped_regular_param?`;
- the legacy predicate is still evaluated, but only inside the helper as
  parity input. The selected consumer no longer calls
  `state_scope_consumer_def_has_untyped_regular_param?` directly.

Falsifiers and evidence:

- pre-slice red gate:
  `REQUIRE_PROMOTED=1 scripts/semantic_state_scope_admission_report.sh
  /private/tmp/adamas_0kq2_red` exited `9` with
  `preferred_source_shape=legacy_direct_edge`, `selected_count=1`, and
  `already_promoted_count=0`;
- fresh stage1 build:
  `crystal build src/adamas.cr -o /private/tmp/adamas_0kq2_stage1
  --error-trace`;
- green promotion gate:
  `REQUIRE_PROMOTED=1 scripts/semantic_state_scope_admission_report.sh
  /private/tmp/adamas_0kq2_stage1` exits `0` with
  `preferred_source_shape=already_promoted_shadow`, `promotion_rows=3448`,
  `promotion_non_preferred=0`, `promotion_malformed=0`,
  `promotion_invalid=0`, `promotion_emitted_mismatch=0`,
  `eligible_count=0`, `selected_count=0`, and `already_promoted_count=1`;
- owner-result buckets for promoted rows:
  `state_scope=1256`, `materialization_registry=1063`,
  `rejected_ambient=269`, `legacy_shim=860`;
- default admission report also marks only
  `prefer_callsite_specialization` as `already_promoted_shadow`;
- compatibility reports remain green:
  `scripts/state_scope_consumer_report.sh`,
  `scripts/materialization_promotion_selection_report.sh`,
  `scripts/semantic_decision_census.sh`, and
  `scripts/codepath_status_census.sh`;
- env-off smoke emits no `[STATE_SCOPE_PROMOTION]` rows and the produced
  binary prints `1`;
- full stage1 regression suites pass: `152/152` original and `36/36`
  combined;
- fresh generated s2 builds with `EXIT: 0` and compiles/runs a no-prelude
  `x = 1` smoke; generated-s2 full-prelude `x = 1` still exits `139` after
  `pass3 after lower_main call`.

Boundary:

- this is a shadow/parity owner-consumption slice, not a behavior change;
- it does not claim green full-prelude generated s2, `s2b`, or `s3b`;
- it does not authorize changing emitted behavior to `owner_result`;
- it does not migrate `lower_call.remangle`, `lower_function_if_needed.*`,
  direct predicate helper rows, or any backend/materialization behavior.

Next local track:

- do not reselect `prefer_callsite_specialization` in the next state-scope
  slice; it is already promoted in shadow mode;
- either add a no-repeat selection gate for a genuinely different
  `SemanticStateScope` consumer, or switch to runtime `CodePathStatus` cleanup
  selection if no root-sized consumer can be admitted;
- behavior-changing call/materialization work remains blocked until a future
  would-change census consumes an owned record and proves a root-sized change
  set.

### Slice 0k-S: CodePathStatus cleanup selection for identity_dry_run

Status:

- implemented behavior-neutral cleanup selection report after Slice 0k-R;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, AST-read behavior, deletion behavior, or `BlockOwner` carrier is
  changed by this slice;
- the selected path is classified, not deleted.

Problem:

- after the first `SemanticStateScope` seam was promoted, the active SDD
  required either a different root-sized state-scope seam or an explicit switch
  to runtime `CodePathStatus` cleanup selection;
- the current state-scope admission report does not name a second admitted
  consumer;
- cleanup must start with a runtime-observed path and a protecting falsifier,
  not with deletion of old debug/probe code.

Implementation:

- added `scripts/codepath_status_cleanup_selection_report.sh`;
- default selected path: `identity_dry_run`;
- the report runs the compiler twice with `ADAMAS_CODEPATH_STATUS_LEDGER=1`:
  one default run, and one run with `ADAMAS_IDENTITY_DRY_RUN=1`;
- it requires exactly one selected runtime row in each run, no malformed rows,
  default status `not_taken`, enabled status `taken`, category `cli.metrics`,
  and owner `CLI`;
- it emits one `[CODEPATH_CLEANUP_SELECTION]` row with
  `status=debug_only`, `protecting_falsifier=env_off_not_taken_env_on_taken`,
  and `action=classify_only`.

Falsifiers and evidence:

- fresh stage1 build:
  `crystal build src/adamas.cr -o /private/tmp/adamas_0ks_stage1
  --error-trace`;
- cleanup selection:
  `SELECTED_CLEANUP_PATH=identity_dry_run
  scripts/codepath_status_cleanup_selection_report.sh
  /private/tmp/adamas_0ks_stage1` exits `0` with `default_rc=0`,
  `enabled_rc=0`, default `rows=26`, default selected status `not_taken`,
  enabled `rows=26`, enabled selected status `taken`, and
  `[CODEPATH_CLEANUP_SELECTION] cluster=cli.metrics path=identity_dry_run
  owner=CLI status=debug_only ... action=classify_only`;
- existing `scripts/codepath_status_runtime_report.sh` still reports
  `rows=26`, `malformed=0`, `taken=8`, and `not_taken=18` on the focused
  no-prelude run;
- static `scripts/codepath_status_census.sh` and
  `scripts/semantic_decision_census.sh` still run;
- `bash -n` and `git diff --check` pass.

Boundary:

- this is a cleanup-selection slice only;
- `identity_dry_run` is `debug_only`, not `delete_ready`;
- no deletion, quarantine, behavior change, or bootstrap claim is made;
- runtime liveness is not a substitute for semantic ownership.

Next local track:

- either add another CodePathStatus cleanup selection for a named path from the
  static census, or promote `identity_dry_run` toward deletion only after a
  separate `delete_ready` slice proves no default behavior change and preserves
  any useful evidence in docs/regressions;
- do not remove debug/probe gates merely because this report classified one
  path as `debug_only`.

### Slice 0k-T: Active architecture board consolidation

Status:

- design-sealed docs/control-plane checkpoint after Slice 0k-S;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, AST-read behavior, deletion behavior, or `BlockOwner` carrier is
  changed by this slice;
- the SDD now has one authoritative current decision surface:
  `Active Architecture Board`.

Problem:

- the SDD intentionally preserves many historical "Current next-slice decision
  after ..." paragraphs;
- those entries are valuable evidence, but they had grown into a competing
  set of apparent next steps;
- selecting work from that append-only history risks repeating the same
  tail-chase pattern under better terminology.

Implementation:

- added an `Active Architecture Board` near the top of this SDD;
- declared the board authoritative over older current-decision ledger
  paragraphs;
- bucketed the current architecture surface into five owner boundaries:
  `SemanticStateScope`, `MaterializationIdentity` / `MaterializationRegistry`,
  `NameResolution` / `MethodNameCodec`, `AstNodeRef` / `ArenaOwnership`, and
  `CodePathStatus`;
- recorded the admitted movement and forbidden repeat for each boundary;
- added a compact mini-Quadrumvirate gate for every future slice.

Boundary:

- this is not a new diagnostic ledger and not a correctness fix;
- it does not claim green full-prelude generated s2, `s2b`, or `s3b`;
- it does not delete `identity_dry_run` or any other debug/probe path;
- it makes stale decision history subordinate to the active board.

Next local track:

- default correctness architecture lane:
  `NameResolution` / `MethodNameCodec` plus
  `MaterializationIdentity` ownership, because repeated frontiers are still
  symbol/owner identity failures;
- cleanup lane remains admitted only as an explicit `CodePathStatus` slice
  with its own path, falsifier, and deletion/quarantine boundary;
- no future slice should start from an old "Current next-slice decision after
  ..." paragraph without first mapping it to one active board row.

### Slice 0k-U: MethodNameCodec admission selection

Status:

- implemented behavior-neutral source-shape admission report after Slice 0k-T;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, AST-read behavior, deletion behavior, or `BlockOwner` carrier is
  changed by this slice;
- the selected owner boundary is `NameResolution` / `MethodNameCodec`.

Problem:

- the active board points the correctness lane at typed symbol/method identity,
  but the code already contains a mix of `MethodNameParts`, compact legacy
  helpers, and direct rendered-string checks;
- implementing another parser or normalizer without selecting a consumer seam
  would repeat the diagnostic-wrapper pattern;
- the next code slice needs a red/green source-shape gate that names one old
  authority edge and one intended owned helper.

Implementation:

- added `scripts/method_name_codec_admission_report.sh`;
- the report selects exactly one first seam:
  `lower_function_if_needed.exact_lookup_keep_requested_name`;
- the old authority edge is the exact-lookup naming branch that decides
  `keep_requested_name` from rendered suffix/arity checks:
  `name.includes?('$')`, `!name.includes?("$arity")`, and
  `resolved_entry_name.includes?("$arity")`;
- the intended owned edge for a future code slice is
  `method_name_codec_exact_lookup_keep_requested_name?`;
- sibling keep-requested-name seams are reported but rejected for now because
  they mix state-scope, collection/module parameter policy, and suffix parsing;
- low-level helpers such as `method_suffix` and `method_owner_from_name` are
  rejected as first migration targets because they are not materialization
  authority seams.

Falsifiers and evidence:

- default source-shape selection:
  `scripts/method_name_codec_admission_report.sh` exits `0` with
  `preferred_source_shape=legacy_string_edge`,
  `selection_status=eligible_codec_owner`,
  `exact_old_requested_suffix_count=1`,
  `exact_old_resolved_arity_count=1`, and `exact_helper_count=0`;
- red gate for the future code slice:
  `REQUIRE_PROMOTED=1 scripts/method_name_codec_admission_report.sh` exits
  `9` with the same selected seam, proving the seam has not yet been promoted;
- this report is source-shape only and does not run or change the compiler.

Boundary:

- this is a MethodNameCodec admission gate, not a behavior fix;
- it does not change requested-name vs target-name materialization behavior;
- it does not claim green full-prelude generated s2, `s2b`, or `s3b`;
- it does not authorize global method-name normalization, backend remangling,
  or a lower-level helper rewrite.

Next local track:

- implement a shadow/parity helper for exactly
  `lower_function_if_needed.exact_lookup_keep_requested_name`;
- future green criteria: the selected source shape becomes
  `already_promoted_shadow`, `REQUIRE_PROMOTED=1` exits `0`, behavior remains
  unchanged, and sibling seams remain unselected residual surface;
- no behavior-changing naming/materialization patch is admitted until this
  selected seam consumes a typed MethodNameCodec-owned fact in shadow/parity
  mode.

### Slice 0k-V: MethodNameCodec exact-lookup shadow helper

Status:

- implemented a behavior-neutral shadow/parity helper for the seam selected by
  Slice 0k-U;
- no default compiler behavior, materialization naming behavior, backend
  remangling behavior, `BlockOwner` carrier, or deletion behavior changed;
- emitted behavior still returns the legacy string-check result.

Problem:

- Slice 0k-U selected the exact-lookup `keep_requested_name` branch as the first
  `MethodNameCodec` authority seam;
- before this slice, `lower_function_if_needed_impl` still directly decided the
  exact-lookup requested-name preservation from rendered string checks:
  `name.includes?('$')`, `!name.includes?("$arity")`, and
  `resolved_entry_name.includes?("$arity")`;
- leaving those checks inline meant the board had a selected seam but no
  promoted consumer.

Implementation:

- added `method_name_codec_exact_lookup_keep_requested_name?`;
- the helper preserves legacy short-circuit behavior for the emitted result;
- added `method_name_codec_exact_lookup_owner_keep_requested_name?`, which uses
  `MethodNameParts` / suffix facts as the shadow owner result;
- added default-off `ADAMAS_METHOD_NAME_CODEC_PROMOTION_LEDGER=1` rows with
  requested/resolved/base names, requested/resolved suffixes, legacy result,
  owner result, emitted result, and parity status;
- replaced only the selected exact-lookup consumer with the helper call;
- intentionally left sibling `callsite_args_keep_requested_name` and
  `suffix_types_keep_requested_name` seams untouched because Slice 0k-U
  classified them as mixed state-scope/suffix policy.

Falsifiers and evidence:

- source-shape promotion:
  `scripts/method_name_codec_admission_report.sh` exits `0` with
  `preferred_source_shape=already_promoted_shadow`,
  `selection_status=already_promoted_shadow`,
  `exact_old_requested_suffix_count=0`,
  `exact_old_resolved_arity_count=0`, and `exact_helper_count=2`;
- red-to-green gate:
  `REQUIRE_PROMOTED=1 scripts/method_name_codec_admission_report.sh` exits
  `0`;
- build and regression evidence are recorded in `TODO.md` / `LANDMARKS.md` for
  the commit that lands this slice:
  `crystal build src/adamas.cr -o /private/tmp/adamas_method_codec_stage1
  --error-trace`, focused split/materialization/dispatch guards, fresh stage1
  -> fresh s2 under `scripts/run_safe.sh`, and generated-s2 no-prelude `x = 1`
  compile/run smoke all pass within the stated scope.

Boundary:

- this is a MethodNameCodec consumer-promotion slice, not a behavior fix;
- the owner result is shadow evidence, not the emitted decision;
- it does not claim green full-prelude generated s2, `s2b`, or `s3b`;
- it does not authorize global method-name normalization, backend remangling,
  lower-level helper rewrites, or a `NamedTuple`/`Tuple` display fix.

Next local track:

- if staying on `MethodNameCodec`, run or extend the promotion ledger on a
  generated-stage corridor and classify parity/divergence rows before any
  behavior flip;
- otherwise choose the next active-board row explicitly, with one old authority
  edge, one owned fact, and one red/green falsifier.

### Slice 0k-W: plan pause after MethodNameCodec shadow helper

Status:

- docs-only control-plane pause after Slice 0k-V;
- stale local `scripts/method_name_codec_promotion_report.sh` scratch was
  removed instead of promoted into the repo;
- no compiler source, emitted behavior, generated-stage behavior,
  materialization naming, backend remangling, `BlockOwner` carrier, or deletion
  behavior changed.

Problem:

- Slice 0k-V already promoted the selected `MethodNameCodec` consumer in
  shadow/parity mode;
- the next tempting move was to add another report wrapper around
  `ADAMAS_METHOD_NAME_CODEC_PROMOTION_LEDGER=1`;
- that shape is only architecture work if it answers a named SDD decision, such
  as "is this shadow owner result safe to flip?" or "which unpromoted seam is
  next?";
- otherwise it repeats the same tail-chase pattern: more evidence rows without
  fewer authority edges.

Decision:

- pause production code and report-surface growth before the next slice;
- a generated-stage MethodNameCodec report may be used as ephemeral evidence,
  but committing a new report requires its own SDD slice with:
  `old_edge`, `owned_fact`, `decision_question`, `red_gate`, `green_gate`,
  `generated_stage_boundary`, and `cleanup_rule`;
- if that receipt cannot be written, the next slice must select another board
  row or move to `CodePathStatus` cleanup with a named path and protecting
  falsifier;
- the active default remains `NameResolution` / `MethodNameCodec` plus
  `MaterializationIdentity`, but the unit of progress is authority-edge
  reduction, not ledger count.

Boundary:

- this is not a behavior fix and not a green full-prelude generated s2, `s2b`,
  or `s3b` claim;
- it does not authorize flipping `method_name_codec_*` owner results into
  emitted behavior;
- it does not authorize backend forwarders, target keepalive, requested-name
  forcing, `NamedTuple`/`Tuple` normalization, or `BlockOwner` rollback.

Next local track:

- write a concrete implementation receipt for the next active-board move before
  editing production code;
- preferred receipt shape: one `NameResolution` / `MethodNameCodec` or
  `MaterializationIdentity` authority edge, one owned typed fact that shadows or
  replaces it, a source-shape gate, and a generated-stage residual boundary;
- if the receipt would only introduce another report, delete the scratch and
  choose a different board row.

### Slice 0k-X: materialization symbol-binding implementation receipt

Status:

- docs-only implementation receipt selecting the next `MaterializationIdentity`
  code slice;
- no compiler source, emitted behavior, generated-stage behavior,
  materialization naming, backend remangling, `BlockOwner` carrier, or deletion
  behavior changed.

Problem:

- previous materialization and MethodNameCodec slices added owner facts and
  promoted selected consumers in shadow mode, but the central symbol-binding
  decision is still split across inline local branches in
  `lower_function_if_needed_impl`;
- `materialized_name` is chosen from `materialize_requested_instance_wrapper`,
  `requested_shape_keyed_block_specialization?`, or `resolved_target_name`;
- `override` is chosen later from requested-wrapper, deferred-lookup,
  untyped-regular-param, or target-materialization branches;
- `record_materialization_keepalive_candidate` and
  `log_materialization_identity_ledger` then receive separately computed symbol
  values;
- this means requested symbol, resolved target symbol, materialized body symbol,
  call-symbol hint, state-scope authority, and keepalive requirement are still
  not one owned fact.

Selected next code slice:

- `board_row`: `MaterializationIdentity` / `MaterializationRegistry`;
- `selected_seam`: `lower_function_if_needed.symbol_binding`;
- `old_edge`: the inline `materialized_name = if ...` block, the later
  `override = if ...` block, and the downstream keepalive/log calls that consume
  those separate locals;
- `owned_fact`: a `MaterializationSymbolBinding` (name may vary, but the role
  must be explicit) built at the HIR materialization seam from requested
  `MethodNameParts`, resolved target `MethodNameParts`, shape-specialization
  facts, selected definition, state-scope/materialization decision facts,
  target map, callsite arg types, and ABI class;
- `legacy_parity`: the helper must return the same materialized body symbol,
  override symbol, call-symbol hint, and keepalive target as the legacy inline
  branches;
- `emitted_behavior`: unchanged. The helper is an owner/shadow extraction, not
  a behavior flip.
- `authority_invariant`: consumers downstream of the selected seam must not
  re-derive body, call, override, or keepalive symbols from raw `name` /
  `target_name` locals after the helper returns. They must consume the binding
  record. Legacy computations may remain only inside the helper as parity
  assertions or implementation details.

Required source-shape gate for the future code slice:

- red before implementation:
  - inline `materialized_name = if materialize_requested_instance_wrapper`
    source shape is present;
  - inline `override = if materialize_requested_instance_wrapper` source shape
    is present;
  - no named `MaterializationSymbolBinding` / symbol-binding owner helper is
    consumed at the selected seam;
- green after implementation:
  - the selected seam calls the named symbol-binding helper/record exactly once;
  - the old inline symbol-binding windows are removed from
    `lower_function_if_needed_impl` or reduced to parity-only assertions inside
    the helper;
  - `record_materialization_keepalive_candidate` and
    `log_materialization_identity_ledger` consume values from the binding record,
    not separately recomputed locals;
  - any remaining legacy symbol-selection branches are inside the helper and
    marked as parity/legacy implementation, not as downstream authority;
  - existing 0k-V MethodNameCodec admission remains
    `already_promoted_shadow`.

Verification for the future code slice:

- build: `crystal build src/adamas.cr -o /private/tmp/adamas_symbind_stage1
  --error-trace`;
- source-shape: a dedicated admission gate or equivalent `rg` check proving the
  red/green source-shape above;
- existing architecture gates:
  `scripts/method_name_codec_admission_report.sh`,
  `REQUIRE_PROMOTED=1 scripts/method_name_codec_admission_report.sh`,
  `scripts/materialization_transaction_report.sh <stage1>`,
  `scripts/materialization_promotion_selection_report.sh <stage1>`,
  `scripts/semantic_decision_census.sh`, and
  `scripts/codepath_status_census.sh`;
- compatibility: focused no-prelude or split/materialization guards that cover
  requested/target symbol identity must remain green;
- generated-stage boundary: fresh stage1 must build fresh s2 via
  `scripts/run_safe.sh`, and the generated-s2 result must either reach the
  symbol-binding seam with parity evidence or state the older residual boundary
  explicitly.

Stop rules:

- if the helper needs to change emitted materialized/override/call symbols in
  the same slice, stop and split a later would-change slice;
- if the source-shape gate cannot prove the selected seam consumes the binding
  record, stop before committing code;
- if the implementation adds only a new report without moving the inline
  symbol-binding authority edge, classify it as stale scratch and delete it;
- if the implementation leaves downstream consumers recomputing body/call/
  keepalive symbols from separate locals after constructing the binding record,
  do not count the slice as architecture progress;
- if the binding record cannot carry keepalive and call-symbol facts without
  backend reconstruction, stop and revise the `MaterializationIdentity`
  contract rather than adding backend rescue logic.

Boundary:

- this receipt is not a behavior fix and not a green full-prelude generated s2,
  `s2b`, or `s3b` claim;
- it does not authorize backend forwarders, target keepalive as a standalone
  patch, requested-name forcing, remangling, `NamedTuple`/`Tuple` normalization,
  global ambient-map changes, or `BlockOwner` rollback;
- it selects the next implementation unit so the following code slice reduces
  a real authority edge instead of adding another ledger.

### Slice 0k-Y: materialization symbol-binding admission gate

Status:

- behavior-neutral source-shape gate for Slice 0k-X;
- no compiler source, emitted behavior, generated-stage behavior,
  materialization naming, backend remangling, `BlockOwner` carrier, or deletion
  behavior changed.

Source/spec:

- `scripts/materialization_symbol_binding_admission_report.sh`;
- active SDD board row: `MaterializationIdentity` /
  `MaterializationRegistry`;
- selected seam: `lower_function_if_needed.symbol_binding`.

What the gate proves today:

- default mode reports
  `source_shape=legacy_split_edge` and
  `selection_status=eligible_symbol_binding_owner`;
- `REQUIRE_PROMOTED=1` exits nonzero until the future code slice has moved
  the consumer-facing authority to a `MaterializationSymbolBinding`-style
  helper/record;
- current counts are expected to show one old materialized-name branch, one old
  override branch, one direct keepalive use, direct ledger symbol use, and zero
  binding consumers.

Green condition for the future code slice:

- default mode reports `source_shape=already_promoted_shadow`;
- `REQUIRE_PROMOTED=1 scripts/materialization_symbol_binding_admission_report.sh`
  exits 0;
- old inline symbol-binding windows are gone from
  `lower_function_if_needed_impl` or moved inside the helper as parity-only
  implementation;
- `record_materialization_keepalive_candidate` and
  `log_materialization_identity_ledger` consume binding-record fields rather
  than independently recomputed locals.

Stop rules:

- if the script reports `partial_binding_authority`, the implementation is not
  architecture progress and must be fixed before commit;
- do not add another materialization report before consuming this gate in a code
  slice;
- do not change emitted symbols, backend stub handling, target keepalive,
  remangling, `NamedTuple`/`Tuple` rendering, ambient-map policy, or
  `BlockOwner` carrier in the same slice.

Verification:

- `scripts/materialization_symbol_binding_admission_report.sh` returns 0 with
  the current `legacy_split_edge` source shape;
- `REQUIRE_PROMOTED=1 scripts/materialization_symbol_binding_admission_report.sh`
  returns 9 today, proving the gate is red before the helper exists;
- MethodNameCodec admission remains `already_promoted_shadow`.

Boundary:

- this is not a behavior fix and not a green full-prelude generated s2, `s2b`,
  or `s3b` claim;
- the next production code slice is now constrained to turn this exact gate
  green through authority migration, not through a record-only wrapper.

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
