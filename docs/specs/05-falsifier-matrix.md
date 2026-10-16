# Crystal V2 Falsifier Matrix

> Status: Rev 2026-07-03 (pruned per docs/sdd_process_review_2026_07_03.md).
> Companion to: `docs/specs/*.md`, `TODO.md`, `LANDMARKS.md`.
> Format: each row maps a normative claim to the smallest known falsifier.
> Cell changelogs were removed in this revision; history lives in git
> (`git log -p -- docs/specs/05-falsifier-matrix.md`). Rows deleted in this
> revision (stale frontier pins and process-paperwork rows) are recoverable
> the same way.

## 1. Status Legend

- `[FALSIFIABLE]`: guard exists or the falsifier command is explicit.
- `[FRONTIER]`: known boundary; not yet fixed.
- `[MISSING-FALSIFIER]`: claim is important but lacks a narrow scripted guard.
- `[REFUTED]`: branch tried and recorded as not a valid fix.
- `[HISTORICAL]`: evidence is scoped to an old generated artifact and cannot
  satisfy a fresh-source readiness gate.

Historical rows are context only; they do not satisfy a `current` or
`pre-s2-clean` phase pressure.

Each non-refuted row has a phase pressure:

- `current`: must be resolved before claiming the active frontier fixed.
- `next-touch`: must be resolved when code in that contract family changes.
- `pre-s2-clean`: must be resolved before declaring `s1 -> s2b` clean.
- `later`: useful but not on the active bootstrap gate.

`[MISSING-FALSIFIER]` rows without phase pressure are invalid.

## 2. Bootstrap Corridor

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| B-GENERIC-DECLARATION-KIND | Concrete declarations promote cached Generic placeholders to Class/Struct while retaining TypeRef identity and parameters | ast_to_hir.cr register_concrete_class; hir.cr stable-ID interning | concrete_generic_placeholder_kind_spec.cr; concrete_generic_placeholder_kind_repro.sh | current | [FALSIFIABLE] Atomic255 passes 3 cases; the baseline fails the Class/Struct kind assertions. Unknown owners stay Generic. Uncached manual placeholders and full LavinMQ parity remain open. |
| B-BLOCK-PROC-ABI | Omitted source bindings preserve expected callback inputs; allocators propagate the selected initializer's Nil result before materialization and retain incompatible-signature rejection | ast_to_hir.cr raw_callback_param_types_for, block_param_types_for_call, lower_block_to_proc and captured initializer refinement | block_proc_expected_arity_spec.cr; block_proc_expected_arity_repro.sh COMPILER | current | [FALSIFIABLE] Arity245 passes 27 HIR cases plus original-first native ignored/trailing-input and Float64/String-discard controls. Previous full240 fails actual-Nil and incompatible-signature guards. Named/splat constructor routing, Void erasure, mixed raw/retained yield and MT/LavinMQ parity remain open. |
| B-EXPLICIT-RETURN-CACHE | Late simple lexical return annotations publish corrected types only to caches owned by the exact annotated Def, without transporting contextual generic bindings | ast_to_hir.cr resolve_return_type_from_def | explicit_return_cache_refresh_spec.cr; explicit_return_cache_refresh_repro.sh | current | [FALSIFIABLE] Atomic239 passes 3 direct cases and 25 annotation/overload neighbors; the baseline retains a stale nested-type placeholder, and the unguarded refresh corrupts a competing generic cache. Native nested-owner control matches Crystal's 42. Compound annotations, MT startup and LavinMQ parity remain open. |
| B-TUPLE-UNION-EACH | Runtime tuple tag precedes concrete macro expansion; returns stop parsed expression sequences | ast_to_hir.cr inline_union_tuple_each / lower_parsed_macro_body / inline_yield_function | tuple_union_iteration_repro.sh CANDIDATE BASELINE; macro_sequence_return_repro.sh CANDIDATE BASELINE (NP) | current | [FALSIFIABLE] Baseline ASan READ4 and NP91 become original-matched normal/ASan passes. next/break/conditional/unconditional return and separate-return empty tuples pass. Ternary empty-tuple producer tags, custom scalar overrides and nested macro BlockNode termination remain outside scope. Fresh S2 builds 431s/smokes; S3 exposes separate union slot READ16. |
| B-MODULE-CLASSVAR-STORAGE | Module class variables retain their declared MIR global storage | ast_to_hir.cr module_class_vars; cli.cr global registration | module_classvar_storage_repro.sh CANDIDATE BASELINE with external CRYSTAL_PATH and LLVM CLANG; getter-only module/class plus cached setter guards | current | [FALSIFIABLE] Baseline ASan READ12 becomes four passing normal/ASan controls. Fresh S2 builds in 422s and NP smoke passes. S3 ASan passes LayoutProbe and exposes a separate Path tuple READ4; S3 remains open. Setter fixture alone is not a baseline discriminator. |
| B-MIXED-RETURN-OWNERSHIP | Unconditional caller cleanup requires every return origin to be owned | hir_to_mir.cr build_owned_return_set / returns_owned_value? | owned_return_provenance_repro.sh; mixed Phi parameter, separate borrowed return, Copy/Cast parameter and unknown call; direct/transitive/all-owned controls | current | [FALSIFIABLE] Four predecessor failures become eight passing focused examples; 49 adjacent MIR examples pass. Fresh S2 ASan passes the MacroValue access and reaches a separate LayoutProbe global-width error. Full S3 and bounded retention remain open. |
| Nested callback result ownership | Callee body/formals/locals and selected declaration namespace determine yielded types; unknown static arguments do not pick a sibling overload | `src/compiler/hir/ast_to_hir.cr` | `spec/hir/nested_yield_callsite_inference_spec.cr`; `regression_tests/nested_yield_callsite_return_repro.sh COMPILER` (`--no-prelude`, inline/raw); old host aborts on `Pointer#name`, successor emits both expected values | current | [FALSIFIABLE] 574 HIR examples and inline/raw runtime values pass; nested positional/named specializations retain String. External S2 reaches Hash layout guard; recursive fixed-point discovery, raw captured scalar mutation and S3 remain open |
| B-PAREN-TERNARY-DECL | Ternary declaration rejection must not erase ordinary nested declarations | parser.cr ternary branch depth and parenthesized argument guard | parser_parenthesized_declaration_arg_spec.cr; parser_ternary_spec.cr; parser_postfix_modifier_spec.cr | current | [FALSIFIABLE] Both branches reject; adjacent named arguments, nested declarations and depth restoration pass. Shared no_type_declaration guard is refuted. Ternary context survives interpolation; invalid initial/adjacent literals terminate before merging. Parser suites: 52 + 42 examples; NP macro runtime guard passes |
| B-PAREN-DECL-ARG | Arbitrary parenthesized calls retain spaced-colon positional declarations | parser.cr parse_parenthesized_call_body | parser_parenthesized_declaration_arg_spec.cr; parenthesized_macro_declaration_repro.sh NP | current | [FALSIFIABLE] Exact predecessor aborts134; parser-only successor passes imported macro, bare and yielded-constructor controls plus40 parser examples. External thread_local expands correctly and File.tempname compiles; Time::Location.local runtime stub remains separate |
| B-LATE-NESTED-RETURN-NAMESPACE | Late nested return annotations retain declaration owner across class registration | ast_to_hir.cr normalize_declared_type_name, annotation_type_ref, resolve_return_type_from_def | nested_module_relative_nullable_annotation_spec.cr; late_nested_return_namespace_repro.sh; file_info_declared_return_namespace_repro.sh | current | [FALSIFIABLE] Cache predecessor retains Other::Info after File::Info registration; final cache test passes. NP bare nullable return exits1 before repair and0 after; relative/absolute and Nil controls pass. External Dir/File.info runtime abort134 becomes0. 576 HIR examples pass with2 pending. Registration-only typed signature remains stale; no broad cache closure. The namespace-repaired S2 builds in418s and compiles/runs the NP exit0 smoke. S3 reaches lower_main but segfaults139 after35s; bootstrap closure remains open. |
| B-HASH-LITERAL-LAYOUT | Hash literal allocation uses registered MIR geometry and GC prefix | llvm_backend.cr __adamas_hash_new and emit_extern_call | hash_literal_allocation_spec.cr; hash_literal_allocation_repro.sh in UInt8/Int8 NP and external --stdlib modes | current | [FALSIFIABLE] Exact predecessor ASan READ12 exceeds48-byte body; backend-only successor passes wide/relocated NP and external dup/mutation runtime guards. Invalid field layouts reject. Qualified ::Hash is admitted by exact root prefix; namespace lookalikes, value kinds and invalid geometry reject. 12 backend examples, two NP orders and allocation ASan pass. S2 build exits0 after415s; S2 NP compile and S3 attempt abort134 in DWARF::Info#type |
| B-MACRO-NIL-DEFAULT | nil? preserves absent/default receiver identity; explicit nil retains its spelling | macro_value.cr; macro_expander.cr evaluate_member_access_expression | macro_nil_predicate_spec.cr; external_record_nil_predicate_repro.sh with external CRYSTAL_PATH and --no-prelude | current | [FALSIFIABLE] Exact HEAD host aborts134 at mandatory record getter; two-file successor passes absent/numeric/false/nil defaults and40 macro examples. Bootstrap propagation remains separate |
| B-NULLABLE-PROC-FIELD | Early canonical/arrow Proc arms reserve tagged field storage; nested Proc arguments do not change reference storage | ast_to_hir.cr hir_union_ivar_storage_size | nullable_proc_field_layout_spec.cr; nullable_proc_field_layout_repro.sh (Hash + ASan); matched S2/S3 | current | [FALSIFIABLE] Exact predecessor fails the Hash ASan guard; candidate host passes both tuple-key spellings and String control plus106 HIR/ABI/backend examples. Matched S2 builds334s and passes both NP tuple controls; ordinary allocation is corrected. S3 ASan finds a distinct Hash literal allocation read; produced full-prelude guard is blocked and S3 remains unbuilt |
| B-TUPLE-STRUCT-CARRIER | Non-lib user struct tuple elements preserve pointer slots at every width; ordinary parent fields remain inline | hir_to_mir.cr lower_field_get and field_store_uses_inline_memcopy?; LayoutContract.tuple_slot_layout | tuple_struct_carrier_coercion_repro.sh in both small-inline modes; nullable tuple guards; produced parse_def_receiver IR and S3 | current | [FALSIFIABLE] Baseline exits 13; isolated HEAD repair passes wide/Nil/repeat/inline-parent controls and 99 ABI/backend examples. Matched S2 builds and passes both modes plus three nullable forms; ASan on actual S3 passes the former tuple read and finds a distinct Hash allocation/field-size mismatch. S3 remains unbuilt; lib-struct tuple policy and pre-existing SmallId ternary failure remain outside scope |
| B-NULLABLE-TUPLE-DESTRUCTURE | Multiple assignment preserves positional types from a nullable concrete Tuple across captured-block spills | ast_to_hir.cr lower_multiple_assign | spec/hir/multiple_assign_nullable_tuple_spec.cr; nullable_tuple_destructure_capture_repro.sh on host; fresh produced empty initializer and ptr spill inspection | next-touch | [FALSIFIABLE] Host runtime 139 -> 0, HIR guards and produced empty initializer pass; produced captured reducer, explicit override value, and full-prelude remain open |
| B-GROUPED-NULLABLE | Grouped nullable unions have one tag and the same TypeRef as flat spelling; generic/Proc boundaries survive | ast_to_hir.cr normalize_union_type_name | spec/hir/grouped_union_type_spec.cr; regression_tests/grouped_nullable_union.sh (host and produced); nested_accessor_defaults.sh (produced literal cases) | next-touch | [FALSIFIABLE] Six host and produced runtimes plus identity/boundary guards pass |
| B-PHI-PRESCAN | Indexed Phi pre-scan preserves cross-block ARC protection and produces no bare getter stub | hir_to_mir.cr cross-block pre-scan | spec/mir/phi_cross_block_prescan_spec.cr (Phi inputs retained, unused managed call decremented); fresh stage2 IR and grouped_nullable_union.sh | next-touch | [FALSIFIABLE] Ownership control and six produced runtimes pass; bare getter references 3 -> 0; no general pending-demand closure |
| B-YIELD-TYPE-MERGE-INDEXED | Yield type merging preserves nil/empty/arity identity, VOID slots, union order and input arrays without zip temporaries | ast_to_hir.cr merge_yield_param_types | spec/hir/merge_yield_param_types_spec.cr; fresh canonical plain smoke and LLDB successor localization | next-touch | [FALSIFIABLE] Two host examples pass; combined produced stage2 advances past null-buffer load to later substitution/Hash stack-boundary fault; general zip and bootstrap remain open |
| B-RAW-YIELD-CALLBACK-ABI | Raw yield respects compatible known Proc argument ABIs without partial conversion | hir_to_mir.cr lower_yield and callback signature lookup | raw_yield_union_callback_abi_spec.cr; raw_yield_union_callback_abi_repro.sh, including optional UNTYPED_CALLBACK=1 actual-union probe | next-touch | [FALSIFIABLE] Ten MIR guards and two typed host runtimes pass; untyped host probe remains 81 (original Crystal 0), produced Path callback still loses tag |
| B-SHORT-CIRCUIT-LOCAL-JOIN | A skipped logical RHS cannot export its narrowed local; executed assignments reach the join | ast_to_hir.cr short-circuit value lowering | short_circuit_nullable_local_repro.sh (14 runtime guards); fresh allocator constructor reducers | next-touch | [FALSIFIABLE] Baseline runtime 71; restored local snapshot passes 14 host and original-Crystal guards; HIR 575/0/2 pending. Fresh stage2 constructor 4/8 -> 6/8, both discovery orders pass; produced reducer blocked by missing choose_or stub134 |
| B-ALLOCATOR-NAMED-SHAPE | Equal runtime types do not merge positional or distinct named-only constructor bodies | ast_to_hir.cr allocator materialization and lower_call | allocator_named_shape_spec.cr; allocator_named_shape_repro.sh; fresh accessor runtime and lstrip/field-store inspection | next-touch | [FALSIFIABLE] Three HIR and eight host cases pass; produced accessor 7/7 and correct count/offset; indexed scan removes Pointer#any? stub; all eight produced cases compile and four pass runtime; four retain selected initializer body/arity mismatches |
| B-ABSOLUTE-POINTER-NULL | Root-qualified builtin Pointer null members retain concrete pointer identity and emit intrinsic zero values | ast_to_hir.cr lower_static_member_access_call | spec/hir/absolute_pointer_null_spec.cr (typed zero, both syntax forms, two defaults, namespaced control); absolute_pointer_null_default.sh on fresh host/stage2 | next-touch | [FALSIFIABLE] HIR ablation fails 2/3; fixed four host/produced runtime cases pass; lower_call-only candidate refuted and dropped |
| B-TUPLE-CASE-SUBJECT | Tuple case patterns extract known subject slots at their storage type, independently of numeric pattern width | ast_to_hir.cr emit_case_comparison | tuple_case_subject_width_spec.cr; tuple_case_subject_width_repro.sh | next-touch | [FALSIFIABLE] Baseline runtime13; isolated HEAD repair passes 12 HIR examples and unsigned/signed runtime controls; original Crystal agrees. Fresh composite stage2 passes the integer/wide-literal regression; generated float literals and bootstrap remain open |
| B1 | Produced stage binaries must be built and run through `scripts/run_safe.sh`. | `00-bootstrap-contract.md` section 4 | Any command trace executing a produced binary directly (without `scripts/run_safe.sh`) is a protocol violation. | current | [FALSIFIABLE] |
| B2 | A moved frontier is acceptable only with a guard and a named residual boundary. | `00-bootstrap-contract.md` section 5 | A commit claims a frontier fix without a scripted guard or a named TODO/LANDMARK residual boundary. No scripted meta-guard. | current | [MISSING-FALSIFIER] |
| B3 | Original-vs-stage semantic oracle is required when a change touches language behavior. | `00-bootstrap-contract.md` section 3.1 | `regression_tests/original_vs_stage_semantic_oracle_contract.sh <compiler>` compares original Crystal and stage output for explicit semantic lines (`TYPE=`, `CONST=`, `UNION=`). Strict-green for the H6-core TypeValue surface; rerun whenever language-visible type identity changes. | current | [FALSIFIABLE] |
| B4-H | A previously generated `s2b` can compile the historical full-prelude tiny source through LLVM entry without worker-only masking, RSS-kill, or post-`lower_main` crash. | `00-bootstrap-contract.md` section 4.2; historical B4 record | `STAGE1_COMPILER=<stage1> GENERATED_S2=<old-s2> REQUIRE_CLEAN=1 scripts/generated_stage_llvm_entry_classifier.sh` reports `classification=clean_both_modes` and the kept output prints `42` under `scripts/run_safe.sh`. This row is retained for compatibility archaeology only; it cannot promote current source. | later | [HISTORICAL] |
| B4-F | Current source must produce a fresh `s2b` and preserve exact semantics in both smoke modes. | `00-bootstrap-contract.md` sections 4.2-4.2.2; `07-compiler-decomposition-and-semantic-replacement.md` section 2.2 | Produce exactly two stages in a new path with `scripts/bootstrap_chain.sh --out <fresh> --stages 2 --timeout <diagnostic-cap-above-300>`, then run `scripts/validate_bootstrap_manifest.sh --run-dir <fresh> --expected-host <trusted-crystal> --max-stage2-wall-sec 300`. The producer timeout is only a resource envelope so an over-budget near-miss can leave a receipt; T8 alone owns the <=300s admission decision. The validator must rehash current source/harness/host identity, lineage, all artifacts, successful numeric B7 coverage, normal no-worker build policy, and exact plain/full-prelude plus no-prelude transcripts. Historical both-smoke certificates at 231.37s, 251.91s, and 253.42s are within that numeric budget but remain stale and cannot certify current source; ~178-190s records are partial. The sealed current-source run exhausted the former 180-second cap at stage2 wall 182.54s with no `cv2_s2`, so the new 300-second policy is unmeasured. Old artifact reuse, worker-only success, emit-only success, unknown resource coverage, or either semantic mismatch fails B4-F. T8 now exists, but no fresh current-source receipt has passed it. | current | [FRONTIER] |
| B5 | The bootstrap ladder must build at least through `s3b`; the prior B5 lower-method locator is historical until current source satisfies B4-F. | `scripts/build_bootstrap_stages.sh`; B5 refined HIR localizer | Historical evidence built and smoked `cv2_s1`/`cv2_s2`, then failed stage 3 with exit 139 after `[STAGE2_DEBUG] pass3 after lower_main call` at about 4800 MB peak RSS. The historical localizer reported `classification=self_build_hir_pending_target_lower_method_body_lowered_boundary`; first bad gate was `ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED`, inside the `AstToHir#lower_method` body loop for `Adamas::Compiler::CLI#run$IO_IO` (all pre-body gates clean). Source-shape guards must stay green: `REQUIRE_METHOD_BODY_SCOPE=1 REQUIRE_LOWER_DEF_BODY_SCOPE=1 REQUIRE_LOWER_MODULE_METHOD_BODY_SCOPE=1 scripts/method_body_lowering_scope_source_shape_guard.sh` reports `method_body_scope_owner_consumed` for `lower_method`, `lower_def`, and `lower_module_method` (one enter/restore pair each, zero selected legacy saves), and `REQUIRE_INLINE_CALLEE_LOCAL_SCAN_SCOPE=1 scripts/inline_callee_local_scan_scope_source_shape_guard.sh` reports `inline_callee_local_scan_scope_consumed`. The sealed current-source run produced no `cv2_s2` because B4-F timed out, so current B5 and its semantic smokes remain unavailable behind that compiler-side performance frontier. A patch that regresses to an earlier target gate, regresses B4-F, fails either source-shape guard, reopens consumed upstream edges from stale evidence, or claims green `s3b` from these helpers or historical G9 alone fails the frontier. | current | [FRONTIER] |
| B6 | A bootstrap manifest must be producer-owned fresh evidence, not self-asserted readiness. | `00-bootstrap-contract.md` section 4.2.1 | `scripts/run_safe.sh crystal 360 4096 spec spec/bootstrap/bootstrap_evidence_integrity_spec.cr spec/bootstrap/bootstrap_chain_timing_spec.cr`; existing run directories, absolute/relative/symlink-parent output paths inside the source scope, stale/symlink/hardlink stage outputs, producer or late evidence mutation, symlinked build logs, blank/extra stdout, stderr or wrapper-marker spoofing, contaminating control environment, and manifest publication collision fail. A generic compiler environment is sanitized before launch. A good two-stage fake ladder writes `bootstrap_chain_v3` with source endpoint consistency, lineage, producer-created cache/run-directory identities, hashed environment context, harness, successful B7 resource, wall-time, and exact smoke hashes. This does not certify transient mutate-restore absence, external input closure, or readiness policy. | current | [FALSIFIABLE] |
| B7 | Resource telemetry must not turn unavailable or partial rooted-ancestry observation into a numeric maximum. | `00-bootstrap-contract.md` section 6 | `scripts/run_safe.sh crystal 240 4096 spec spec/runtime/run_safe_resource_metrics_spec.cr spec/runtime/run_safe_process_tree_spec.cr`; valid fake snapshots aggregate parent and child; malformed/unavailable `ps`, empty/malformed/partial-PID `lsof`, topology churn, and a malformed FD topology fence fail the affected metric to `unknown`; a liveness-confirmed natural-exit fence aborts only its incomplete pair and preserves earlier completed samples, while a rootless snapshot of a live target fails closed; a spoofed target row cannot enter the atomic producer-owned evidence file; malformed bounds and pre-existing evidence paths reject before target launch; a publication race fails the wrapper; timeout, signal, nested-supervisor, and descendant-cleanup paths preserve their scoped behavior. | current | [FALSIFIABLE] |

## 3. HIR Name Resolution

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| H1 | Qualified nested names must not duplicate owner segments. | `01-hir-name-resolution.md` section 2 | `regression_tests/p2_qualified_module_namespace_no_prelude.sh <compiler>` finds `Float::Float::ParsedNumberStringT` or duplicated `Float::FastFloat`. | current | [FALSIFIABLE] |
| H2 | Self-reopen wrappers must not recursively register the current owner. | `01-hir-name-resolution.md` section 2.2, LM-553 | `regression_tests/p2_self_nested_module_registration_frontier.sh <compiler>`. | current | [FALSIFIABLE] |
| H3 | Nested builtin annotations must remain top-level unless structurally nested. | `01-hir-name-resolution.md` section 3, LM-554 | `regression_tests/p2_full_prelude_generic_template_namespace_no_pollution.sh <compiler>`. | current | [FALSIFIABLE] |
| H4 | Type-literal name queries lower to literal strings, not static stubs. | `01-hir-name-resolution.md` section 4, LM-558 | `regression_tests/p2_type_literal_name_query_no_stub.sh <compiler>`. | current | [FALSIFIABLE] |
| H5 | Function body presence must distinguish real bodies from stubs. | `01-hir-name-resolution.md` section 6 | `regression_tests/hir_function_body_presence_contract.sh` proves a registered bodyless HIR function is not `has_function_with_body?` and HIR->MIR preserves it as an empty unreachable stub, while real body evidence lowers as body. | current | [FALSIFIABLE] |
| H6 | Type-visible runtime values must share one HIR-owned `TypeValue` / `RuntimeTypeIdentity` fact for the H6-core surface. | `01-hir-name-resolution.md` section 4.1 | `regression_tests/type_value_core_runtime_identity_contract.sh <compiler>` compares original Crystal and stage output for direct/interpolated `typeof` forms, `.class` forms, and type-literal `.name` / `.to_s` / `inspect`; deliberately excludes the parser-confounded no-parens command-call row (H7). Wider historical guard: `regression_tests/type_value_runtime_identity_contract.sh <compiler>`. | current | [FALSIFIABLE] |
| H7 | No-parens command calls must preserve a parenthesized member-access argument as the argument, not as member access on the command-call result. | 0k-BF / 0k-BG parser-frontier split | `regression_tests/command_call_member_access_preservation_contract.sh` asserts `puts (true ? 1 : nil).class` parses as a command call whose argument is `.class`; current parser is measured-red under `ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH=1`. | pre-s2-clean | [FRONTIER] |
| H8 | Runtime `.class` on a dynamic multi-variant union must report the concrete runtime class, not the static union display name. | `01-hir-name-resolution.md` section 4.1 | `regression_tests/type_value_dynamic_union_class_residual.sh <compiler>` compares original Crystal and stage output for direct/interpolated `.class` on an `ARGV`-dependent `Int32`-or-`String` union; current stage is measured-red under `ADAMAS_EXPECT_DYNAMIC_UNION_CLASS_MISMATCH=1`. | pre-s2-clean | [FRONTIER] |

## 4. Generic Template Registration

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| G1 | Generic/container fixes must not use arbitrary depth caps. | `02-generic-template-registration.md` section 2 | Add a deep nested tuple/hash/array/proc oracle before changing demand or registration pruning code. Static diff review alone is not enough. | next-touch | [MISSING-FALSIFIER] |
| G2 | Empty or repeated generic owner names such as `Iterator::` or `Indexable::Indexable::...` are invalid. | `02-generic-template-registration.md` section 3 | Add trace/IR guard that fails on empty owner suffixes or repeated adjacent owner segments in generated stage. | next-touch | [MISSING-FALSIFIER] |
| G3 | Generic template and instance keys must be semantic keys, not rendered strings. | `02-generic-template-registration.md` section 3 | `regression_tests/generic_identity_key_contract.sh` proves `GenericTemplateKey` and `GenericInstanceKey` equality/hash use owner, source `DefIdentity`, declared type params, specialization args, and lexical owner rather than display/rendered names. | pre-s2-clean | [FALSIFIABLE] |
| G4 | Broad source-gated generic-template body scan is not an acceptable fix. | `02-generic-template-registration.md` section 5 | Reverted experiment regressed earlier around `Crystal::PointerLinkedList` / trace paths. | current | [REFUTED] |
| G5 | Produced `s2` full-prelude `puts 42` must get past the generic/template registration frontier. | `TODO.md`, LM-559 | `ADAMAS_TRACE_CLASS_FRONTIER=1 scripts/run_safe.sh <produced-s2> 60 4096 /tmp/hello.cr -o /tmp/hello_bin`. Historical B4-H evidence was green, but current admission requires B4-F fresh production plus both semantic smoke modes; a regression reopens this row. | pre-s2-clean | [FALSIFIABLE] |
| G6 | The current owner-cache carrier must materialize `Hash(UInt64, BlockOwner)#[]=` as a real body, not an undefined-extern abort stub. | `TODO.md`, LM-ARCH-0K-AW | `regression_tests/block_owner_index_assign_materialization_repro.sh <compiler>` finds a non-stub self-IR body for the current `BlockOwner` carrier. Transaction guard: `scripts/block_owner_materialization_transaction_availability_report.sh <compiler>` must report at least one exact/all-equal BlockOwner setter `[MAT_TX]`, joined `[MAT_EMIT]` rows with `body_present=1`, at least one non-stub LLVM body, and zero setter stubs. Green G6 remains non-bootstrap evidence. | current | [FALSIFIABLE] |
| G7 | A demanded runtime return union may not store a bare generic template, while a bare generic parameter restriction may still dispatch through concrete callsite instances. | Original Crystal 1.21 storage legality; `TODO.md` bare reference-generic frontier | The `bare generic` HIR group must accept concrete `LayoutBox(Int32)`/`String` callsites through a `LayoutBox | String` parameter restriction and reject demanded explicit `LayoutBox | String` and `LayoutBox?` returns with `can't use LayoutBox(T) in unions yet`. A fresh compiler must reproduce both diagnostics and compile/run the positive oracle; an uncalled annotated definition must retain the original compiler's lazy acceptance. Broad rejection in union construction, eager registration validation, MIR candidate expansion, or parameter-restriction rejection fails this row. | current | [FALSIFIABLE] |
| G9 | Function lowering state must not be treated as a function body availability proof. | post-lowering `FunctionAvailabilityContract` | `STAGE1_COMPILER=<stage1> REQUIRE_REACHED=1 SAMPLES=8 scripts/generated_stage_lower_method_terminal_classifier.sh` joins `[MAT_TX]`, `[MAT_DONE]`, and `[MAT_EMIT]` with method entry/name/call checkpoints; a prior bounded classifier run reported `classification=eligible_lower_method_terminal_edge` with `selected_cause=lower_method_terminal_abstract_method` (residual 3 rows). Pre-lowering visibility fields and `materialization_action=created_body` are not post-lowering body evidence; sampled per-method fixes, backend undefined-extern rescue, and forwarders remain invalid moves from that prior bounded classifier evidence. | next-touch | [FALSIFIABLE] |

## 5. MIR Call ABI

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| M1 | Exact static calls lower before receiver mutation. | `03-mir-call-abi.md` section 3 | `regression_tests/p2_stage2_static_call_named_llvm_no_prelude.sh <compiler>` emits fallback `@func1` or wrong arity. | current | [FALSIFIABLE] |
| M2 | Receiver calls include a runtime receiver; static calls do not. | `03-mir-call-abi.md` section 4 | Add MIR shape check for the static-call reducer: named callee, callee arity equals args, no synthetic receiver. | next-touch | [MISSING-FALSIFIER] |
| M3 | Null/missing HIR `TypeRef` is not an ordinary runtime object. | `03-mir-call-abi.md` section 6 | Add no-prelude MIR oracle covering a null `TypeRef` conversion path. | pre-s2-clean | [MISSING-FALSIFIER] |
| M4 | Debug value-location metadata is opt-in during bootstrap and not semantic. | `03-mir-call-abi.md` section 7 | Build with metadata disabled and verify semantic guards still pass. No dedicated script. | current | [MISSING-FALSIFIER] |

## 6. LLVM Emission

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| L1 | LLVM backend must resolve MIR `FunctionId` to the named callee. | `04-llvm-emission.md` section 2, LM-559 | `regression_tests/p2_stage2_static_call_named_llvm_no_prelude.sh <compiler>` rejects `@func1`. | current | [FALSIFIABLE] |
| L2 | LLVM calls must not have empty return type spelling. | `04-llvm-emission.md` section 3, LM-559 | Same guard rejects `call  @`. | current | [FALSIFIABLE] |
| L3 | Emitted IR for the static-call reducer must pass `llc` when available. | `04-llvm-emission.md` section 6 | Same guard runs `llc -filetype=obj` if `llc` exists. | current | [FALSIFIABLE] |
| L4 | Hardcoded IO overrides should use generated accessors instead of unstable offsets. | `04-llvm-emission.md` section 4 | Add guard that changes/observes fd ivar layout and verifies IO overrides still emit correct fd load. | next-touch | [MISSING-FALSIFIER] |
| L18 | The parallel-rescue output-ownership fix (`LLVMOutputOwnershipContract`) must keep its shape: the rescue fallback must not restore a stale zero-position saved output buffer over live output. | Slice 0k-EJ root cause / 0k-EL behavior fix | `REQUIRE_OUTPUT_OWNERSHIP=1 scripts/llvm_output_ownership_source_shape_guard.sh` must report `output_ownership_shape=output_ownership_contract_consumed_by_parallel_restore` with zero parallel direct saved-output snapshots/restores. | next-touch | [FALSIFIABLE] |
| L19 | The `String::HEADER_SIZE` scalar-global producer edge is consumed; do not reopen from stale `ptr null` / `i32 0` evidence. | Slice 0k-EN | `STAGE1_COMPILER=<stage1> REQUIRE_RAW_DUMP=1 REQUIRE_CLASSIFICATION=1 scripts/generated_stage_finalize_to_s_classifier.sh` must report `normal_string_header_size_global_shape=i32_12` and `raw_dump_classification=raw_dump_before_to_s_buffer_valid`. Adjacent guards must pass: `regression_tests/p2_constant_globals_no_prelude.sh <stage1>`, `regression_tests/p2_prescan_complex_constants_frontier.sh <stage1>`, `regression_tests/p2_macro_number_parsed_literals_no_prelude.sh <stage1>`. | next-touch | [FALSIFIABLE] |
| L20 | The function-return contract mismatch is consumed: non-void MIR `Call` results stay available through hoisted cross-block slots. | Slice 0k-EP | `STAGE1_COMPILER=<stage1> scripts/generated_stage_return_contract_mismatch_report.sh` must not select `function_return_contract_mismatch_frontier` and must report `normal_llc_type_mismatch=0` while L19 signals stay green. | next-touch | [FALSIFIABLE] |
| L21 | The zero-struct/value-storage LLVM validity edge is consumed: raw stack value storage and raw zero sentinels, not named aggregate storage. | Slice 0k-ER | `STAGE1_COMPILER=<stage1> scripts/generated_stage_zero_struct_sentinel_report.sh` must report `selection_status=rejected`, `reason=invalid_null_constant_error_missing`, with L19/L20 signals preserved and `Slice(UInt8).new` storage as raw `[16 x i8]` alloca/zeroinitializer. | next-touch | [FALSIFIABLE] |
| L22 | Runtime-helper demand/definition availability is consumed; no reopen from stale undefined-helper evidence. | Slice 0k-ET | `STAGE1_COMPILER=<stage1> scripts/generated_stage_gc_realloc_helper_report.sh` must report `selection_status=rejected`, `reason=undefined_gc_realloc_helper_error_missing`, with helper call/define counts joined. `regression_tests/gc_aware_realloc_gating_repro.sh <stage1>` proves both sides of the demand contract: GC-free programs emit no wrapper and link clean; GC-using programs emit the wrapper and run clean. B4-F exact plain/no-prelude gates must stay green; B4-H is historical only. | next-touch | [FALSIFIABLE] |

## 7. CLI Output

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| C1 | Emit-only success does not prove normal binary output success. | `06-cli-output-contract.md` section 2 | Compile the same reducer with `--emit llvm-ir --no-link` and with normal `-o <bin>`; emit-only pass plus normal-mode exit 139 is the divergence signature. No dedicated script. | current | [MISSING-FALSIFIER] |
| C2 | Post-LLVM tail fixes must localize crash after LLVM finalization. | `06-cli-output-contract.md` section 4, LM-564 | `regression_tests/p2_stage2_cli_output_tail_no_prelude.sh <compiler>`; a tail fix lacking the section 7 localization log is invalid evidence. | current | [FALSIFIABLE] |

## 8. Architecture Transition

These rows are the compact admission surface for
`07-compiler-decomposition-and-semantic-replacement.md`. They are design
guards until the named scripts/reducers exist; they do not authorize a default
compile-path switch.

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| T0 | Slice 1A provenance is fail-closed, default-off, and remains guard-only until a real typed consumer exists. | `07-compiler-decomposition-and-semantic-replacement.md` sections 2.1, 3.3, and 13.2 | Port or land the Slice 1A `regression_tests/arena_identity_provenance_shape_guard.sh` plus positive/negative owner reducers: default mode performs no registry retention/lookup, guard mode rejects zero/multiple-owner matches, and no `ResolutionId`/materialization behavior changes. If two subsequent slices add no consumer, the T0 expiry rule removes or re-admits the guard with a new falsifier. | current | [MISSING-FALSIFIER] |
| T8 | Fresh-s2 readiness is a performance and semantic vector, not a historical artifact or timeout proxy. | `00-bootstrap-contract.md` section 4.2.2; `07-compiler-decomposition-and-semantic-replacement.md` sections 2.2 and 9; `docs/compiler_architecture_sdd.md` section 0 | `scripts/run_safe.sh crystal 240 4096 spec spec/bootstrap/bootstrap_manifest_validator_spec.cr` proves with 27 examples that `scripts/validate_bootstrap_manifest.sh` accepts a complete receipt at the inclusive 300-second boundary and rejects post-publication artifact tampering, rehashed semantic/framing or resource-outcome mismatch, 300.01 seconds, out-of-grammar wall precision, a caller-relaxed budget, ambiguous resource/wall rows, build-log/receipt disagreement, manifest/log wall disagreement, forged or partial B7 coverage, worker/emit-only policy, broken lineage, stale source/shared-harness or smoke-input identity, duplicate fields, symlink evidence, an untrusted/non-executable host, and a run path inside the source scope. This executable seals the decision vector, not the current B4-F result; a fresh current-source receipt must still pass it. | current | [FALSIFIABLE] |
| T9 | Lawful concrete and union generic instances must preserve selected definition/instance, coercion/value type, receiver/value arity, body, and emitted-symbol continuity. | `07-compiler-decomposition-and-semantic-replacement.md` sections 2.4, 11, and 13.3; `docs/compiler_architecture_sdd.md` sections 6.5 and 8 | [Reducer](../../regression_tests/union_static_generic_materialization_guard.cr) and [guard](../../regression_tests/union_static_generic_materialization_guard.sh) compare concrete `Array(ArenaLike) << AstArena`, explicit `.as(ArenaLike)`, and true union flow. Concrete flow may lawfully instantiate `<<`/`push` with `AstArena`; explicit and true union flow may instantiate union/reduced-union variants. Original Crystal's oracle uses `DefInstanceKey(def.object_id, actual typed args, block/named)`; Adamas authority must use `DefIdentity` plus actual typed args, block, and named arguments. Mangled names are later serialization. Focused HIR mode is green after failing closed when the left `<<`/`>>` type is unavailable. A source-bound full-compiler probe exposed `exact_lookup` rewriting concrete `push$AstArena` to the union body; the current bounded rule preserves a requested typed name only when its base and actual typed args exactly re-serialize to it. Concrete-request/union-actual, base mismatch, block mismatch, and splat controls fail closed. Candidate SHA-256 `4d6c37ac...` preserves concrete requested/target/materialized names through `instance_class_info_lower_method`; the focused guard, 43 focused examples, 617 other fast HIR examples (2 existing pending), and union-value runtime storage are green. This proves the current HIR leg only. A historical full-G9 artifact classified an orphan zero-argument call/unreachable definition as `MEASURED_RED`; it is stale and not reproduced from current source. Any selected-instance, coercion/value type, receiver/value arity, body, or emitted-symbol discontinuity fails. | current | [FALSIFIABLE] |
| STABLE6 | The attempted in-process `MaterializationReplayShadow` is **REFUTED IN-PROCESS PROTOTYPE / NOT ADMITTED**. | `07-compiler-decomposition-and-semantic-replacement.md` section 2.5; `docs/compiler_architecture_sdd.md` section 0.3 | Local evidence stays scoped: simple OFF/ON HIR/runtime parity, focused 17/0, baseline HIR 286/0 plus two existing pending examples, host build, and local adversary ROBUST. The frozen pre-shadow `c216b9ef...` + `d7ad2cac...` phase-stats-only control timed out at 180s (`run_safe` exit 143), had no s2, and grew 604 -> 1535 -> 7422 -> 19238 -> 28234 (+27630), no stack overflow (repeat log `e568...`). Same-binary ON/OFF both had no s2 and exit 11 stack overflow in `declared_type_match_score`/alias/type-name during `lower_missing` p0 around #800 (~141s/~139s), identical 604 -> 1544 -> 7430 -> 19246 -> 28369 (+27765), logs `18603d...`/`51146a...`, RSS unavailable; ON final scan-i4: registered=27363, agree=42801, mismatch=484, unjoined=4459, ambiguous=300, no_mat=12864, calls=60909, not_yet=1. No causal proof is claimed, but runtime-OFF changes self-host source/workload/failure class, so whole-system admission is rejected; default-off is not zero compile-time cost. Prototype only in `/private/tmp`, removed from main code. T1 remains missing, the B4-F <=300s policy remains unmeasured/open, and no speed claim is allowed. | current | [REFUTED] |
| T1 | `ResolutionId` and `MethodInstanceKey` preserve typed identity continuity across resolution, materialization, and emission. | `07-compiler-decomposition-and-semantic-replacement.md` sections 6 and 13 | This one-reducer availability guard, `regression_tests/t1_identity_boundary_guard.sh <compiler>`, runs `t1_same_spelling_shapes.cr` through `scripts/run_safe.sh` with the supplied compiler/config, hard-caps each outer captured log at `T1_MAX_LOG_BYTES+1`, requires compiler/reducer `rc=0`, and requires legacy route rows for r1/r2/r3/r5; r4 is classified as runtime-executed inline/block and is not required to have a legacy MAT row. The inner `run_safe.sh` capture is time/memory guarded but has no byte-cap claim. The guard checks only the exact versioned record `[T1_IDENTITY_JOIN] schema=t1_identity_join_v1 case_id=r1..r5 resolution_id=<u64> def_arena_id=<u64> def_expr_index=<i32> receiver_semantic_type_id=<u32|none> arg_semantic_type_ids=<ordered-u32-list|none> block_semantic_type_id=<u32|none> named_semantic_args=<ordered-NameId:SemanticTypeId-list|none> producer_phase=post_resolution_pre_hir_coercion`. The exact semantic r1-r5 local decision and its selected-Def/receiver-owner guards, including cross-arena stale shared-context symbol rejection and same-arena reopening identity, are covered separately by `spec/semantic/type_inference_selected_def_identity_spec.cr`; that immediate semantic consumer is not a producer stream or HIR continuity proof. Current `T1_STATUS=MEASURED_RED` means schema/path availability is absent for this supplied compiler/config; by default it exits 1, while `T1_ALLOW_MEASURED_RED=1` accepts the expected diagnostic exit 0; this does not prove global absence or continuity. Alias/generic/absolute-`::Hash` cases and exactly five downstream joins remain pending full acceptance. Any tagged schema row is `UNEXPECTED_SCHEMA_APPEARED` (exit 1), and configuration/compile/runtime errors exit 2. | next-touch | [FALSIFIABLE] |
| T2 | Candidate semantic decisions do not use rendered/mangled strings as authority. | `07-compiler-decomposition-and-semantic-replacement.md` sections 5–6 | Source-shape plus runtime ledger finds no string-keyed semantic cache, owner choice, overload choice, or late name rewrite on the candidate route. | next-touch | [MISSING-FALSIFIER] |
| T3 | The candidate semantic pipeline does not require the legacy supply-driven queue. | `PLAN_DEMAND_DRIVEN_REWRITE_RFC.md` sections 3.2, 4, and 7 | With `ADAMAS_SEMANTIC_COMPILE=1 ADAMAS_SEMANTIC_ASSERT_NO_LEGACY_QUEUE=1`, hello, generic, macro, block, recursive, and stage reducers execute none of `emit_all_tracked_signatures`, `process_pending_lower_functions`, or `force_lower_function_for_return_type`. | next-touch | [MISSING-FALSIFIER] |
| T4 | Legacy and candidate paths are normalized-equivalent before promotion. | `PLAN_DEMAND_DRIVEN_REWRITE_RFC.md` section 6; `07-compiler-decomposition-and-semantic-replacement.md` section 10 | Normalize IDs, function/signature sets, instruction/call shapes, effects, hierarchy, externs, type descriptors; then require MIR, LLVM, and selected runtime smokes to agree. | next-touch | [MISSING-FALSIFIER] |
| T5 | A zero-copy change is safe and resource-positive under an explicit ownership contract. | `07-compiler-decomposition-and-semantic-replacement.md` section 7 and 12 | Allocation/retention census plus arena-expiry negatives records copies, retained bytes, temporary strings, and peak RSS across parser→HIR→MIR→LLVM; unknown lifetime or protected-metric regression fails. | next-touch | [MISSING-FALSIFIER] |
| T6 | Backend emission remains mechanical and does not reconstruct source semantics. | `docs/compiler_architecture_sdd.md` sections 6.7 and 9; `07-compiler-decomposition-and-semantic-replacement.md` section 8 | Backend source-shape/IR guard proves it consumes typed symbols and `AbiFacts` without calling name resolution, overload selection, materialization, arena recovery, or string-prefix layout inference. | next-touch | [MISSING-FALSIFIER] |
| T7 | Candidate owners stay within structural budgets; the existing `TypeInferenceEngine` is not promoted unchanged as a new authority. | `07-compiler-decomposition-and-semantic-replacement.md` sections 4.1 and 8.2 | Source-shape census checks coordinator/method/file/public-API/state-surface ceilings and requires a same-slice exception record (reason, owner, impact, expiry, replacement, falsifier) for every breach; a direct unchanged `TypeInferenceEngine` promotion fails. | next-touch | [MISSING-FALSIFIER] |

STABLE6 telemetry remains an adversarial diagnostic, not a release certificate.
The local parity verdict is **ROBUST** only for the simple bounded checks; the
whole-system verdict is **BROKEN for admission** because runtime-OFF changes
the self-host source/workload and failure class. A current compiler-consumer
inventory found no semantic object flow from the aggregate prepass into
per-file HIR, so a cross-arena `MethodSymbol` admission, new in-process
callsite owner, or new `AstToHir` ivar is rejected at this boundary. Existing
unit offsets are a structural map, not a consumer. T1 pauses before
`ResolutionId`; T9's focused and source-bound full-compiler HIR routes are now
green through exact-target body lowering. Current HIR-to-MIR-to-LLVM
emitted-symbol continuity remains the active materialization falsifier. The
historical zero-argument symptom is stale and unreproduced. T1 remains missing
and B4-F remains unmeasured/open under the 300-second policy.
The separate full-prelude/union audit remains intentionally red/noisy (about
2673 registered, 2568 agree, 404 mismatch, 1 stale, 199 untracked required,
225 unjoined, 1 ambiguous, and 11377 calls); its similar plain run is not
combined with it, and those counters do not prove duplicate semantic instances
or speed.
Keep the context bridge explicit: `StaleCallSite`,
`UntrackedRequiredCallSite`, and `StaleTransactionRef` remain distinct
diagnostic meanings.

## 9. Refuted Branches

| ID | Branch | Evidence | Status |
|----|--------|----------|--------|
| R1 | Source-first generic type-param extraction as a broad fix. | Did not move the Float/ParsedNumberStringT frontier. | [REFUTED] |
| R2 | Caching `node.body` as a broad generic-template registration fix. | Did not move the frontier. | [REFUTED] |
| R3 | Source-gating generic-template nested-type body scan. | Failed earlier around `Crystal::PointerLinkedList` / trace paths. | [REFUTED] |
| R4 | Re-enabling source-backed top-level return annotations after LM-558. | Regressed produced `s2` full-prelude `puts 42` to earlier class registration crash around `class register idx=51/104`. | [REFUTED] |

## 10. Bootstrap Investigation Process

| ID | Claim | Source | Smallest Falsifier | Phase | Status |
|----|-------|--------|--------------------|-------|--------|
| P1 | Trace absence is not enough to prove a function was not entered. | LM-565 | A tail/root claim relies only on a missing trace line when lldb, breakpoint, or IR control-flow evidence is practical. Review condition; no script. | current | [MISSING-FALSIFIER] |
| P2 | Small helpers in self-host critical paths are semantic risk until s1->s2 proves otherwise. | LM-565 | A helper/refactor in compiler bootstrap code is committed with only host or no-prelude evidence after touching a produced-stage path. Review condition; no script. | current | [MISSING-FALSIFIER] |
| P3 | Sidecar model output is candidate evidence, not acceptance evidence. | LM-565 | A fix adopts Cursor/Grok/Spark claims without local reproduction or a guard. Review condition; no script. | current | [MISSING-FALSIFIER] |
| P4 | Bootstrap cache/IO/hash code is runtime surface, not harmless infrastructure. | LM-564, LM-565 | A cache or filesystem-tail change lacks a produced-stage guard covering the path that consumes the cache/hash result. Review condition; no script. | next-touch | [MISSING-FALSIFIER] |
| P5 | A gate-local root fix must name deeper roots that remain open. | LM-564, LM-565 | LANDMARK/TODO wording claims a subsystem is fixed when the evidence only clears a current bootstrap gate. Review condition; no script. | current | [MISSING-FALSIFIER] |


| B-SHARED-MODULE-UNION-YIELD | Zero-argument shared module blocks use each concrete union self and preserve caller state | ast_to_hir.cr resolve_union_method_call; inline_union_shared_module_yield; inline_union_yield_variants | shared_module_union_yield_spec.cr; shared_module_union_yield_repro.sh | current | [FALSIFIABLE] Atomic258 passes 3 HIR cases and union259 original-first native guard. Overrides and distinct Defs reject before IR. Nonzero args, separate block metadata failure, and LavinMQ parity remain open. |


| B-BLOCK-FORALL-NUMERIC-MACRO | Call-local method forall shadows receiver maps; numeric generic arguments preserve macro literal kinds | ast_to_hir.cr lower_call; lower_method; macro_value_for_type_name | block_forall_receiver_binding_spec.cr; block_forall_receiver_binding_repro.sh | current | [FALSIFIABLE] union258 has 5 errors in 7 new HIR examples; sort279 passes all 13 focused examples and six original-first native calls. Concrete owner U and wrong-value rejection survive. Wider numeric syntax, multi-result specialization, and LavinMQ parity remain open. |


| B-NAMED-TUPLE-UNION-LAYOUT | Preserve keys and per-arm literal indexes; structurally rebuild direct-call arguments before union embedding | ast_to_hir.cr normalize_method_owner_name; lower_named_tuple_literal_index; repair_named_tuple_call_arguments | named_tuple_union_field_owner_spec.cr; named_tuple_union_literal_index_spec.cr; named_tuple_structural_coercion_spec.cr; named_tuple_union_literal_index_repro.sh | current | [FALSIFIABLE] Pre-fix union owners fail 2/6 examples and source-layout wrapping exits 6; namedtuple298 passes 31 focused examples and 22 original-first native checks plus missing-key rejection. Virtual calls, union-to-union widening, rooted names, returns/casts, and LavinMQ parity remain open. |


| B-NAMED-TUPLE-SUBSTITUTION | Preserve keys and substitute/canonicalize field values recursively | ast_to_hir.cr substitute_type_params_in_type_name | named_tuple_type_substitution_spec.cr; named_tuple_type_substitution_repro.sh | current | [FALSIFIABLE] namedtuple301 fails 5/6; namedtuple302 passes 6 substitution and 31 neighboring HIR examples. Generic-owner lexical aliases and full LavinMQ parity remain open. |


| B-NAMED-TUPLE-CONTEXT | Resolve field values in their lexical context and resolve each rooted union member independently | ast_to_hir.cr resolve_type_name_in_context; resolve_named_tuple_type_name_in_context; qualify_alias_target_in_context | named_tuple_type_context_spec.cr; named_tuple_type_context_repro.sh | current | [FALSIFIABLE] The pre-fix context suite fails 6/10 and the generic-owner native consumer fails lowering. namedtuple311 passes 47 HIR examples and the same three native value checks as Crystal. Full LavinMQ parity remains open. |


| Recursive macro receiver graph | macro_recursive_type_receiver_spec.cr; macro_recursive_type_receiver_repro.sh | macro305 overflows before repair; isolated macro315 passes 55 HIR examples and three original-first native macro observations; unknown members after recursive edges remain rejected | Generic-module validation context and nested AliasType identity remain separate |


| Terminal no-parentheses block argument | parser_multiline_named_tuple_body_spec.cr; block_argument_collection_boundary_repro.sh | Six of nine initial cases fail before repair; isolated parser325 passes 90 parser examples and three original-first native checks; binary ampersand remains positional | Parenthesized extra-block diagnostics and newline handling remain separate |


| Distinct instance bodies on union block receivers | distinct_owner_union_yield_spec.cr; distinct_owner_union_yield_repro.sh | Prior compiler executes the first body for both arms; isolated union335 passes 59 HIR examples and four original-first native value/non-local-return checks | Only zero-positional-argument instance block calls admitted; positional arguments and distinct module bodies remain open |


| Proven-disjoint case body admission | case_unreachable_body_spec.cr; case_unreachable_body_repro.sh | Prior HEAD fails two new HIR cases and emits dead Nil/Bool#each; isolated case341 passes 65 HIR examples and original-first runtime/HIR checks | Unknown hierarchy, predefined roots and effectful conditions preserved; recursive macro projection and full LavinMQ parity remain open |


### Recursive macro TypeNode projection (2026-10-15)
- Positive/identity: recursive Array/Hash and NamedTuple arguments preserve the
  actual cycle-closing alias; a referring ordinary alias expands; a mutual
  cycle preserves the same boundary as original Crystal. Alias leaves retain
  nil acceptance without becoming unions or classes.
- Namespace/caching: a namespaced alias target uses its declaration scope even
  when a global same-name alias exists; adding a later alias invalidates the
  discovered boundary set; nominal self-mappings are not recursion.
- DoD: source358's 27 focused HIR/semantic cases pass; run
  `regression_tests/macro_recursive_type_projection_repro.sh <compiler>` for
  original-first safe native compilation/execution. The native fixture checks
  recursive generic reflection plus namespace ownership.
- Refutation: source340 overflows during native TypeNode hydration; source349
  gives `Array(Int32)` instead of `Array(Array(Outer::Field) | Nil)` in the
  namespace case. A private trace also exposed eager re-entry from receiver
  validation; finite projection at that entry removes the repeated expansion.
- Residual: recursive Proc/pointer shorthand value projection is untested;
  LavinMQ source357 still rejects protected `DefinitionsStore#load_apply`.


### Generic receiver fallback overload suffix (2026-10-15)
- RED/GREEN: `pointer_appender_owner_context_spec.cr` requires a bare generic
  exact target with `$UInt8`/`$Int32` to become a concrete-owner target with the
  same suffix. Case341 base fails one of two examples; the one-hunk fix passes.
- Guard: unrelated ancestor and existing concrete-target fallbacks retain their
  behavior; source360 passes 29 focused cases. The original-first native script
  checks direct/captured UInt8 and Int32 outputs W/B/* on both compilers.
- Scope: native base also passes; the HIR assertion, rather than the native
  guard, is the discriminator. Full-prelude startup still depends on Once ABI.


### Bound local receiver in semantic typeof (2026-10-15)
- RED: full359 reports Void for four of five typeof_bound_locals context cases,
  matching the pinned LavinMQ spec failure at typeof(msgs.receive).
- GREEN: atomic source368 passes 16 focused cases. Stale box ownership, a reused
  AST with Int32/Int64 receivers, and inference-state restoration are guards.
- Runtime guard: typeof_bound_locals_repro.sh compares Crystal and Adamas;
  receive exits 91 if executed, while both binaries output * and exit zero.
  The native control also passes the prior implementation and is not the RED
  discriminator. LavinMQ end-to-end parity is not established by these checks.


### Generated getter versus positive-arity source family alias (2026-10-15)
- RED: full369 rejects a public generated getter as private. Visibility-only
  source375 compiles it but the native probe exits 81 because the bare getter
  symbol contains the one-argument source body and receives a synthesized zero.
- GREEN: atomic source378 passes 13 HIR examples and the original-first native
  getter/property regression with identical output * and zero exit status.
- Guards: reverse declarations, explicit empty calls, private getter versus
  public overload, private positive-arity call rejection, and private zero-arg
  and default-argument source definitions. Original Crystal confirms the latter
  overlap is private. Body assertions require one self parameter and FieldGet,
  with no FieldSet. Refresh after accessor or source-family resolution changes.


### Inherited Enum self return before lazy body lowering (2026-10-15)
- RED: source377 has four failures in the eight-case attachment suite; the
  native source386 and atomic-baseline regression choose Enum instead of the
  concrete enum and exit 81, while original Crystal succeeds.
- GREEN: atomic source389 passes eight HIR cases and native output * with the
  same zero exit as original Crystal. Full source388 compiles the previous
  Log.setup_from_env named-overload blocker; runtime hits the separate Once ABI
  failure and is not counted as a runtime pass.
- Guards: UInt8/UInt64 carriers, both declaration orders, class and instance
  self returns, different enum owners, explicit Enum/Int64 contracts, unrelated
  struct owners, and source overrides. Nullable/composite self, aliases, and
  post-attachment redefinition remain untested. Refresh on enum return caches,
  attachment, provenance consumption, or layout changes.


### Cross-file super defaults (2026-10-15)
- RED: source392 gives caller literal 99 instead of producer literal 42 in both
  two-arena HIR cases. The native script exits 81 on source389 after original
  Crystal succeeds. Full LavinMQ repeats its AccessRefused SuperNode to overflow.
- GREEN: source399 passes three HIR examples and native class, direct included
  module, and ancestor included-module checks with output * and exit zero,
  matching original Crystal. Explicit caller arithmetic remains effective.
- Guards: caller arena restoration and existing ancestor-loop resolution.
  Previous-definition and module-super chains, lexical constant shadowing,
  parameter-referential defaults, and named-only combinations remain untested.
  Refresh on selected definition ownership or omitted argument lowering changes.


### Tuple literal slices and runtime Range dispatch (2026-10-15)
- RED: source399 fails 14 of 16 early HIR checks. Source422 passes literal slices
  but the typed-Range guard selects Tuple#[]$Int32 instead of Range dispatch;
  native builds accept a runtime range that original Crystal rejects.
- GREEN: source432 passes 16 focused HIR examples, positive heterogeneous Int64/
  Bool native slices, negative/exclusive/omitted/clamped/empty ranges, and a
  side-effecting receiver evaluated once. Original-first native controls also
  match runtime/non-Int32 Range and invalid-start rejection. Source433 repeats
  native success with full prelude and composed fixes.
- Scope guard: ordinary runtime/non-Int32 range source rejection is preserved.
  Metaclass, []?, constant-held and union-receiver ranges are still untested.
  Refresh after Tuple layout, AST range, or scalar overload repair changes.


### Explicit raw Proc constructor signature (2026-10-15)
- RED: source432 emits Struct Proc for authenticated Proc(Nil).new and
  Proc(Int32, Nil).new when selected generic Proc.new returns self.
- GREEN: source440 emits Proc descriptors with exact argument/result type
  parameters. All seven HIR cases pass, preserving the existing four negative
  ownership/shape controls. Original-first native null/non-null callback
  context behavior remains equal with explicit PASS and exit zero.
- Scope: only authenticated raw-pair constructor production. Raw callback
  consumers, captured lifetime, MT startup, and LavinMQ parity stay open.
  Refresh on constructor receiver AST, selected definition, or Proc descriptors.


### Raw yield callback consumes a direct null-environment Proc (2026-10-15)
- RED: source440 fails six of 18 MIR carrier cases. The typed raw formal keeps
  an object type, and direct MakeProc values reach raw callbacks boxed.
- GREEN: source450 passes all 18 cases, including opaque/typed formals,
  copied raw pointer and Pointer(Void) carriers, and negative non-null,
  heap, copied-object, no-Yield, and signature controls. Native raw callback
  and raw Proc-pair context controls pass both compilers; the former also
  passes source440 and is not a behavioral RED.
- Composition: source457 passes the same MIR suite plus full-prelude
  Random::Secure checkpoints. Atomic source450 still fails before the first
  checkpoint in separately traced PCG32/Secure.rand overload selection.
- Scope: selected null-environment raw callback adaptation only. Captured
  raw-yield transport, lifetime, general MT startup, and LavinMQ parity stay
  open. Refresh on block ABI, Proc/Yield signatures, pointer provenance, or
  selected-callee lowering changes.


### Block-signature aliases carry lexical inputs and Nil results (2026-10-15)
- RED: source457 loses Int32/UInt64 callback inputs (two HIR failures); source477
  repairs inputs but reports an ABI conflict for an aliased Nil constructor
  callback. Source450's indexed native callback aborts at Pointer#[]?.
- GREEN: source492 passes 16 HIR examples and original-first indexed dispatch.
  Source488 additionally passes the same HIR suite and full-prelude router
  callback fixture. The simpler integer-return native fixture passes the old
  compiler too and must not be reported as a discriminating RED.
- Guard: included-module aliases beat conflicting receiver aliases; alias chains,
  zero inputs, omitted callback parameters, and literal signatures are covered.
- Scope: selected block-annotation alias consumers. Refresh on declaration
  namespace, alias parsing, or callback ABI changes. The real upstream build now
  exposes a separate Hash#map NamedTuple element-type error; parity stays open.


### Proc outer unions and complete specialization suffixes (2026-10-15)
- RED: source492 fails five of eight descriptor cases and returns true for both
  tuple arguments in the original-first native probe. Parser-only source496
  repairs descriptors but returns false for both Proc arguments. Its two added
  specialization cases also fail (proc517).
- GREEN: source510 passes 21 focused HIR examples and the native regression
  script (proc518/proc514), matching Crystal's true/false/true/false output
  (proc513). Typed Proc input/result signatures produce distinct call keys.
- Guard: signature scans and body lowering, aliases/chains, reversed arms,
  nested Arrays, and genuine inner input/result unions. Bare unknown Proc stays
  on the unchanged descriptor fallback. Inner unions are structural guards only:
  the extended Proc-result inference/demand path still has a missing stub.
- Scope: type parsing and concrete Proc specialization identity. Refresh on these
  consumers or union ABI changes. Whole broker/test parity remains open.


### Proc semantic result union before body optimization (2026-10-15)
- RED: source510 has five missing-union descriptor errors in six initial cases
  (proc527), and the original-valid typed consumer aborts at Proc(Nil) demand
  (proc537). The original infers a Nil | Int32 result from both literal branches.
- GREEN: source533 passes 28 focused HIR examples (proc538), five typed-call
  outputs (proc539), and the seven-output native regression with both dynamic
  branch payloads (proc540). All native outputs equal original Crystal.
- Guard: a same-type branch stays Int32; a typed static guard retains Int32 |
  String; return values carry the function's retained union ABI. Unknown or
  incompatible inference is not widened. Actual Proc(Nil) covariance is rejected
  by Crystal (proc520) and must not become an admission rule.
- Scope: unannotated Proc result inference and emitted return normalization.
  Proc signature predicates remain a separate observed defect (proc535).
  Refresh after inference/pruning/ABI changes; whole LavinMQ parity stays open.


### Complete Proc signature predicates and branch narrowing (2026-10-15)
- RED: source533 disagrees with Crystal on the 23-output native regression
  (proc569). Static-only source541 still picks an unrelated Proc union arm and
  rejects bare Proc (proc544); source548 fixes predicates but loses a concrete
  signature after bare-Proc narrowing (proc550). Non-union-target unit probes
  fail five descriptor assertions on source541 (proc552).
- GREEN: source554 passes 69 HIR examples (proc564) and 23 native outputs equal
  to Crystal (proc568), including concrete/absent/input/result/arity checks,
  both Proc union tags, tuple exclusion, repeated predicates, and narrowed .call.
- Guard: multiple matching arms survive a partial intersection; exact single
  arms unwrap; absent signatures add no cast; bare Array matches both generic
  instances. Undecidable class checks keep runtime fallback.
- Exclusions: proc553 crashes the original compiler and is an invalid runtime
  oracle. The Char#ord WIP test has the same baseline failure (proc557/proc555).
  No LavinMQ parity claim. Refresh on Proc/union identity or narrowing changes.


### NamedTuple literal-key expression inference (2026-10-15)
- RED: nt586 runs the seven new HIR cases on source554: :config/:label/:count
  and their enclosing mapped result all lose their inferred type (four failures).
- GREEN: nt585 runs those cases plus prior semantic Proc-return controls on
  atomic nt576: 14 examples, zero failures/errors. nt589 runs the portable
  regression wrapper on the same sealed suite.
- Guards: unknown keys remain unresolved, Array(Int32) and Hash(String, Bool)
  retain their element types. Native generic-block nt584 prints true/guest equal
  to Crystal; parent nt587 also passes, so native success is not the RED oracle.
- Open: full-prelude atomic Hash-map lowering reaches a UInt64 comparison-block
  contract error (nt578/nt581), and full493+hunk LavinMQ still rejects :vhost
  after BaseUser/User result transport. Do not promote local inference evidence
  to LavinMQ compilation or runtime parity. Refresh on inference changes.


### Dynamic Char#ord union receiver (2026-10-15)
- RED char595: parent nt576 fails both Char variant order HIR cases; the
  argument-taking overload guard passes. RED char599: the dynamic native
  consumer builds then aborts in Char#ord, while original Crystal prints three
  true values.
- GREEN char594: atomic char590 passes all 33 focused HIR cases. Native char598
  and portable regression char600 match Crystal for ASCII, Unicode, and the
  custom receiver. Static consumers char593/char596 pass on both versions and
  must not be treated as RED evidence.
- Scope: zero-argument, block-free Char#ord union dispatch. Other primitive
  conversions and heterogeneous result types remain open; no LavinMQ parity
  claim follows. Refresh on dispatch, primitive conversion, or ABI changes.


### Ordinary indented root collection (2026-10-15)
- RED root607: original Crystal prints BAC; parent char590 builds and exits 0
  with empty output. root606 was killed by the FD watchdog and is inconclusive.
- GREEN root608/root609/root611: sealed root605 retains column-zero, space and
  tab roots, preserves nested-class ownership, and matches native BAC output.
- Scope: ordinary parser roots. Generated/recovered macro root admission and
  arena identity are not established by these checks. Refresh on parser-root
  or collector changes; no LavinMQ parity claim follows.


### Generated root arena/runtime collection (2026-10-16)
- RED root629: pinned Crystal 1.21 prints ABCDE; root605 parent builds and exits
  zero with only E. Earlier root613 used the externally updated Crystal 1.22;
  root629 is the repeated same-version behavioral falsifier.
- GREEN root625: eight HIR examples pass, preserving conditional/begin/percent-word
  loop roots and nested class ownership, and rejecting malformed full expansion.
  root624 repeats Crystal/native ABCDE with recovered pinned Crystal 1.21;
  root615/root617 also passed before the external toolchain replacement.
- Guard limits: module-macro absolute owner tests fail 3/3 on parent root627 and
  candidate root623; full-prelude startup exits 1 on both root620 and root618.
  Root619 hung in the separate require-piece cursor loop and was terminated;
  its incomplete run is not a passing guard. Root612's host hash changed during
  an external Homebrew update; use the completed sealed root614 build instead.
- Refresh on parser/collector/main-arena binding changes. No LavinMQ parity or
  arbitrary array-loop/shared macro-context claim follows.


### Macro require scanner cursor conservation (2026-10-16)
- RED root631: the compiled parent piece scanner exceeds an eight-second SAFE
  runtime limit on unmatched else/elsif fragments; root632 raw scanning returns
  repeated preceding text plus the already-consumed else tag.
- GREEN root633: seven scanner cases pass, including both unmatched tags,
  known/nested branch selection, quoted/commented tags and unterminated tags.
  root630 passes twelve combined scanner/root cases; root634 portable regression
  passes; root635 native active require matches pinned Crystal 1.21 output A.
- Scope: consume input before continuation in both scanner representations.
  Unknown-condition dependency admission, skip_file and final language validity
  require separate evidence. Refresh after scanner cursor/control-stack changes.


### Invocation flag transport and isolation (2026-10-16)
- RED flags638: pinned Crystal 1.21 compiles all five native define modes;
  parent root626 rejects -Dcontract_feature after the absent mode passes.
- GREEN flags639: absent BDF and four define spellings ACE match Crystal.
  flags640: 30 combined guards pass, including 15 flag tests, seven require
  scanner tests, four generated-root tests and four indentation tests.
- Guards include both CLI parsers, missing values, sequential isolation,
  declaration/method/macro agreement, inactive requires, release and 16 host or
  optional flag names. Optional flags have no invented HIR defaults.
- Scope: host-target CLI flag transport. LSP configuration, cross-target
  semantics and multithreaded runtime behavior remain separate obligations.
  Refresh on option/context/expander changes; rollback CLI and HIR together.


### Nested numeric generic carrier transport (2026-10-16)
- RED range647: original AA/exit0, parent BB/exit0 for UInt64 endpoint ranges
  under Range(Int, Int). range650: five failing exact-specialization checks.
- Adversary range655: unguarded recursion fails mixed concrete/abstract and
  signed/unsigned negative controls. Final range659: 26 examples, zero failures.
- GREEN range660/662: native AA agrees with pinned Crystal 1.21; portable
  regression cleans its private files on success. Concrete, unrelated,
  constructor/arity and signedness predicate guards remain negative.
- Startup parent642: exit1 before user output; first raise643 is
  Random::Secure.rand_range$Range(Int32,Int32) consuming UInt64 fields.
  Final startup661 prints A/exit0 with the ordinary full prelude.
- Scope: exact body transport and measured startup. Generic admission fallback,
  nested unresolved variables, multithreaded startup and LavinMQ parity are open.
  Refresh after restriction/overload/ABI changes; rollback the bounded HIR unit.


### Nominal enums against module suffix collisions (2026-10-16)
- RED enum665: two wrong-owner HIR failures. Classifier-only enum668 still fails
  twice, discriminating the later namespace/dispatch overwrite.
- RED enum679: native parent emits IAIIC; original Crystal emits AABIC.
- GREEN enum674: 23 HIR checks; enum678/680 emit AABIC and exit 0. Aliases,
  distinct enum owners, integer conversion and real module dispatch are controls.
- Counterexample to broad closure: enum672 full-prelude hashing times out;
  enum676 LLDB identifies a null seed load in Crystal::Hasher.new. enum675
  real LavinMQ compilation traps. Neither is covered by the owner-identity fix.
  Refresh after enum provenance, namespace recovery or dispatch changes.


### Uninitialized aggregate classvar allocation (2026-10-16)
- Invalid uninit682 typed-initializer syntax was rejected by original Crystal;
  it is not regression evidence. Corrected immutable uninit684 uses a separate
  type declaration and assignment.
- RED uninit685: original LADR/0, lazy parent timeout. RED uninit692 eager parent:
  build 0, runtime 139. LLDB enum676 independently locates the null Hasher seed.
- GREEN uninit689/690: full/no prelude LADR/0, matching Crystal; uninit692 eager
  candidate also LADR/0. Full-prelude uninit691 hash consumer matches AI/0.
- uninit695 exposed an empty Bash array under nounset; it did not execute the
  regression. Corrected uninit696 prints its explicit PASS in both modes.
- Scoped verdict ROBUST for backing storage in these consumers. Neither these
  outputs nor structural allocation prove seed entropy or whole LavinMQ parity.
  Refresh after classvar init or aggregate representation changes.


### Materialized recursive union macro reflection (2026-10-16)
- RED macro703: five materialization orders, three projection-cycle errors.
  Array(Field) prewarming alone can hide the failure, so order is part of input.
- RED macro710: original method consumer AA/0; diagnostic parent rejects the
  same recursive projection cycle. This diagnostic guard is not production code.
- GREEN macro714: 17 examples, zero failures/errors, including canonical duplicate
  aliases and an explicit expanded-union type argument. GREEN macro712: AA/0
  matching Crystal; macro716: explicit portable PASS.
- macro713 confirms the same eight unrelated broader projection failures on
  parent and candidate. No claim that the full reflection suite passes.
- macro706/707 top-level macro-for omitted output and cannot certify this fix;
  corrected macro709 uses method-scoped expansion and distinguishes the parents.
- Integrated macro715 reaches protected load_apply access rejection in LavinMQ.
  This closes the observed recursive projection frontier, not LavinMQ parity.
  Refresh after alias registry, runtime canonicalization or reflection changes.


### Full-prelude protected callbacks retain lexical scope (2026-10-16)
- RED protected720: nested Hash/Array method reference; Crystal emits A/0,
  parent compiler rejects protected load_apply in the caller's own method.
- GREEN protected726/727: class A/0 and included-module B/0 match Crystal.
- Guard protected729: both compilers reject a protected method reference from
  an unrelated class. Visibility precedence and rejection remain enforced.
- Portable protected732: explicit PASS for full-prelude AB output plus the
  foreign-owner rejection. All binaries execute through scripts/run_safe.sh.
- protected734: parent/candidate retain the identical Proc-forwarding failure
  among four HIR controls. Existing no-prelude protected callback checks pass
  on both and cannot stand in for this full-prelude discriminator.
- Certificate scope is callback lexical namespace transport, not application
  parity; refresh after block owner, Proc lowering or namespace changes.


### Module instance versus class dispatch (2026-10-16)
- RED module762: Crystal ABBC/0; parent binds the class-method target to a
  distinct instance Def and rejects the conflict. Both Defs share a live arena.
- Narrow trial module749 fixes only the late fallback and remains RED in
  module753/755; module756 also separates the module resolver's receiver paths.
- GREEN module758/759: native ABBC/ABCD match Crystal. Portable module764
  additionally checks reversed binding order BBCA and prints explicit PASS.
- Guards module761: eight passing HIR examples for included extend-self,
  macro-generated extend-self and module setter virtual dispatch.
- Integration module765 reaches unsupported non-empty named hash literals.
  Separate module757/760 compile but Array#sample emits NUL: generated
  Random.thread_default reads null without initialization. RNG parity remains
  open and must not be inferred from this dispatch-only certificate.
- All binaries run through scripts/run_safe.sh. Refresh after module lookup,
  receiver category or selected-target materialization changes.


### Non-empty named hash lowering (2026-10-16)
- RED named768 on module756: original HTTP::Headers fixture prints LavinMQ/0;
  candidate rejects the unsupported non-empty named collection literal.
- GREEN named772 on named767: both print LavinMQ/0.
- Portable named774: five original-first native fixtures compare exact output
  and print explicit PASS. They exercise complex key/value order before new,
  repeated []= calls, container result, constructor mutation of a captured local,
  explicit/bare generic Hash receivers and existing typed empty construction.
- HIR named773: four examples, zero failures/errors/pending.
- Empty concrete receivers and heterogeneous/constant inference remain untested
  adjacent boundaries. Full LavinMQ and Random runtime parity remain open.
- All binaries execute through scripts/run_safe.sh; refresh after literal,
  generic receiver or operand timing changes.


### Module macro classvar declarations (2026-10-16)
- RED random792: three HIR examples, one failure and one error on named767;
  direct/class registration controls pass, generated module declarations vanish.
- RED random793: original-first native getter prints NAA, candidate AA; both
  build and exit zero, so exit status alone misses the skipped constructor.
- GREEN random794: three HIR examples, zero failures/errors/pending on random787.
- GREEN random795: explicit original/candidate PASS with exact NAA output;
  constructor executes once and the second getter returns its cached value.
- Absolute root Thread registration and owner reflection remain separate open
  falsifiers. Older Proc alias check fails equally in random788 and random789.
- All binaries use scripts/run_safe.sh. Refresh after macro-output declaration,
  arena or classvar type lowering changes; this is not LavinMQ runtime parity.


### Module macro absolute class registration (2026-10-16)
- RED random805 on random787: bogus AbsoluteThreadMacroOwner::Thread exists.
- RED random806: Crystal ABCNAAA/0; candidate A/NUL/C/N then abort134 on the
  wrongly nested ModuleMacroCachedOwner::Thread.current stub.
- GREEN random807: one HIR example, zero failures/errors/pending; root method and
  real relative nested shadowing resolve to the intended owners.
- GREEN random808: both compilers explicitly PASS exact ABCNAAA native output,
  including relative macro classes, cached construction and Array#sample.
- Broad random798/801 trials remain RED for separate class-macro/owner-reflection
  examples; those extra trial changes are not part of this repair.
- All test binaries run through scripts/run_safe.sh. Refresh after declaration
  absolute flags, output registration, class naming or lookup changes.


### Macro regex replacement and result reflection (2026-10-16)

- RED random837: 7 semantic examples fail on source random803.
- RED random844: Crystal emits replacements and StringLiteral/MacroId labels;
  candidate exits 0 with unchanged strings and two ASTNode labels.
- GREEN random843: 7 examples, 0 failures/errors/pending on sealed random842.
- GREEN random846: original and candidate explicitly PASS the same seven lines.
- GREEN random851: 33 existing macro method examples pass on random842.
- Broader random849 includes uncommitted split/pair/parse_type WIP and fails
  16 examples; parent random850 cannot compile that WIP (MacroRegexValue absent).
  Neither run establishes a regression or closure for those uncommitted features.
- Guards cover invalid arity/named arguments, pattern/replacement kinds and bad
  regex syntax; positive controls cover i/m/x flags, captures and empty matches.
- Separate random830 command-call syntax still loses macro arguments; keep it
  open and do not attribute its blank output to regex replacement semantics.


### Declaring module owner during early macro expansion (2026-10-16)

- RED random811: Crystal prints four declaration names; parent loses module names.
- RED random816: parent aborts on the missing intended Thread TLS getter.
- RED random818: 2 HIR examples fail before explicit module owner projection.
- GREEN random847: 9 owner/regex examples, 0 failures/errors/pending.
- GREEN random848: original and candidate PASS reflection, thread_cache and kind
  fixtures; actual generated fields and repeated cached getter calls are checked.
- random828 is retained as the earlier failure that exposed missing regex gsub;
  random845 composes the owner changes with the separately verified random842.
- All binaries use run_safe.sh; cache parity is single-thread only. Refresh after
  macro registration, owner lifetime/projection or type-kind dispatch changes.


### Typeof values retain semantic identity through member and call dispatch (2026-10-16)

- RED typeof876 on random845: 6 examples, 1 failure, 4 errors; member lookup
  receives Nil instead of a marked semantic type value.
- RED typeof880 on intermediate typeof865: original union .name() has enclosing
  parentheses, while the candidate's separate call fast path loses them.
- GREEN typeof884 on sealed typeof881: 13 examples, 0 failures/errors/pending;
  includes both syntaxes, semantic markers, active locals and no argument calls.
- GREEN typeof883 on the same host: both compilers PASS identical 11-line native
  output, with union name/to_s/inspect, custom self.name and effectful operands.
- Test and script hashes are pinned in their source manifests/receipts. Earlier
  typeof867/869/873 probes used an incorrect Literal.value test accessor and
  are test-harness failures, not evidence of a compiler regression.
- Refresh on producer metadata, receiver lookup or name-query changes. No
  LavinMQ execution or general type-value transport claim follows from this gate.


### Infer generic constructor parameters from initializer restrictions (2026-10-16)

- RED constructor914 on constructor900: three of 15 HIR examples fail because
  preliminary .new inference still guesses positional actuals or a bare owner.
- RED constructor908: original Crystal prints ProjectionContext(Int32) and 65;
  candidate fails to infer through the concrete generic module application.
- GREEN constructor921 on sealed constructor913: 29 examples, no failures/errors.
- GREEN constructor934 on the same host: original and candidate match 23 native
  output lines; both reject conflicting formal bindings and invalid enum members.
- Independent open falsifier constructor932 on parent typeof881: an explicitly
  instantiated ProjectionContext(Int32) compiles but aborts at an abstract module
  stub. The concrete field type survives; dispatch/fanout still needs repair.
- Invalid harness attempt constructor919 referenced a nonexistent Array spec;
  its failure is not compiler evidence. Refresh constructor gates on solver,
  expression producer, include/ancestor registration or overload-order changes.


### Preserve applied generic module reference dispatch (2026-10-16)

- RED module945 on module938: three applied includer HIR examples error because
  the runtime census contains only erased module identities.
- RED module947 on module943: one of eight examples fails; a qualified applied
  module key alone does not register its Generic descriptor as a MIR reference.
- Refuted module943 mixed native case: semantic index pollution truncates type
  names and makes a namespace Context#value call itself. Use the runtime census.
- RED module951 on module948: the smaller mixed native case passes, but adding
  a second namespace specialization aborts at Action(S)#value. Missing concrete
  bodies expose the obsolete parenthesis-free module fanout path.
- GREEN module958 on module956: 54 HIR/MIR examples, no failures/errors; includes
  concrete/transitive/qualified census, applied-only keys, short-name collisions
  and non-module value/pointer header guards.
- GREEN module959 on module956: original Crystal and candidate agree on 24
  output lines in each specialization order and both member-call syntaxes.
- Open: struct/value module view ABI and late include/descendant registration.
  Refresh on include census, namespace, kind classification or demand changes.


### Preserve pointerof source pointee identity (2026-10-16)

- RED pointer1026 on parent module956: three pointerof source-identity examples
  produce one failure (Proc signature erased) and two errors (raw ivar pointer
  has no concrete pointee descriptor).
- GREEN pointer1021 on pointer1020: all three HIR examples pass; ivar pointer
  identity is concrete while arithmetic remains byte based and field loads are
  absent from the address path.
- GREEN original-first pointer1028: eight native outputs match Crystal for
  generic/inherited ivars, nested pointers, local/ivar Procs, String bytes,
  struct field writeback and reference-field writeback.
- GREEN pointer1024/pointer1027: CFG alias/writeback and heap-promoted aggregate
  address guards. Scoped adversary ROBUST for the tested storage corridor.
- Existing RED pointer1022 on parent module956: String missing-body call-result
  identity is inconsistent with its UInt8 pointer descriptor (one of three
  examples); do not count it as fixed by the pointerof producer repair.
- Open: escaped-address lifetime, foreign aggregate/union storage and full
  LavinMQ compilation/test parity. Refresh after storage, interning or ABI edits.
