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
| B-INFERRED-BLOCK-RESULT | Exact calls retain transient block hints alongside authoritative declaration bindings; included source and case yield dependencies distinguish wildcard result shapes | ast_to_hir.cr apply_deferred_module_context; lower_call included-source lookup; generic_proc_annotation?; yield_in_value_position? | inferred_block_return_shape_repro.sh COMPILER | current | [FALSIFIABLE] Flat2053 matches original ABCD/ABABABAB/ABCDE; the immediate pre-case candidate aborts after A and earlier flat_map confuses array element types. Deferred-binding, yielding-macro and raw-callback identity neighbors pass. Dynamic Proc locals remain RED. Fresh S2 stops at comparator UInt64 inference; the bundled Hash#any? neighbor fails on both parent and candidate. LavinMQ parity remains open. |
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


### Preserve backend String byte-pointer contracts (2026-10-16)

- RED string1035 on parent pointer1020: one of three String pointer-identity
  examples fails. RED string1036 after HIR repair: native bytes are correct but
  String.new copies neither string. RED string1044: one of three backend cases
  selects a zeroed generic allocator instead of the native String copy body.
- GREEN string1045 on string1040: nine HIR/MIR examples, including source-method
  priority, unrelated names, existing pointerof cases and wrong ABI/owner/pointee.
- GREEN original-first string1043: UTF-8, ASCII and empty byte roundtrips agree
  under full/no prelude; both source call spellings and override guards agree.
  Scoped adversary ROBUST for these byte contracts.
- Open: UTF-8 character-count metadata, broad native-contract coverage and full
  LavinMQ parity. Refresh after method lookup or native/missing-body changes.


### Preserve hexadecimal f digits during numeric normalization (2026-10-16)

- RED number1054 on String1040: 0xf0 parses as zero, one of three examples fails.
- GREEN number1055 on number1053: parser hex digits, signed/unsigned suffixes
  and float suffix controls all pass.
- GREEN original-first number1056: 17 native values agree with Crystal under
  full/no prelude; includes hexadecimal f32/f64 tails and arithmetic.
  Scoped adversary ROBUST for suffix identity; refresh after numeric parsing
  changes. Overflow/range correctness and LavinMQ parity remain open.


### Keep C-string character length lazy (2026-10-16)

- RED string1060 on number1053: C-string String#size returns byte count for
  multibyte data. GREEN string1058 on string1057: 15 valid/invalid/truncated/NUL
  sequences and repeated reads match original Crystal under full prelude.
- GREEN string1059: existing full/no-prelude byte and source-body priority guards.
  Scoped adversary ROBUST for the native constructor's lazy metadata contract.
- Open: no-prelude String#size and other native String metadata producers.
  Refresh after constructor, layout or String#size lowering changes.


### Preserve receiver semantics across union argument arms (2026-10-16)

- RED equality1108 on parent string1057: binary class == with a self|Tuple RHS
  reaches a bodyless combined target. RED equality1094 on intermediate1091:
  splitting the argument still loses subclass overrides (TFTFFFFF vs TFFTTFFT).
- GREEN equality1109 on equality1098: all 44 original-first results match in
  full/no prelude. Includes explicit operators, reversed overload declaration
  order, self restrictions, forwarding, virtual overrides and Int32/Char returns.
- GREEN equality1104-1106: typed !=, class-argument and union-receiver guards.
  Scoped adversary ROBUST for declared call shapes; pending Proc materialization
  and LavinMQ parity remain open. Refresh after union/lookup/virtual ABI changes.


### Preserve call shape when local overload lookup reaches ancestors (2026-10-16)
- RED ancestor1138 on equality1098: inherited named permissions call reaches a
  native bus error after local overload lookup loses the applicable ancestor.
- GREEN ancestor1135 on isolated ancestor1133: ten no-prelude outputs plus full
  Hash permissions agree with Crystal; default/named ordering, splat, block,
  local narrow/broad overrides and later ancestor reopening are guarded.
- GREEN ancestor1139: all 44 original-first union equality outputs match under
  full/no prelude. Scoped adversary ROBUST for these shapes; no LavinMQ closure.
  Refresh after lookup, self-call inference, numeric hierarchy or shape changes.


### Preserve declaration context for block-dependent result annotations (2026-10-16)
- RED blockmap1164 on ancestor1133: the LavinMQ permissions callback reaches
  Pointer$H$IDX$$Symbol after included map result inference loses its annotation.
- RED blockmap1150 and namespace-only blockmap1151: namespaced Envelope(U)
  resolves as a global decoy, prints an invalid native value and times out.
- GREEN blockmap1163 on isolated blockmap1152: ten original-first native outputs
  match pinned Crystal 1.21, including namespace collision, wrapper return ABI,
  alternating module type bindings and a local override.
- GREEN blockmap1166/1167: eleven ancestor cases and all 44 full/no-prelude union
  equality results. Scoped adversary ROBUST; Channel.select and LavinMQ remain
  open. Refresh after declaration context, annotation or block inference changes.


### Preserve source generic restrictions and Proc adaptation phases (2026-10-16)
- RED generic1171 on blockmap1152: the original accepts the parent-typed Proc
  input, while the candidate reaches an accept_parent_input stub and aborts.
- GREEN generic1170 on generic1165: 22 pinned Crystal 1.21 native outputs plus
  incompatible-input rejection, including declaration-order reversals, crossed
  restrictions, nested Procs, abstract numerics and generic-owner bindings.
- GREEN generic1175: 47 source admission/numeric HIR examples, including direct
  serialized targets, memoized misses, unknown arguments and valid alternatives.
- GREEN generic1169/1173/1174: ten block outputs, eleven ancestor cases and 44
  full/no-prelude union results. Scoped adversary ROBUST; Proc phase ordering for
  excluded call shapes and complete LavinMQ parity remain open. Refresh after
  source restriction, alias, candidate ordering or emitting-handoff changes.


### Preserve absolute names inside contextual generic arguments (2026-10-16)
- RED rooted1253 on generic1165: Array(::AdmissionView) is captured by the
  lexical AdmissionScope::AdmissionView declaration and a valid call is rejected.
- GREEN rooted1254 on rooted1250: absolute and nested generic arguments produce
  31/21/41 as Crystal 1.21 does; lexical-only and root-only controls produce 11
  and 31. Both compilers reject an unrelated namespace implementation.
- Scoped adversary ROBUST for contextual generic arguments. Signature-recovery
  colon handling, included forall identity and LavinMQ remain open. Refresh
  after contextual name resolution or cache changes.


### Keep canonical generic identities through annotations and storage (2026-10-16)
- RED generic1293 on rooted1250: canonical root arguments are captured by
  lexical class/enum homonyms in direct and composite bound annotations.
- GREEN generic1294 on generic1292: five original-first fixtures match Crystal
  1.21 on 22 native lines, including mixed bound/source fields and late nested
  declarations. generic1295 keeps the old forward-nilable layout behavior;
  generic1296 passes 43 HIR examples; generic1297 retains absolute-name controls
  and rejects an unrelated namespace on both compilers.
- Scoped adversary ROBUST for generic registration, annotation and field storage.
  Residual falsifier generic1282/1290: Box(Payload).new(Scope::Payload.new) must
  reject as Crystal does; compatibility still loses bound identity. Ordinary
  typed fallback after PICK=nil and LavinMQ SelectContext union admission remain
  open. Refresh after binding, name-cache or nullable layout changes.


### Canonicalize Union constructors and preserve admitted generic variants (2026-10-16)
- RED generic1343/1292: Union#id and erased Context#id stubs; wrong nominal
  family and wrong applied argument are both admitted incorrectly.
- GREEN generic1342/1339: original-first union storage and bare generic body
  fixtures match Crystal 1.21 on 8 native lines; both invalid unions reject with
  ordinary diagnostics and no output binary. Invalid binaries are never run.
- GREEN generic1346: 62 HIR examples cover stale nominal caches, duplicate and
  nested union arms, StaticArray/tuple-splat substitution, unresolved arms,
  nullable equivalence, per-arm admission and exact runtime specialization.
- GREEN generic1347/generic1351: existing Proc restrictions and 22 bound annotation
  native outputs remain intact. Scoped adversary ROBUST for this slice.
- Open: abstract Int subsumption, transitive included bindings and full LavinMQ.
  Constructor trace generic1350 shows a spurious positional block demand from a
  named self-forwarder; close the producer contract before enabling strict
  constructor rejection. Refresh all dependent evidence on union cache,
  restriction or exact-runtime-parameter changes.


### Infer bare generic class-method owners independently of cached siblings (2026-10-16)
- RED generic1365/1349: explicit Int32 then bare String method prints 7/16;
  LLVM defines the String-named specialization with i32 parameter and return.
- RED generic1382/1339: native matrix times out after first output and admits
  a wrong nominal family. GREEN generic1381/1376: 15 native results, structural,
  multi-param, default and ambient cases, both overload orders, and rejection
  of wrong bare family and wrong explicit applied argument.
- GREEN generic1383: 73 HIR examples; generic1387/1388: prior union/Proc corpora.
  Scoped adversary ROBUST for tested positional calls. Two alias-binding HIR
  failures are pre-existing (generic1380 parent, generic1379 candidate).
- Open union1385: valid String|Array(String) fails a final single-overload
  source check; certify complete per-arm dispatch rather than relaxing source
  restrictions. Open generic1371: optional Proc boxing times out. Refresh on
  owner inference, ordering, registration or runtime ABI changes.


### Admit complete union argument source variants with deferred ABI contracts (2026-10-16)
- RED union1440 on1376: valid matrix, inline fetch and generic inline fetch
  each fail single-overload rejection. GREEN union1423 on1412: 26 native outputs
  match Crystal 1.21; complete three-arm/Nil, mixed returns, both source orders,
  inherited/generic declarations and single argument evaluation; uncovered Int32
  arm rejects in both compilers.
- GREEN union1439: 82 HIR examples, including exact deferred target contracts;
  mutated target return and retargeted call reject before MIR. Scoped adversary
  ROBUST for the tested source identity and argument/result ABI boundaries.
- Frontier lavin1418/channel1415: HTTP::Headers#concat passes; VHost#add_policy
  still receives Nil|Hash. RED noreturn1422 isolates an unannotated raise wrapper
  that fails to kill a guard continuation. Separate RED union1399/1376: direct
  Int64|String printing loses the integer arm. Neither is union feature closure.
- Refresh on source admission, deferred queue, retained contexts, RTA call repair
  or ABI changes. Broader/default/named/splat/block deferred shapes remain open.


### Propagate proven completed direct-call NoReturn effects (2026-10-16)
- RED noreturn1464/1412: unannotated bad_request -> halt_request -> raise
  does not exclude the failing guard continuation; consume receives Nil|Hash.
- GREEN noreturn1463/1432: guard output and overload/conditional/rescue/nil
  runtime controls match pinned Crystal 1.21; returning, conditional and nil
  Hash guard negatives reject with concrete type diagnostics on both compilers.
- GREEN noreturn1466: 82 HIR examples. Delta adversary ROBUST within these
  selected direct-call boundaries. Four String negatives and rescuing Hash
  remain pre-existing admission gaps on parent and candidate; complex CFG
  probes are inconclusive due an unrelated shared stdlib sort-block failure.
- Frontier lavin1443/channel1441: VHost#add_policy passes; synthetic
  IO::Memory.new rejects Slice(UInt8)|String. union1453 is the same short
  rejection, while Bytes[] variant union1451 separately produces 0/0 vs 4/2
  after incorrectly inferring String|UInt8 and selecting a capacity allocator.
- Refresh after selection, body state, exception/CFG or narrowing changes.


### Retain exact source identity for materialized initializer specializations (2026-10-16)
- RED union1484/1432: scalar-primed IO::Memory.new loses the initialize
  declaration for a Slice(UInt8)|String union, although the body exists.
- GREEN union1480/1471: both union arms and scalar factory/slice controls
  match Crystal outputs 4/2/7/5. GREEN union1481: 85 HIR examples, including
  rejection after initializer ABI mutation and source-arena removal.
- Scoped delta verdict ROBUST for existing exact-ABI materialized allocators.
  RED union1474: unprimed demand remains absent. OPEN union1479/1476:
  parent and candidate both accept Bool|String and coerce it to a capacity
  argument; Crystal rejects it. These are separate surviving falsifiers.
- Lavin1475/channel1473 passes IO::Memory and reaches nullable Proc admission
  in HTTP::Server.build_middleware. No broker binary or test parity exists.
- Expiry: source/body/arena/context/ABI changes require replay of these probes.


### Share Proc syntax between source admission and TypeRef construction (2026-10-16)
- RED proc1490/1471: four source restriction checks reject valid arrow Proc
  spellings while equivalent TypeRef construction already succeeds.
- RED proc1495/1471: qualified callback/result-discard portable reproducer.
- GREEN proc1492/1491: eight source checks; GREEN proc1496: 93 HIR examples.
- GREEN proc1494/1491: eight original-first native outputs and rejection of
  wrong Proc input type, arity and explicit result. Scoped adversary ROBUST.
- Lavin1497/channel1493 passes nullable build_middleware admission and reaches
  IO::Memory#write_byte receiving a JSON value union instead of UInt8.
- No broker executable/parity claim. Expiry: Proc grammar, alias/context or
  restriction changes require replay of the original-first controls.


### Prove builtin/container case disjointness without target descriptors (2026-10-16)
- RED case1511/proc1491: four known container kinds yield unknown versus
  descriptorless builtins. RED case1527: impossible UInt8 arm rejects Array|Int64.
- GREEN case1526/case1509: ten original-first native outputs across four
  container kinds and a reachable UInt8 arm. GREEN case1519: 115 HIR examples.
  Scoped disjointness adversary ROBUST; conservative unknown/hierarchy cases
  and effectful case-condition controls retain their previous behavior.
- Surviving parent failures: five implicit-Nil/Phi examples (case1516/1517),
  restricted free functions accepting UInt8 for String/Array(Int32)
  (case1521/1525), JSON scalar runtime exit 132 (json1500/json1524).
- No broker or test-parity claim. Expiry: changes to builtin identity,
  container representation or static case proofs require replay.


### Preserve nullable Proc and unknown branch inference (2026-10-16)
- RED nullable1532/case1509: nullable Box.capture emits FF instead of TF.
  RED nullable1539: eight of ten focused inference examples fail.
- GREEN nullable1542/nullable1529: seven original-first native fixtures, with
  HIR evidence for nullable Proc producers and their callsites. GREEN
  nullable1538: ten unit examples; nullable1533: 115 related HIR examples.
- Adversaries include recursive unknown arms, empty elsif/else, missing else,
  terminal returns, unknown case/ternary/rescue arms, and untyped Proc inputs.
  Scoped verdict ROBUST. The earlier unknown-only proposal failed the empty
  branch oracle and was superseded, not accepted as a partial solution.
- No LavinMQ parity claim. Expiry: branch-inference, Proc-signature or terminal
  Return changes require replay of these controls.


### Materialize unknown bare-call results before caller typing (2026-10-16)
- RED return1577/nullable1529: a bare rescue call returns String in its body
  but its caller prints a blank line through the stale Void argument contract.
- GREEN return1576/return1567: six original-first native fixtures covering the
  regression and bare self/default, class, module, top-level/default and main.
- GREEN return1569: two prior NoReturn native fixtures and three nullable Hash
  rejection guards. GREEN return1570: seven nullable Proc oracles. GREEN
  return1571: 125 HIR examples. Scoped completion adversary ROBUST.
- OPEN return1574: puts evaluates an explicit union-returning call twice;
  this is distinct from completing a previously unknown bare-call result.
- No broker or upstream parity claim. Expiry: changes to lazy demand, caller
  result typing or completion guards require replay. Manifest ba8a274f2cc2de70cfd0087218b86e29206ed056b618dd822adba91026991013.


### Certify wholly bottom concrete generic union calls (2026-10-16)
- RED union1589/return1567: all-raising generic class union rejected as an
  unresolved return. GREEN union1588/union1582: six matching original-first
  member/call/wrapper outputs and two retained mixed/rescued guards.
- GREEN union1590: five certificate checks, including returning descendants,
  missing body evidence, block and splat boundaries. GREEN union1592: prior
  NoReturn native/Hash guards. GREEN union1593: 130 HIR examples. Scoped ROBUST.
- OPEN union1564: broader descendant result erasure also exists on the parent.
- OPEN lavin1581/1587: new integrated channel materializes non-Flags enum each;
  locate the responsible delta before claiming further LavinMQ progress.
- OPEN final gate: fresh source-revision bootstrap and produced-stage LavinMQ
  runtime/upstream parity. Manifest 3f3f824e6a14973dcc9fc9bc908a58f09e5ae8002a35008b2416100a3ccf74dc. Expiry: effect, selected-source
  identity, dispatch, union ABI or demand changes.


### Evaluate intercepted print arguments once with their lowered types (2026-10-16)
- RED print1603/union1582: union_puts duplicates each effect and loses the
  numeric value. GREEN print1599/print1596: six matching original-first
  outputs cover both union arms, effects, Nil, Void, NoReturn and Int64.
- GREEN print1600: 130 focused HIR examples. Scoped ROBUST.
- REFUTED print1575 single-arm sufficiency: print1583/1584 found the numeric
  union arm still missing. print1586 adds ordinary virtual-target demands;
  print1596 composes the completed bare-call and wholly-bottom changes.
- OPEN lavin1601: the bare-call delta alone reproduces extra non-Flags enum
  each materialization. The print delta is not a necessary cause.
- OPEN fresh bootstrap and produced-stage LavinMQ functional/upstream parity.
  Manifest 406d797dd63957b34631b1f62631ef4f0af11e88566b3e78af6df54a0d69e93c. Expiry: print interception, argument binding,
  virtual demand or return ABI changes.


### Preserve omitted literal Nil default provenance (2026-10-16)
- RED nil1643/print1596: an omitted literal Nil backtrace creates unrelated
  LibPCRE2::Error#each demand. GREEN nil1640/print1613: five original-first
  stdout/stderr comparisons, covering both call orders, explicit Nil/Array,
  module forwarding, local reassignment and Crystal.print_error_buffered.
- GREEN nil1641: 130 HIR examples. Scoped ROBUST for literal-default fallback.
- REFUTED necessity of a foreign ambient T for this Enum failure: default
  reducer uses no custom generics and no OpenSSL; it still fails on the parent.
- OPEN buffered1636: parent with typed defaults misbinds *args/named slots.
- OPEN buffered1614/1615: duplicate SSL_get_error LLVM declarations.
- OPEN lavin1639: next integrated error is IO::Memory#write_byte receiving
  Char | JSON::Any | Tuple(String, JSON::Any).
- OPEN s2_print1606: Array(String) -> Enumerable(String)? admission; current
  S3/S4 convergence and produced-stage LavinMQ functional/upstream parity.
  Manifest c96214e5769ab5cd7a2977d287bd125da18b61f29b53b2d0bfbe432f14a592d9. Expiry: default provenance, argument binding,
  specialization or virtual-demand changes.


### Preserve captured locals through inline try/tap (2026-10-16)
- GREEN capture1680/capture1679: six original-first native stdout/stderr
  fixtures cover direct try and tap, nil tap and try, nullable captures and
  results, proc syntax, early return, nested try/tap, and an enclosing loop.
- RED capture1682/print1613: direct_try prints trace/before instead of
  trace/one/two and after/1. GREEN capture1681: 130 HIR examples.
- Scoped adversary ROBUST for tested captured-local continuation shapes.
  String.build parent control capture1662 was already GREEN.
- OPEN args1676/args1667: parent typed splat loses an argument; packing trial
  emits a stub. Current bootstrap and produced-stage LavinMQ parity stay open.
  Manifest adf2bf5f78f5acca641b592c705f23a564cf073b40d0331751a0e8c1a38ea43e. Expiry: scope, branch-merge, capture, or stdlib changes.


### Compare initialize allocator and explicit new source priority (2026-10-16)
- GREEN ctor1689/ctor1684: original-first broad Int/Number wrapper cases,
  exact Int64 wrapper, reversed incomparable declaration order, equivalent
  alias restrictions in both orders, and a cross-arena exact wrapper.
- RED ctor1690/capture1679: broad wrapper and alias-wrapper-first selected
  instead of initialize-derived allocator. GREEN ctor1687: 130 HIR examples.
- Scoped adversary ROBUST. OPEN: cross-arena equal/incomparable ties and
  excluded named, block, splat, tuple or multi-argument constructor shapes.
- RED json_ctor_relation_20261016: JSON::Any scalar is not closed by this fix.
  Current bootstrap and produced-stage LavinMQ parity remain open. Manifest
  6c1df4d1076a51cad95c203404d64b531b3dac373ccc50024c243adce1a0daf5. Expiry: restriction/order, arena, selection, or stdlib changes.


### Prove registered source carriers disjoint from concrete scalars (2026-10-16)
- GREEN disjoint1708/disjoint1698: struct/class union arms omit impossible
  scalar bodies; a real UInt8 arm survives with its payload. Original-first
  stdout/stderr agreement. RED disjoint1713 exact ctor1684 parent.
- GREEN disjoint1709: 135 HIR examples. RED disjoint1710 parent: 3/5 new
  examples fail. Ancestor carriers, unknown descriptors and Pointer guarded.
- Scoped ROBUST for registered source carriers versus concrete scalar builtins.
  String, modules and erased Pointer are outside the new proof.
- RED io1712: pre-existing write_byte/puts ordering mismatch, separately open.
  Current bootstrap and produced-stage LavinMQ parity remain open. Manifest
  8cc553d5cf15bf27de935d7ee0ec0ccaaf4bffabd7b16589c79af8faec65c373. Expiry: hierarchy, builtin parents, predicate/narrowing or stdlib.


### Validate ordinary named calls against source external labels (2026-10-16)
- GREEN named1724/named1716: external labels, argument reordering, defaults,
  ordinary labels, **kwargs, and direct/inherited block calls match original
  Crystal; eight invalid internal/unknown-label shapes are rejected by both.
- RED named1725 exact disjoint1698 parent: admits direct_internal_label.
- GREEN named1726: 135 focused HIR examples. Scoped ROBUST for ordinary named
  calls. String.build special lowering remains separately open, as do current
  bootstrap and produced-stage LavinMQ parity. Manifest fc447cf488ebc1cab04deef54cb4d8189f27c5c18ed17f2cfb1d3092c6707099.
  Expiry: parameter label representation, resolver, inline yield or named pack.


### Preserve concrete union carriers in array literals (2026-10-16)
- GREEN union1746/union1745: empty and returned nonempty struct union arrays,
  mixed struct/Int32/Nil with source mutation, nullable inherited reference.
- RED union1747 exact named1716 parent: first case prints B instead of A.
- GREEN union1750: 137 focused HIR examples, including concrete UnionWrap and
  already-union carrier reuse. RED union1751: exact parent fails only the
  concrete-wrap case. Scoped ROBUST. Manifest 18a1f9248a33b971b6b96afc0ce575599d925e5b4b55b5a748b16d5f0f62276c; host b7aacdbd5461ca777c425cdef9fdd97c93a7e3a502b4e34862de41fefe8179e3.
- OPEN union1744 basic JSON: Empty JSON after initial state-tag correction.
  Bootstrap and produced-stage LavinMQ parity remain open. Refresh after array
  lowering, union coercion, MIR allocation or payload ownership changes.


### Bind postfix member calls to the yield result (2026-10-16)
- GREEN yield1761 on sealed yield1759: four original-first native families
  compare stdout/stderr for nested yields, whitespace/newline/do forms,
  explicit/grouped arguments, retained tap results and actual argument calls.
- RED yield1764 exact union1745 parent: ABC becomes ACB.
- GREEN yield1760 seven AST examples; RED yield1758 exact parent has three
  receiver-shape errors. Original AST oracle yield1755 confirms ownership.
- GREEN yield1768: 2238 selected tracked parser examples, zero failures/errors,
  one existing pending. Modified local suites and untracked WIP were excluded.
  Scoped ROBUST. Manifest 3e01ac0eb917a7c9ce2147c6a61ca147ba338ea2499dc76968718477261f91b1; host eab90be1b7514d6368b60e624a05dc87978888bc2d58a219e833f037f05757a1.
- OPEN JSON, buffering, current bootstrap and produced-stage LavinMQ parity.
  Refresh after yield arguments, postfix members, trivia or block binding.


### Retain concrete receivers through selected Object wrapper calls (2026-10-16)
- GREEN json1786 on sealed json1777: three original-first native families
  compare exact stdout/stderr for direct/yielded self dispatch, interleaved
  sibling receivers and a lexical Token shadow at the concrete caller.
- RED json1787 exact yield1759 parent: direct/yielded fixture exits 138.
- BASELINE FAILURE json1788 candidate and json1789 exact parent: the same
  nine tracked Object-filter HIR examples pass; the existing nilable-enum
  case-equality guard fails identically. No full-suite green claim.
  Scoped ROBUST for reference-wrapper receiver transport. Manifest df8894909e1a9f52804c3158c76e2a18b2809bd80aa3e76865509c50dc4cdc60; host 6b6c06abd9bd310f5514918b62030550b282f01bf7210da6c299a53f1246b806.
- OPEN generic inherited cross-method dispatch, typed-to-arity fallback,
  nilable enum guards, full JSON, current bootstrap and LavinMQ parity.
  Refresh after wrapper admission, selected-call ownership, arena, namespace
  or specialization suffix changes.


### Keep selected deferred callees through final target rematching (2026-10-16)
- GREEN json1821 on sealed json1811: four original-first native fixtures,
  exact stdout/stderr; the added annotated case invokes zero-argument wrappers
  from main and a typed nested caller over generic and ordinary receivers.
- RED json1822 on exact json1777 parent: three existing controls pass, then
  annotated_zero_arg exits 138. Annotation-free control json1802 is A/A;
  annotated json1806 is original A / parent 138. Trace json1810 shows the
  selected concrete target Pending and queued before final ancestor rematch.
- Guards retain lexical source scope and sibling receiver isolation. The
  selected-target guard requires both Pending state and a present queue item.
  Scoped ROBUST for the scheduling contract. Manifest aa5828b6d8acae75382b2aecc3475aa24e7389b111511a85d13d14fb10e384c2; host fd5a2c6bb5716f3ca0216261dd7f3dc374c7a72c7892da82d6a16995c1e23ee5.
- OPEN json1819 no-parentheses member selection, json1812 concrete JSON
  helper suppression, current bootstrap and LavinMQ parity. Refresh after
  lookup, worklist/state or final rematch changes.


### Retain concrete Object-wrapper receivers for member calls (2026-10-16)
- GREEN json1830 sealed json1823: six original-first native fixtures, exact
  stdout/stderr; minimal annotated member call plus generic/ordinary siblings,
  nested callers and lexical source guards. RED json1832 exact json1811 parent:
  four prior cases pass, then isolated annotated_member exits 138.
- The expanded member scope fixture passed on the parent (json1826) and is
  only a regression guard; other demands can mask the missing handoff.
  Scoped ROBUST for member receiver selection. Manifest 6ab6d2a44ed7a29fd1e103d8918dce2b2078af4a4ee33f041b58d402d466b87e; host a7c0b64ae6e8763aa95f1ce07f100255dc0e1244665f354746657e7cd47a732d.
- OPEN helper-filtered JSON body demand and current bootstrap/LavinMQ parity.
  Refresh after member selection, wrapper admission or arena transport changes.


### Retain source-selected wrapper targets across deferred body demand (2026-10-16)
- GREEN json1838 sealed json1834: seven original-first native fixtures with
  exact stdout/stderr, including helper-filtered explicit zero-argument calls.
  RED json1839 exact json1823 parent: six controls pass, new case exits 138.
- The exact retained target is admitted by the existing structural wrapper
  predicate. Global RTA/helper filtering remains active; the ordinary emitted
  call sweep supplies demand. Scoped ROBUST for this identity boundary.
  Manifest cb17812b3f04f58039ab270bac08f557b1d8a8ef06f6ea35c26d6d54f41d1836; host d9ea1ea8fd01c3b6d1aac56c0c0b3a4a0adc10e7153ea4f7a8c59e44740da817.
- OPEN normal-prelude full JSON, current bootstrap and LavinMQ parity. Refresh
  after selection, wrapper admission or missing-target demand changes.


### Retain class references published by synthesized Array append (2026-10-16)
- GREEN array1845 sealed array1841: direct class append, capacity-growth class
  append after caller-local release, and scalar guard; original-first exact
  stdout/stderr. RED array1842 exact json1834 parent: direct prints X, not A.
- Agent's isolated direct and growth parents also print X; class-only candidate
  prints A. LLVM has one retain at the common slot store. Scoped ROBUST for
  TypeKind.Reference values in ptr-backed synthesized append. Manifest aea7f1ea28c80b7803398deeb834985b6d1b152ae3ea3d969809ca5738b50950; host cc7d89542be7a77df8d362da257bcf738acfbb26a23e8e15a8b6a9130e7581ce.
- OPEN Array-kind and aggregate child ownership, fresh bootstrap and LavinMQ
  parity. Refresh after append synthesis, type classification or RC changes.


### Preserve postfixes in spaced parenthesized command arguments (2026-10-16)
- GREEN parser1867 sealed array1841_spaced_parenthesized_argument_final:
  original-first native assertions for bare/member/keyword command arguments,
  chained members, indexes, binary suffixes, multiple grouped arguments,
  adjacent explicit calls and a newline boundary; exact empty stdout/stderr.
- RED parser1868 exact array1841 parent: native abort at misparsed
  `expect_two$ParenBox`. Scoped ROBUST for this grammar boundary. Manifest 1ec5f1d623f9820756a525127e83f1ad54611f22bc7e017b130f731f4a659fe7; host cbc7a0f65770f957e1d08f68619c61e7cb5abb5e0c48e2deefd0760d089d9bc2.
- Refresh after command-call, parenthesis or postfix parsing changes. IO
  runtime, fresh bootstrap and LavinMQ test parity remain open.


### Match nested field reads to the field storage policy (2026-10-16)
- GREEN file1877: sealed file1869_nested_field_slot_policy_candidate,
  nested_struct_field_slot_policy_repro.sh compares exact stdout AB and empty
  stderr against original Crystal for pointer-carried and inline child structs.
- RED file1878: exact parser-fixed parent differs at the first stdout byte.
- Scoped ROBUST for child-slot read/store symmetry. Source manifest 6cb6e3bdbc808d8c9867532929d513dafb4e754c622efda52c41679a1df947e6; host d4ef999c6408f3cee2d95279403d96781d169a6c37dd3f7b49b6f1b01e2e3a64.
  Refresh after layout or field-lowering changes. File.close, bootstrap, and
  LavinMQ parity remain open.


### Preserve source named/rest binding through ABI packing (2026-10-16)
- GREEN caller1967: sealed caller1966_named_rest_scope_and_ancestor_guards;
  named_rest_argument_binding_repro.sh has twelve original-first exact stdout
  and empty runtime stderr cases: restrictions, overload order, forwarding,
  evaluation/default scope, bare named separator, inheritance, and recursion.
- RED caller1968: exact file1869 parent misbinds named-rest forwarding.
- Scoped ROBUST for the non-block, non-double-splat source-binding slice.
  Source manifest cb10c6312ef8c9c06346ca7c3007ff30163ff51cf5135bba061174522e75afaa; host 87b2034bc14df31d6e96366fca429931289639860d91b41c10ba9408528eb497. Refresh after source selection, locals restoration, or ABI changes.
  Deferred includes/contextual Symbol shapes and bootstrap/LavinMQ remain open.
