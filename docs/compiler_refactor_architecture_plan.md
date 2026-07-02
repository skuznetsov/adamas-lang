# Compiler Refactor Architecture Plan

Status: Draft; reference-only for near-term bootstrap work. Active bootstrap
architecture is governed by `docs/compiler_architecture_sdd.md`.
Date: 2026-04-11
Scope: compile pipeline maintainability, LLVM IR emission, and HIR service
boundaries
Related: `PLAN_DEMAND_DRIVEN_REWRITE_RFC.md`, `docs/ast_to_hir_audit.md`,
`docs/codegen_architecture.md`

2026-07-02 post-0k-CV note: the active SDD has paused production source again
after an unfinished local 0k-CU `BlockCallReturnContract` WIP was reviewed and
removed. This plan must not treat the assigned-tail block-return slice as the
automatic next implementation step. The next movement is architecture
burn-down: select one durable owner spine plus one producer-to-consumer
authority edge, retire/refute a stale report surface, or promote a missing
contract falsifier. A source-shape helper, crash-stack movement, or partial
local WIP is not progress toward green `s2b`/`s3b` unless it consumes an old
authority edge and runs the generated-stage gate named by a fresh receipt.

2026-07-02 post-0k-CW note: architecture burn-down selected
`MaterializationTransaction` exact body availability. Source-shape evidence
shows `SemanticStateScope`, `MaterializationSymbolBinding`, and the main
`CallMaterializationTransaction` seam are already promoted or shadow-only, so
they are not the next owner-spine selection. Generated-stage transaction
evidence reports `post_consumer_state=selected_consumed_by_contract_consumer`,
`contract_mismatch_rows=0`, `residual_exact_missing_body_rows=14`,
`residual_exact_missing_body_groups=9`, and
`residual_selection_status=rejected_exact_missing_body_ambiguous`. The next
executable movement is a read-only `FunctionAvailabilityContract` /
exact-missing-body classifier that splits those all-equal rows by producer
cause: HIR body absent, HIR body present but not lowered to MIR, MIR function
absent, backend emitted-set miss, or legitimate extern/runtime helper. Do not
patch sampled Array/Slice/IO/Atomic/String::Builder/Int32 methods directly and
do not add backend undefined-extern rescue or forwarders from this evidence.

2026-07-02 post-0k-CX note: the read-only exact-body lifecycle classifier is
now implemented as `scripts/generated_stage_exact_body_availability_classifier.sh`.
A fresh current-source stage1 run reports
`classifier_classification=reached_tx_and_emit`,
`residual_exact_missing_body_rows=14`,
`residual_body_lifecycle_cause_kinds=1`,
`selected_cause=created_body_backend_missing`, `selected_rows=14`,
`classification=rejected_body_lifecycle_class_too_wide`, and 9 lifecycle
groups. This changes the next question: the residual is not explained by "HIR
materializer never created the bodies", because the self-applying transaction
ledger records `materialization_action=created_body`. It is still too broad for
a behavior patch. The next executable step is another read-only split inside
`created_body_backend_missing`: HIR body still visible after materialization,
HIR/RTA prune before MIR, MIR function missing, backend lookup/emitted-set miss,
or legitimate extern/runtime helper. Do not use the sampled method names,
backend rescue, forwarders, requested-name forcing, `NamedTuple`/`Tuple`
rendering, ambient-map policy, or `BlockOwner` changes as shortcuts.

2026-07-02 post-0k-CY note: the active SDD has refined 0k-CX with
`scripts/generated_stage_created_body_visibility_classifier.sh` and extra
self-applying `[MAT_TX]` / `[MAT_EMIT]` visibility facts. Fresh current-source
stage1 evidence reports `classifier_classification=reached_tx_and_emit`,
`created_body_missing_visibility_rows=14`, `visibility_cause_kinds=1`,
`selected_cause=state_in_progress_without_hir_function`, `selected_rows=14`,
`classification=rejected_visibility_class_too_wide`, 9 visibility groups, and
`missing_visibility_field_rows=0`. This corrects the 0k-CX reading:
`materialization_action=created_body` is not proof that a HIR function body was
present for this residual. The stronger facts are `body_function_present=0`,
`body_has_body=0`, `body_state=in_progress`, and backend
`lookup/module/plan/emitted` visibility all zero. The next executable movement
is not a backend plan/lookup fix. This post-0k-CY next-step wording is
superseded by the post-0k-CZ correction below: the next classifier must measure
post-lowering completion rather than treating pre-lowering `InProgress` as a
completed-body root.

2026-07-02 post-0k-CZ note: hostile review corrected the post-0k-CY next-step
wording. Source inspection shows `[MAT_TX]` body visibility is recorded before
`lower_method(...)`, while the `ensure` block updates/deletes the lowering
state only after the materialization attempt finishes. Therefore
`state_in_progress_without_hir_function` is a pre-lowering visibility fact, not
a proven root. The next executable architecture movement remains read-only and
behavior-neutral, but it must measure post-lowering completion: add a
`FunctionAvailabilityContract` completion ledger fact after materialization
finishes, join it to `[MAT_TX]` / `[MAT_EMIT]`, and only then classify true
body absence versus HIR-to-MIR/backend visibility. Do not patch the old
0k-CY sample rows, backend stubs, forwarders, requested-name policy,
`NamedTuple`/`Tuple`, ambient maps, or `BlockOwner` from pre-lowering evidence.

2026-07-02 post-0k-DA note: the post-lowering completion ledger now exists and
the generated-stage classifier consumes `[MAT_TX]`, `[MAT_DONE]`, and
`[MAT_EMIT]`. Fresh evidence reports `mat_tx_rows=724`, `mat_done_rows=794`,
`created_body_missing_completion_rows=14`,
`selected_cause=lowering_completed_without_hir_function`, and
`classification=rejected_completion_class_too_wide` across 9 completion groups.
This confirms the residual survives completion but remains too broad for a
behavior fix. The acceleration path is not another standalone census: introduce
a `MaterializationAttemptResult` terminal-status owner so the next split is a
contract consumed by materialization/ExternCall fallback decisions, not another
log surface.

2026-07-02 post-0k-DB note: the attempted acceleration path was corrected by
falsifier. A separate `MaterializationAttemptResult` row/storage surface and a
HIR-to-MIR consumer ledger caused generated-stage tx-only runs that never
reached backend emission (`mat_emit_rows=0`). The accepted behavior-neutral
slice instead enriches the existing `[MAT_DONE]` row with `status`, `reason`,
and `created_function_count`. Fresh classifier evidence reaches
`[MAT_EMIT]` again (`mat_emit_rows=173`) and selects the still-broad terminal
cause `attempt_lowering_returned_no_hir_function` with 14 rows across 9
groups. The next architecture movement should split that producer path
directly; it should not reintroduce an independent result store or consumer
ledger until a generated-stage falsifier proves that surface is self-host safe.

2026-07-02 post-0k-DC note: the producer path was split one level deeper while
keeping `[MAT_DONE]` as the authority. Fresh current-source evidence from
`STAGE1_COMPILER=/tmp/adamas_producer_path_stage1 SAMPLES=8 scripts/generated_stage_created_body_visibility_classifier.sh`
reaches `[MAT_EMIT]` (`mat_emit_rows=173`) and selects a single still-broad
producer class:
`attempt_lowering_returned_no_hir_function__producer_instance_class_info_lower_method__created_none`
with 14 rows across 9 root-sized groups. This refutes outer
materialization-path ambiguity: every residual reaches the instance
class-info `lower_method` branch and creates no HIR function. A deeper
optional trace object threaded through `lower_method` was preflight-refuted
because it regressed generated-stage runs to `tx_only_no_emit`. The next
architecture movement should split `lower_method` terminal behavior with a
self-host-safe producer observation, preferably a temp-source classifier or a
field that does not alter `lower_method` call ABI.

2026-07-02 post-0k-DD note: that self-host-safe observation now exists as
`scripts/generated_stage_lower_method_terminal_classifier.sh`. It injects
`[MAT_METHOD_EXIT]` probes only into copied temp source, builds a generated
probe `s2` from that copy, and runs the existing completion classifier with
`GENERATED_S2=<probe>`. Fresh evidence preserves `[MAT_EMIT]` reachability and
splits the 14-row residual into three terminal buckets:
`lower_method_terminal_no_exact_method_exit` (9 rows),
`lower_method_terminal_abstract_method` (4 rows), and
`lower_method_terminal_created_hir_function` (1 row). The result is mixed, so
it is still not a behavior license. The next architecture movement should
split the broad `no_exact_method_exit` bucket by source identity / resolved
DefNode / full-name derivation, not patch the sampled methods or backend
fallback.

2026-07-02 post-0k-DE note: the `lower_method` terminal classifier was refined
after hostile review found that `created_hir_function` is not a real terminal
state. The classifier now logs temp-only entry/name rows and a final
`completed_method` terminal. Fresh evidence preserves `[MAT_EMIT]` reachability
and reports `method_entry_rows=338`, `method_name_rows=285`,
`method_exit_rows=623`, `residual_rows=14`, and four buckets:
`no_exact_no_entry` (6 rows), `abstract_method` (4 rows),
`no_exact_matching_full_name_without_exit` (3 rows), and `completed_method`
(1 row). The next architecture movement should split `no_exact_no_entry` by
actual lower_method call input, selected DefNode/source owner, and
requested/target/body symbol relation. This is still classifier-only evidence,
not a behavior license.

2026-07-02 post-0k-DF note: a temp-only `[MAT_METHOD_CALL]` row was added at
the `instance_class_info_lower_method` call site. Fresh evidence still reaches
`[MAT_EMIT]` and reports `method_call_rows=242`. The broad bucket is now
`no_exact_no_call` (6 rows): sampled rows have zero exact/requested call rows,
while abstract controls join to matching call rows. The next architecture
movement should split the control region after transaction logging but before
the actual `lower_method` call, especially type-param isolation, namespace
override, arity fallback, and any pre-call return/skip edge.

2026-07-02 post-0k-DG note: that pre-call split now exists in
`scripts/generated_stage_lower_method_terminal_classifier.sh` as temp-only
`[MAT_PRECALL]` checkpoints. Fresh evidence reports
`completion_classifier_classification=reached_tx_and_emit`,
`method_call_rows=242`, `precall_rows=1628`, `method_entry_rows=338`,
`method_name_rows=285`, `method_exit_rows=623`, `residual_rows=14`, and the
selected broad class `lower_method_terminal_no_exact_after_tx_no_call` (6
rows). The selected samples reach `after_tx` but not `inside_type_params`;
abstract controls traverse all pre-call checkpoints and join to call rows.
This refutes namespace override and arity repair as the first boundary for the
selected six rows, but it is still not a behavior license. The acceleration
path is no longer another local marker. The next architecture movement should
write a pre-code receipt for the scoped type-param/block-yield owner edge after
transaction logging, or refute the current `MaterializationTransaction` row and
return to the Current Execution Board.

2026-07-02 post-0k-DH note: that receipt is now written in
`docs/compiler_architecture_sdd.md`. It selects a `contract-owner-migration`
for the implicit body-lowering scope-entry edge after
`CallMaterializationTransaction` logging: existing
`CallMaterializationTransaction` plus `SemanticStateScope` must own the
`after_tx -> inside_type_params` contract instead of leaving it implicit in
nested block helpers. The next source slice is admitted only if it removes or
root-sizes the six-row `after_tx_no_call` class while preserving generated-stage
`[MAT_EMIT]` reachability and abstract-method controls.

2026-07-02 post-0k-DI note: that source slice is implemented for the instance
materialization path. Scope entry now applies `merged_params` and
`namespace_override` explicitly after transaction logging, with restore in
`ensure`, instead of relying on nested helper blocks as the only authority edge.
The focused generated-stage gate
`STAGE1_COMPILER=/tmp/adamas_scope_entry_stage1 REQUIRE_REACHED=1 SAMPLES=8 scripts/generated_stage_lower_method_terminal_classifier.sh`
reports `completion_classifier_classification=reached_tx_and_emit`,
`method_call_rows=266`, `precall_rows=1330`, `method_entry_rows=356`,
`method_name_rows=310`, `method_exit_rows=666`, `residual_rows=3`,
`terminal_cause_kinds=1`, `terminal_groups=2`,
`selected_cause=lower_method_terminal_abstract_method`, `selected_rows=3`, and
`classification=eligible_lower_method_terminal_edge`. The old six-row
`after_tx_no_call` class is consumed. This is not a green `s2b`/`s3b` claim; the
next production decision must return to the Current Execution Board and remeasure
the generated-stage pressure gate before choosing another owner edge.

2026-07-02 post-0k-CS note: hostile review of the post-0k-CR route found that
the active SDD is still being followed, but the emergency B4/O1 lane can become
another symptom scheduler if every moved crash stack automatically selects the
next classifier. This plan remains a reference map only. The active execution
surface is now the 0k-CS board rule in `docs/compiler_architecture_sdd.md`:
the paired assigned-tail passthrough + return-shape wrapper materialization
slice may proceed as one `bootstrap-emergency-with-ledger` behavior slice, but
after it lands, or if it widens beyond the root-sized discriminator, production
code must return to the Active Architecture Board. The next non-emergency
movement should be architecture burn-down: select a durable owner spine, retire
or refute a stale report surface, or promote one missing contract falsifier
from `docs/specs/05-falsifier-matrix.md`. Do not keep appending near-term
crash-stack decisions here as if this document were the authoritative backlog.

2026-07-02 post-0k-CT note: the active SDD now has a short
`Current Execution Board` and required `SliceReceipt` above the historical
ledger. This plan is not allowed to reselect work by reading the freshest
crash-stack section or by continuing the 0k-CR emergency lane by inertia.
Before any non-doc compiler source slice, use the SDD receipt fields:
board lane, tranche, old authority edge, owner fact/service, producers,
consumers, measured-red baseline, focused DoD, architecture DoD,
generated-stage gate, negative controls, rejected shortcuts, and residual
boundary. If a proposed slice cannot fill those fields, the next movement is
docs/probe work or architecture burn-down, not production code.

2026-07-02 post-0k-CU implementation note: the admitted breakglass lane is now
consumed by the HIR `BlockCallReturnContract` slice. Fresh evidence reports
`classification=current_0k_cu_block_call_return_contract_applied`,
`assigned_tail_multi_shape_keys=0`, `timed_cp_phase_keys=5`,
`timed_cp_phase_nil_value_coexist_keys=0`, and
`timed_cp_phase_set_return_keys=1`; the broad non-owner space remains rejected
(`candidate_multi_shape_keys=207`, `candidate_additional_return_shape_bodies=224`).
The generated-stage O1 gate moved past the old `affected_block_ids` /
`Set(UInt32)#includes?` frontier and now reports
`b4_classification=llvm_entry_failure_after_lower_main` with
`workers1_exit139=0`. This is not green `s2b`/`s3b`; the next production
movement must return to the Current Execution Board and reselect an owner edge
for the post-`lower_main` RSS/resource residual instead of continuing the
0k-CU lane by inertia.

2026-07-02 post-0k-DK note: the post-0k-CU residual is now classified through
the generated-stage transaction report rather than a raw RSS tail. The gate
`STAGE1_COMPILER=/tmp/adamas_postcu_stage1 TAIL_LINES=30 REQUIRE_JOINED=1 REQUIRE_POST_CU_RESOURCE=1 scripts/generated_stage_execution_transaction_report.sh`
exits 0 with `final_classification=abort_resource_after_lower_main`,
`join_status=joined`, `resource.default_memory_kill=1`,
`resource.workers1_memory_kill=1`, `output.commit_record=llvm_ir_started_without_commit:file`,
and `tail.semantic_vs_input_split=tail_not_reached_after_output_start`. This is
still `admission_status=rejected_no_root_sized_consumer`: the next production
slice must split a transaction-owned resource/output/function-plan edge before
changing memory limits, worker policy, rand fallback, output behavior, tail
stubs, or backend emission.

2026-07-02 post-0k-DL note: the resource/output/function-plan ambiguity is now
split one level deeper with default-off `llvm.generate_phase` rows. Fresh
evidence from
`STAGE1_COMPILER=/tmp/adamas_phase_stage1 TAIL_LINES=30 REQUIRE_JOINED=1 REQUIRE_POST_CU_RESOURCE=1 REQUIRE_RESOURCE_PHASE_SPLIT=1 scripts/generated_stage_execution_transaction_report.sh`
preserves `final_classification=abort_resource_after_lower_main` and
`admission_status=rejected_no_root_sized_consumer`, but reports
`resource.llvm_generate_last_phase=function_emission_start`,
`resource.llvm_generate_phase_split=during_function_emission`, and
`runtime.llvm_generate_phase_rows=2`. The next executable movement is therefore
not tail/output/metadata/DWARF/type-name cleanup and not resource-budget
acceptance. It must name a root-sized function-emission authority edge inside
`LLVMIRGenerator#generate`: function-plan memory growth, sequential/parallel
chunk emission, worker/parent output buffering, or another measured
function-emission consumer.

2026-07-02 post-0k-CR note: the return-shape census now also measures
assigned-tail yield passthrough (`result = yield; ...; result`). Strict current
evidence keeps the broad 0k-CQ result for naive `contains_yield` scope, but
narrows assigned-tail passthrough to one multi-shape key:
`CopyPropagationPass#timed_cp_phase$String_block`
(`assigned_tail_multi_shape_keys=1`,
`timed_cp_phase_assigned_tail_passthrough_keys=1`). The next behavior slice is
admitted only as a paired owner-contract migration: make assigned-tail
passthrough block-return-dependent and use that owner fact to choose
return-shape-specific wrapper materialization. A classifier-only change is not
enough because the current failure requires the wrapper body itself to stop
lowering `yield : Void`.

2026-07-02 post-0k-CQ note: the first 0k-CP return-shape census exists as
`scripts/hir_block_return_shape_census.sh`, and it refutes naive
block-return-shape specialization for all untyped `&` helpers. Current
classification is `current_0k_cp_hir_block_return_shape_broad`, with
`candidate_multi_shape_keys=208` and
`candidate_additional_return_shape_bodies=228`. The `timed_cp_phase` row is
still present, but the broad census shows that `contains_yield` plus untyped
block parameter is not a valid owner boundary. The near-term refactor lane must
now add a read-only return-demand / yield-passthrough discriminator before any
behavior fix: classify helpers whose method return semantically depends on the
yielded value, and exclude ordinary iterators/scope helpers that merely
observe varied block returns.

2026-07-02 post-0k-CP note: production compiler source remains paused after
the 0k-CO producer-order classifier. The current B4 path is not a
CopyPropagation, Set/Hash, backend, worker, output, or resource fix lane. The
selected refactor direction is a HIR-owned block-call return materialization
contract: untyped `&` helpers that can return `yield` must not share a wrapper
whose yield ABI was frozen by an earlier nil/non-returning callsite. The next
executable step is a read-only return-shape census that measures how many
shared wrappers have multiple observed block-return shapes and whether
specializing by `(callee shape, arg shape, block-return shape)` is root-sized.
Do not implement a behavior slice until that census protects nil/non-returning
negative controls and rules out broad wrapper explosion.

2026-07-02 post-0k-CO note: the timed phase HIR source seam is now pinned to
producer ordering. New classifier:
`scripts/mir_timed_phase_hir_producer_order_classifier.sh`. Strict mode reports
`current_0k_co_hir_timed_phase_shared_wrapper_order_frontier`: the shared
`timed_cp_phase$String_block` wrapper is first lowered from an earlier callsite
with `block_return=nil`, so yield fallback returns nil/`Void`; later the
`apply_collect_affected_blocks` callsite records `block_return=Set(UInt32)` for
the same wrapper name, but the wrapper is already void-yielded and
`yield_return_function_for_block_call?` is false. The near-term refactor lane is
now a pre-code fix design for callsite block-return specialization /
wrapper-materialization ownership for untyped `&` helpers. Do not use
CopyPropagation guards, `timed_cp_phase` annotation/inlining, or MIR/LLVM
backend rescue as the next move.

2026-07-02 post-0k-CN note: the timed phase frontier is now localized above
HIR->MIR and LLVM backend return handling. New classifier:
`scripts/mir_timed_phase_source_seam_classifier.sh`. Strict mode reports
`current_0k_cn_hir_timed_phase_source_seam`: the HIR collect block proc returns
`Set(UInt32)`, but the HIR `timed_cp_phase$String_block` wrapper has
`yield : Void` and the `apply_collect_affected_blocks` call/local are already
typed `Nil|Void`. The next near-term refactor lane is still read-only:
pin which HIR producer chose the void block/call return, among block-return
name recording, yield-return function selection, block-return callsite
recording, and untyped-`&` fallback. Do not patch CopyPropagation,
`timed_cp_phase`, MIR lowering, LLVM backend block calls, or Set/Hash
delegates before that producer is named.

2026-07-02 post-0k-CM note: the MIR optimization/container frontier is now
localized past Set/Hash construction. New classifier:
`scripts/mir_timed_phase_return_frontier_classifier.sh`. Strict mode reports
`current_0k_cm_timed_cp_phase_block_return_frontier`: the
`apply_collect_affected_blocks` block builds and returns a `Set(UInt32)`, but
produced `s2b` materializes `CopyPropagationPass#timed_cp_phase(String, &)` as
a void/null-return `String_block` wrapper and `apply_replacements` consumes the
result as `Nil|Void`. The near-term refactor lane must now localize the
compiler-source seam for bare-block/yield return materialization. Do not patch
`Set#includes?`, guard `affected_block_ids`, inline `timed_cp_phase`, or add a
backend block-return rescue before that seam is named.

2026-07-02 post-0k-CL note: the first `MIROptimizationInvariant` classifier
exists as `scripts/mir_optimization_container_frontier_classifier.sh`. It is
read-only and confirms the current produced-s2 crash as
`current_0k_ck_mir_cp_container_frontier`, with the null Set load owned by
`CopyPropagationPass#affected_blocks_use_only_local_replacements?` and the
source-level candidate container narrowed to `affected_block_ids`. The next
near-term work is still producer localization, not a fix: trace how
`apply_replacements`' `apply_collect_affected_blocks` timed block returns a
null Set receiver under produced `s2b`. Do not patch `includes?`, add a null
guard around `affected_block_ids`, or add backend Set/Hash rescue before that
producer is named.

2026-07-02 post-0k-CK note: after 0k-CJ the active architecture path is no
longer allowed to continue by consuming another `GeneratedStageExecution`
helper edge. Fresh B4 evidence keeps the produced-stage classifier red, but a
workers=1 `lldb` run localizes the current crash inside MIR optimization:
`Set(UInt32)#includes?` is called by
`CopyPropagationPass#affected_blocks_use_only_local_replacements?` during
`Function#optimize_with_potential`, with null registers at the Set load. The
near-term refactor lane must therefore add a read-only
`MIROptimizationInvariant` / compiler-runtime-container classifier before any
source fix. The classifier must distinguish: bad `Set(UInt32)` receiver,
valid Set with null `@hash`, wrong namespaced Set/Hash constructor body,
constant/default initialization failure, or malformed CopyPropagation
local-replacement state. Do not resume output/resource/tail/worker,
backend Set/Hash rescue, direct CopyPropagation guards, broad namespace
normalization, physical extraction, or `BlockOwner` rollback from this stack.

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

2026-07-01 post-0k-BC note: the TypeValue falsifier now exists as
`regression_tests/type_value_runtime_identity_contract.sh`. It is strict by
default and measured-red only under `ADAMAS_EXPECT_TYPEVALUE_MISMATCH=1`.
Fresh measured-red evidence shows blank direct/interpolated `typeof` rows
followed by exit 139 at direct `.class`. The next production implementation
unit is therefore no longer another report: add the smallest HIR-owned
`TypeValue` / `RuntimeTypeIdentity` fact that can serve the reached `typeof`,
runtime `.class`, nilable `.class`, direct output, interpolation, and
type-literal name/string consumers while preserving the H4 type-literal query
guard. If the required consumer set widens beyond the H6 guard, stop at
classification rather than patching one output path.

2026-07-01 post-0k-BD note: the TypeValue production slice now has an
implementation receipt. The next code change is admitted only as owner-fact
migration for the H6-reached source-visible type-value surface. It must name
the old authority edge it replaces (`typeof` nil placeholder, runtime `.class`
type-literal construction, dot-class side map, direct-output conversion,
interpolation conversion, or type-literal query lowering) and keep generic
materialization, `BlockOwner`, requested-name policy, ambient maps, backend
stubs/forwarders, and broad `NamedTuple`/`Tuple` rendering out of scope. If
that boundary cannot be kept, pause implementation and return to G3 semantic
key migration rather than shipping a local output fix.

2026-07-01 post-0k-BE note: the project is paused before production code again
because a well-scoped measured-red guard can still pull the work back into
local tail-chasing. The next code slice must first declare an architecture
tranche: `contract-owner-migration`, `semantic-service-extraction`,
`cleanup/delete`, or `bootstrap-emergency-with-ledger`. TypeValue remains
admitted only as `contract-owner-migration`; it must retire or shadow the H6
authority edges through one owner fact and must not become another output
special-case. If TypeValue needs generic materialization, `BlockOwner`,
requested-name policy, ambient maps, backend stubs/forwarders, or broad
`NamedTuple`/`Tuple` rendering, pause and return to G3 semantic-key migration
or a narrower semantic-service extraction plan.

2026-07-01 post-0k-BF note: the first local TypeValue owner-fact preflight was
reverted and converted into a planning checkpoint. It made the B3 oracle and H4
type-literal no-stub guard green, but strict H6 still failed only on direct
`puts (true ? 1 : nil).class`. Controls showed `puts((true ? 1 : nil).class)`,
`x.class`, and interpolation worked, while debug showed the command-call
argument reached HIR as `TernaryNode` rather than `.class`. Do not force H6
green with a source-text direct-output workaround. The next useful step is a
frontend command-call preservation falsifier or an explicit split of H6 into a
TypeValue core guard plus a separate measured-red parser/lowering guard.

2026-07-01 post-0k-BG note: the command-call preservation falsifier now exists
as `regression_tests/command_call_member_access_preservation_contract.sh`.
Strict mode is measured-red: `puts (true ? 1 : nil).class` parses as a root
`MemberAccessNode` on the command-call result, while controls preserve
`puts((true ? 1 : nil).class)`, `x.class`, and bare ternary command calls. The
next production slice should make this parser-frontier guard strict-green
without touching TypeValue, `BlockOwner`, generic materialization,
requested-name or ambient-map policy, backend stubs/forwarders, or broad
`NamedTuple`/`Tuple` rendering. After that, rerun H6 to separate remaining
TypeValue rows from frontend syntax preservation.

2026-07-01 post-0k-BH note: production work is paused again after a local
parser WIP was reverted before verification. The WIP showed the risk: closing
the 0k-BG guard by widening no-parens `LParen` parsing can quickly become a
broad parser-precedence patch rather than architecture work. The parser
frontier is still admitted, but only as one bounded exception: make the guard
strict-green with targeted parser-spec evidence in one implementation loop, or
stop and split H6 into TypeValue-core plus command-call-frontend guards before
resuming TypeValue owner-fact migration. This pause is the refactor plan's
current control point: do not let the parser exception reset the project back
to crash-stack-first work.

2026-07-01 post-0k-BI note: H6 is now split. New guard
`regression_tests/type_value_core_runtime_identity_contract.sh` excludes the
parser-confounded no-parens command-call row and remains measured-red on
current `bin/adamas`; the existing command-call parser guard remains separately
measured-red. This unblocks the intended `contract-owner-migration` lane again:
the next implementation unit should introduce one HIR-owned
`TypeValue` / `RuntimeTypeIdentity` fact for the core rows. A green core guard
is not a full old-H6 claim while the command-call frontend guard is still red.

2026-07-01 post-0k-BJ note: the TypeValue implementation lane now has an
owner-fact design gate. The next code slice is still the H6-core
`contract-owner-migration`, but it must be rejected if it merely makes the
output rows green. The implementation must create a named HIR-owned
`TypeValue` / `RuntimeTypeIdentity` fact carrying semantic `TypeRef`, display
name, origin, and runtime stringification policy; producers and consumers must
route through that fact. `@type_literal_values` may remain as a static-call
compatibility flag, but `dot_class_literal?`, nil placeholder shape, rendered
names, or backend stringification must not remain the sole authority for
source-visible type behavior. Parser, generic materialization, `BlockOwner`,
requested-name, ambient-map, backend forwarder/stub, and broad
`NamedTuple`/`Tuple` work remain out of scope for this slice.

2026-07-01 post-0k-BK note: production work is paused again after hostile
review of the repeated local-fix pattern. The architecture issue is no longer
"which current symptom can be made green fastest"; it is that HIR/MIR/backend
paths keep deriving semantic facts from rendered names, ambient maps, side
sets, and phase-local fallback state. The next movement must therefore be
either a docs/planning consolidation that retires or tightens a stale lane, or
the already-admitted H6-core `contract-owner-migration` for a named HIR-owned
`TypeValue` / `RuntimeTypeIdentity` fact. Do not resume backend forwarder,
target keepalive, materialization rescue, parser-precedence, global
ambient-map, `NamedTuple`/`Tuple`, or `BlockOwner` work from the latest
frontier unless a new SDD slice first names the old authority edge, falsifier,
root-size budget, and residual boundary.

2026-07-01 post-0k-BL note: the architecture pause now has an execution
ladder, and the uncommitted TypeValue owner-fact WIP has been quarantined
instead of allowed to steer by inertia. The refactor track should now treat
every production slice as a small owner-boundary migration: row selection,
legacy authority edge, owner fact/service, producer/consumer inventory,
measured-red baseline, focused DoD, architecture DoD, generated-stage
relevance, and residual boundary. Resuming the TypeValue WIP is still admitted,
but only through that ladder and only as H6-core `contract-owner-migration`;
it must not be used as proof that the broader compiler architecture has been
rewritten. If a next fix cannot name the owner fact/service or generated-stage
gate it moves, it belongs in SDD planning or cleanup classification, not in
production code.

2026-07-01 post-0k-BM note: the first post-ladder production slice landed the
H6-core TypeValue owner fact. This is an example of the intended architecture
movement: the slice added one HIR-owned fact, migrated a bounded producer and
consumer set to that fact, strengthened the falsifier with multi-argument
`typeof`, and recorded the next edge case instead of hiding it. It is not a
general runtime type-name service. The next TypeValue-related work must choose
between H7 parser `semantic-service-extraction` and H8 runtime union
`.class` type-name service; neither should be folded back into the H6-core
commit or implemented as backend-only stringification.

2026-07-01 post-0k-BN note: the first integration check after the TypeValue
owner-fact slice changes the near-term priority. H7 and H8 remain real
frontiers, but the produced-stage bootstrap blocker now occurs when the
produced `s2b` enters LLVM function emission for a full-prelude tiny source.
Default workers expose a parallel-emission `Invalid bound for rand: 0`
symptom and then a 4096MB RSS kill; `ADAMAS_LLVM_WORKERS=1` removes that
symptom but still exits 139 after `pass3 after lower_main call`. The next
refactor movement should therefore be a generated-stage
`LLVMEmissionSession` classification slice: identify the owner boundary for
function-list selection, worker/fallback policy, side-effect tables,
output-buffer lifetime, and memory/resource growth before changing behavior.
Do not treat raising memory limits, disabling workers, patching the rand
symptom, or resuming cleanup of `fused_parallel_requested` as architecture
progress.

2026-07-01 post-0k-BO note: B4 now has an executable classifier:
`scripts/generated_stage_llvm_entry_classifier.sh`. The current measured-red
gate is `REQUIRE_CURRENT_FRONTIER=1`; the future green gate is
`REQUIRE_CLEAN=1`. Fresh evidence reproduces the split that matters for the
next architecture movement: stage1 and produced `s2b` build successfully,
default LLVM workers reach `pass3 after lower_main call` and then hit the
parallel-rand/RSS symptom, while `ADAMAS_LLVM_WORKERS=1` reaches the same
transition and exits 139 without the rand symptom. At 0k-BO this selected a
first-bad `LLVMEmissionSession` owner-boundary question rather than a worker
patch. This sentence is superseded by 0k-BP/0k-BQ: the next implementation is
not a classifier extension by default; it is the behavior-neutral
`LLVMEmissionSession` owner-record migration and source-shape guard.

2026-07-01 post-0k-BP note: production fixes from the B4 crash stack are
paused. The next movement is not "extend the classifier" by default; it is to
design the owner contract that such a classifier would exercise.
`PhaseAuthority` / `GeneratedStageExecution` is the next architecture tranche:
classify phase facts as semantic, phase-local, emission-session-owned, or
debug-only; name old authority edges for function-list identity,
worker/fallback policy, side-effect table merge, output-buffer lifetime,
resource-budget accounting, and generated-stage evidence. A B4 classifier
extension is architecture work only if it answers one of those owner questions.
A behavior slice is admitted only after the owner contract and focused guard
name the old authority edge being replaced, shadowed, or refuted. This keeps B4
as the active bootstrap pressure gate without letting it become another
crash-stack-first implementation lane.

2026-07-01 post-0k-BQ note: the `PhaseAuthority` tranche now has a concrete
first owner contract: `LLVMEmissionSession`. The source inventory pins the
legacy edges to CLI step 5 and `LLVMIRGenerator#generate` /
`emit_functions_parallel`: CLI mutates backend setup flags and owns `.ll` file
writing, while the backend selects/filter/dedups functions, chooses workers,
forks/merges worker side effects, emits tail declarations/stubs, and records
memory evidence through mutable fields. The next code slice is admitted only
as behavior-neutral `contract-owner-migration`: introduce a session/plan record
that captures setup facts, function plan, worker plan, side-effect merge
contract, tail plan, output ownership, and generated-stage evidence. It must
add a source-shape guard proving at least one old authority edge is consumed by
the session record. Do not change emitted LLVM semantics, worker defaults,
fallback behavior, undefined externs, missing-body stubs, output-file behavior,
or `BlockOwner` in that first slice.

2026-07-01 post-0k-BR note: the first `LLVMEmissionSession` implementation
slice is in place and behavior-neutral. It consumes `function-list-inline` only:
`generate` now builds an `LLVMEmissionSession` and reads the final
`functions_to_emit` plan from it, while the previous reachability / unresolved
skip propagation / return-type precompute / dedup algorithm lives in
`build_llvm_emission_function_plan`. New source-shape guard:
`scripts/llvm_emission_session_source_shape_guard.sh`. Important adversary
finding: Crystal `record` macro carriers are not safe by default for generated
stage owner objects; a rejected preflight changed B4 to a
`LLVMEmissionFunctionPlan#functions_to_emit` stub. The committed carrier uses
explicit private classes/methods and preserves B4 as
`classification=current_0k_bn_frontier`. At 0k-BR the next architecture movement
still had to select one remaining `LLVMEmissionSession` edge, not patch the B4
crash stack: worker/fallback policy, side-effect merge contract, tail
declarations/stubs, output ownership, or resource evidence. Slice 0k-BS below
then consumes the worker-policy edge.

2026-07-01 post-0k-BS note: the second `LLVMEmissionSession` implementation
slice is in place and behavior-neutral. It consumes `worker-policy-inline`:
`generate` now reads effective worker count from the session, while
`build_llvm_emission_worker_plan` preserves the existing `parallel_llvm_workers`
policy and debug-metadata sequential override. The first worker-plan shape with
a separate helper class failed B4 during stage1->s2 build under the 4096MB
gate; the committed shape stores requested/effective worker count and reason
code directly on `LLVMEmissionSession`. This keeps B4 at
`classification=current_0k_bn_frontier` and does not fix worker rand/RSS,
workers=1 exit 139, fallback behavior, side-effect merging, tail stubs, output
ownership, or resource gates. Before 0k-BT, next candidates were side-effect
merge contract, tail declaration/stub plan, output ownership, or resource
evidence; 0k-BT below tightens this to vertical contract work only.

2026-07-01 post-0k-BT note: pause production code before the next
`LLVMEmissionSession` micro-slice. A local side-effect-tag vocabulary WIP was
stashed because tag/getter ownership alone is too thin to count as the next
architecture movement. The next executable slice must be a vertical contract
slice, not a field-count burn-down: it must define one of
`SideEffectMergeContract`, `TailDeclarationPlan`, `OutputOwnership`, or
`ResourceEvidence`, name the old authority edge and downstream consumer, prove
that consumer no longer treats mutable backend fields/ad-hoc files/tail fallback
as sole authority, and rerun B4. Do not commit vocabulary-only, scalar-only, or
report-only `LLVMEmissionSession` changes as standalone progress.

2026-07-01 post-0k-BU note: the selected vertical contract is
`SideEffectMergeContract`. The next code slice is now constrained to
`parallel-side-effect-file-merge`: worker `.se` row writing and parent merge
inside `emit_functions_parallel` must move behind a session-owned contract while
preserving the existing `.se` format and merge semantics. The source-shape guard
must be red before patch under `REQUIRE_SIDE_EFFECT_CONTRACT=1` and green only
when both writer and parent merge consumers delegate through the contract. This
is not a tail-stub fix, output-ownership fix, resource fix, worker-count fix, or
B4 green claim.

2026-07-02 post-0k-BV note: pause production code again before implementing
the side-effect contract. Hostile review found a second-order metric drift:
`LLVMEmissionSession` edge consumption can become the new local progress proxy
even while B4 remains at the same produced-stage boundary. The
`SideEffectMergeContract` implementation is still admitted, but at that point
it is the then-future Slice 0k-BW and must include the convergence vector from
the SDD:
B4 before/after, default-worker versus `ADAMAS_LLVM_WORKERS=1` split,
side-effect source shape, tail-input versus semantic-failure classification,
output/resource evidence boundary, and post-edge routing. If 0k-BW makes the
source-shape guard green while preserving B4 and every vector row unchanged,
do not select `TailDeclarationPlan`, `OutputOwnership`, or `ResourceEvidence`
by inertia; write a higher-level `GeneratedStageExecution` transaction
redesign checkpoint first.

2026-07-02 post-0k-BW note: the side-effect contract consumer migration landed
in behavior-neutral mode. `emit_functions_parallel` no longer owns the raw
worker `.se` writer tags or parent raw-tag merge switch inline; the source-shape
guard is green. The convergence vector did not narrow: B4 remains
`classification=current_0k_bn_frontier`, default workers still hit the
parallel-rand/RSS path, and `ADAMAS_LLVM_WORKERS=1` still exits 139 after
`pass3 after lower_main call`. This is useful ownership progress but not
bootstrap progress by itself. Per the 0k-BV stop rule, do not continue with the
next unconsumed local session edge. The next refactor movement should be a
docs/design `GeneratedStageExecution` transaction checkpoint that models the
whole generated-stage LLVM-entry product and its commit/abort evidence before
any more production compiler edits.

2026-07-02 post-0k-BX note: that checkpoint is now design-sealed. The next
executable refactor slice is not `TailDeclarationPlan`, `OutputOwnership`,
`ResourceEvidence`, worker policy, side-effect semantics, or a backend
forwarder. It is a default-off generated-stage execution transaction report
that joins invocation setup, function plan, worker/fallback, side-effect
contract, tail inputs, output ownership, resource evidence, and B4 final
classification under one transaction id. A future behavior slice must consume a
root-sized transaction-owned row or explicitly refute this boundary; local
LLVM logs and source-shape success are not enough.

2026-07-02 post-0k-BY note: the first generated-stage execution transaction
report now exists as `scripts/generated_stage_execution_transaction_report.sh`.
It preserves the B4 current-frontier pressure and emits one transaction id, but
current source is still rejected for behavior admission:
`final_classification=abort_unjoined_evidence`,
`join_status=phase_local_only`, and
`admission_status=rejected_unjoined_evidence`. The next refactor slice should
add default-off runtime transaction rows for HIR/MIR module identity,
`LLVMEmissionSession` id, side-effect row counts, tail semantic-vs-input split,
and output commit record. Do not move to worker/tail/output/resource behavior
while the report remains phase-local only.

2026-07-02 post-0k-BZ note: the post-0k-BY hostile Quadrumvirate review keeps
that next slice but tightens its completion rule. Runtime rows are not an
architecture win by themselves. The slice must move the transaction report to
joined evidence and produce one of three outcomes: exactly one root-sized
transaction-owned old authority edge, an explicit refutation of
`GeneratedStageExecution` as the wrong owner boundary, or a named stop because a
required row cannot be produced default-off. If joined evidence is broad or
ambiguous, the next movement is a selector/falsifier slice, not a behavior
patch. Worker/tail/output/resource fixes, backend forwarders, `NamedTuple` /
`Tuple` rendering, ambient-map policy, parser behavior, and `BlockOwner`
changes remain rejected while this decision is missing.

2026-07-02 post-0k-CA note: the runtime-row join slice landed. The active
transaction report now reaches `join_status=joined` on the real current B4
frontier while preserving `b4.classification=current_0k_bn_frontier` and
classifying the result as `final_classification=abort_resource` /
`admission_status=rejected_no_root_sized_consumer`. This converts the gate from
unjoined evidence to joined abort evidence, but it is still not behavior
admission and not green `s2b`/`s3b`. The next architecture movement must select
one root-sized transaction-owned old authority edge from the joined rows, or
refute `GeneratedStageExecution`; do not patch workers, tail stubs, output,
resources, backend forwarders, `NamedTuple`/`Tuple`, ambient maps, parser
behavior, or `BlockOwner` from the joined row alone.

2026-07-02 post-0k-CB note: hostile review of the post-0k-CA route found that
even a joined transaction selector can become another proxy metric if it only
chooses the next local LLVM symptom. The refactor plan is therefore reset to
owner-spine consolidation before more production compiler behavior. The active
spines are `SemanticIdentity`, `MaterializationTransaction`, and
`PhaseAuthority` / `GeneratedStageExecution`. A future selector over joined
rows is guard-only unless it maps evidence to one of those spines and names a
producer-to-consumer authority edge. Do not implement `ResourceEvidence`,
output/tail fixes, worker/memory-budget behavior, backend forwarders,
`NamedTuple`/`Tuple` rendering, ambient-map policy, parser behavior, or
`BlockOwner` changes merely because the current joined rows mention output
start, resource abort, or missing tail rows.

2026-07-02 post-0k-CC note: owner-spine consolidation is now design-sealed.
B4 and L6 remain `PhaseAuthority` guard-only pressure gates, H7/H8 remain
`SemanticIdentity` pre-s2-clean residuals, and G6 is selected as the next
implementation lane under `MaterializationTransaction`. The next code slice is
not a backend rescue and not a carrier rollback. It must start from
`regression_tests/block_owner_index_assign_materialization_repro.sh`, preserve
`BlockOwner`, and prove that `Hash(UInt64, BlockOwner)#[]=` is demanded,
materialized, and visible to HIR/MIR/backend body-presence checks under one
semantic identity before changing behavior.

2026-07-02 post-0k-CD note: production compiler edits are paused before the G6
implementation. Hostile review found that the current G6 row is still vulnerable
as a value proxy: a patch can make the `Hash(UInt64, BlockOwner)#[]=`
self-IR body non-stub while leaving the deeper materialization authority split in
place. The next executable planning unit is a pre-code
`MaterializationTransaction` gate. It must name the old authority edge, owner
record/consumer, producer and consumer chain, invariant, negative controls, and
residual generated-stage pressure before any `ast_to_hir.cr`, `hir_to_mir.cr`,
or `llvm_backend.cr` production edit. Accepted implementation after that gate is
only an owner-edge migration or root-sized behavior flip; backend undefined
extern rescue, forwarders, requested-name forcing, broad `NamedTuple`/`Tuple`
rendering, global ambient-map policy changes, parser changes, and `BlockOwner`
rollback remain rejected.

2026-07-02 post-0k-CE note: the G6 pre-code plan gate is now design-sealed. The
next implementation is not a generic materialization experiment and not a backend
stub workaround. It is a transaction-owned availability slice over the exact
setter chain: `lower_assign` index-target `[]=` demand, `lower_function_if_needed`
materialization binding, HIR transaction contract, HIR-to-MIR contract
attachment, and backend body visibility. The code slice must prove the demanded
`Hash(UInt64, BlockOwner)#[]=` call-visible symbol, selected semantic target,
materialized body symbol, HIR/MIR body presence, and backend-visible body are one
semantic function before it changes emitted behavior. Stop if the setter demand
has no transaction id, if only a sibling body exists, if MIR falls back to
`ExternCall`, if backend alone knows the missing body, or if the would-change set
is broader than the current `BlockOwner` setter family.

2026-07-02 post-0k-CF note: the G6 availability slice landed as a
behavior-neutral executable guard, not as a compiler source patch. Fresh
`scripts/block_owner_materialization_transaction_availability_report.sh
bin/adamas` reports one exact/all-equal BlockOwner setter transaction, seven
joined body-present emissions, one non-stub LLVM body, and zero setter stubs.
Fresh B4/L6 pressure gates still report `classification=current_0k_bn_frontier`,
`join_status=joined`, and `admission_status=rejected_no_root_sized_consumer`.
Therefore the next architecture movement is back under `GeneratedStageExecution`:
select one root-sized joined consumer edge before changing workers, resources,
output commit behavior, tail stubs, or backend missing-body behavior. Do not
continue materialization behavior work unless the new G6 guard regresses.

2026-07-02 post-0k-CG note: the post-G6 route is tightened again to avoid
selector/report tail-chasing. "Select one root-sized joined consumer edge" now
means "write the pre-code owner-edge plan for a
`GeneratedStageExecutionOutcome` / phase-outcome authority" before any
production source edit. A standalone selector, extra transaction report, or
crash-marker narrowing is not architecture work unless it retires/refutes a
previous report surface and names one code-owned authority edge. The next valid
slice must choose B4/L6 under `PhaseAuthority` / `GeneratedStageExecution`,
declare `contract-owner-migration`, name the old authority edge and owner
fact/service, enumerate producers/consumers, and state the measured-red baseline
plus generated-stage gate. Worker/resource/output/tail/backend fixes,
materialization behavior, parser behavior, broad `NamedTuple`/`Tuple` rendering,
global ambient-map changes, physical file extraction, and `BlockOwner` rollback
remain rejected.

2026-07-02 post-0k-CH note: the pre-code owner-edge plan now exists. The first
`GeneratedStageExecutionOutcome` edge is `cli.output_commit_record`: the CLI
directly emits `output.llvm_ir_start`, `output.llvm_ir_written`, and
`output.binary_compile_result` transaction rows, and the shell report derives
`output.commit_record` / final classification from those rows. The next source
slice, if taken, must be behavior-neutral and root-sized: add an
invocation-lifetime outcome owner/helper for the CLI output corridor, make the
output row producer serialize from that owner while preserving the current
`GSETX` row format, add a source-shape guard that rejects direct scattered row
writes, and rerun the joined B4/L6 pressure gate expecting the same measured-red
classification unless a separate behavior slice is explicitly admitted. Do not
reselect worker/resource/tail/backend, parser, materialization,
`NamedTuple`/`Tuple`, ambient-map, physical extraction, or `BlockOwner` work
from this edge.

2026-07-02 post-0k-CI note: the refactor track now has a bootstrap-potential
gate to stop disciplined proxy descent. The current 0k-CH implementation
candidate may be finished as a checkpoint or reverted, but it must not
automatically select another behavior-neutral edge. Before any later production
slice, write
`BootstrapPotential = (B4/L6 phase, plausible owner-spine count, live
proxy-surface count, unmigrated authority-edge count)` and state the
lexicographic descent. If only `unmigrated authority-edge count` decreases while
B4/L6, owner-spine ambiguity, and proxy surfaces stay fixed, the next work is
SDD redesign, owner-spine refutation, direct root localization, or an explicitly
bounded `bootstrap-emergency-with-ledger` behavior slice. This is the current
control point for avoiding source-shape theater.

2026-07-02 post-0k-CJ note: the 0k-CH output-owner checkpoint is implemented
and verified. `GeneratedStageExecutionOutcome` now owns the CLI output
start/write/compile-result row serialization, with
`scripts/generated_stage_outcome_source_shape_guard.sh` proving no direct
scattered output row writes remain outside the helpers. This is a completed
checkpoint, not a new bootstrap claim: B4/L6 remains
`current_0k_bn_frontier` / `abort_resource` / `joined` /
`rejected_no_root_sized_consumer`. Per 0k-CI, the next source slice must not
select another behavior-neutral owner edge unless it decreases B4/L6 phase,
plausible owner-spine count, or live proxy-surface count.

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
