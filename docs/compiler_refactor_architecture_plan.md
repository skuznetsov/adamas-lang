# Crystal V2 Compiler Refactor Architecture Plan

> Status: runner and bounded MIR repairs implemented; matched combined baseline 33/37; B4-F open (2026-09-04).
> Section 0 integrates the current reliability and architecture work. Its
> implementation steps are not completed by this document. Sections 1-9 retain
> the original staged refactor design (2026-04) as a deferred reference;
> their Phases 0-5 are not the current execution queue.
> Surface admission remains in `docs/compiler_architecture_sdd.md` and
> `docs/specs/07-compiler-decomposition-and-semantic-replacement.md`.
> The 2026-07-01..03 dated note stack (149 entries) that previously occupied
> this file was process work-log, not plan content; it is preserved in git
> history: `git show 95539f64:docs/compiler_refactor_architecture_plan.md`.
> Rationale for the eviction: `docs/sdd_process_review_2026_07_03.md`.

## 0. Current execution plan

### 0.1 Objective and evidence boundary

Deliver compatible compilation through the complete fresh bootstrap ladder,
with trustworthy runtime checks and bounded time/memory. Reduce the cost of
getting there by preserving decisions at their actual consumer boundaries.
File size, queue size, record count, and local speed are explanatory metrics,
not acceptance criteria by themselves.

The review inspected `930bdc59` plus existing uncommitted changes in
`src/compiler/hir/ast_to_hir.cr` and `spec/hir/ast_to_hir_spec.cr`; those changes
are not owned by this plan. No new full bootstrap was run for the review.
The September 3-4 measurements below are recorded in `TODO.md`, not refreshed
performance certificates. Old R0 snapshots and temporary artifact paths in
the SDDs remain historical evidence, not certificates for this checkout.

| Observation | What it supports | What it does not support |
|---|---|---|
| Exact registration invalidation removed 579 wrong zero-argument `Object#hash$Crystal::Hasher` calls; printed bodies stayed essentially flat. | Provisional arity facts can outlive their authority. | All demand amplification has this cause. |
| Constructor admission reduced first-wave bodies 5,196 -> 1,137 and time about 29s -> 0.79s; full HIR changed only 246.5s -> 245.3s. | Later scans can undo an admission improvement. | Rejecting the constructor rule itself, or certifying global speed from its local result. |
| Concrete inequality-wrapper ownership reduced Object equality replay keys 22,958 -> 8,770 in one adjacent sample. | Some fanout is caused by loss of a concrete receiver. | A general inherited-method cloning rule or stable timing gain. |
| Single-active-unit semantic analysis already hands exact selected definitions to HIR under `ADAMAS_SEMANTIC_COMPILE`. | There is a reusable, bounded production consumer. | Multi-arena, macro-generated-node, generic-receiver, or default bootstrap coverage. |
| Missing-scan specs already cover exact revisions, raw demand versus availability, and mutation during a scan. | Reuse the existing diagnostic machinery. | Production incremental reuse or a complete invalidation proof. |

Fresh review probes found that **both regression runners can report PASS for
exit 7**. `local output=$(scripts/run_safe.sh ...)` masks the command status;
the marker branch also tests output before failure. In isolated temporary
fixtures using the actual runners and safe supervisor, `run_all.sh` accepted
marker+exit7 and unmarked+exit7; `run_combined.sh` additionally accepted
golden-output+exit7. Exit-zero positives, output mismatches, compile failures,
and missing binaries supplied controls. Therefore the recorded combined
27/37 pass count must be re-established after the runner repair. Known failing
fixtures remain failures; additional failures may be revealed.
Step 1 is now implemented: the [runner contract spec](../spec/regression_runner_contract_spec.cr)
covers 21 individual cases and all four aggregate success/failure combinations.
The safe spec runner passes 6 examples; the original 17-case manual witness
changed from five false PASS results to zero and was retired into these specs.
Step 2 now gives every run a fresh output directory, passes explicit `-o`,
requires a newly produced executable, and supervises each compile with defaults
of 120 seconds / 4096 MB. `REGRESSION_COMPILE_TIMEOUT` and
`REGRESSION_COMPILE_MAX_MEM` override those budgets. The 14-example runner
contract suite covers stale source-adjacent and legacy-bin sentinels, failed
partial output, non-executable output, compiler timeout plus child cleanup,
and default cleanup / optional raw-log retention. Existing runtime budgets
remain 10/15 seconds and 512 MB. Use one explicit job and
`REGRESSION_KEEP_LOGS=1` for real-program baselines; retained
logs contain per-test compile/runtime exit codes and supervisor output.
Per-test artifact directories are removed on completed success and failure
paths even when logs are retained, including compiler-generated siblings such
as LLVM IR. A focused old-runner/new-spec ablation fails both retention cases;
the repaired runners pass both, and the full contract suite passes 14 examples.

The fresh combined baseline is complete: candidate `d58cd268` and a same-source
control with only the pre-repair optimizer both produced 33/37 PASS. All paired
verdicts, exit codes and program output matched. Two fixtures share one bodyless
Tuple target error, one segfaults, and one deliberately exercises a second
`String::Builder#to_s` without a dedicated expected-termination oracle. These
remain non-PASS results; see the current `TODO.md` table. The old 27/37 number
has been superseded for this checkout, without attributing its difference to
the MIR repair. The fresh canonical stage2 gate timed out and remains open.

### 0.2 Causal model and alternatives

The strongest common mechanism is **a decision survives in a weaker form than
the evidence that established it**: a concrete receiver becomes `Object`, an
exact definition retains provisional arity, or a later phase reconstructs a
choice from its rendered symbol. The repair should preserve the earliest
correct fact through one real consumer, then remove the superseded guess.
This is supported for particular defects, not proven as one universal cause.

Three hypotheses compete at the remaining lowering frontier:

1. **Wrong demand:** valid callers lose owner/argument facts and request an
   unnecessarily broad target family. Trace one surviving Object equality
   shape from caller and selected definition through emitted/replayed target;
   a concrete-to-broad transition is the discriminator.
2. **Wrong admission:** correct calls in unadmitted callers create new demand.
   Compare the requesting caller with the existing reachability/dispatch
   authority, including later liveness changes. A currently dead caller is
   not proof that its demand can be discarded forever.
3. **Expensive correct closure:** admitted, correctly typed requests are
   repeatedly scanned or resolved. Measure scan, resolution, materialization,
   and already-present-body request costs separately. Counts without cost do
   not select this hypothesis.

If declaration identity stays stable but arity, return type, or coercion
changes, follow the first registration/type-state mutation before blaming the
scheduler. Stable identity alone does not establish a correct call contract.

Start with the five remaining Object equality target shapes named by the
current TODO and the existing binary lowering trace/analyzer. Select the first
incorrect transition with material measured cost. If identities and admission
are correct, pivot to reuse of scan work. Do not invent another registry to
avoid deciding between these hypotheses.

There are separate obligations that this causal model does not discharge:

| Boundary | Fact to preserve | Existing consumer / expiry |
|---|---|---|
| Resolution -> emitted call/body | Preserve selected `DefIdentity`, receiver/argument shape, and arena ownership. | Existing same-arena lookup and normal-emission guards check the selected Def; `SelectedCallTarget` itself carries only DefNode + symbol. Complete typed shape/expiry propagation remains proposed. |
| Caller -> missing-demand processing | Raw demand, caller admission, target availability, and relevant revisions. | `lower_missing_call_targets`; body/queue/type/state changes may require re-evaluation even with unchanged caller text. |
| MIR -> LLVM storage | Representation, size/stride/alignment, access semantics in a named storage context. | Field and container emission; layout or storage-context changes invalidate the fact. |
| Optimizer -> emitted MIR / diagnostics | Actual accepted IR and freshly computed potential under the applicable effect model. | Serial and worker codegen; every mutation invalidates the previous measurement. |
| Test process -> verdict | Exit status, output, and fresh executable provenance. | Both regression runners and their aggregate; runner or compiler changes invalidate the baseline. |

These contracts share a discipline, not a universal new `Fact` framework.
Session-local IDs are not persistent cache keys. LSP per-file caching does not
establish compiler semantic-cache validity. Field storage and Array/Slice
element storage must remain distinct even when the type name is identical.

### 0.3 Order of work and promotion policy

**First restore trustworthy observations; then repair the next demonstrated
boundary; use that repair to reduce duplicate authority.** Run at most one
bootstrap-affecting implementation stream against a source snapshot. An
independent MIR/runner investigation may proceed alongside it.

Before a compiler edit that overlaps the dirty HIR paths, create a disposable
worktree/source snapshot including the intended working-tree base and preserve
the user's patch separately. Candidate and control must derive from that same
base. Stage only the candidate's own delta; rollback must never discard the
pre-existing patch. Planning changes do not authorize committing that patch.

The reliability/architecture join has two distinct scopes:

- A targeted correctness repair in the existing compile path may proceed
  while B4-F is red. It needs a failing reducer, the owning producer and
  consumer, a nearest adversary control, affected tests, and a source-matched
  bootstrap classification when it changes that corridor. Any extracted
  helper must be consumed by that same repair. This cannot authorize a new
  semantic pipeline, weakened liveness, or a broad fallback.
- Promotion of a replacement semantic path, removal of a legacy queue/shim,
  and bootstrap readiness still require the same-source B4-F <=300s result
  and both exact semantic smokes, plus the slice's own equivalence gates.
  A local correction or diagnostic timing improvement is not that promotion.

This makes the existing emergency-fix lane explicit; it does not require a
broken bootstrap to pass before its cause can be fixed. Do not repeat the old
T0 A/B for unrelated runner or MIR repairs. Reconcile that A/B if a candidate
actually depends on T0 provenance or changes its authority.

| Step | Smallest deliverable and exact surface | Falsifier / acceptance | Risk and rollback |
|---|---|---|---|
| 1. Repair verdict propagation | `regression_tests/run_all.sh`, `run_combined.sh`; add `spec/regression_runner_contract_spec.cr` with fake compilers in temporary directories. Separate declaration from command assignment, capture status immediately, require successful execution before marker/golden matching. | Exit7 with matching marker, without marker, and with matching golden output must fail; exit0 positives pass. Compile failure, missing binary, signal/timeout, and aggregate failure propagation are controls. No compiler bootstrap is needed. | SAFE; one runner/test commit, independently reversible. |
| 2. Re-establish a bounded baseline | Both runners and `regression_tests/run_all_suites.sh`: supervise compiler invocations as well as produced tests, with explicit compile budgets; use one job for the baseline and fresh per-run outputs. | Hanging compiler is stopped; compile-success-without-output cannot reuse a stale executable. Re-run old/new compiler fixtures with raw exit/output, classify each failure by stage and boundary. Do not grandfather ten failures as an acceptable release baseline. | CAUTION for process supervision; preserve runtime budgets, test kill/cleanup paths, revert this slice alone. |
| 3. Repair one measured lowering edge | `src/compiler/hir/ast_to_hir.cr`, existing HIR specs, and one source-backed regression. Use `lowering_binary_trace.cr` / `scripts/analyze_lowering_trace.cr` to choose among section 0.2 hypotheses. | A reducer must reproduce the first owner/arity/admission loss; original Crystal and a genuine Object/base/union or late-live control separate legal dispatch from the bug. Verify the emitted target/body and rerun the affected HIR suite. Then classify a matched fresh bootstrap. | CAUTION; no speculative wrapper widening, global attempted-set, or demand cap; one fix/test commit, preserving the user's dirty work. |
| 4. Make scan reuse earn its complexity | Only if measured correct rescanning dominates: extend existing `missing_incremental_*` helpers and `spec/hir/missing_incremental_shadow_spec.cr`, `missing_revision_ledger_spec.cr`. | Preserve raw demands across temporary body/in-progress availability; reject reuse after same-scan mutation and late queue/type/state changes. Compare order and selected batch as well as set membership. A mismatch retains the authoritative full scan. | CAUTION; shadow first, explicit fallback; no production switch from bounded parity alone. |
| 5. Preserve one semantic decision end to end | Extend the existing same-arena selected-definition consumer only when a classified defect requires it; use `semantic_cli_spec.cr`, `semantic_cli_compile_contracts_spec.cr`, and identity specs. | Selected Def, coerced values, materialized body, emitted target, and runtime agree. Include equal numeric ExprIds in foreign arenas, alias/overload distinctions, and a multi-active-unit control. Keep unsupported shapes explicit. | CAUTION; reuse existing identity types and opt-in boundary; default replacement remains subject to the full promotion gate. |

Steps 3-5 are conditional, not three mandatory abstraction layers. If the next
failure is an earlier semantic error, fix it before optimizing its downstream
work. If the first proposed repair has no discriminating RED case, return to
the competing hypotheses rather than constructing infrastructure around it.

### 0.4 Bounded companion work

**MIR optimization acceptance.** Audit `src/compiler/mir/optimizations.cr`
with `spec/compiler/mir/ltp_wba_spec.cr`. A fresh reducer demonstrated a
rejected dual-frame constant fold that remains in MIR: two constants, an add,
an allocation, and two stores keep the operands live; the add becomes a
constant while initial/final potential and the only trace entry all remain
`{I=0, -M=0, P=2, |Delta|=6}`. This is a demonstrated acceptance/accounting
defect, not a demonstrated miscompile or incorrect numeric result. The current
Spike/Diamond constructors remove an RC pair, strictly reducing the first
potential component; their non-decrease branch is not the demonstrated route.
The witness is now a regression in
[`ltp_wba_spec.cr`](../spec/compiler/mir/ltp_wba_spec.cr). Its original RED
result was a one-entry trace despite changed MIR at unchanged potential.

The bounded CF repair is implemented. A non-increasing constant fold is
explicitly ordinary normalization, with a freshly recomputed baseline recorded
by the caller; it is not added to certified `moves_applied`. A fold that raises
the selected-frame potential restores the instruction arrays and analysis
maps. The snapshot covers this pass's actual mutation surface, not generic
object state. Direct Spike/Diamond and curvature paths remain unchanged.
The witness and an adversary CF-then-later-DCE case both pass, and both compare
reported potential with a fresh computation over retained MIR. The LTP and
ordinary optimization suites pass 29 + 46 examples. Serial and worker paths
share `Function#optimize_with_potential`; this source check is not a fresh
worker-runtime or bootstrap certificate. Miscompilation and full LTP/WBA
proof closure have not been demonstrated by this accounting repair.

**ABI facts.** Extend the existing A' inline-Array producer/consumer before
proposing another registry. `populate_inline_value_array_storage_facts` in
`hir_to_mir.cr` already writes eligibility and per-site stride facts; LLVM
consumes them under `ADAMAS_INLINE_VALUE_ARRAY_STORAGE`. The CLI explicitly
populates them after MIR optimization and disables subsequent worker
optimization that would clone instructions and lose those facts. Preserve
this lifetime boundary when extending the path; gate-on observations do not
establish default bootstrap coverage.

Use `spec/mir/abi_layout_spec.cr`, `spec/mir/llvm_backend_spec.cr`, and a runtime
fixture with the same >8-byte plain user struct in a field and Array/Slice.
Check eligible payload loads/stores, stride and bulk copy, absent/ineligible
facts retaining the legacy path, and post-optimization fact survival in serial
and worker emission. A field being inline does not imply inline container
storage. Admit unions/tuples only where the selected seam supports them.
Keep `LayoutContract` narrow; broader AbiFacts migration and the streaming
writer remain later. No unused ABI registry is an intermediate milestone.

**Deferred until a real consumer requires them:** physical file splitting,
compiler-wide incremental caching, a backend rewrite, generalized runtime
allocation redesign, and bulk migration of semantic ownership. The runtime
`Slab` malloc/free placeholder is a separate performance opportunity. The
non-atomic helper bodies in `runtime/arc.cr` do not prove generated AtomicARC
unsafe: the LLVM backend emits separate atomic operations on its Darwin path.
Any concurrency audit must follow the actual generated consumer and platform.

### 0.5 Executable checkpoints and stop conditions

Refresh the affected consumer inventory before editing. The review's bounded
search `rg -n 'run_safe.sh|exit_code|run_all.sh|run_combined.sh' regression_tests/run_all.sh regression_tests/run_combined.sh regression_tests/run_all_suites.sh`
identified both verdict producers and their aggregate consumer. For semantic
work, `rg -n 'bind_semantic_call_targets|semantic_call_target|if semantic_target' src/compiler/cli.cr src/compiler/hir/ast_to_hir.cr`
locates the CLI handoff, lookup, and final normal-emission check. These are
routing anchors, not proofs of complete semantic or runtime coverage.

Both manual review witnesses have been promoted into normal specs and removed
from `scripts/probes`; their original RED behavior and limited claim scopes
remain recorded above and in git history.

Use the existing safe spec runner; run only the checks affected by the slice:

```bash
scripts/run_all_specs.sh 1 180 4096 spec/regression_runner_contract_spec.cr
scripts/run_all_specs.sh 1 300 8192 spec/hir/ast_to_hir_spec.cr
scripts/run_all_specs.sh 1 180 4096 spec/hir/missing_incremental_shadow_spec.cr spec/hir/missing_revision_ledger_spec.cr
scripts/run_all_specs.sh 1 120 4096 spec/compiler/mir/ltp_wba_spec.cr spec/mir/optimizations_spec.cr
scripts/run_all_specs.sh 1 300 8192 spec/mir/llvm_backend_spec.cr
scripts/run_all_specs.sh 1 300 8192 spec/semantic_cli_spec.cr spec/semantic_cli_compile_contracts_spec.cr spec/semantic/identity_spec.cr
```

Run only the checks relevant to the chosen change. Host/unit green is a local
certificate. For a bootstrap-affecting repair, use a reconciled source
snapshot and an absent output path; clear disallowed experimental environment
settings rather than changing the canonical producer's policy:

```bash
probe_parent=$(mktemp -d /private/tmp/adamas-plan-gate.XXXXXX)
scripts/build_bootstrap_stages.sh --out "$probe_parent/run" --stages 2 --timeout 300 --mem 12288
scripts/validate_bootstrap_manifest.sh --run-dir "$probe_parent/run" --expected-host "$(command -v crystal)"
```

The producer owns fresh cache creation and stage supervision. Success requires
an actual stage2, both exact smoke modes, the <=300s policy, and accepted
source/resource evidence. A timeout or invalid receipt remains an explicit
classification, not a reason to relabel an emit-only result as bootstrap.
After B4-F, refresh B5 from the new stage2 and continue the fresh ladder through
stages 3-5; historical `CLI#run` stops are locators, not current failure claims.
Retain only the compact useful evidence before cleaning owned probe outputs.

Stop or pivot when semantics diverge, demand disappears only through an
unproved admission restriction, reuse misses a late-live target, or a local
improvement leaves the measured global cost unchanged. Keep the useful local
result but reopen its global explanation. For speed claims, compare the same
source/host/cache/worker policy with adjacent counter-order samples; report
time, RSS, actual output and demand together, without forcing a single score.

### 0.6 Decision maintenance

Maintain this section in place as the execution order; keep run results in
`TODO.md` and git, and contracts in the SDD. Preserve a refutation with the
assumption and falsifier that defeated it: constructor admission can be locally
correct despite a refuted global-speed explanation, and raw-demand reuse can
remain useful despite a refuted target-availability shortcut.

The review used opposed Luna Max analyses and local source/probe checks.
Agreement between agents is corroboration, not independent verification.
Grok produced no review signal because session creation returned permission
denied. Do not add another certificate, owner record, or recurring review unless
it changes the next action, a correctness boundary, recovery, or continuity.

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

The 2026-07 bootstrap objective does not start here; semantic ownership
boundaries are sealed first through the SDD. The writer slice remains a
later backend-local candidate.

## 9. Decision Summary

Recommended direction:

- Use MIR as the compact durable IR.
- Use typed per-function streaming for `.ll` emission.
- Extract HIR services by behavior boundary, not by line count.
- Keep the demand-driven semantic rewrite as the strategic long-term track.
- Do not start the bootstrap effort with the LLVM writer. That remains a later
  backend-local refactor candidate after semantic ownership boundaries are
  sealed.

This plan should be revisited after the architecture SDD seals the active
semantic-owner frontiers enough that backend-local refactoring cannot hide a
state-scope, materialization, arena, or ABI owner bug.
