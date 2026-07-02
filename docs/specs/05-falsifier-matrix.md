# Crystal V2 Falsifier Matrix

> Status: Draft v0.1, 2026-05-08.
> Companion to: `docs/specs/*.md`, `TODO.md`, `LANDMARKS.md`.
> Format: each row maps a normative claim to the smallest known falsifier.

## 1. Status Legend

- `[FALSIFIABLE]`: guard exists or the falsifier command is explicit.
- `[FRONTIER]`: known boundary; not yet fixed.
- `[MISSING-FALSIFIER]`: claim is important but lacks a narrow guard.
- `[REFUTED]`: branch tried and recorded as not a valid fix.

Each non-refuted row has a phase pressure:

- `current`: must be resolved before claiming the active frontier fixed.
- `next-touch`: must be resolved when code in that contract family changes.
- `pre-s2-clean`: must be resolved before declaring `s1 -> s2b` clean.
- `later`: useful but not on the active bootstrap gate.

`[MISSING-FALSIFIER]` rows without phase pressure are invalid.

## 2. Bootstrap Corridor

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| B1 | Produced stage must be built through `scripts/run_safe.sh`. | `00-bootstrap-contract.md` section 4 | Review/CI command check; direct produced binary execution is protocol violation. | current | [FALSIFIABLE] |
| B2 | A moved frontier is acceptable only with a guard and a named residual boundary. | `00-bootstrap-contract.md` section 5 | Commit lacks guard or TODO/LANDMARK boundary for a claimed fix. | current | [FALSIFIABLE] |
| B3 | Original-vs-stage semantic oracle is required when a change touches language behavior. | `00-bootstrap-contract.md` section 3.1, Slice 0k-BM | `regression_tests/original_vs_stage_semantic_oracle_contract.sh <compiler>` compares original Crystal and stage output for explicit semantic lines (`TYPE=`, `CONST=`, `UNION=`). Slice 0k-BM made this strict-green for the H6-core TypeValue surface; rerun it whenever language-visible type identity changes. | current | [FALSIFIABLE] |
| B4 | Produced `s2b` must compile a full-prelude tiny source through LLVM entry without worker-only masking, RSS-kill, or post-`lower_main` crash. | Slice 0k-BN/0k-BO/0k-BP/0k-CK / `00-bootstrap-contract.md` section 4.2 | `scripts/generated_stage_llvm_entry_classifier.sh` builds/accepts stage1 and produced `s2b`, then compiles a full-prelude tiny source with default LLVM workers and `ADAMAS_LLVM_WORKERS=1`. `REQUIRE_CURRENT_FRONTIER=1` currently exits 0 with `classification=current_0k_bn_frontier`; `REQUIRE_CLEAN=1` is the future acceptance gate. Slice 0k-CK adds the direct workers=1 localization: `lldb` stops in `Set(UInt32)#includes?` called by `CopyPropagationPass#affected_blocks_use_only_local_replacements?` during `Function#optimize_with_potential`, with null registers at the Set load. This keeps B4 as the pressure gate but shifts the next admitted classifier to MIR optimization/container invariants, not worker/resource/output/tail or another GeneratedStageExecution owner edge. | current | [FRONTIER] |

## 3. HIR Name Resolution

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| H1 | Qualified nested names must not duplicate owner segments. | `01-hir-name-resolution.md` section 2 | `regression_tests/p2_qualified_module_namespace_no_prelude.sh <compiler>` finds `Float::Float::ParsedNumberStringT` or duplicated `Float::FastFloat`. | current | [FALSIFIABLE] |
| H2 | Self-reopen wrappers must not recursively register the current owner. | `01-hir-name-resolution.md` section 2.2, LM-553 | `regression_tests/p2_self_nested_module_registration_frontier.sh <compiler>`. | current | [FALSIFIABLE] |
| H3 | Nested builtin annotations must remain top-level unless structurally nested. | `01-hir-name-resolution.md` section 3, LM-554 | `regression_tests/p2_full_prelude_generic_template_namespace_no_pollution.sh <compiler>`. | current | [FALSIFIABLE] |
| H4 | Type-literal name queries lower to literal strings, not static stubs. | `01-hir-name-resolution.md` section 4, LM-558 | `regression_tests/p2_type_literal_name_query_no_stub.sh <compiler>`. | current | [FALSIFIABLE] |
| H5 | Function body presence must distinguish real bodies from stubs. | `01-hir-name-resolution.md` section 6 | `regression_tests/hir_function_body_presence_contract.sh` proves a registered bodyless HIR function is not `has_function_with_body?` and HIR->MIR preserves it as an empty unreachable stub, while real body evidence lowers as body. | current | [FALSIFIABLE] |
| H6 | Type-visible runtime values must share one HIR-owned `TypeValue` / `RuntimeTypeIdentity` fact for the H6-core surface. | `01-hir-name-resolution.md` section 4.1, B3 frontier | `regression_tests/type_value_core_runtime_identity_contract.sh <compiler>` compares original Crystal and stage output for direct/interpolated `typeof(1)`, direct/interpolated multi-arg `typeof(1, "x")`, direct/interpolated `1.class`, local and parenthesized nilable `.class`, and type-literal `.name` / `.to_s` / `inspect`; it deliberately excludes the parser-confounded no-parens command-call row. The wider historical guard remains `regression_tests/type_value_runtime_identity_contract.sh <compiler>`. | current | [FALSIFIABLE] |
| H7 | No-parens command calls must preserve a parenthesized member-access argument as the argument, not as member access on the command-call result. | 0k-BF / 0k-BG parser-frontier split | `regression_tests/command_call_member_access_preservation_contract.sh` asserts `puts (true ? 1 : nil).class` parses as a command call whose argument is `.class`; current parser is measured-red under `ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH=1`. | pre-s2-clean | [FRONTIER] |
| H8 | Runtime `.class` on a dynamic multi-variant union must report the concrete runtime class, not the static union display name. | `01-hir-name-resolution.md` section 4.1, Slice 0k-BM residual | `regression_tests/type_value_dynamic_union_class_residual.sh <compiler>` compares original Crystal and stage output for direct/interpolated `.class` on `ARGV`-dependent `Int32 | String`; current stage is measured-red under `ADAMAS_EXPECT_DYNAMIC_UNION_CLASS_MISMATCH=1`. | pre-s2-clean | [FRONTIER] |

## 4. Generic Template Registration

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| G1 | Generic/container fixes must not use arbitrary depth caps. | `02-generic-template-registration.md` section 2 | Add a deep nested tuple/hash/array/proc oracle before changing demand or registration pruning code. Static diff review alone is not enough. | next-touch | [MISSING-FALSIFIER] |
| G2 | Empty or repeated generic owner names such as `Iterator::` or `Indexable::Indexable::...` are invalid. | `02-generic-template-registration.md` section 3 | Add trace/IR guard that fails on empty owner suffixes or repeated adjacent owner segments in generated stage. | next-touch | [MISSING-FALSIFIER] |
| G3 | Generic template and instance keys must be semantic keys, not rendered strings. | `02-generic-template-registration.md` section 3 | `regression_tests/generic_identity_key_contract.sh` proves `GenericTemplateKey` and `GenericInstanceKey` equality/hash use owner, source `DefIdentity`, declared type params, specialization args, and lexical owner rather than display/rendered names. | pre-s2-clean | [FALSIFIABLE] |
| G4 | Broad source-gated generic-template body scan is not an acceptable fix. | `02-generic-template-registration.md` section 5 | Reverted experiment regressed earlier around `Crystal::PointerLinkedList` / trace paths. | current | [REFUTED] |
| G5 | Produced `s2` full-prelude `puts 42` must get past the later generic/template registration frontier. | `TODO.md`, LM-559 | `ADAMAS_TRACE_CLASS_FRONTIER=1 scripts/run_safe.sh <produced-s2> 60 4096 /tmp/hello.cr -o /tmp/hello_bin`. | pre-s2-clean | [FRONTIER] |
| G6 | The current owner-cache carrier must materialize `Hash(UInt64, BlockOwner)#[]=` as a real body, not an undefined-extern abort stub. | `TODO.md`, LM-ARCH-0K-AW, Slice 0k-CC/0k-CD/0k-CE/0k-CF | `regression_tests/block_owner_index_assign_materialization_repro.sh <compiler>` finds a non-stub self-IR body for the current `BlockOwner` carrier. Slice 0k-CF adds the stronger transaction guard: `scripts/block_owner_materialization_transaction_availability_report.sh <compiler>` must report at least one exact/all-equal BlockOwner setter `[MAT_TX]`, joined `[MAT_EMIT]` rows with `body_present=1`, at least one non-stub LLVM body, and zero setter stubs. Fresh `bin/adamas` evidence reports `tx_rows=1`, `joined_emit_rows=7`, `body_present_rows=7`, `real_defs=1`, and `stub_defs=0`. Green G6 remains non-bootstrap evidence: B4/L6 still gate `s2b`/`s3b`. | current | [FALSIFIABLE] |

## 5. MIR Call ABI

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| M1 | Exact static calls lower before receiver mutation. | `03-mir-call-abi.md` section 3 | `regression_tests/p2_stage2_static_call_named_llvm_no_prelude.sh <compiler>` emits fallback `@func1` or wrong arity. | current | [FALSIFIABLE] |
| M2 | Receiver calls include a runtime receiver; static calls do not. | `03-mir-call-abi.md` section 4 | Add MIR shape check for the static-call reducer: named callee, callee arity equals args, no synthetic receiver. | next-touch | [MISSING-FALSIFIER] |
| M3 | Null/missing HIR `TypeRef` is not an ordinary runtime object. | `03-mir-call-abi.md` section 6 | Add no-prelude MIR oracle covering a null `TypeRef` conversion path. | pre-s2-clean | [MISSING-FALSIFIER] |
| M4 | Debug value-location metadata is opt-in during bootstrap and not semantic. | `03-mir-call-abi.md` section 7 | Build with metadata disabled and verify semantic guards still pass. | current | [FALSIFIABLE] |

## 5a. MIR Optimization Invariants

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| O1 | Produced-stage MIR optimization must not read null or uninitialized compiler-runtime `Set`/`Hash` state while validating CopyPropagation local replacements. | Slice 0k-CK/0k-CL/0k-CM/0k-CN | `REQUIRE_CURRENT_CN=1 scripts/mir_timed_phase_source_seam_classifier.sh` emits a HIR dump and checks the post-0k-CM source seam. It currently reports `classification=current_0k_cn_hir_timed_phase_source_seam`: the collect block proc returns `Set(UInt32)`, but the HIR `timed_cp_phase$String_block` wrapper has `yield : Void` and the `apply_collect_affected_blocks` call/local are already `Nil|Void`. The next classifier must name the exact HIR producer (`block_return_name`, `yield_return_function_for_block_call?`, `record_block_return_type_for_call`, `infer_yield_return_type`, or registration-time `Void` fallback), or refute this boundary before any behavior patch. | current | [FRONTIER] |

## 6. LLVM Emission

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| L1 | LLVM backend must resolve MIR `FunctionId` to the named callee. | `04-llvm-emission.md` section 2, LM-559 | `regression_tests/p2_stage2_static_call_named_llvm_no_prelude.sh <compiler>` rejects `@func1`. | current | [FALSIFIABLE] |
| L2 | LLVM calls must not have empty return type spelling. | `04-llvm-emission.md` section 3, LM-559 | Same guard rejects `call  @`. | current | [FALSIFIABLE] |
| L3 | Emitted IR for the static-call reducer must pass `llc` when available. | `04-llvm-emission.md` section 6 | Same guard runs `llc -filetype=obj` if `llc` exists. | current | [FALSIFIABLE] |
| L4 | Hardcoded IO overrides should use generated accessors instead of unstable offsets. | `04-llvm-emission.md` section 4 | Add guard that changes/observes fd ivar layout and verifies IO overrides still emit correct fd load. | next-touch | [MISSING-FALSIFIER] |
| L5 | Generated-stage LLVM emission must have an explicit `LLVMEmissionSession` owner record and a convergence vector before behavior patches to worker policy, side-effect merge, tail stubs, output files, or resource acceptance. | Slice 0k-BQ/0k-BR/0k-BS/0k-BT/0k-BU/0k-BV/0k-BW | `REQUIRE_SESSION=1 REQUIRE_WORKER_PLAN=1 scripts/llvm_emission_session_source_shape_guard.sh` must report `source_shape=session_consumes_function_plan` and `worker_shape=session_consumes_worker_plan` for the consumed `function-list-inline` and `worker-policy-inline` edges. Slice 0k-BT adds a guardrail: a future side-effect, tail, output, or resource slice must prove a downstream consumer reads a vertical `LLVMEmissionSession` contract, not merely that the session gained fields/getters/tags. Slice 0k-BV made the side-effect source-shape extension executable. Slice 0k-BW makes `REQUIRE_SESSION=1 REQUIRE_WORKER_PLAN=1 REQUIRE_SIDE_EFFECT_CONTRACT=1 scripts/llvm_emission_session_source_shape_guard.sh` green with `side_effect_contract_shape=session_consumes_side_effect_merge_contract`, writer/merge contract calls `1/1`, and inline raw writer/merge counts `0/0`. That green source shape does not satisfy bootstrap completion: B4 remains `classification=current_0k_bn_frontier`, so the next movement must be a `GeneratedStageExecution` transaction checkpoint before tail-stub, output, resource, worker, or another local session-edge production slice. A production behavior change in side-effect merge, tail stubs, output files, or resource acceptance without that transaction/convergence ledger is a falsifier. | current | [FALSIFIABLE] |
| L6 | The next generated-stage LLVM-entry movement must be transaction-level and owner-spine aware, not another local session-edge, joined-row proxy, or report-only selector. | Slice 0k-BX/0k-BY/0k-BZ/0k-CA/0k-CB/0k-CC/0k-CF/0k-CG/0k-CH/0k-CI/0k-CJ/0k-CK | `scripts/generated_stage_execution_transaction_report.sh` must join invocation setup, function plan, worker/fallback policy, side-effect contract, tail declaration/stub inputs, output ownership, resource evidence, and B4 final classification under one transaction id for the same produced-compiler run. Slice 0k-CJ implements the selected output-row owner checkpoint and strict source guard, but the joined pressure gate still reports `b4.classification=current_0k_bn_frontier`, `join_status=joined`, `final_classification=abort_resource`, and `admission_status=rejected_no_root_sized_consumer`. Slice 0k-CK demotes another generated-stage owner-edge migration because direct workers=1 evidence points into MIR optimization / compiler-runtime Set state. Production behavior patches to workers, tail stubs, output semantics, resources, side effects, backend forwarders, memory budgets, `ADAMAS_LLVM_WORKERS=1`, `NamedTuple`/`Tuple` rendering, ambient maps, parser behavior, materialization behavior, physical extraction, or `BlockOwner` remain invalid from L6 alone. | current | [FALSIFIABLE] |

## 7. CLI Output

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| C1 | Emit-only success does not prove normal binary output success. | `06-cli-output-contract.md` section 2 | Same reducer passes `--emit llvm-ir --no-link` but normal `-o <bin>` exits 139. | current | [FALSIFIABLE] |
| C2 | Post-LLVM tail fixes must localize crash after LLVM finalization. | `06-cli-output-contract.md` section 4, LM-564 | `regression_tests/p2_stage2_cli_output_tail_no_prelude.sh <compiler>`; a future tail fix lacking the section 7 localization log is invalid evidence. | current | [FALSIFIABLE] |
| C3 | Binary-output fix must verify adjacent modes. | `06-cli-output-contract.md` section 5 | A commit claims binary-output fix with only `--emit llvm-ir --no-link` evidence. | current | [FALSIFIABLE] |

## 8. Refuted Branches

| ID | Branch | Evidence | Status |
|----|--------|----------|--------|
| R1 | Source-first generic type-param extraction as a broad fix. | Did not move the Float/ParsedNumberStringT frontier. | [REFUTED] |
| R2 | Caching `node.body` as a broad generic-template registration fix. | Did not move the frontier. | [REFUTED] |
| R3 | Source-gating generic-template nested-type body scan. | Failed earlier around `Crystal::PointerLinkedList` / trace paths. | [REFUTED] |
| R4 | Re-enabling source-backed top-level return annotations after LM-558. | Regressed produced `s2` full-prelude `puts 42` to earlier class registration crash around `class register idx=51/104`. | [REFUTED] |

## 9. Bootstrap Investigation Process

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| P1 | Trace absence is not enough to prove a function was not entered. | LM-565 | A tail/root claim relies only on a missing trace line when lldb, breakpoint, or IR control-flow evidence is practical. | current | [FALSIFIABLE] |
| P2 | Small helpers in self-host critical paths are semantic risk until s1->s2 proves otherwise. | LM-565 | A helper/refactor in compiler bootstrap code is committed with only host or no-prelude evidence after touching a produced-stage path. | current | [FALSIFIABLE] |
| P3 | Sidecar model output is candidate evidence, not acceptance evidence. | LM-565 | A fix adopts Cursor/Grok/Spark claims without local reproduction or a guard. | current | [FALSIFIABLE] |
| P4 | Bootstrap cache/IO/hash code is runtime surface, not harmless infrastructure. | LM-564, LM-565 | A cache or filesystem-tail change lacks a produced-stage guard covering the path that consumes the cache/hash result. | next-touch | [FALSIFIABLE] |
| P5 | A gate-local root fix must name deeper roots that remain open. | LM-564, LM-565 | LANDMARK/TODO wording claims a subsystem is fixed when the evidence only clears a current bootstrap gate. | current | [FALSIFIABLE] |
| P6 | A stashed or local WIP is not completion evidence after an architecture pause. | Slice 0k-BL | A future production slice resumes a WIP without a fresh measured-red baseline, owner-edge statement, producer/consumer map, and residual boundary. | current | [FALSIFIABLE] |
| P7 | A generated-stage classifier is architecture work only when it answers an owner-boundary question. | Slice 0k-BP/0k-BQ | A future B4 classifier extension only narrows a crash marker or offset and lacks a `PhaseAuthority` / `GeneratedStageExecution` owner question, producer/consumer map, old authority edge, and residual boundary. | current | [FALSIFIABLE] |
| P8 | A report-only slice after a report-only stop rule is architecture work only if it retires, refutes, or replaces a prior report surface with a code-owned authority edge plan. | Slice 0k-AP/0k-CG/0k-CH | A future slice adds another selector/report/counter for B4/L6 but does not retire/refute an older report surface and does not name a `GeneratedStageExecutionOutcome` owner fact/service plus one old authority edge and consumer migration target. | current | [FALSIFIABLE] |
| P9 | A phase-outcome owner implementation is valid only when a source consumer migrates to it under a guard while preserving the measured-red behavior boundary. | Slice 0k-CH/0k-CJ | `REQUIRE_OUTPUT_OUTCOME=1 scripts/generated_stage_outcome_source_shape_guard.sh` must report `source_shape=outcome_serializes_output_commit_rows` and zero direct output rows outside outcome helpers. A future commit that changes `GeneratedStageExecutionOutcome`, output row names/values, or the CLI output corridor must keep this guard green and must not change B4/L6 behavior without an admitted behavior slice. | current | [FALSIFIABLE] |
| P10 | Behavior-neutral owner migrations are architecture progress only when they decrease `BootstrapPotential`, not merely a local source-shape/proxy metric. | Slice 0k-CI | A future source slice after the current 0k-CH candidate does not state `BootstrapPotential = (B4/L6 phase, plausible owner-spine count, live proxy-surface count, unmigrated authority-edge count)` before edits, or it only decreases `unmigrated authority-edge count` while B4/L6, owner-spine ambiguity, and live proxy surfaces stay unchanged, then selects another behavior-neutral edge instead of SDD redesign, owner-spine refutation, direct root localization, or an explicit `bootstrap-emergency-with-ledger` behavior slice. | current | [FALSIFIABLE] |
| P11 | A B4 root-localization slice may redirect the active owner spine only when it names a direct runtime stack and the next discriminating classifier, not when it merely narrows a marker or crash offset. | Slice 0k-CK | A future slice uses the `Set(UInt32)#includes?` / `CopyPropagationPass` stack to patch `CopyPropagation`, backend Set/Hash delegates, LLVM workers/resources/output/tail, or broad namespace/container rendering without first classifying the bad Set/Hash producer versus malformed optimization state. | current | [FALSIFIABLE] |
