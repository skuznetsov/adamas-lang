# Compiler Refactor Architecture Plan

Status: Draft; reference-only for near-term bootstrap work. Active bootstrap
architecture is governed by `docs/compiler_architecture_sdd.md`.
Date: 2026-04-11
Scope: compile pipeline maintainability, LLVM IR emission, and HIR service
boundaries
Related: `PLAN_DEMAND_DRIVEN_REWRITE_RFC.md`, `docs/ast_to_hir_audit.md`,
`docs/codegen_architecture.md`

2026-07-01 alignment note: this plan remains the long-term refactor map, but
the active path to green `s2b`/`s3b` is now governed by
`docs/compiler_architecture_sdd.md`. Do not start with physical extraction or
the LLVM writer merely because this older plan lists it as the safest first
candidate. The current bootstrap evidence shows repeated failures in semantic
ownership boundaries: call/materialization symbol identity, ambient state
scope, type/name identity, AST arena ownership, ABI facts, and file identity.
The first executable architecture implementation is therefore Phase 1/1b census
plus owner ledgers, not a broad backend writer slice.

2026-07-01 pivot note: after the 0k-L override owner-consumption helper, the
near-term path must stay on architecture implementation rather than returning
to the next generated-stage crash. The first extraction work is not a physical
file split. It is the promotion of one owned fact at a time:

1. `MaterializationDecision` owner surface for requested, selected, target,
   body, emitted call, state-scope authority, target map, call arg types, and
   ABI shape.
2. `SemanticStateScope` snapshots for naming/materialization decisions that
   currently read ambient mutable maps.
3. `NameResolution` / `MethodNameCodec` for typed parsing of owners, suffixes,
   and mangled method names.
4. `AstNodeRef` / `ArenaOwnership` for owner-scoped AST reads.
5. `CodePathStatus` for deleting or quarantining stale debug, fallback, and
   workaround paths only after runtime evidence and a protecting falsifier.

Each slice must replace or shadow a named authority edge before any behavior
change. A new report without a promoted consumer, a backend forwarder without a
HIR-owned transaction, or a consumer guard around the latest crash remains a
symptom fix, not architecture work.

2026-07-01 post-0k-N note: the first `MaterializationDecision` promotion seam
is now closed in shadow mode, and the promotion-selection report marks it
`already_promoted_shadow` rather than selecting it again. The focused report
has no second eligible `MaterializationDecision` consumer, so the next
near-term extraction lane should be `SemanticStateScope`: add a behavior-neutral
scope snapshot at a naming/materialization seam and prove parity against the
legacy ambient reads. Do not continue materialization-selection work unless a
fresh focused report names a different unpromoted consumer with complete owner
fields.

2026-07-01 post-0k-O note: `SemanticStateScope` is not admitted as another
diagnostic report lane. The next code slice must replace one named ambient-state
authority edge in shadow/parity mode, with a source-shape guard proving that the
selected consumer no longer calls the old helper directly. If that receipt is
not root-sized, switch to runtime `CodePathStatus` cleanup selection instead of
adding another scope ledger.

2026-07-01 post-0k-P note: the first `SemanticStateScope` owner-consumption
candidate is now selected by report, not by memory: `prefer_callsite_specialization`.
The selection report is intentionally not a behavior license. It exposes mixed
migration classes for the selected seam and provides a red
`REQUIRE_PROMOTED=1` gate that only the future shadow/parity helper should turn
green.

2026-07-01 post-0k-Q note: pause code before accepting the first
`SemanticStateScope` helper. A helper/report that only wraps
`def_has_untyped_regular_param?` and prints more rows is not architecture work;
it is diagnostic debt. The next implementation must define a
`SemanticStateScopeDecision`-style owned record for exactly
`prefer_callsite_specialization`, compute an owner result separately from the
legacy parity result, keep emitted behavior unchanged, and prove by source
shape that the selected consumer no longer reaches directly for the old
ambient-state helper. If that receipt is not root-sized, switch to
`CodePathStatus` cleanup selection instead of adding more state-scope ledgers.

2026-07-01 post-0k-R note: the first `SemanticStateScope` seam is now promoted
in shadow/parity mode. `prefer_callsite_specialization` calls a named
`SemanticStateScopeDecision` helper, the helper emits owner-result
classification under a default-off promotion ledger, and emitted behavior still
returns the legacy result. The admission report marks the seam
`already_promoted_shadow`; do not select it again. This is still not a green
bootstrap claim: generated s2 builds and passes a no-prelude smoke, but the
full-prelude generated-s2 smoke still exits 139 after `pass3 after lower_main
call`. The next architecture lane must choose a different root-sized
state-scope consumer or move to `CodePathStatus` cleanup selection.

2026-07-01 post-0k-AW note: the paired
`lower_function_if_needed.callsite_args` and `.suffix_types` keep-requested-name
consumers now share a `KeepRequestedNameDecision` state record in parity mode,
and the current owner-cache materialization guard targets `BlockOwner` instead
of the retired `NamedTuple` carrier. This closes the immediate 0k-AV
state-model checkpoint but should not be treated as bootstrap progress by
itself. The refactor track should now pivot from seam-by-seam helper promotion
to contract burn-down: add or strengthen falsifiers for function-body presence,
generic template/instance semantic keys, and original-vs-stage semantic
oracles before admitting another behavior fix from a generated-stage crash
stack.

2026-07-01 post-0k-AX note: the active refactor plan is now contract-first,
not crash-stack-first. The next executable production slice should start from
`docs/specs/05-falsifier-matrix.md`, not from the newest `s2b` symptom. The
first three priorities are H5 function-body presence, G3 generic semantic
keys, and B3 original-vs-stage semantic oracle coverage. A helper, ledger, or
report is architecture work only when it closes one of those holes or removes a
named old authority edge; otherwise it is diagnostic debt.

2026-07-01 post-0k-AY note: H5 now has a focused executable guard,
`regression_tests/hir_function_body_presence_contract.sh`, covering the HIR
body-presence truth table and the HIR->MIR bodyless-stub boundary. The next
contract burn-down target is G3: generic template/instance semantic identity
must be keyed by owner/source/type-param/specialization facts, not by rendered
names.

2026-07-01 post-0k-AZ note: G3 now has a focused executable guard,
`regression_tests/generic_identity_key_contract.sh`. The slice adds
`GenericTemplateKey` and `GenericInstanceKey` under
`src/compiler/semantic/identity/` and proves semantic equality/hash are keyed by
owner, source `DefIdentity`, declared type parameters, specialization argument
identities, and lexical owner rather than display/rendered names. This is only
the contract object and falsifier; generic materialization and registration
call sites still need explicit authority-edge migration before claiming
bootstrap behavior progress.

2026-07-01 post-0k-BA note: B3 now has an executable original-vs-stage semantic
oracle, `regression_tests/original_vs_stage_semantic_oracle_contract.sh`. It is
intentionally strict by default and measured-red only when
`ADAMAS_EXPECT_ORIGINAL_STAGE_MISMATCH=1` is set. Current stage output matches
original Crystal for `CONST=7` but diverges on source-visible type lines:
original prints `TYPE=Int32` and `UNION=Int32`, while the stage compiler emits
blank `TYPE=` and `UNION=`. This is a named semantic frontier, not accepted
bootstrap progress.

2026-07-01 post-0k-BB note: the measured-red B3 frontier is now classified as
`TypeValue` / `RuntimeTypeIdentity`, not a one-line `typeof` output bug. The
next executable implementation unit should first add the narrow falsifier that
proves direct and interpolated `typeof`, runtime `.class`, nilable `.class`,
and type-literal `.name` / `.to_s` / `inspect` all agree with original Crystal.
Only after that guard exists should production code introduce one HIR-owned
type-visible value fact and migrate the reached consumers to it. Do not use a
string-only `lower_typeof` patch, interpolation-only special-case, backend
stub, generic materialization change, or `BlockOwner` change as a shortcut.

2026-07-01 post-0k-S note: the lane switched to runtime `CodePathStatus`
cleanup selection for one debug/probe cluster instead of adding another
state-scope helper. `scripts/codepath_status_cleanup_selection_report.sh`
classifies `cli.metrics.identity_dry_run` as `debug_only` by proving the
selected path is `not_taken` by default and `taken` with
`ADAMAS_IDENTITY_DRY_RUN=1`. This is classify-only; no deletion is admitted
until a later `delete_ready` slice proves default behavior, HIR/MIR/LLVM shape,
and bootstrap guards.

2026-07-01 post-0k-T note: the active SDD now has one authoritative
`Active Architecture Board`. Older "Current next-slice decision after ..."
paragraphs in the SDD are historical ledger entries, not competing next-step
selectors. The board's default correctness lane is `NameResolution` /
`MethodNameCodec` plus `MaterializationIdentity`, because repeated expensive
frontiers are still symbol/owner identity failures. That does not authorize a
behavior fix: the next slice must first name one board row, one old authority
edge, one owned fact replacing or shadowing it, and one falsifier/DoD. Cleanup
work remains an explicit `CodePathStatus` lane, not an architecture substitute.

2026-07-01 post-0k-U note: the first `MethodNameCodec` seam is now selected by
source-shape report, not by memory. The selected seam is
`lower_function_if_needed.exact_lookup_keep_requested_name`: the exact-lookup
materialization branch still decides requested-name vs resolved-name from
rendered suffix/arity checks. The next code slice is admitted only as a
shadow/parity helper for this seam. Do not start with low-level helper
rewrites, global method-name normalization, backend remangling, or behavior
changes to materialization naming.

2026-07-01 post-0k-V note: the selected `MethodNameCodec` seam is now promoted
in shadow/parity mode. `lower_function_if_needed.exact_lookup_keep_requested_name`
calls `method_name_codec_exact_lookup_keep_requested_name?`; default behavior
still returns the legacy result, while the optional promotion ledger computes a
typed `MethodNameParts` owner-result. Do not flip the owner-result into emitted
behavior from this slice. The next slice must either run/extend the promotion
ledger on a generated-stage corridor or explicitly select another active-board
authority edge with a red/green gate.

2026-07-01 post-0k-W note: pause before adding more report surfaces. A local
MethodNameCodec promotion-report scratch was removed because it would have made
existing rows easier to print without reducing an authority edge or naming the
decision it unlocks. Future generated-stage reports are admitted only when the
SDD records their `decision_question`, source-shape gate, generated-stage
boundary, and cleanup rule. The near-term architecture unit is still one owned
fact at a time, but "owned fact" means a consumer stops treating rendered names,
ambient maps, arena-local ids, or backend fallback state as authority; it does
not mean another standalone ledger wrapper.

2026-07-01 post-0k-X note: the next implementation unit is selected before
production edits: `lower_function_if_needed.symbol_binding`. The current code
still chooses `materialized_name`, `override`, keepalive target, and
materialization ledger call-symbol hints through separate inline branches. The
next code slice should introduce one behavior-neutral
`MaterializationSymbolBinding`-style owner record/helper and make those
consumers read from it while preserving legacy emitted symbols. This is the
smallest useful step toward the larger `MaterializationDecision` /
`MethodNameCodec` architecture: requested, target, body, call, state-scope,
target-map, call-arg, and ABI facts must become one HIR-owned binding before
any forwarder, remangle, requested-name, or keepalive behavior fix is allowed.
This is not satisfied by constructing a record and then continuing to recompute
the symbols at downstream consumers; the consumer-facing authority must move to
the binding record while legacy branch logic remains confined to parity inside
the helper.

2026-07-01 post-0k-Y note: the source-shape gate for that seam now exists:
`scripts/materialization_symbol_binding_admission_report.sh`. The current
source is intentionally red under `REQUIRE_PROMOTED=1` (`legacy_split_edge`),
so the next code slice has a concrete movement target: turn the gate green by
making keepalive and materialization-ledger consumers read from the binding
record, without changing emitted symbols.

2026-07-01 post-0k-Z note: the `MaterializationSymbolBinding` shadow/parity
slice landed. The symbol-binding source-shape gate is now green, and
keepalive/materialization-ledger consumers read the binding record instead of
recomputing split symbol locals. This is still not a full bootstrap claim:
fresh generated s2 builds and no-prelude smoke passes, but full-prelude
generated-s2 smoke still exits 139 after `pass3 after lower_main call`. The
next slice must classify that residual with fresh generated-stage evidence or
select another owner seam; do not jump to backend rescue or keepalive/remangle
behavior patches.

2026-07-01 post-0k-AA note: pause the fresh `lower_super` / inline-yield
diagnostic direction until it has an owner-boundary gate. A local
`SUPER_CTX`-style ledger WIP was removed because it would have added another
env-gated report without first naming the authority edge it reduces. The next
admitted implementation is not a `lower_super` guard. It is an
`InvocationContext` / `InlineYieldFrame` source-shape gate that selects one
consumer seam and proves where ambient invocation fields (`@current_class`,
`@current_method`, class-vs-instance state, source module, and inline-yield
frame stacks) are still used as semantic authority. Only after that gate is
red can a behavior-neutral shadow/parity owner helper be implemented.

2026-07-01 post-0k-AB note: the `InvocationContext` source-shape gate now
exists. `scripts/invocation_context_admission_report.sh` selects
`lower_super.previous_def.invocation_context` and is intentionally red under
`REQUIRE_PROMOTED=1`: current `lower_super` / `lower_previous_def` still have
direct ambient owner/method, method-kind, super-source, and forward-policy
reads, and no invocation-frame helper. The next code slice is therefore the
shadow/parity helper that moves this selected consumer seam to an explicit
invocation-frame owner fact while preserving emitted behavior.

2026-07-01 post-0k-AC note: the selected `InvocationContext` seam is now
promoted in shadow/parity mode. `lower_super` / `lower_previous_def` consume an
`InvocationContext` owner fact for owner class, method name, class-vs-instance
state, super-source module, function name, and legacy forwardable argument ids.
The source-shape gate is green under `REQUIRE_PROMOTED=1`, and full suites pass,
but this is not a behavior flip and not a green `s2b`/`s3b` claim. The next
slice must either classify the residual generated-stage frontier with fresh
owner-boundary evidence or select a different active-board authority edge with
a red/green gate. Do not continue by adding another context report, changing
super forwarding, resetting inline-yield stacks, or treating this helper as a
bootstrap fix.

2026-07-01 post-0k-AD note: the near-term plan now pauses seam-by-seam
production work and selects a vertical `CallMaterializationTransaction` spine
as the next correctness axis. This is a docs-only checkpoint, not a behavior
change. The next executable slice is 0k-AE: a red/green source-shape gate for
one consumer that still splits requested symbol, selected definition, state
scope, target/body symbol, emitted call symbol, callsite arg types, target map,
and ABI shape across local strings or ambient maps. The next code slice must
make that selected consumer read a single owner record in shadow/parity mode
before any behavior flip. Generated-stage runs are admitted only when they
answer a transaction-spine yes/no question; otherwise they repeat the crash
stack selection loop. Backend forwarders, requested-name forcing, target
keepalive, `NamedTuple`/`Tuple` rendering changes, global ambient-map predicate
changes, and `BlockOwner` rollback remain rejected.

2026-07-01 post-0k-AE note: the transaction-spine source-shape gate now exists
as `scripts/call_materialization_transaction_admission_report.sh`. Current
source is intentionally measured-red:
`preferred_source_shape=legacy_split_transaction_edge`,
`transaction_type_count=0`, `transaction_helper_count=0`, and
`REQUIRE_PROMOTED=1` exits 9. The next code slice is 0k-AF: add a
behavior-neutral `CallMaterializationTransaction` record/helper for the selected
`lower_function_if_needed.call_materialization_transaction` seam and make one
selected consumer read that record in shadow/parity mode. This must preserve
emitted behavior; flipping requested/target/body/call symbols is still rejected
until a later would-change census proves the affected set is root-sized.

2026-07-01 post-0k-AF note: the first vertical transaction consumer is now
promoted in shadow/parity mode. `CallMaterializationTransaction` owns request
name parts, requested/target/body/call symbols, selected definition and owner,
state scope, target map, call arg shape, ABI shape, wrapper/forwarder contract,
and rejection reason for the materialization identity/state-scope ledger path.
The old split-argument `log_materialization_identity_ledger(...)` calls are
gone; `log_call_materialization_transaction_ledger(transaction)` reads the
record instead. The transaction gate is green but still reports
`residual_legacy_edge_count=26`, so this is selected-consumer promotion, not
full transaction-spine completion and not a green `s2b`/`s3b` claim. Next work
must either select another transaction consumer with a red/green gate or run a
generated-stage classifier only if it answers a transaction-spine yes/no
question.

2026-07-01 post-0k-AG note: the next transaction consumer is selected before
more compiler behavior edits. The source-shape gate
`scripts/call_materialization_transaction_consumer_selection_report.sh`
selects `lower_function_if_needed.instance_symbol_consumers` because
`CallMaterializationTransaction` records already exist in that branch, while
override, keepalive, and diagnostic materialization-symbol consumers still
bypass them through `MaterializationSymbolBinding` fields. This is an
architecture stop-rule, not another diagnostic lane: the next code slice must
move those selected consumers to transaction fields in shadow/parity mode, and
`MaterializationSymbolBinding` may remain only as a parity input inside the
transaction constructor/helper. A code slice that constructs transactions but
leaves selected downstream consumers reading `symbol_binding.*` is wrapper
theater, not transaction-spine progress.

2026-07-01 post-0k-AH note: the selected
`lower_function_if_needed.instance_symbol_consumers` group is now promoted in
shadow/parity mode. The instance-method override, keepalive, and diagnostic
materialization-symbol consumers read `CallMaterializationTransaction` fields
instead of direct `MaterializationSymbolBinding` fields; the binding remains
only as a parity input to the transaction constructor. The selected-consumer
gate is green with `selected_binding_consumer_count=0`, and the transaction
gate is green with `transaction_field_read_count=6` and
`residual_legacy_edge_count=20`. This is still not a behavior flip, not a
full transaction-spine completion, and not a green full-prelude generated s2,
`s2b`, or `s3b` claim. The next slice should either select the next
transaction consumer with a red/green source-shape gate or run a generated-stage
classifier that answers whether the transaction spine is still on the active
frontier. Before adding more default-path transaction fields, consider splitting
a cheap owner-core record from debug-payload ledger fields.

2026-07-01 post-0k-AI note: pause further production transaction-consumer
migrations until generated-stage reachability is classified. The current
transaction source-shape metric is no longer enough by itself: after 0k-AH, the
selected consumers are promoted, but the broader transaction gate still reports
`residual_legacy_edge_count=20`. Continuing to lower that counter without a
fresh generated s2 full-prelude signal risks optimizing the architecture metric
instead of the bootstrap frontier. The next executable slice should be a
generated-stage transaction-spine classifier: build/use a fresh generated s2
through `scripts/run_safe.sh`, run the existing materialization transaction
ledger on a full-prelude corridor, and classify `reached_tx_and_emit`,
`tx_only_no_emit`, `no_tx_rows`, or `s2_build_fails`. Only the first result
admits another reached transaction-consumer migration. The other outcomes route
to transaction-to-emission correlation, a different owner boundary, or build
corridor repair.

2026-07-01 post-0k-AI implementation note: the generated-stage transaction
classifier now exists as `scripts/generated_stage_transaction_spine_classifier.sh`.
On fresh current source it builds generated s2 successfully and classifies the
full-prelude corridor as `reached_tx_and_emit` (`compiler_rc=139`,
`mat_tx_rows=615`, `transaction_bound_mat_emit_rows=29`, `stub_rows=0`). This
keeps the `CallMaterializationTransaction` lane active, but narrows the next
architecture step: select one reached transaction/emission edge with a
red/green gate before any behavior fix. Do not continue by globally lowering
`residual_legacy_edge_count` or by patching the segfault directly.

2026-07-01 post-0k-AJ implementation note: the reached-edge selector now exists
as `scripts/generated_stage_transaction_edge_selection_report.sh`. On a fresh
generated-stage corridor it selects
`call_materialization.wrapper_or_call_remap.extern_missing_body` with
`candidate_selected_rows=4`, `candidate_selected_distinct_txs=3`,
`source_shape=eligible_reached_edge`, and
`selection_status=eligible_reached_transaction_emission_edge`. The selected old
authority edge is backend extern emission from `call_symbol_hint` while the
transaction already records `required_contract=wrapper_or_call_remap` and
`body_symbol != call_symbol_hint`. The next architecture slice is therefore a
shadow/parity consumer of the transaction contract facts, not a backend
forwarder, requested-name force, target keepalive, `NamedTuple`/`Tuple`
normalization, global ambient-map change, or direct segfault patch.

2026-07-01 post-0k-AK checkpoint note: pause code before accepting that
shadow-consumer as the next committed slice. A local uncommitted implementation
that threaded transaction contract facts into MIR calls and backend `[MAT_EMIT]`
rows was removed because it made the old 0k-AJ selector's success condition
stale before the plan defined post-consumer semantics. The next plan step is to
refresh the SDD board and define the selector states
`selected_not_consumed`, `selected_consumed_by_contract_consumer`, and
`selected_refuted_or_stale`. A consumer implementation is admissible only after
that distinction is explicit; otherwise the work risks turning the selector
into a value proxy and chasing its own changed output.

2026-07-01 post-0k-AL implementation note: the distinction is now executable.
`scripts/generated_stage_transaction_edge_selection_report.sh` reports
`post_consumer_state` and can require one state through
`REQUIRE_POST_CONSUMER_STATE`. Synthetic ledger checks covered
`selected_not_consumed`, `selected_consumed_by_contract_consumer`, and
`selected_refuted_or_stale`; the fresh generated-stage corridor is currently
`selected_not_consumed` with `candidate_selected_rows=4` and
`contract_mismatch_rows=0`. The next admitted production slice is therefore the
behavior-neutral transaction contract consumer. Its DoD is the state transition
to `selected_consumed_by_contract_consumer`, not a behavior fix or backend
rescue.

2026-07-01 post-0k-AM implementation note: the behavior-neutral transaction
contract consumer is now landed. HIR owns the transaction contract facts by
transaction id, MIR `Call`/`ExternCall` carry them as metadata, backend
`[MAT_EMIT]` rows print them, and optimizer call copies preserve them. The fresh
generated-stage gate is `selected_consumed_by_contract_consumer` with
`contract_mismatch_rows=0`, and full suites pass. The next architecture step is
not to patch the old wrapper/remap symptom. That edge is consumed. Re-select the
next reached transaction/emission edge, with the current broad residual being
exact-contract missing-body emits that must be split before any behavior change.

2026-07-01 post-0k-AN pacing note: before the next production edit, choose one
explicit lane: correctness-selection, consumer-migration, cleanup/delete, or
consolidation. This is now part of the active SDD guard. A new selector is not
progress unless it has a decision question, root-size budget, negative control,
and a named old authority edge. If it only prints a broader residual, it stops at
classification. A second report-only slice must retire, merge, or refute a
previous report surface. This keeps the near-term refactor map aligned with
bootstrap progress instead of growing another diagnostic layer around the same
hidden ownership problem.

2026-07-01 post-0k-AO selection note: the first correctness-selection pass after
0k-AM did not produce a next behavior edge. The exact-contract missing-body
residual is 14 rows across 9 root-sized groups, and
`REQUIRE_RESIDUAL_SELECTED=1` rejects it as ambiguous. This pushes the refactor
plan away from direct materialization patches for the sample methods and toward
either a stronger discriminator that proves one old authority edge, or an
explicit consolidation / cleanup lane. Treat the grouped samples as routing
data, not as a prioritized fix list.

2026-07-01 post-0k-AP consolidation note: the report/gate surface is now
statused in the active SDD. Existing reports are not all live work queues:
promoted source-shape reports are guards, generated-stage transaction selection
is an active stop gate, `codepath_status_cleanup_selection_report.sh` is the
cleanup entry point and now creates repo-local `tmp/` before `mktemp`, and
older census/ledger reports are historical unless a future SDD slice reactivates
one with a full receipt. This makes the near-term plan more opinionated: if no
root-sized correctness discriminator exists, move to `CodePathStatus`
cleanup/delete rather than adding another diagnostic surface.

2026-07-01 post-0k-AP cleanup preflight note: the existing cleanup entry does
not yet provide a deletion target. Fresh stage1 runs classify both supported
paths, `identity_dry_run` and `phase0_metrics`, as `debug_only` with env-off
`not_taken` and env-on `taken`. That protects them from deletion; the next
cleanup/delete slice must select another path or extend the selector before
claiming delete readiness.

2026-07-01 post-0k-AR cleanup inventory note: the cleanup selector now has a
fail-closed runtime inventory mode. A fresh stage1 no-prelude compile reports
26 runtime paths and zero delete-ready rows; `REQUIRE_DELETE_READY=1` fails.
Default-not-taken rows are explicitly `not_taken_unproven`, not deletion
targets. The next cleanup/delete step must add a protecting falsifier for one
named path or define a stricter `eligible_delete_ready_candidate` class before
removing code.

2026-07-01 post-0k-AS cleanup classification note: the first follow-up
`not_taken_unproven` row, `fused_parallel_requested`, is classified as
`experimental_live`, not delete-ready. The env-off/env-on falsifier proves the
path is selectable and still compiles the no-prelude reducer when enabled. This
keeps cleanup honest: reduce unknowns one path at a time, but do not turn
experimental-live evidence into deletion.

2026-07-01 post-0k-AT architecture pivot note: pause the cleanup/report lane
for the bootstrap objective. It has produced negative facts, not a route to
green `s2b`/`s3b`. The next implementation unit is not the already promoted
`lower_function_if_needed.override` seam. It is a no-repeat
`SemanticStateScope` selector that enumerates the remaining direct
`state_scope_consumer_def_has_untyped_regular_param?` callers, rejects promoted
and backend-adjacent seams, and selects at most one root-sized consumer for a
future shadow/parity owner decision. If no such consumer exists, move up to a
state-model redesign checkpoint instead of adding more ledgers. Rejected
repeats: backend forwarder, requested-name forcing, target keepalive,
`NamedTuple`/`Tuple` rendering changes, global ambient-map policy changes,
cleanup classification as bootstrap progress, and `BlockOwner` rollback.

2026-07-01 post-0k-AU source-selector note: the existing
`semantic_state_scope_admission_report.sh` now has `SOURCE_SHAPE_ONLY=1`. The
source-only selector confirms the no-repeat gate rather than choosing a local
consumer: `prefer_callsite_specialization` and
`lower_function_if_needed.override` are already promoted, `lower_call.remangle`
is backend-adjacent, and both `lower_function_if_needed.callsite_args` and
`lower_function_if_needed.suffix_types` remain unpromoted frontend direct
consumers. It reports `selected_count=0` and
`state_model_redesign_required=1`, while `REQUIRE_SELECTED=1` exits `9`.
Therefore the next architecture step is a state-model redesign checkpoint for
shared `lower_function_if_needed` keep-requested-name state, unless a stronger
falsifier collapses the two frontend candidates to exactly one root-sized
authority edge.

2026-07-01 post-0k-AV checkpoint note: pause production code before turning that
state-model redesign into another helper. A local uncommitted shared
keep-requested-name helper WIP was reverted because it demonstrated the next
failure mode: a source-shape report can say `state_model_redesign_complete=1`
while the architecture still treats the report as the value being optimized.
The next implementation may reintroduce the shared model only as a
behavior-neutral owned fact with explicit legacy result, owner result, emitted
parity result, stale-regression audit, and generated-stage guard. This is not a
license to force requested names, normalize `NamedTuple`/`Tuple`, add backend
forwarders, change global ambient-map policy, or roll back `BlockOwner`.

## 1. Purpose

This document captures a staged architecture plan for reducing the debugging
and maintenance cost of the Crystal V2 compiler without interrupting the
current runtime-stability work.

The goal is not to split files because they are large. The goal is to replace
implicit string/state coupling with explicit contracts:

- HIR lowering should expose narrow services for overload resolution, macro
  provenance, primitive lowering, and call lowering.
- LLVM emission should move from ad hoc string construction toward a typed,
  streaming writer that avoids large intermediate strings and stringly typed
  fixups.
- Rollout must keep current HIR/MIR/backend contracts stable until shadow
  checks prove equivalence.

## 2. Current Pain Points

### 2.1 HIR lowering

`src/compiler/hir/ast_to_hir.cr` is a single stateful class that currently owns
too many responsibilities:

- declaration collection and registration
- macro expansion and macro-origin/provenance handling
- type lookup and type inference shortcuts
- overload lookup and callsite specialization
- primitive and union lowering
- RTA/lazy lowering and pending-function queues
- HIR instruction emission
- many debug and bootstrap workarounds

This creates poor debugging locality. A bug that appears as a runtime stub can
originate from overload registration, macro provenance, type substitution, or a
late pending-function replay. The code allows local fixes that are correct for a
single symptom but fragile for the surrounding pipeline.

### 2.2 LLVM backend

`src/compiler/mir/llvm_backend.cr` still mixes:

- type mapping
- string formatting for LLVM IR
- function emission scheduling
- call argument coercion
- debug metadata generation
- backend-synthesized runtime shims
- parallel worker output merging
- textual post-fixups such as `fixup_call_arg_types(args : String)`

The project already hit a verified self-host failure from intermediate LLVM
header string construction: `Array(String)#join` in function header emission
caused a `Negative capacity` failure in stage2. The local fix streamed function
headers directly into the output buffer. That fix is the right pattern to
generalize.

### 2.3 Textual `.ll` as the only boundary

The current backend often treats LLVM IR as plain text too early. This makes
the code easy to print, but hard to validate:

- call arguments become `"TYPE VALUE"` strings before the backend has finished
  checking type/value consistency
- phi incoming lists and parameter lists are assembled through generic
  containers and joins
- debug metadata and normal IR write into the same textual surface
- malformed IR is frequently caught late by `opt`/`llc`, or by runtime behavior
  after a coercion happened in the wrong string branch

The desired direction is not a full in-memory LLVM AST. The desired direction is
a compact typed streaming layer that validates small fragments before writing
text.

## 3. Non-Goals

- Do not rewrite the whole compiler while runtime benchmark frontiers are still
  moving.
- Do not change stdlib files.
- Do not switch the compile path to the demand-driven semantic pipeline in this
  plan. That is covered by `PLAN_DEMAND_DRIVEN_REWRITE_RFC.md`.
- Do not build a full persistent LLVM AST for the entire module. That would add
  memory pressure and duplicate LLVM's own IR model.
- Do not replace LLVM text emission with the LLVM C API in this plan. That may
  become a later option, but it is not required to solve the current
  maintainability and self-host fragility problems.

## 4. Target Architecture

### 4.1 HIR service boundaries

The first HIR target is to make the existing pipeline more modular without
changing its external behavior.

Proposed service extraction order:

1. `MethodNameCodec`
   - Owns mangling/demangling and method-name part parsing.
   - Removes repeated method-name parsing from resolver and backend-adjacent
     code.
   - Exit gate: old and new codecs produce identical normalized names for the
     regression corpus.

2. `OverloadSelector`
   - Owns overload candidate filtering by receiver, arg types, named args,
     block presence, and concrete suffix preservation.
   - Must not emit HIR or mutate pending-function queues.
   - Exit gate: targeted overload regressions and a traceable candidate ledger.

3. `MacroExpansionRegistry`
   - Owns macro expansion provenance, source path retention, and generated
     owner mapping.
   - Must expose a canonical "generated def identity" instead of pathless or
     arena-local fallbacks.
   - Exit gate: macro-body and module-path regressions plus debug-source
     identity checks.

4. `PrimitiveLowerer`
   - Owns primitive operations, primitive-union binary ops, casts, and unsafe
     reinterpretation lowering.
   - Must be independent from overload lookup except for a small typed
     `PrimitiveCall` input.
   - Exit gate: primitive union, float unsafe-as, integer formatting, and
     numeric benchmark reducers.

5. `CallLowerer`
   - Owns final callsite emission after method resolution has produced a
     typed target.
   - Must not redo overload selection from string names.
   - Exit gate: callsite target set is stable against legacy path in shadow
     comparison.

Extraction should happen by vertical slices. A file split without reducing the
state surface is not an improvement.

### 4.2 Typed streaming LLVM writer

Introduce a backend-internal writer layer that still emits `.ll` text, but does
not force all intermediate state into strings.

Suggested types:

```crystal
module Crystal::MIR::LLVMText
  struct LlType
    getter text : String
  end

  struct LlValue
    getter type : LlType
    getter name : String
  end

  struct LlParam
    getter type : LlType
    getter name : String?
  end

  struct LlArg
    getter type : LlType
    getter value : String
  end

  abstract class LlSink
    abstract def write(bytes : Bytes) : Nil
    abstract def write(text : String) : Nil
  end

  class LlWriter
    def function_header(return_type : LlType, name : String, params : Slice(LlParam))
    end

    def call(result : String?, return_type : LlType, callee : String, args : Slice(LlArg))
    end

    def phi(result : String, type : LlType, incoming : Slice(Tuple(String, String)))
    end
  end
end
```

This layer should keep the current `.ll` output format. The difference is that
the backend builds typed fragments and streams them directly, rather than
joining arrays of strings and then parsing those strings again.

### 4.3 Compact `.ll` representation

The recommended compact representation is per-function and stream-oriented:

- Keep MIR as the durable compact IR.
- For LLVM output, keep only the current function's typed emission state in
  memory.
- Write function bodies to a sink as soon as their dependency set is known.
- Let parallel workers produce bounded shards and merge them through a typed
  section manifest, not through ad hoc string concatenation.
- Keep metadata sections append-only and explicit; do not interleave metadata
  construction with normal instruction formatting unless the writer API makes
  that relationship visible.

Avoid a full-module LLVM object graph unless there is a specific optimization
or verification pass that cannot be expressed on MIR plus per-function LLVM
fragments.

## 5. Rollout Plan

Near-term override: while `s2b`/`s3b` are not stable, execute the rollout in
the order declared by `docs/compiler_architecture_sdd.md`:

1. Phase 0b architecture transition gate.
2. Phase 1 static/dynamic semantic decision census.
3. Phase 1b dead-code and workaround census.
4. Phase 2/2a typed facades and state-scope/materialization identity ledgers.
5. Only then resume behavior-changing compiler fixes unless a bootstrap
   emergency fix also adds a surviving owner ledger or falsifier.

The backend writer plan below is still valid, but it is no longer the first
implementation candidate for the active bootstrap objective.

### Phase 0: Contracts and metrics

Purpose: make the current behavior observable before refactoring.

Tasks:

- Add or update docs for backend output contracts:
  - valid LLVM value names
  - argument coercion rules
  - union payload conventions
  - debug metadata attachment rules
  - section ordering for globals, declarations, functions, metadata
- Add counters for:
  - total `emit` calls
  - total `emit_raw` calls
  - bytes emitted by family
  - number of call-arg fixups
  - number of string joins still used in backend hot paths
- Add a grep-friendly `ADAMAS_LLVM_WRITER_TRACE=1` trace for one function.

Exit criteria:

- No behavior changes.
- Existing regression suite is not worse.
- One representative benchmark compile produces a small writer metrics report.

### Phase 1: Function header and declaration writer

Purpose: generalize the already verified "stream function headers" pattern.

Tasks:

- Add `LLVMText::LlWriter` and route only function headers through it.
- Route forward declarations and intrinsic declarations through the same writer.
- Replace `param_types.join(", ")` patterns in function/declaration headers.

Exit criteria:

- Stage1 compiler build passes.
- Existing stage2 smoke that previously moved past `Negative capacity` still
  moves past that point.
- Emitted `.ll` diff is normalized-equivalent for headers and declarations.

### Phase 2: Typed call arguments

Purpose: remove the most fragile stringly typed call boundary.

Tasks:

- Replace `args : String` in call emission with `Array(LlArg)` or a small
  stack-friendly builder.
- Convert `fixup_call_arg_types(args : String)` into typed validation and typed
  coercion before final formatting.
- Make conversion paths return `LlArg`, not `"TYPE VALUE"` strings.

Exit criteria:

- No `split(", ")` or reparsing of call argument strings in backend call
  emission.
- Float/int/pointer/union call coercion reducers pass.
- `tmp/repro_ryu_fixed_direct.cr` and benchmark formatting reducers remain
  green before and after this phase.

### Phase 3: Phi, parameter, and metadata list writer

Purpose: remove the next highest-risk join-heavy IR lists.

Tasks:

- Route phi incoming lists through `LlWriter#phi`.
- Route debug metadata reference arrays through bounded writer helpers where
  practical.
- Preserve deterministic ordering for diffability.

Exit criteria:

- No regression in debug-info emission.
- `--debug` builds keep stepping behavior no worse than baseline.
- Large metadata arrays avoid per-element `DIDerivedType` string explosion when
  a compact `DIArray`/subrange representation is available and semantically
  valid.

### Phase 4: Backend section manifest

Purpose: make parallel worker output merging explicit.

Tasks:

- Introduce a small `LlSectionManifest` for declarations, globals, functions,
  metadata, duplicate constants, and synthesized runtime shims.
- Make each worker return a manifest plus bounded text shards.
- Merge sections in one deterministic place.

Exit criteria:

- Parallel and single-worker LLVM output are normalized-equivalent.
- Worker output no longer relies on implicit string concatenation order.
- `ADAMAS_LLVM_WORKERS=1` and default worker count both pass selected
  compile/run reducers.

### Phase 5: HIR service extraction

Purpose: reduce HIR debugging surface after the backend writer is safer.

Tasks:

- Extract `MethodNameCodec`.
- Extract `OverloadSelector` behind a legacy-compatible facade.
- Extract `MacroExpansionRegistry`.
- Extract `PrimitiveLowerer`.
- Extract `CallLowerer`.

Exit criteria:

- Each extraction is one logical commit.
- Each service has focused regression coverage and at least one traceable
  reducer.
- Legacy and extracted paths can be compared with a normalized shadow check
  before deleting old code.

## 6. Verification Strategy

Every phase must define a small acceptance gate before implementation.

Minimum gates:

- compiler host build:
  - `crystal build src/adamas.cr -o /tmp/cv2_refactor_gate --error-trace`
- safe compile/run for selected reducers:
  - `scripts/run_safe.sh /tmp/cv2_refactor_gate ...`
- normalized `.ll` comparison for the touched backend surface
- at least one negative/adversary check:
  - run the same reducer with `ADAMAS_LLVM_WORKERS=1`
  - run with debug metadata enabled if the phase touches metadata
  - compare against original Crystal for user-visible runtime formatting

Do not label a phase complete if only the `.ll` file is syntactically emitted.
For runtime-visible codegen changes, a produced binary must run through
`scripts/run_safe.sh`.

## 7. Migration Rules

- Keep one logical change per commit.
- Keep the old path until the new path has a shadow or normalized equivalence
  gate.
- Prefer writer APIs that accept slices or small stack-friendly builders over
  `Array(String)#join`.
- Do not add broad stubs to make a reducer pass.
- Do not introduce new global mutable state in service extraction. If a service
  needs state, make it explicit in a context object.
- Do not move code across files without either reducing state coupling or adding
  a testable contract.

## 8. First Implementation Candidate

Historical candidate: the safest first implementation candidate was a
backend-only writer slice:

1. Create `src/compiler/mir/llvm_text_writer.cr`.
2. Add `LlType`, `LlValue`, `LlParam`, `LlArg`, and `LlWriter`.
3. Route only `emit_function_definition_header(...)` through `LlWriter`.
4. Preserve current textual output byte-for-byte except for harmless whitespace
   if the normalized comparison allows it.
5. Add one regression or script-level check that exercises a function with:
   - zero params
   - multiple params
   - debug metadata enabled
   - entry function opt guard attributes

This remains intentionally small and useful after semantic ownership is under
control. It proves the typed writer seam without changing call coercion,
metadata ownership, or worker merging.

Active candidate for the 2026-07 bootstrap objective: implement the
architecture SDD's Phase 1/1b census and owner-ledger path first. After the
fresh generated-stage lower-call arena parity report showed
`210/210 agree_all_have` with zero owner divergence buckets, the next
architecture slice is `NodeSlotIntegrity / AstArenaStorage`, not another
`lower_call` arena-selection consumer patch and not the LLVM writer.
After the `NodeSlotIntegrity` report also refuted missing slot and
out-of-range `ExprId`, the plan must not automatically add another diagnostic
probe. Payload/deep-read integrity is an allowed future falsifier only as a
named SDD slice. The active architecture plan now pivots to sealing the
`SemanticStateScope` / `MaterializationIdentity` transaction record and adding
runtime `CodePathStatus` evidence before deletion or physical extraction.
The first transaction-record slice is intentionally limited: it records
pre-call requested/target/body/call-hint relations and required contracts, but
it does not yet prove final backend emitted-call identity. The next
architecture step is either transaction-completeness or runtime
`CodePathStatus`, not a materialization behavior fix. Final-call linkage or a
sibling emitted-call ledger is admissible only when it closes the Phase 2b
transaction contract; it must not become a backend undefined-extern rescue or
another diagnostic ladder after a ledger has already refuted the local
hypothesis.

The first runtime `CodePathStatus` slice now exists for coarse
CLI/compiler-driver control flow. Treat it as a cleanup/bloat evidence channel,
not as a semantic owner boundary: it can show that a branch was observed or not
observed in a focused run, but deletion still requires the SDD's protecting
falsifier and bootstrap guard. The bootstrap-correctness path remains
`SemanticStateScope` / `MaterializationIdentity` transaction completeness.
The next correctness slice is therefore design-sealed as transaction
completion: join requested symbol, selected definition, target symbol, created
body symbol, emitted backend call symbol, state-scope authority, target map,
callsite arg types, and ABI shape before any behavior patch.
Slice 0k-A has now supplied the default-off emitted-call correlation channel,
and Slice 0k-B has added default-off selected-definition and state-scope owner
fields to the same transaction rows. A behavior fix is still premature if it
consumes only `[MAT_EMIT]` body-present/stub evidence, broad `tx=none`
diagnostics, or backend `@undefined_externs`. The first behavior slice must
now choose a targeted transaction row, run a would-change census, and prove the
would-change set is not wider than the classified owner row set.
The first full generated-s2 report after 0k-B is a new stop signal rather than
a behavior-fix green light: generated s2 emits HIR-side `[MAT_TX]` rows while
compiling full `src/adamas.cr`, then crashes with `compiler_rc=139` before any
`[MAT_EMIT]` rows are emitted. Therefore the next correctness step is not a
backend forwarder, keepalive, or requested-name materialization patch. It must
either make generated-stage emitted-call seam reachability a named owner
problem, or start the `SemanticStateScope` shadow facade so ambient-map naming
authority becomes an explicit fact before behavior changes.

Initial executable entry point:

```bash
scripts/semantic_decision_census.sh
scripts/codepath_status_census.sh
scripts/codepath_status_runtime_report.sh <compiler>
scripts/arena_ownership_census.sh
scripts/lower_call_arena_ledger_smoke.sh <compiler>
scripts/node_slot_integrity_report.sh <compiler>
scripts/materialization_transaction_report.sh <compiler>
scripts/semantic_state_scope_report.sh <compiler>
scripts/call_materialization_transaction_admission_report.sh
```

Acceptance for this first architecture slice:

- no compiler behavior changes;
- output contains concrete candidate sites for NameResolution, TypeIdentity,
  SemanticStateScope, CallResolution, Materialization, AbiFacts/LayoutContract,
  backend semantic leakage, and debug/workaround gates;
- TODO/LANDMARKS identify the next dynamic ledger to implement before the next
  behavior-changing bootstrap fix;
- the script does not classify dead/live status by itself.
- the `AstNodeRef` shadow facade and lower-call parity report already showed
  current/ref/heuristic owner agreement at the generated-stage crash edge;
- the next architecture slice is therefore a behavior-neutral
  `NodeSlotIntegrity / AstArenaStorage` ledger, not another raw-read consumer
  patch;
- after `NodeSlotIntegrity` evidence refutes the local slot hypotheses, the
  next default slice is architecture sealing, not a second diagnostic ladder.
- after the first runtime `CodePathStatus` ledger, cleanup/deletion work is
  still blocked until a candidate path reaches `delete_ready` with a protecting
  falsifier. Correctness work should continue through transaction completeness,
  not through another crash-stack-local patch.
- the next correctness implementation should upgrade
  `scripts/materialization_transaction_report.sh` or add a sibling emitted-call
  transaction report. It must classify call/materialization rows as `exact`,
  `materialization_keepalive`, `wrapper_forwarder`, or `rejected_mismatch`
  before any behavior patch changes naming, materialization, or backend calls.
- after Slice 0k-B, owner fields exist for the transaction report, but they are
  still diagnostic. Do not start a forwarder, target keepalive, or
  requested-name materialization patch until the targeted row and would-change
  census are both named.
- after the post-0k-B full generated-stage checkpoint, focused transaction
  reports are not enough to justify a behavior change. The full generated-s2
  corridor currently does not reach `[MAT_EMIT]`, so the next slice is
  architecture planning/owner-boundary work unless a fresh run reaches a joined
  transaction row for the intended target.
- the first `SemanticStateScope` shadow ledger now makes naming/materialization
  authority explicit at the HIR materialization seam. Treat it as a facade and
  would-change-census input, not as a state-scope behavior fix. It self-applies
  far enough for a generated-s2 no-prelude report, but it does not make the
  full generated-stage frontier reach `[MAT_EMIT]`.
- after the first full generated-s2 state-scope run, the next step is now an
  explicit migration contract, not another local crash-edge patch. The full
  corridor emits owned `[STATE_SCOPE]` rows but still crashes before
  `[MAT_EMIT]`; the parallel `NodeSlotIntegrity` corridor reports only healthy
  slots for the instrumented lower-call edge. Treat this as evidence that
  `StateScope`, `MaterializationRegistry`, `AstNodeRef`, and `CodePathStatus`
  need executable consumer-migration gates. Do not re-enter backend forwarder,
  requested-name materialization, arena-scan, global ambient-map, or
  `NamedTuple`/`Tuple` normalization work from this evidence.

## 9. Decision Summary

Recommended direction:

- Use MIR as the compact durable IR.
- Use typed per-function streaming for `.ll` emission.
- Extract HIR services by behavior boundary, not by line count.
- Keep the demand-driven semantic rewrite as the strategic long-term track.
- Do not start the current bootstrap effort with the LLVM writer. That remains
  a later backend-local refactor candidate after semantic ownership boundaries
  are sealed. The active path is the architecture SDD sequence:
  semantic/CodePath census, owner ledgers, typed facades, and only then bounded
  behavior slices that consume named facts.
- The immediate next executable architecture slice should classify and shadow
  consumers, not change semantics: first choice is a
  `StateScopeConsumerCensus`/shadow report for naming/materialization consumers;
  second choice is a `MaterializationRegistry` transaction-consumer report; an
  `AstNodeRef` raw-read migration or `CodePathStatus` deletion slice must carry
  its own focused falsifiers.
- `StateScopeConsumerCensus` must be implemented as a migration gate, not as a
  row-producing diagnostic report. It must enumerate the known
  naming/materialization consumers, emit one authority and one migration
  decision per reached consumer, and block later behavior patches on any
  `diagnostic_only` or `blocked_unknown` row. The implementation commit should
  add only the default-off report/ledger; changing naming or materialization
  semantics requires a later would-change census.
- Slice 0k-F now supplies that default-off report/ledger. Focused stage1
  evidence covers all required consumers with `rows=42224` and zero malformed
  / invalid rows, but it also reports `diagnostic_only=5935` and
  `keep_legacy_shim=5935`. Those blockers are now classified with
  `unclassified_blocked=0` into `legacy_shim.concrete_typed_params=4481`,
  `legacy_shim.skipped_untyped_params=924`,
  `legacy_shim.no_regular_params=530`, and zero
  `legacy_shim.regular_untyped_param_review` rows. Generated s2 self-builds,
  then its consumer report fails closed with `compiler_rc=139` after `17` rows
  because the generated compiler crashes before reaching every required
  consumer. The next architecture step is therefore to use already-owned
  `migrate_to_state_scope`, `migrate_to_materialization_registry`, or
  `rejected_ambient` rows as the input to a bounded would-change census, not to
  change naming/materialization behavior from diagnostic-shim rows alone.
- The first owned-row preflight is deliberately measured-red: a proposed
  owner-result probe records `owned_candidate_rows=36289`,
  `owner_result_unknown=0`, and `owned_would_change=3779`. StateScope and
  ambient-rejected rows are parity-clean under the naive probe, but
  MaterializationRegistry rows split (`legacy_result_1=3779`,
  `legacy_result_0=3765`). This refutes using the migration class itself as a
  behavior replacement rule. The next MaterializationRegistry work must model
  the specific decision being owned before any naming or materialization
  behavior changes.
- The first MaterializationRegistry attribution slice shows that the split is
  not local to one consumer and not explained by target-map presence. Every
  reached consumer is mixed, while selected-definition parameter class is the
  strongest separator (`regular_untyped_params=3362/3`,
  `concrete_typed_params=2/2033`, `no_regular_params=4/572`, with mixed
  short/skipped untyped classes). That makes a parameter-class contract the
  next planning surface before any behavior patch.

This plan should be revisited after the architecture SDD seals the active
semantic-owner frontiers enough that backend-local refactoring cannot hide a
state-scope, materialization, arena, or ABI owner bug.
