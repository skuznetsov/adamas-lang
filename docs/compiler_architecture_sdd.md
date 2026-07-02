# Compiler Architecture Frontier SDD

Document status: ACTIVE FRONTIER SDD. Behavior-neutral architecture slices are
landing as bootstrap control gates. This is not approval to start a broad
refactor while the current `s2b`/`s3b` bug frontiers are still moving.
The authoritative current decision surface is the "Active Architecture Board"
below. The older "Current next-slice decision after ..." paragraphs are kept as
historical ledger entries and must not override the board.
Slice 0k-BE adds a tranche selector on top of the board: the next production
code slice must declare whether it is `contract-owner-migration`,
`semantic-service-extraction`, `cleanup/delete`, or
`bootstrap-emergency-with-ledger` before editing code.
Slice 0k-BH adds a narrower pause gate after the 0k-BG parser falsifier:
the command-call parser frontier may get one bounded closure attempt, but a
second parser loop, adjacent parser regression, or broadened command-call
precedence work must stop and return to the split-H6 / TypeValue-owner route.
Slice 0k-BI takes that split-H6 route: it adds a TypeValue-core guard that
excludes the parser-confounded direct no-parens command-call row, leaving the
command-call frontend guard as a separate measured-red frontier.
Slice 0k-BJ adds the pre-implementation TypeValue owner-fact design gate:
the next code slice must prove it is replacing the old type-visible authority
edges, not just making the H6-core output rows green.
Slice 0k-BK is an architecture pause checkpoint after the hostile self-review of
recent repeated patterns. Production code remains paused. The next movement is
valid only if it declares whether it is (a) the already-admitted H6-core
`contract-owner-migration` for a HIR-owned `TypeValue` / `RuntimeTypeIdentity`
fact, or (b) a docs/planning consolidation that retires or tightens stale
architecture lanes. A fresh backend forwarder, target keepalive,
materialization rescue, `NamedTuple`/`Tuple` rendering patch, global
ambient-map policy change, parser precedence loop, or `BlockOwner` rollback is
not architecture progress unless a new SDD slice first proves it replaces a
named authority edge with an owned fact and a falsifier.
Slice 0k-BL converts that pause into an execution ladder. A local
`TypeValue` / `RuntimeTypeIdentity` WIP was quarantined before this docs-only
slice because even an admitted behavior lane can become tail-chasing when it is
continued by inertia. The next production slice must pass the ladder in
Slice 0k-BL: choose one active-board row, name the old authority edge, name the
owner fact/service, enumerate producers and consumers, run the smallest
measured-red baseline first, and state which generated-stage gate it moves.
Green focused rows are not bootstrap progress unless this chain is present.
Slice 0k-BM is the first post-ladder production slice: it implements the
H6-core `RuntimeTypeIdentity` owner fact, makes the H6-core and B3 guards
strict-green, and records dynamic multi-variant union `.class` as a separate
H8 pre-s2-clean residual. The owner fact deliberately separates type identity
from string materialization: explicit type literals carry identity but are not
stringified as call arguments unless the producer marks
`runtime_stringification_required`. It does not claim full old-H6, green `s2b`,
or green `s3b`.
Slice 0k-BN is a docs-only generated-stage checkpoint after 0k-BM. A fresh
stage1 can build a produced `s2b`, but that produced compiler compiling a
full-prelude `puts 42`/hello source fails at the transition into LLVM emission:
default workers report `parallel emission failed: Invalid bound for rand: 0`
and then hit the 4096MB `run_safe` RSS limit, while
`ADAMAS_LLVM_WORKERS=1` removes that worker symptom but still exits 139 after
`pass3 after lower_main call`. This selects a generated-stage
`LLVMEmissionSession` classification lane before more production code.
Slice 0k-BO makes that lane executable with
`scripts/generated_stage_llvm_entry_classifier.sh`. The classifier is a
measured-red/current-frontier gate today and a future clean gate through
`REQUIRE_CLEAN=1`; it does not change compiler behavior.
Slice 0k-BP is a docs-only architecture freeze after hostile review of the
post-0k-BO decision. It pauses production symptom fixes from the B4 crash stack.
The B4 classifier remains the active bootstrap pressure gate, but the next
architecture movement must first define the owner boundary it is meant to
exercise. That boundary is tentatively named `PhaseAuthority` /
`GeneratedStageExecution`: the contract that decides which phase facts cross
HIR, MIR, LLVM emission, and generated-stage execution, and which facts are
only phase-local implementation details. A future classifier extension is
admitted only if it answers one of those owner-boundary questions; a worker
patch, memory-budget patch, backend fallback patch, or direct segfault fix is
not admitted by this checkpoint.
Slice 0k-BQ design-seals that owner boundary. It names
`LLVMEmissionSession` as the first concrete `PhaseAuthority` owner record for
the generated-stage B4 corridor. The source inventory shows that CLI step 5
currently wires generator flags, HIR extern maps, constant initialization, and
LLVM output file ownership directly, while `LLVMIRGenerator#generate` owns
function-list selection, unresolved-pattern filtering, return-type precompute,
deduplication, worker selection, worker side-effect merge, tail declarations,
and missing-body stubs through mutable backend fields. The next production
slice is admitted only as a behavior-neutral `LLVMEmissionSession` record and
source-shape guard that captures this plan in one place before changing worker
behavior, memory behavior, tail stubs, or output ownership.

Current frontier: the compiler can make progress through bounded bug slices,
but many semantic decisions are still inferred repeatedly across HIR, MIR, and
LLVM lowering. This creates hidden oracles, string-name coupling, phase-local
fallbacks, and hard-to-localize bootstrap failures. The immediate live
bootstrap boundary after 0k-BM is the produced-stage entry into LLVM function
emission, not another TypeValue core row. After 0k-BP, this boundary is treated
as an architecture-design pressure point rather than a license to patch the
latest emitted symptom.

## Active Architecture Board

Status: execution board after Slice 0k-BQ. This board exists to
prevent the next step from being selected by the latest generated-stage crash
stack. A next slice is admitted only if it moves one board row by replacing or
shadowing a named authority edge, producing `CodePathStatus` evidence for a
named path, or refuting a row with fresher generated-stage evidence.

| Owner boundary | Current status | Next admitted movement | Forbidden repeat |
| --- | --- | --- | --- |
| `SemanticStateScope` | `prefer_callsite_specialization` is promoted in shadow/parity mode; emitted behavior still returns the legacy result. The `lower_function_if_needed.override` seam is also already promoted through the MaterializationDecision shadow helper and must not be reselected. Slice 0k-AU extends the existing admission report with a source-only no-repeat selector. It finds two unpromoted frontend direct consumers (`lower_function_if_needed.callsite_args` and `lower_function_if_needed.suffix_types`), rejects `lower_call.remangle` as backend-adjacent, and selects no single root-sized consumer. Slice 0k-AV defined the admitted shared state-model shape. Slice 0k-AW implements that shared `KeepRequestedNameDecision` state in behavior-neutral parity mode for both paired frontend consumers and replaces the stale `NamedTuple` owner-cache guard with a current `BlockOwner` guard. | The paired keep-requested-name inline edges are now consumed in parity mode. Next movement is not another crash-stack fix. Move to contract-first SDD hardening: close missing falsifiers for semantic identity, function-body presence, and generic instance/template keys, or select a fresh owner boundary only if it replaces a named authority edge with an owned fact and a falsifier. | Reselecting `prefer_callsite_specialization` or `lower_function_if_needed.override`; choosing either `callsite_args` or `suffix_types` by source order or convenience; treating `state_model_redesign_complete=1` as bootstrap progress; changing emitted behavior from a shadow row; globally clearing/ignoring `@type_param_map`; backend forwarders; requested-name forcing; `BlockOwner` rollback. |
| `TypeValue` / `RuntimeTypeIdentity` + frontend command-call preservation | Slice 0k-BA made the original-vs-stage semantic oracle executable and measured-red: current stage preserves `CONST=7` but prints blank `TYPE=` / `UNION=` where original Crystal prints `Int32`. Slice 0k-BC added the original H6 guard, which is measured-red but includes a parser-confounded direct no-parens `puts (true ? 1 : nil).class` row. Slice 0k-BD seals the TypeValue production receipt. Slice 0k-BF records a reverted TypeValue owner preflight: B3/H4 went green, but strict H6 still failed only on the direct command-call row. Slice 0k-BG adds the focused parser-shape guard and proves that row is a frontend command-call preservation frontier. Slice 0k-BH pauses parser production after a reverted local WIP. Slice 0k-BI implements the split-H6 route with `regression_tests/type_value_core_runtime_identity_contract.sh`. Slice 0k-BJ/0k-BL gate the owner-fact implementation and quarantine WIP inertia. Slice 0k-BM implements the H6-core owner fact: H6-core, B3, and H4 are strict-green on a fresh stage1 compiler, while H7 command-call parsing remains measured-red and H8 dynamic multi-variant union `.class` is now an explicit pre-s2-clean residual guard. | The next TypeValue movement is no longer H6-core row-greening. It must choose one of two separate lanes: H7 parser `semantic-service-extraction` for no-parens command-call preservation, or H8 runtime type-name service for dynamic multi-variant union `.class`. H8 may use the HIR `RuntimeTypeIdentity.runtime_stringification_required` policy as the source-level owner fact, but must not implement backend stringification without a new SDD slice naming the HIR/MIR/runtime boundary. | A string-only `lower_typeof` fix; an interpolation-only fix; a direct `puts` special-case without a type-value owner; source-text direct-puts workaround for `puts (expr).class`; using a stashed WIP as evidence without fresh baseline; backend stubs/forwarders; treating green H6-core as full old H6 green while command-call/dynamic-union guards remain red; changing `BlockOwner`, requested-name policy, ambient-map policy, broad `NamedTuple`/`Tuple` rendering, or generic materialization in the same slice; starting H7 or H8 code without a new row-specific SDD entry and measured-red baseline. |
| `GeneratedStageExecution` / `LLVMEmissionSession` | Slice 0k-BN records the first post-0k-BM integration check: stage1 can produce `s2b`, but produced `s2b` compiling a full-prelude tiny source fails after `pass3 after lower_main call`. Slice 0k-BO adds `scripts/generated_stage_llvm_entry_classifier.sh`; fresh `REQUIRE_CURRENT_FRONTIER=1` evidence reports `classification=current_0k_bn_frontier`, default LLVM workers hit `Invalid bound for rand: 0` plus RSS-kill, and `ADAMAS_LLVM_WORKERS=1` removes that worker symptom but still exits 139 at the same transition. This refutes treating parallel scheduling or memory budget alone as the root. Slice 0k-BP freezes production fixes from this symptom and reclassifies B4 as a pressure gate for a higher owner boundary: `PhaseAuthority` / `GeneratedStageExecution`. Slice 0k-BQ design-seals the first concrete owner: `LLVMEmissionSession`, with source anchors in CLI step 5 and `LLVMIRGenerator#generate` / `emit_functions_parallel`. | Next movement is a behavior-neutral `contract-owner-migration` slice for `LLVMEmissionSession`: introduce one session/plan record that captures function-list identity, skip/dedup decisions, worker/fallback policy, side-effect-table merge contract, output-buffer/file ownership, resource-budget evidence, and generated-stage gate linkage. Add a source-shape guard proving selected old authority edges no longer live only as scattered locals/backend fields. Do not change emitted LLVM or worker behavior in that first code slice. | Patching `emit_functions_parallel` because of the rand symptom; raising `run_safe` memory as acceptance evidence; forcing `ADAMAS_LLVM_WORKERS=1` as a fix; adding another classifier that only narrows a crash offset without naming a phase owner fact; changing tail missing-body stubs, undefined-extern rescue, output files, or worker fallback before the session record exists; deleting or resuming `fused_parallel_requested` cleanup as bootstrap progress; selecting H7/H8 code as bootstrap-moving work without showing it changes this produced-stage LLVM-entry boundary. |
| `MaterializationIdentity` / `MaterializationRegistry` | Slice 0k-Z promotes the selected `lower_function_if_needed.symbol_binding` seam in behavior-neutral shadow/parity mode. `scripts/materialization_symbol_binding_admission_report.sh` now reports `already_promoted_shadow` even with `REQUIRE_PROMOTED=1`; keepalive and materialization-ledger consumers read from `MaterializationSymbolBinding` fields instead of recomputing split locals. | Do not flip emitted symbols from this slice. Next movement must either run a generated-stage materialization/symbol-binding classification on the residual full-prelude s2 crash, or select the next root-sized owner consumer with a red/green gate. | Backend undefined-extern rescue; target keepalive as a standalone patch; requested-name forcing; `NamedTuple`/`Tuple` display normalization; global ambient-map predicate changes; `BlockOwner` rollback; treating the green source-shape gate as green `s2b`/`s3b`. |
| `NameResolution` / `MethodNameCodec` | File identity was fixed; method/symbol identity is still partly rendered-string driven. Slice 0k-V promotes the selected `lower_function_if_needed.exact_lookup_keep_requested_name` seam through `method_name_codec_exact_lookup_keep_requested_name?` in shadow/parity mode; emitted behavior still returns the legacy result. Slice 0k-W pauses standalone promotion-report proliferation. | Either select the next root-sized codec seam with a red/green source-shape gate, or define a generated-stage classification slice that consumes the existing promotion ledger to answer one blocking yes/no decision before changing emitted naming behavior. | String-slice parsing patches at individual callsites; treating rendered names as canonical identity; broad normalization without a falsifier; selecting lower-level helpers before a materialization seam; flipping owner-result behavior from shadow rows; committing another report surface that does not reduce or select an authority edge. |
| `CallMaterializationTransaction` spine | Slice 0k-AJ selects the reached transaction/emission edge `call_materialization.wrapper_or_call_remap.extern_missing_body`. Slice 0k-AK adds the docs stop rule for post-consumer selector decay. Slice 0k-AL makes that rule executable. Slice 0k-AM implements the behavior-neutral consumer: HIR stores transaction contract facts by tx id, HIR-to-MIR attaches them to transaction-bound `Call`/`ExternCall`, backend `[MAT_EMIT]` logs them mechanically, and optimizer replacement preserves them. Slice 0k-AO extends the same selector with a post-consumer exact-contract residual split. Fresh generated-stage evidence reports `post_consumer_state=selected_consumed_by_contract_consumer`, `contract_mismatch_rows=0`, `residual_exact_missing_body_rows=14`, `residual_exact_missing_body_groups=9`, and `residual_selection_status=rejected_exact_missing_body_ambiguous`. | The 0k-AJ selected edge is consumed, and the immediate exact-contract residual is ambiguous rather than root-selected. The next movement must either add a stronger discriminator that can select exactly one old authority edge from the 9 residual groups, or switch to `consolidation` / `cleanup/delete` under the 0k-AN covenant. | Treating consumed edge disappearance as failure; making old `REQUIRE_SELECTED=1` green by redefining rows; behavior-patching any residual sample (`Array#<<`, `Slice#[]`, `IO#read`, etc.) without a unique selector; backend forwarder or undefined-extern rescue; requested-name forcing; broad `NamedTuple`/`Tuple` rendering changes; global ambient-map policy changes; `BlockOwner` rollback; another standalone report that does not remove ambiguity or retire/refute an older surface. |
| `InvocationContext` / `InlineYieldFrame` | Slice 0k-AC promotes the selected `lower_super.previous_def.invocation_context` seam in behavior-neutral shadow/parity mode. `scripts/invocation_context_admission_report.sh` now reports `already_promoted_shadow` even with `REQUIRE_PROMOTED=1`; `lower_super` and `lower_previous_def` consume an `InvocationContext` owner fact instead of directly reading ambient owner/method, method-kind, super-source, and forward-policy state. | Do not flip super lookup, previous-def lookup, or argument-forwarding behavior from this slice. Next movement must either classify the residual generated-stage frontier with fresh owner-boundary evidence or select a different root-sized board row with a red/green source-shape gate. | A new `ADAMAS_SUPER_CALL_CONTEXT_LEDGER` report without a decision question; direct `lower_super` guards; changing super lookup or argument forwarding from a crash stack; inline-yield stack resets as a consumer fix; treating the green source-shape gate as green bootstrap evidence. |
| `AstNodeRef` / `ArenaOwnership` | Explicit-owner lower-call rows and `NodeSlotIntegrity` refuted owner drift, out-of-range ids, and missing slots for the instrumented edge. | Resume only with a named payload/deep-read or uninstrumented-consumer falsifier, including cleanup rules for its ledger. | Lower-call arena routing, broad arena scans, parser allocation rewrites, or another unbounded crash-edge probe. |
| `CodePathStatus` | Runtime cleanup inventory now reports 26 no-prelude CLI paths and `inventory_delete_ready_rows=0`. `identity_dry_run` and `phase0_metrics` are `debug_only`; `fused_parallel_requested` is `experimental_live`; none are `delete_ready`. Slice 0k-AT pauses cleanup as the default bootstrap lane because no delete-ready row exists and bloat is not the active constraint for green `s2b`/`s3b`. | Resume only if the user explicitly selects bloat reduction, or if a future run produces an `eligible_delete_ready_candidate` with default-behavior, HIR/MIR/LLVM, bootstrap, and protecting-falsifier evidence. | Deleting `identity_dry_run`, `phase0_metrics`, or `fused_parallel_requested`; deleting any `not_taken_unproven` path from inventory alone; adding more cleanup classifications as a substitute for semantic owner migration; using runtime liveness as semantic ownership evidence. |

### Slice 0k-BP: Architecture freeze after B4 classifier

Status:

- docs-only planning/control slice;
- production compiler behavior is frozen for the B4 crash stack;
- `scripts/generated_stage_llvm_entry_classifier.sh` remains the active
  measured-red/future-green bootstrap pressure gate;
- no source behavior, parser behavior, materialization behavior, backend
  emission behavior, cleanup behavior, or `BlockOwner` carrier changes are
  admitted by this slice.

Problem:

- the project can now localize generated-stage failures quickly enough that
  "find the next first bad transition" has become a tail-chasing risk;
- B4 names a real live bootstrap blocker, but by itself it only says that the
  produced compiler fails entering LLVM emission after `lower_main`;
- another local classifier or backend patch could make that symptom move while
  preserving the same architectural weakness: facts crossing HIR, MIR, LLVM,
  and generated-stage execution are still inferred from phase-local state,
  rendered names, fallback globals, and backend side effects.

Hostile self-review:

- **Claim under attack:** "Extending the B4 classifier is the next architecture
  implementation." That is only true if the extension answers an owner-boundary
  question. A classifier that only says "crashes between marker X and marker Y"
  is useful debug evidence, not architecture work.
- **Opposite hypothesis:** "Stop all B4 work and design in the abstract."
  That is also unsafe: the active objective is green `s2b`/`s3b`, and B4 is the
  current integration pressure gate that prevents the plan from drifting away
  from generated-stage reality.
- **Decision:** freeze production fixes, keep B4 as pressure evidence, and
  make the next movement a `PhaseAuthority` / `GeneratedStageExecution` owner
  contract before any behavior patch.

Owner contract to design next:

`PhaseAuthority` / `GeneratedStageExecution` is the proposed owner boundary for
facts that must survive from stage1 execution into generated-stage compiler
execution. It is not a physical file split. It must state, for each phase fact,
whether the fact is:

1. **Semantic:** must be preserved across stage1, produced `s2b`, and later
   `s3b` compilers.
2. **Phase-local:** may be recomputed or discarded inside one HIR/MIR/LLVM
   lowering session.
3. **Emission-session state:** must be owned by a single `LLVMEmissionSession`
   object or equivalent record during one LLVM generation run.
4. **Debug/probe-only:** may not affect acceptance or generated-stage behavior.

Minimum fact inventory before behavior edits:

| Fact family | Current risk | Owner question |
| --- | --- | --- |
| Function-list identity | function emission may depend on order, missing bodies, fallback externs, or post-DCE visibility | Which list is authoritative for LLVM emission and generated-stage body presence? |
| Worker/fallback policy | default workers show `Invalid bound for rand: 0`; single worker still crashes | Is worker selection semantic, resource policy, or debug execution mode? |
| Side-effect tables | backend tables such as emitted functions, undefined externs, string/name caches, and parallel merge products can diverge | Which tables are session-owned and how are parallel results merged or rejected? |
| Output buffers and files | produced-stage output can fail after HIR/MIR success | Which phase owns `.ll`, object, binary, and temp-file lifetimes? |
| Resource budgets | `run_safe` RSS kill is currently evidence, not an accepted workaround | Which memory counters are evidence only, and which are acceptance gates? |
| Generated-stage evidence | stage1 green guards can hide self-host-only failures | Which guards must run on produced `s2b` before a slice can claim bootstrap progress? |

Admitted next step:

1. Write or update the architecture plan so it has an explicit
   `PhaseAuthority` / `GeneratedStageExecution` tranche with producer/consumer
   inventory and old authority edges.
2. Only after that plan exists, extend the B4 classifier if the extension maps
   directly to one of the fact families above.
3. Only after a classifier names a first bad owner boundary, write a focused
   production slice that replaces, shadows, or refutes that old authority edge.

Rejected shortcuts:

- patching `emit_functions_parallel`, worker count, random bound handling, or
  memory limits from the current B4 output;
- adding backend undefined-extern rescue, target keepalive, or forwarders;
- using B4 to justify H7/H8 parser/type-name work as bootstrap-moving;
- adding another diagnostic report that does not retire, merge, or select a
  named authority edge;
- rolling `BlockOwner` back to tuple/namedtuple owner metadata;
- claiming `s2b` or `s3b` progress from stage1-only source guards.

DoD for this planning slice:

- `TODO.md`, `LANDMARKS.md`, this SDD, the refactor plan, and the falsifier
  matrix identify 0k-BP consistently;
- B4 remains `[FRONTIER]` and executable, not deleted or weakened;
- no compiler production code changes are included;
- the next production movement has an execution ladder: row, tranche, old
  authority edge, owner service/fact, producer/consumer map, baseline guard,
  architecture guard, generated-stage relevance, residual boundary.

### Slice 0k-BQ: `LLVMEmissionSession` owner-contract design

Status:

- docs-only design-seal slice;
- defines the first concrete `PhaseAuthority` owner record for the B4
  generated-stage corridor;
- no compiler production behavior, parser behavior, materialization behavior,
  backend emission behavior, cleanup behavior, or `BlockOwner` carrier changes
  are included.

Source inventory:

| Fact family | Current source anchor | Current authority shape | Contract decision |
| --- | --- | --- | --- |
| Step-5 generator setup | `src/compiler/cli.cr:2873-2921` | CLI constructs `LLVMIRGenerator`, then mutates flags (`emit_type_metadata`, debug info, reachability, prelude/GC, fused lowering, worker opts) directly on the backend object. | Session input facts should be captured in one immutable or append-only setup record before `generate`. |
| HIR extern forwarding maps | `src/compiler/cli.cr:2896-2910` | CLI builds two local maps and assigns optional backend fields. | Session must name whether extern forwarding is semantic linkage input or backend helper state. |
| Constant initializers | `src/compiler/cli.cr:2923-2937` | CLI derives global initializer facts from HIR converter side maps and pushes them into backend state. | Session must record initializer source and count so generated-stage acceptance can distinguish semantic global facts from CLI convenience state. |
| LLVM output path and file ownership | `src/compiler/cli.cr:2939-2979` | CLI owns `.ll` path, calls `llvm_gen.generate`, unlinks/opens/writes the output file, and treats returned string bytes as the backend product. | Session must separate IR text ownership from file-output ownership; a backend crash and file-output crash are different boundaries. |
| Function-list identity | `src/compiler/mir/llvm_backend.cr:2932-3044` | Backend selects `@module.functions` or reachable subset, filters unresolved patterns, propagates skip ids, precomputes return types, dedups by mangled name, and chooses sequential vs parallel emission inline. | Session plan must record original count, selected count, skipped ids/reasons, dedup decisions, and final function ids/names before emission. |
| Worker/fallback policy | `src/compiler/mir/llvm_backend.cr:3032-3044`, `17051-17062`, `17414-17776` | Backend reads env-derived worker count, rewrites it for debug metadata, then either forks workers or emits sequentially; parallel failure falls back to sequential in the same method. | Session must classify worker count as resource policy, not semantic identity; fallback must be recorded as evidence, not silently accepted as equivalent behavior. |
| Backend side-effect tables | `src/compiler/mir/llvm_backend.cr:2087-2133`, `17562-17618`, `17693-17763` | `@emitted_functions`, `@undefined_externs`, `@called_crystal_functions`, string constants/aliases, return types, module singleton globals, and debug file use are mutable backend fields serialized by workers and merged by parent. | Session must define which tables are emission-session-owned, their merge contract, and whether missing entries are semantic failures or tail-generation inputs. |
| Tail declarations/stubs | `src/compiler/mir/llvm_backend.cr:3125-3144`, `3493-3638`, `3705-3798` | Undefined extern declarations and missing Crystal stubs are emitted after function emission from mutable call/emitted/undefined sets. | Session must distinguish legitimate extern declarations from body-missing semantic gaps and backend dead-code stubs. |
| Resource evidence | `src/compiler/mir/llvm_backend.cr:17065-17363` | Memory snapshots are optional debug output that count many backend sets, but no owner record ties them to acceptance or failure classification. | Session must keep memory/RSS evidence as measurement unless a later SDD slice promotes a resource gate. |

Old authority edges named by this slice:

1. `function-list-inline`: final functions to emit are selected and filtered
   inside `LLVMIRGenerator#generate` as local variables.
2. `worker-policy-inline`: worker count and fallback are computed in backend
   helpers and can silently fall back to sequential emission.
3. `side-effect-field-bag`: emitted/called/undefined/string/debug facts live as
   mutable backend fields and ad-hoc worker side-effect files.
4. `tail-stub-from-mutable-sets`: tail declarations and dead-code stubs are
   derived from backend sets after emission, without a session-level body
   presence contract.
5. `output-file-owned-by-cli`: CLI owns `.ll` file writing after backend
   returns an IR string, so backend generation and file-output failures can be
   conflated by generated-stage traces.

New owner record:

`LLVMEmissionSession` is the admitted first implementation artifact. It should
be created before function emission and should carry, at minimum:

- setup facts copied from CLI/options: debug mode, reachability mode,
  no-prelude/no-GC mode, worker optimization flags, fused-lowering presence,
  type metadata flag, HIR extern map counts, constant initializer count, and
  output mode;
- function plan: original function count, selected function ids/names,
  skipped ids with reason (`unresolved_name`, `unresolved_extern`,
  `depends_on_skipped`), deduped mangled names, and final function count;
- worker plan: requested worker count, effective worker count, reason for
  sequential mode, parent-emitted function ids, worker assignment counts, and
  whether fallback occurred;
- side-effect merge plan: owned sets for emitted functions, return types,
  undefined externs, called Crystal functions, string aliases, zero-struct
  globals, module singleton globals, and debug files;
- tail plan: counts and names for legitimate extern declarations, late-emitted
  known Crystal functions, dead-code stubs, and unresolved missing bodies;
- generated-stage evidence: whether this session was executed by a produced
  compiler and which B4 gate (`current-frontier` or `clean`) it is meant to
  satisfy.

First implementation slice admitted after 0k-BQ:

Tranche: `contract-owner-migration`.

Risk tier: CAUTION, because it touches LLVM emission state, but the first slice
must be behavior-neutral.

Rollback: safety commit before code edits; ordinary revert if parity/source
guards fail.

Required source files:

- `src/compiler/mir/llvm_backend.cr` for `LLVMEmissionSession` record and
  session-plan construction;
- `src/compiler/cli.cr` only if setup facts must be passed explicitly instead
  of read from already assigned backend properties;
- `scripts/generated_stage_llvm_entry_classifier.sh` only if the session record
  exposes new default-off evidence that the classifier can consume;
- docs/ledgers for residual boundary sync.

DoD for the first code slice:

1. Fresh B4 measured-red baseline before patch:
   `REQUIRE_CURRENT_FRONTIER=1 scripts/generated_stage_llvm_entry_classifier.sh`.
2. Source-shape guard proving the selected authority edge is consumed by
   `LLVMEmissionSession` instead of only inline locals/fields. If no script
   exists yet, add one before production changes.
3. Focused parity check: stage1 still passes the existing suite relevant to
   LLVM emission; at minimum B3/H6-core guards and B4 measured-red must not
   regress.
4. Generated-stage relevance: B4 may remain red, but its output must report the
   same or narrower frontier; if the first bad boundary changes, record it as
   residual before commit.
5. No emitted LLVM semantics, worker count defaults, fallback policy,
   undefined-extern behavior, missing-body stubs, output-file behavior, or
   `BlockOwner` carrier may change in the first slice.

Adversary notes:

- A behavior-neutral session record can still become diagnostic debt if no
  consumer migrates to it. The first implementation must consume at least one
  old authority edge in source shape, not only allocate a struct.
- A broad `LLVMEmissionSession` god object would repeat the current backend
  field bag. The record must classify facts into setup, function plan, worker
  plan, side-effect merge, tail plan, and generated-stage evidence.
- A green stage1 suite is insufficient. The session is justified only because
  B4 is the active generated-stage pressure gate; B4 remains the acceptance
  guard for bootstrap movement.

Slice 0k-AP consolidation result: the architecture report surface is now
treated as a registry, not as a menu of competing next steps. Existing reports
are statused below. A script marked `guard` may protect a promoted seam, but it
does not select new work. A script marked `historical` is evidence for its
recorded slice only and must not drive a future patch without a fresh SDD
receipt. A script marked `cleanup-entry` may be used only after the slice
chooses the `cleanup/delete` lane.

| Surface | Status | Use after 0k-AP |
| --- | --- | --- |
| `scripts/generated_stage_transaction_edge_selection_report.sh` | `active-stop-gate` | Proves the consumed 0k-AJ edge and the ambiguous 0k-AO residual. It can admit a future correctness-selection slice only if `REQUIRE_RESIDUAL_SELECTED=1` becomes root-sized with a named old authority edge. |
| `scripts/generated_stage_llvm_entry_classifier.sh` | `active-stop-gate` | Protects the active 0k-BN/0k-BO produced-stage LLVM-entry frontier. `REQUIRE_CURRENT_FRONTIER=1` asserts the current measured-red boundary; `REQUIRE_CLEAN=1` is the future green gate. It is not a worker-count workaround or memory-budget acceptance gate. |
| `scripts/generated_stage_transaction_spine_classifier.sh` | `supporting` | Builds the generated-stage corridor for the edge selector. It is not a standalone next-step selector. |
| `scripts/call_materialization_transaction_admission_report.sh` | `guard` | Historical 0k-AE/0k-AF transaction-spine admission. Protects the owner boundary; do not reselect it as new work. |
| `scripts/call_materialization_transaction_consumer_selection_report.sh` | `guard` | Historical 0k-AG/0k-AH consumer selection. Protects the promoted instance-symbol consumers; do not reselect it. |
| `scripts/materialization_symbol_binding_admission_report.sh` | `guard` | Protects the promoted `MaterializationSymbolBinding` seam. It is not a behavior license. |
| `scripts/method_name_codec_admission_report.sh` | `guard` | Protects the promoted exact-lookup `MethodNameCodec` seam. It is not permission for global name normalization. |
| `scripts/invocation_context_admission_report.sh` | `guard` | Protects the promoted `InvocationContext` seam. It is not permission for direct `lower_super` behavior patches. |
| `scripts/semantic_state_scope_admission_report.sh` | `guard` | Protects the promoted `prefer_callsite_specialization` state-scope seam. It is not permission to wrap `def_has_untyped_regular_param?` again. |
| `scripts/codepath_status_cleanup_selection_report.sh` | `cleanup-entry` | The only currently admitted cleanup/delete entry point. It creates repo-local `tmp/` before `mktemp` so scratch cleanup does not break the lane. A cleanup slice still needs default-behavior, HIR/MIR/LLVM, bootstrap, and protecting-falsifier evidence. |
| `scripts/codepath_status_census.sh`, `scripts/codepath_status_runtime_report.sh` | `cleanup-supporting` | Supporting evidence for cleanup only; runtime liveness alone is not semantic ownership. The runtime report creates repo-local `tmp/` before `mktemp`. |
| `scripts/semantic_decision_census.sh`, `scripts/semantic_state_scope_report.sh`, `scripts/state_scope_consumer_report.sh`, `scripts/materialization_decision_report.sh`, `scripts/materialization_promotion_selection_report.sh`, `scripts/materialization_override_promotion_report.sh`, `scripts/materialization_transaction_report.sh`, `scripts/materialization_identity_ledger_smoke.sh`, `scripts/arena_ownership_census.sh`, `scripts/lower_call_arena_ledger_smoke.sh`, `scripts/lower_call_arena_parity_report.sh`, `scripts/node_slot_integrity_report.sh`, `scripts/layout_probe_report.sh` | `historical` | Evidence for earlier slices or local audits. They may be run as guards when their owner row is touched, but they are not next-step selectors. |

Default next track after Slices 0k-AO/0k-AP: the selected
`wrapper_or_call_remap.extern_missing_body` edge is consumed, not fixed by a
behavior change. Do not implement a backend forwarder or requested-name/materialized-body
repair from this consumed edge. Slice 0k-AO tried the first post-consumer
correctness-selection split and showed that the exact-contract missing-body
residual is not a single next edge: it contains 14 rows across 9 individually
root-sized groups. That is ambiguous, not permission to pick one sample by
intuition. The next executable architecture slice must either add a stronger
discriminator that removes this ambiguity and names one old authority edge, or
switch to `consolidation` / `cleanup/delete` under the pacing covenant. A
cleanup slice remains admitted only when the goal is explicitly bloat reduction
and the selected path has its own `CodePathStatus` falsifier.

Post-0k-AM architecture pacing covenant:

- A next slice must choose exactly one lane before it edits production code:
  `correctness-selection`, `consumer-migration`, `cleanup/delete`, or
  `consolidation`.
- `correctness-selection` may add or extend a selector only when it states a
  decision question, declares a root-size budget, has a negative control, and
  names the old authority edge that a future consumer would replace or shadow.
  If the result is broad, such as the current `other_missing_body_rows=14`, the
  slice stops at classification; it does not authorize behavior changes.
- `consumer-migration` is admitted only after a selected edge is already
  root-sized and has a named owned fact. The DoD must prove that at least one
  legacy consumer reads that fact in shadow/parity mode, or that the old edge is
  explicitly refuted.
- `cleanup/delete` is admitted only through `CodePathStatus` with default
  behavior, HIR/MIR/LLVM shape, bootstrap guard, and a protecting falsifier.
- `consolidation` is admitted when the current architecture surface has too
  many reports/ledgers for the evidence they carry. It must retire, merge, or
  mark stale at least one older report/gate or historical next-step paragraph;
  otherwise it is another report slice in disguise.
- No two consecutive report-only slices are allowed unless the second one
  deletes, retires, or refutes a previous report surface. `residual_*` counters,
  row counts, and crash-stack movement are routing signals, not progress
  metrics.

This covenant is a stop rule, not a new behavior plan. It exists to prevent the
architecture track from replacing consumer-patch tail-chasing with
selector/report tail-chasing.

Executed result after Slice 0k-AP: the report surface is consolidated instead
of expanded. The current scripts were classified into `active-stop-gate`,
`supporting`, `guard`, `cleanup-entry`, `cleanup-supporting`, and `historical`
roles, and the cleanup-entry script now creates repo-local `tmp/` before
`mktemp`. This retires old source-shape and ledger reports as next-step
authorities unless a future SDD slice explicitly reactivates one with a decision
question, root-size budget, negative control, and old authority edge.
Decision: the default next executable slice should be `cleanup/delete` through
`CodePathStatus`, or a narrowly justified correctness-selection discriminator
that selects exactly one authority edge. It must not be another standalone
report or a behavior fix from residual samples.

Cleanup preflight after Slice 0k-AP: a fresh stage1 ran the cleanup-entry gate
for both currently supported paths. `SELECTED_CLEANUP_PATH=identity_dry_run`
and `SELECTED_CLEANUP_PATH=phase0_metrics` both reported `default_rc=0`,
`enabled_rc=0`, `default_status=not_taken`, `enabled_status=taken`, and
`status=debug_only`. Decision: neither path is `delete_ready`; the next cleanup
slice must select a different named path or first extend the cleanup selector to
enumerate a root-sized candidate with a protecting falsifier. This refutes
deleting either current CLI metrics path from the existing cleanup-entry report.

Executed result after Slice 0k-AR: the cleanup-entry report now has a
fail-closed runtime inventory mode. With `LIST_RUNTIME_PATHS=1`, a fresh stage1
no-prelude compile reports `inventory_rows=26`, `inventory_paths=26`,
`inventory_malformed=0`, `inventory_delete_ready_rows=0`, and
`inventory_status=no_delete_ready_candidate`. Negative control:
`LIST_RUNTIME_PATHS=1 REQUIRE_DELETE_READY=1` exits 9 with that status. The
inventory includes default-live paths such as `run`, `compile`, `safe_parser`,
`flush_pending_functions`, `escape_analysis`, `serial_lowering`, and
`mir_opt_deferred_workers`; all other rows are `not_taken_unproven`, not
deletion targets. Decision: no cleanup/delete behavior change is admitted yet.
The next cleanup slice must pick one `not_taken_unproven` path and add a
protecting falsifier, or define a stricter `eligible_delete_ready_candidate`
class before deleting code.

Executed result after Slice 0k-AS: the cleanup-entry report now supports
`SELECTED_CLEANUP_PATH=fused_parallel_requested`. A fresh stage1 no-prelude run
reports `[CODEPATH_CLEANUP_SELECTION] cluster=cli.mir
path=fused_parallel_requested owner=CLI status=experimental_live
default_status=not_taken enabled_status=taken ... action=keep_experimental_live`.
Decision: the fused parallel MIR path remains an opt-in experimental path, not
a deletion target from current cleanup evidence. `REQUIRE_DELETE_READY=1` still
fails with `inventory_status=no_delete_ready_candidate`.

Slice 0k-AT architecture pivot: cleanup/report pursuit is paused for the
bootstrap objective. The last three cleanup steps proved useful negative facts
(`debug_only`, `experimental_live`, and zero delete-ready rows), but they do not
move the root architecture condition for green `s2b`/`s3b`: semantic identity is
still reconstructed from rendered names, ambient maps, and phase-local fallback
state. The next admitted slice is therefore not another cleanup classification
and not a generated-stage behavior fix. It is a no-repeat
`SemanticStateScope` selection gate over the remaining direct ambient-predicate
consumers. This gate must enumerate current direct calls to
`state_scope_consumer_def_has_untyped_regular_param?`, reject already-promoted
seams (`prefer_callsite_specialization` and `lower_function_if_needed.override`)
and backend-adjacent seams, then select at most one root-sized consumer for a
future behavior-neutral owner decision. If no such consumer exists, the next
movement is a higher-level state-model redesign checkpoint, not another report
or cleanup classification.

0k-AT stop rules:

- do not add a backend forwarder, target keepalive, requested-name force, or
  `NamedTuple`/`Tuple` rendering change for the `@block_owner Hash#[]=`
  frontier;
- do not resume `CodePathStatus` classification unless cleanup/bloat is
  explicitly selected as the active constraint;
- do not globally clear, ignore, or reinterpret `@type_param_map`;
- do not patch `raw_annotation_needs_callsite_specialization?` directly or
  choose a consumer by intuition; first prove the selected consumer is
  unpromoted, root-sized, and not backend-adjacent;
- keep `BlockOwner`; converting it back to tuple/namedtuple owner metadata is
  outside the admitted surface.

Slice 0k-AU no-repeat gate result: `SOURCE_SHAPE_ONLY=1
scripts/semantic_state_scope_admission_report.sh` now runs without compiling a
program and enumerates the live direct callers of
`state_scope_consumer_def_has_untyped_regular_param?`. It reports
`prefer_callsite_specialization` and `lower_function_if_needed.override` as
`already_promoted_shadow`, `lower_call.remangle` as `rejected_backend_adjacent`,
and the two remaining frontend direct consumers
`lower_function_if_needed.callsite_args` / `.suffix_types` as
`rejected_multiple_frontend_candidates`. The source-only selector therefore
prints `frontend_candidate_count=2`, `selected_count=0`,
`already_promoted_count=2`, and `state_model_redesign_required=1`. With
`REQUIRE_SELECTED=1`, the same command exits `9`, proving that no future slice
may silently choose one of the two frontend consumers. The next admitted move is
the state-model redesign checkpoint unless a stronger falsifier collapses that
pair to exactly one root-sized authority edge.

### Slice 0k-AU: SemanticStateScope no-repeat source selector

Status:

- implemented as source-shape-only mode in the existing
  `scripts/semantic_state_scope_admission_report.sh`;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, cleanup behavior, or `BlockOwner` carrier is changed by this slice.

Problem:

- Slice 0k-AT said to enumerate the remaining direct ambient-predicate
  consumers before choosing another `SemanticStateScope` helper;
- choosing one of the remaining `lower_function_if_needed` consumers by source
  order would repeat the earlier symptom-patching pattern;
- the gate must therefore either select exactly one root-sized unpromoted
  frontend consumer or force a redesign checkpoint.

Implementation:

- `SOURCE_SHAPE_ONLY=1` skips compiler execution and scans
  `src/compiler/hir/ast_to_hir.cr` directly;
- it reports `[STATE_SCOPE_SOURCE]` rows for the known state-scope consumers;
- it reports `[STATE_SCOPE_NO_REPEAT]` selection rows;
- `REQUIRE_SELECTED=1` fails unless exactly one unpromoted frontend consumer is
  source-selected.

Fresh evidence:

- default source-only gate:
  - `prefer_callsite_specialization`: `already_promoted_shadow`;
  - `lower_function_if_needed.override`: `already_promoted_shadow`;
  - `lower_function_if_needed.callsite_args`: `legacy_direct_edge`,
    `rejected_multiple_frontend_candidates`;
  - `lower_function_if_needed.suffix_types`: `legacy_direct_edge`,
    `rejected_multiple_frontend_candidates`;
  - `lower_call.remangle`: `legacy_direct_edge`, `rejected_backend_adjacent`;
  - `malformed_direct=0`, `frontend_candidate_count=2`,
    `selected_count=0`, `already_promoted_count=2`,
    `state_model_redesign_required=1`.
- negative selection gate:
  `SOURCE_SHAPE_ONLY=1 REQUIRE_SELECTED=1
  scripts/semantic_state_scope_admission_report.sh` exits `9`.

Boundary:

- this is a source-shape selector, not a behavior fix;
- it does not prove `s2b`/`s3b` progress;
- it prevents the next slice from picking either `callsite_args` or
  `suffix_types` without a stronger discriminator.

Next local track:

- move to a state-model redesign checkpoint for the shared
  `lower_function_if_needed` keep-requested-name state, or first produce a
  stronger falsifier that collapses the two frontend candidates to one
  root-sized authority edge.

### Slice 0k-AV: plan before shared keep-requested-name state

Status:

- docs-only hostile self-review checkpoint;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, cleanup behavior, or `BlockOwner` carrier is changed by this slice.

Problem:

- Slice 0k-AU proved that `callsite_args` and `suffix_types` must not be picked
  independently;
- a local uncommitted shared helper WIP could make the source-shape report say
  `state_model_redesign_complete=1`, but that alone would only prove that two
  callsites share a helper;
- the root architecture problem is stronger: keep-requested-name identity must
  be produced as one owned state fact and then consumed mechanically, without
  turning `state_model_redesign_complete` into a value proxy for green
  `s2b`/`s3b`.

Admitted next implementation shape:

- introduce one behavior-neutral shared keep-requested-name state record/helper
  for the paired `lower_function_if_needed.callsite_args` and
  `lower_function_if_needed.suffix_types` consumers;
- the record must expose at least:
  - requested symbol;
  - resolved/materialized symbol;
  - selected definition identity;
  - predicate input types;
  - collection-policy input types when they intentionally differ from predicate
    input types;
  - legacy result;
  - owner result;
  - emitted result, which remains legacy/parity for this slice;
  - reason/classification that explains which authority decided the result.
- both consumers must read the emitted result from that record instead of
  recomputing the legacy expression inline;
- optional ledgers may print the record, but the ledger is not the owner.

DoD for the future production slice:

- source-shape gate:
  `SOURCE_SHAPE_ONLY=1 REQUIRE_REDESIGNED=1
  scripts/semantic_state_scope_admission_report.sh` reports both frontend
  keep-requested-name consumers as shared and no direct frontend candidate;
- negative source-shape gate:
  `SOURCE_SHAPE_ONLY=1 REQUIRE_SELECTED=1
  scripts/semantic_state_scope_admission_report.sh` still exits non-zero, proving
  no single consumer was silently reselected;
- behavior smoke:
  fresh stage1 builds and compiles/runs at least one trivial program and one
  generic keep-requested-name stress program through `scripts/run_safe.sh`;
- regression audit:
  the old `hash_named_tuple_index_assign_materialization_repro.sh` was retired
  because it searched for the obsolete `Hash(UInt64, NamedTuple)#[]=` carrier.
  Add a `BlockOwner` successor before using owner-cache materialization as a
  gate;
- generated-stage guard:
  run the existing generated-stage classifier or a narrower successor only as a
  guard. A crash-stack movement or a green source-shape gate is not a bootstrap
  claim.

Stop rules:

- stop if the implementation changes emitted keep-requested-name behavior;
- stop if the shared helper hides the old
  `state_scope_consumer_def_has_untyped_regular_param?` authority without
  recording a distinct owner result;
- stop if a stale `NamedTuple`-based regression is used to reject a
  `BlockOwner`-based implementation;
- stop if the next step becomes backend forwarder, target keepalive,
  requested-name force, `NamedTuple`/`Tuple` rendering normalization, global
  ambient-map policy, or `BlockOwner` rollback.

Executed result after Slice 0k-AW: the admitted shared state model exists in
production code and remains behavior-neutral. `KeepRequestedNameDecision`
records the requested symbol, resolved/materialized symbol, selected
definition, predicate input types, collection-policy input types, legacy
result, owner result, emitted result, and reason. Both
`lower_function_if_needed.callsite_args` and
`lower_function_if_needed.suffix_types` read `emitted_result` from the record.
The source-shape gate reports both consumers as
`shared_keep_requested_name_model`, `redesigned_frontend_count=2`, and
`state_model_redesign_complete=1`; `REQUIRE_SELECTED=1` still exits `9`, so no
single consumer was reselected. The stale
`hash_named_tuple_index_assign_materialization_repro.sh` guard has been
replaced by `regression_tests/block_owner_index_assign_materialization_repro.sh`
for the current `Hash(UInt64, BlockOwner)#[]=` carrier. This slice does not
flip requested-name policy and does not prove green `s2b`/`s3b`.

0k-AW architecture pause: the next movement must not be selected from the next
runtime crash stack. The accumulated pattern is now clear enough to change the
work order: local consumer fixes repeatedly expose deeper identity and state
ownership gaps. The next SDD update should burn down contract holes from
`docs/specs/05-falsifier-matrix.md` before another behavior fix. Priority
contract holes are function-body presence versus stub, generic template and
instance semantic keys versus rendered strings, and original-vs-stage semantic
oracle coverage for future language-behavior changes.

### Slice 0k-AX: contract-first pivot after shared state

Status:

- docs-only architecture pivot;
- no compiler behavior, materialization behavior, remangling behavior, backend
  behavior, cleanup behavior, or `BlockOwner` carrier is changed by this slice.

Problem:

- `s2b`/`s3b` failures are still the final acceptance pressure, but the last
  frontier chain showed that choosing work from the latest crash stack
  repeatedly selects symptoms;
- many local fixes were useful, but the recurring root class is missing
  compiler contracts: semantic identity is rendered as strings, body presence
  is inferred late, generic instance identity is reconstructed from names, and
  stage equivalence sometimes lacks an original-vs-stage oracle;
- another report or parity helper is only admitted if it closes a contract
  hole or removes/refutes an older report surface.

Admitted next slices, in order:

1. `FunctionBodyPresence`: H5 falsifier is now present as
   `regression_tests/hir_function_body_presence_contract.sh`. It distinguishes
   registered bodyless HIR functions from real body evidence and verifies the
   HIR->MIR boundary preserves bodyless functions as unreachable stubs.
2. `GenericIdentityKey`: G3 falsifier is now present as
   `regression_tests/generic_identity_key_contract.sh`. It introduces first-class
   semantic keys for generic templates and instances and proves equality/hash
   are separated from display/rendered names.
3. `StageSemanticOracle`: B3 oracle shape is now present as
   `regression_tests/original_vs_stage_semantic_oracle_contract.sh`. It states
   exact semantic output lines and is currently measured-red for type-visible
   behavior.

Stop rules:

- do not select the next slice from a crash stack unless the crash directly
  falsifies one of the above contracts;
- do not add a new report unless it retires, merges, or refutes an older
  report surface, or it is the executable falsifier for H5/G3/B3;
- do not claim progress from source-shape counters, row counts, or crash
  movement alone;
- do not use backend forwarders, target keepalive, requested-name forcing,
  `NamedTuple`/`Tuple` rendering normalization, global ambient-map policy, or
  `BlockOwner` rollback as shortcuts around these contracts.

DoD for the next production slice:

- cite one contract row from `docs/specs/05-falsifier-matrix.md`;
- add or update the smallest falsifier for that row before behavior changes;
- name the old authority edge being replaced, shadowed, or refuted;
- run the falsifier plus `git diff --check`;
- update TODO/LANDMARKS/SDD with residual risk and no green `s2b`/`s3b` claim
  unless a generated stage actually proves it.

Executed result after Slice 0k-AY: H5 is no longer missing a falsifier. The
new focused guard `regression_tests/hir_function_body_presence_contract.sh`
runs `spec/hir/function_body_presence_contract_spec.cr` and proves the HIR
truth table for body presence plus the HIR->MIR bodyless-stub boundary. This is
not a compiler behavior change. The next contract-first target is G3 generic
template/instance semantic keys, not a generated-stage crash-stack patch.

Executed result after Slice 0k-AZ: G3 is no longer missing a falsifier. The
new semantic identity objects live in
`src/compiler/semantic/identity/generic_identity_key.cr`, and the guard
`regression_tests/generic_identity_key_contract.sh` runs
`spec/semantic/generic_identity_key_spec.cr`. The guard proves that generic
template identity includes owner, source `DefIdentity`, and declared type
parameters, and that generic instance identity includes the template key,
specialization argument identities, and lexical owner even when display names
match. This is not a migration of generic materialization call sites yet. The
next contract-first target is B3 original-vs-stage semantic oracle coverage, or
a separately admitted slice that replaces a named old generic-identity authority
edge with these semantic keys.

Executed result after Slice 0k-BA: B3 is no longer missing an executable oracle,
but the oracle is measured-red. The new guard
`regression_tests/original_vs_stage_semantic_oracle_contract.sh` builds and runs
the same source with original Crystal and the supplied stage compiler through
`scripts/run_safe.sh`, then compares explicit source-visible lines:
`TYPE=...`, `CONST=...`, and `UNION=...`. Current stage output preserves
`CONST=7` but prints blank `TYPE=` and `UNION=` where original Crystal prints
`Int32`. This closes the missing-oracle hole and opens a named semantic
frontier; it is not a compiler behavior fix and not a green `s2b`/`s3b` claim.
Next work may either fix that original-vs-stage type-visible semantic frontier
or begin migrating a named old generic-identity authority edge to the G3 keys.

### Slice 0k-BB: TypeValue boundary before fixing B3

Status:

- docs-only hostile self-review checkpoint;
- no compiler behavior, type-literal behavior, output behavior,
  materialization behavior, generic behavior, backend behavior, cleanup
  behavior, or `BlockOwner` carrier is changed by this slice.

Problem:

- B3 is now an executable original-vs-stage oracle, but its measured-red rows
  are type-visible semantics, not an arbitrary runtime-output bug;
- a local patch to `lower_typeof` would be tempting because current source
  explicitly emits `nil` for `typeof(...)`, but that only covers one edge;
- the same semantic surface crosses `typeof`, runtime `.class`, type literals,
  `.name` / `.to_s` / `inspect`, direct `puts`, and string interpolation;
- current implementation treats those as separate ad hoc paths: placeholder
  nil values, nil type-literal pointers, name-query lowering, and interpolation
  special cases.

Design boundary:

- introduce `TypeValue` / `RuntimeTypeIdentity` as the next owner boundary;
- one HIR-owned fact must carry at least:
  - the semantic `TypeRef`;
  - the canonical type display name;
  - the origin (`typeof`, runtime `.class`, explicit type literal, or type
    literal query);
  - whether the value is compile-time-only or needs runtime stringification;
- consumers must read that fact instead of inferring type visibility from
  runtime pointer nil-ness, dot-class side maps, or rendered-name shortcuts.

Admitted next production slice:

1. Extend the B3/HIR falsifier before behavior changes so it covers:
   - direct `puts typeof(1)`;
   - interpolated `"#{typeof(1)}"`;
   - direct `puts 1.class`;
   - interpolated `"#{1.class}"`;
   - direct and interpolated `(true ? 1 : nil).class`;
   - type literal `.name`, `.to_s`, and `inspect` queries.
2. Add the smallest owner fact/helper that lets these edges share one
   representation while preserving existing H4 type-literal name-query guard.
3. Flip only the reached consumers needed by that falsifier.
4. Run strict B3, H4, `git diff --check`, and the narrow new TypeValue guard.

Stop rules:

- do not make `lower_typeof` return a plain string as a standalone fix;
- do not add another special case only inside string interpolation or direct
  `puts`;
- do not treat runtime pointer shape of a type literal as the semantic
  authority;
- do not use backend dead-code stubs, forwarders, or LLVM stringification as
  the repair layer;
- do not change generic materialization, `BlockOwner`, requested-name policy,
  or ambient-map policy in the same slice;
- do not claim green `s2b`/`s3b` from B3 alone.

Next local track:

- implement the TypeValue falsifier/owner slice, then use the strict B3 oracle
  as the acceptance gate for this frontier. If the TypeValue scope becomes
  broad or mixed, stop at classification and return to the G3 semantic-key
  migration lane rather than patching one output path.

Executed result after Slice 0k-BC: H6 now has an executable focused falsifier,
`regression_tests/type_value_runtime_identity_contract.sh`. It compares
original Crystal and the supplied stage compiler on direct and interpolated
`typeof(1)`, runtime `1.class`, nilable `(true ? 1 : nil).class`, and
type-literal `.name` / `.to_s` / `inspect`. The guard is strict by default and
measured-red only with `ADAMAS_EXPECT_TYPEVALUE_MISMATCH=1`. Fresh evidence
shows the current stage binary emits blank direct/interpolated `typeof` rows
and then exits 139 at the direct `.class` row. This closes the
missing-falsifier part of the TypeValue boundary but does not implement the
HIR-owned `TypeValue` fact, does not fix B3, and does not prove green
`s2b`/`s3b`. The next production slice is the owner-fact
implementation/migration for the reached type-visible consumers, or a
stop-at-classification if that migration is broader than the H6 guard.
Slice 0k-BI later split this guard for implementation: the old guard remains a
wider full-surface acceptance check, while
`regression_tests/type_value_core_runtime_identity_contract.sh` is the current
TypeValue owner-fact implementation gate.

### Slice 0k-BD: TypeValue implementation receipt

Status:

- docs-only architecture receipt before production implementation;
- no compiler behavior, output behavior, type-literal behavior,
  materialization behavior, generic behavior, backend behavior, cleanup
  behavior, `BlockOwner` carrier, requested-name policy, or ambient-map policy
  is changed by this slice.

Problem:

- the H6/H6-core guard family is strong enough to admit implementation, but it
  is narrow enough that a local fix can still look green while preserving the
  old scattered authority model;
- `typeof`, runtime `.class`, direct output, interpolation, and type-literal
  name/string queries currently reach different source paths;
- therefore the implementation needs a receipt that names which old authority
  edges are being replaced before any behavior changes land.

Old authority edges to replace or explicitly preserve:

1. `typeof(...)` lowering that currently emits a nil placeholder;
2. runtime `.class` lowering that currently constructs a type-literal value
   with runtime nil-pointer behavior;
3. dot-class side maps used as stringification evidence;
4. direct-output conversion paths such as `puts` / `print`;
5. string-interpolation conversion paths;
6. type-literal `.name`, `.to_s`, and `inspect` query lowering, which must be
   preserved as the H4 guard expects.

Implementation receipt for the next code slice:

- introduce exactly one HIR-owned `TypeValue` / `RuntimeTypeIdentity` fact for
  the reached surface;
- the fact carries semantic `TypeRef`, canonical display name, origin
  (`typeof`, runtime `.class`, explicit type literal, or type-literal query),
  and runtime-stringification versus compile-time-only status;
- consumers must ask this fact for type-visible behavior instead of using
  pointer nil-ness, dot-class membership, rendered-name shortcuts, or backend
  stringification;
- emitted behavior may change only where the strict H6/B3/H4 gates cover it.

DoD for the implementation slice after 0k-BI:

- strict `regression_tests/type_value_core_runtime_identity_contract.sh
  <compiler>` passes;
- strict `regression_tests/original_vs_stage_semantic_oracle_contract.sh
  <compiler>` passes for the B3 type-visible rows;
- `regression_tests/p2_type_literal_name_query_no_stub.sh <compiler>` remains
  green;
- `regression_tests/command_call_member_access_preservation_contract.sh`
  remains a separate frontend frontier unless this same slice explicitly
  chooses the parser route, which is currently rejected for TypeValue-core work;
- `git diff --check` passes;
- TODO/LANDMARKS/SDD state whether generated `s2b` / `s3b` was actually run;
  without that evidence, no green bootstrap claim is admitted.

Stop rules:

- if the needed consumer set expands beyond the H6-core guard, stop at
  classification and either widen H6 first or return to the G3 semantic-key
  migration lane;
- if a fix wants generic materialization, `BlockOwner`, requested-name policy,
  ambient-map policy, backend forwarders/stubs, LLVM stringification, or broad
  `NamedTuple`/`Tuple` rendering changes, it is not a TypeValue implementation
  slice;
- if the implementation creates another local side map that is not the single
  owner fact consumed by all reached paths, treat it as a symptom patch and
  reject it before commit.

### Slice 0k-BE: architecture tranche selector before more code

Status:

- docs-only architecture checkpoint after the 0k-BD TypeValue receipt;
- no compiler behavior, output behavior, type-literal behavior,
  materialization behavior, generic behavior, backend behavior, cleanup
  behavior, `BlockOwner` carrier, requested-name policy, or ambient-map policy
  is changed by this slice.

Problem:

- the active board already rejects many old symptom patches, but it can still
  let the project turn each measured-red guard into another isolated local
  code slice;
- the current TypeValue receipt is well-scoped, yet a green H6/B3 result could
  still leave the larger `s2b`/`s3b` semantic-owner architecture unchanged;
- therefore the next production slice must declare its architecture tranche
  before editing code.

Tranche selector:

1. `contract-owner-migration` - a named old authority edge is retired or
   shadowed by one owned fact, with a focused falsifier and no unrelated
   behavior change.
2. `semantic-service-extraction` - a cross-cutting semantic service boundary is
   introduced in parity/shadow mode when single-row owner facts keep becoming
   islands. This is not a physical file split and not a rewrite.
3. `cleanup/delete` - a path is removed or quarantined only through
   `CodePathStatus`, runtime evidence, and a protecting falsifier.
4. `bootstrap-emergency-with-ledger` - an urgent generated-stage fix is allowed
   only if the same commit adds or consumes a surviving owner ledger/falsifier
   and states the residual boundary.

Current TypeValue classification:

- TypeValue is admitted only as `contract-owner-migration`;
- it must retire or shadow the named H6 authority edges from 0k-BD:
  `typeof` nil placeholder, runtime `.class` type-literal construction,
  dot-class side maps, direct-output conversion, interpolation conversion, and
  type-literal query lowering;
- it must not be used to claim green `s2b` / `s3b` unless those generated
  stages are actually run and pass their declared gates.

Stop rules:

- if the TypeValue implementation needs generic materialization, `BlockOwner`,
  requested-name policy, ambient-map policy, backend stubs/forwarders, LLVM
  stringification, or broad `NamedTuple`/`Tuple` rendering changes, stop and
  reclassify the work as G3 semantic-key migration or
  `semantic-service-extraction`;
- if a future code slice cannot name its tranche, old authority edge, owned
  fact, falsifier, and residual rejected surface, it is not admitted;
- if a slice merely moves the latest crash frontier while preserving the
  old authority edge, classify it as tail-chasing and reject it before commit.

Next local track:

- either implement 0k-BD under `contract-owner-migration`, or write a narrower
  `semantic-service-extraction` plan if the implementation preflight shows
  TypeValue cannot stay inside H6;
- this handoff is superseded by Slice 0k-BF, which records that the first
  implementation preflight did expose a separate frontend command-call
  boundary.

### Slice 0k-BF: failed TypeValue preflight exposes command-call frontend gap

Status:

- docs-only failed-preflight checkpoint;
- no compiler behavior, output behavior, type-literal behavior,
  materialization behavior, generic behavior, backend behavior, cleanup
  behavior, `BlockOwner` carrier, requested-name policy, or ambient-map policy
  is changed by this slice;
- the local production WIP that triggered this checkpoint was reverted before
  commit.

Problem:

- the 0k-BE tranche selector admitted TypeValue only as
  `contract-owner-migration`;
- a local WIP followed that direction by adding one HIR-owned type-visible
  value fact and migrating the H6-reached `typeof`, runtime `.class`,
  interpolation, direct-output, `<<`, and call-argument consumers;
- that WIP made the B3 semantic oracle and H4 type-literal no-stub guard green,
  but strict H6 still failed on one row:
  `puts (true ? 1 : nil).class` printed a blank line instead of `Int32`;
- controls under the same WIP showed `puts((true ? 1 : nil).class)`,
  `x = true ? 1 : nil; puts x.class`, and
  `"#{(true ? 1 : nil).class}"` all printed `Int32`.

Boundary:

- the failed H6 row is not another TypeValue owner edge;
- debug evidence under the reverted WIP showed the direct command-call argument
  reached lowering as `Adamas::Compiler::Frontend::TernaryNode`, not as a
  `.class` member access;
- the first new boundary is therefore frontend command-call expression
  preservation for `(expr).member` arguments, especially ternary/grouped
  expressions, not HIR TypeValue stringification.

Stop rules:

- do not make H6 green through a source-text direct-puts workaround;
- do not add backend stubs/forwarders, requested-name policy, ambient-map
  policy, `BlockOwner` rollback, generic materialization changes, or broad
  `NamedTuple`/`Tuple` rendering to solve this row;
- do not commit a TypeValue owner migration while the strict H6 guard still
  conflates TypeValue with command-call frontend preservation.

Next local track:

- classify/falsify the command-call `.class` preservation gap as its own
  `semantic-service-extraction` / parser-frontier slice; or
- split H6 into a TypeValue core guard plus a separate measured-red frontend
  command-call guard before resuming TypeValue production code.

### Slice 0k-BG: command-call member-access preservation guard

Status:

- executable falsifier for the 0k-BF frontend boundary;
- no compiler behavior, output behavior, type-literal behavior,
  materialization behavior, generic behavior, backend behavior, cleanup
  behavior, `BlockOwner` carrier, requested-name policy, ambient-map policy, or
  TypeValue owner fact is changed by this slice.

Guard:

- `regression_tests/command_call_member_access_preservation_contract.sh`;
- strict by default;
- measured-red mode:
  `ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH=1 regression_tests/command_call_member_access_preservation_contract.sh`.

Measured-red evidence:

- strict mode exits 1 today;
- current parser shape for `puts (true ? 1 : nil).class` is a root
  `Adamas::Compiler::Frontend::MemberAccessNode`, meaning `.class` is attached
  to the command-call result;
- the desired shape is a command `CallNode` whose single argument is a
  `.class` member access;
- measured-red mode exits 0 and records the mismatch.

Negative controls:

- `puts((true ? 1 : nil).class)` must parse as a command call with a `.class`
  argument;
- `x = true ? 1 : nil; puts x.class` must parse the second root as a command
  call with a `.class` argument;
- `puts (true ? 1 : nil)` must remain a command call with a ternary argument.

Boundary:

- this guard measures parser/frontend AST shape, not runtime stringification;
- it is not evidence that TypeValue is implemented or that B3/H6 are fixed;
- it gives the next production slice a frontend target without authorizing a
  source-text direct-output workaround.

Next local track:

- implement a `semantic-service-extraction` / parser-frontier slice that makes
  this guard strict-green without changing TypeValue, `BlockOwner`, generic
  materialization, requested-name policy, ambient-map policy, backend
  stubs/forwarders, or broad `NamedTuple`/`Tuple` rendering; then rerun H6 to
  see whether the remaining rows are pure TypeValue.

### Slice 0k-BH: Architecture Pause Gate after parser WIP

Status:

- docs-only frontier-control checkpoint;
- a local uncommitted parser WIP was removed before this checkpoint;
- no compiler behavior, parser behavior, TypeValue behavior, materialization
  behavior, backend behavior, or `BlockOwner` carrier changed by this slice.

Problem:

- Slice 0k-BG legitimately made the command-call parser boundary measured-red;
- the first local production attempt widened `LParen` handling in
  no-parens command-call parsing and added a tight postfix hook, which touches
  a broad parser precedence surface;
- that kind of parser change can easily become another latest-red-row chase
  unless it is treated as a bounded exception rather than the new default lane.

Decision:

- the next production code movement is paused until it chooses one of two
  routes before editing:
  - route A: one bounded `semantic-service-extraction` parser-frontier closure
    attempt for
    `regression_tests/command_call_member_access_preservation_contract.sh`;
  - route B: split H6 into a TypeValue-core guard and a measured-red
    command-call-frontend guard, then resume the TypeValue owner-fact migration.

Route A DoD:

- `regression_tests/command_call_member_access_preservation_contract.sh` is
  strict-green by default;
- the same guard fails under `ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH=1`,
  proving the measured-red inversion is closed;
- targeted parser specs covering ordinary parenthesized calls, typed fields,
  ternary command-call arguments, and command-call member access remain green;
- no TypeValue, materialization, `BlockOwner`, requested-name, ambient-map,
  backend stub/forwarder, or `NamedTuple`/`Tuple` rendering behavior changes.

Stop rules:

- if route A needs a second implementation loop, stop and take route B;
- if route A regresses adjacent parser specs, stop and take route B unless the
  regression is fixed by narrowing the same one-loop parser change;
- if route A grows into generic command-call precedence work, stop and take
  route B;
- if route A tries to green H6 through source-text direct-output handling,
  backend stubs/forwarders, or TypeValue output special-cases, reject it.

Boundary:

- this pause gate does not demote the 0k-BG guard; the command-call parser
  boundary is still measured-red;
- this pause gate does not implement TypeValue;
- this pause gate exists to prevent the parser exception from overriding the
  broader architecture rule: one owner per semantic decision.

### Slice 0k-BI: split H6 into TypeValue-core and command-call frontend

Status:

- guard/test plus ledger checkpoint;
- no compiler behavior, parser behavior, TypeValue behavior, materialization
  behavior, backend behavior, or `BlockOwner` carrier changed by this slice.

Problem:

- the original H6 guard correctly covered source-visible type values, but one
  row (`puts (true ? 1 : nil).class`) is now known to be parser-confounded;
- keeping that row inside the TypeValue implementation acceptance gate blocks
  owner-fact work on a frontend command-call bug;
- removing the row silently would weaken the contract unless the parser row has
  its own guard.

Implementation:

- add `regression_tests/type_value_core_runtime_identity_contract.sh <compiler>`;
- keep the old `regression_tests/type_value_runtime_identity_contract.sh`
  available as the wider historical/full-surface H6 guard;
- keep
  `regression_tests/command_call_member_access_preservation_contract.sh` as the
  separate measured-red frontend guard for the no-parens command-call row.

Core guard rows:

- direct `typeof(1)`;
- interpolated `typeof(1)`;
- direct `1.class`;
- interpolated `1.class`;
- local nilable `.class`;
- interpolated local nilable `.class`;
- parenthesized nilable `.class` through ordinary call parentheses;
- `Int32.name`, `Int32.to_s`, and `Int32.inspect`.

Fresh evidence:

- `ADAMAS_EXPECT_TYPEVALUE_CORE_MISMATCH=1
  regression_tests/type_value_core_runtime_identity_contract.sh bin/adamas`
  exits 0 and reports measured-red after the stage binary prints blank direct
  and interpolated `typeof` rows and exits 139 at `DIRECT_CLASS`;
- strict `regression_tests/type_value_core_runtime_identity_contract.sh
  bin/adamas` exits 1 on the same runtime failure;
- `ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH=1
  regression_tests/command_call_member_access_preservation_contract.sh`
  exits 0, proving the frontend command-call row remains separately
  measured-red.

Next local track:

- resume `contract-owner-migration` for a HIR-owned `TypeValue` /
  `RuntimeTypeIdentity` fact against the H6-core guard;
- after the core guard is strict-green, do not claim the full old H6 surface
  green until the command-call frontend guard is also resolved.

Forbidden repeats:

- do not put the no-parens command-call row back into the core TypeValue guard;
- do not make the core guard green with string-only `lower_typeof`,
  interpolation-only, direct-output-only, backend, or parser special-cases;
- do not change generic materialization, requested-name policy, ambient-map
  policy, `BlockOwner`, or broad `NamedTuple`/`Tuple` rendering in the
  TypeValue-core slice.

### Slice 0k-BJ: TypeValue owner-fact implementation gate

Status:

- docs-only design gate before the TypeValue production implementation;
- no compiler behavior, parser behavior, TypeValue behavior, materialization
  behavior, backend behavior, requested-name policy, ambient-map policy,
  `BlockOwner` carrier, or broad `NamedTuple`/`Tuple` rendering changes.

ProblemCard:

- signal: repeated frontiers were fixed locally, then reappeared one layer later
  because the underlying semantic owner did not move;
- why now: H6-core is measured-red and narrow enough to invite an output-only
  patch, while the SDD requires `contract-owner-migration`;
- bounded context: HIR type-visible values only;
- not merely: a test-green wish or a stringification patch;
- validation boundary: H6-core/B3/H4 plus source-shape evidence that old
  type-visible authority edges are no longer the consumers' sole authority.

Pre-action quadrum:

- Cassandra: the likely failure mode is a new side map that makes direct output
  and interpolation print `Int32` but leaves `typeof`, runtime `.class`,
  type-literal queries, and call-argument conversion as independent authorities;
- Maieutic: if the H6-core guard turns green but the consumers still decide
  source-visible type behavior from nil placeholders, `dot_class_literal?`, or
  rendered-name shortcuts, the slice is not architecture work;
- Daedalus: shift the next implementation from "fix output rows" to "install
  one HIR-owned fact and route every reached producer/consumer through it";
- Adversary verdict: direct code is admitted only if it can name the owner fact,
  producers, consumers, retired/shadowed old edges, and residual frontend row.

Required owner fact shape for the next code slice:

1. A named HIR-owned fact, `TypeValue` / `RuntimeTypeIdentity`, keyed to a
   `ValueId` at the HIR boundary. The first implementation may store it beside
   `LoweringContext` value metadata, but it must be the owner consulted by
   consumers, not a backend or output-only side table.
2. Required fields:
   - semantic `TypeRef`;
   - canonical display name;
   - origin: `typeof`, runtime `.class`, explicit type literal, or
     type-literal query;
   - runtime policy: compile-time-only value versus runtime stringification
     required.
3. Required producer coverage:
   - `lower_typeof`;
   - runtime `.class` lowering in member access;
   - `lower_type_literal_from_name`;
   - type-literal `.name` / `.to_s` / `inspect` query lowering when it creates a
     source-visible type string.
4. Required consumer coverage:
   - direct output paths that currently route through ordinary call lowering;
   - string interpolation conversion;
   - call-argument conversion for runtime `.class` values;
   - type-literal name/string query lowering protected by H4;
   - local/copy propagation for the H6-core local nilable rows.

Compatibility rule:

- `@type_literal_values` may remain temporarily as a static-call compatibility
  flag, but source-visible runtime stringification must not depend solely on
  `ctx.type_literal?`, `ctx.dot_class_literal?`, nil literal shape, or backend
  stringification after the implementation slice.
- `@dot_class_literals` is a legacy authority edge for stringification. A
  TypeValue patch may keep it only as a compatibility shim while each surviving
  use is justified as non-authoritative or replaced by the owner fact.

Implementation phases admitted inside one code slice:

1. Add the owner fact and producer helpers.
2. Route direct-output, interpolation, call-argument, and type-literal-query
   consumers through the fact.
3. Propagate the fact through local/copy paths needed by H6-core.
4. Leave the command-call parser guard separate and measured-red unless the
   slice explicitly changes tranche to parser `semantic-service-extraction`
   before editing parser code.

DoD for the next code slice:

- strict `regression_tests/type_value_core_runtime_identity_contract.sh
  <compiler>` passes;
- strict `regression_tests/original_vs_stage_semantic_oracle_contract.sh
  <compiler>` passes for the type-visible B3 rows;
- `regression_tests/p2_type_literal_name_query_no_stub.sh <compiler>` remains
  green;
- `ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH=1
  regression_tests/command_call_member_access_preservation_contract.sh` remains
  measured-red unless the slice explicitly chose the parser route first;
- source-shape review lists every remaining `dot_class_literal?` and
  `type_literal?` consumer touched by the slice and states whether it is
  compatibility-only or still an authority edge;
- `git diff --check` passes;
- TODO/LANDMARKS/SDD state whether generated `s2b` / `s3b` was actually run.

Stop rules:

- if the patch can pass H6-core without adding the named owner fact, reject it
  as a symptom fix;
- if direct output and interpolation become green but `typeof`, runtime
  `.class`, type-literal query, or local/copy propagation still has its own
  independent authority, stop and split the implementation;
- if the patch needs parser precedence, generic materialization, requested-name
  policy, ambient-map policy, backend stubs/forwarders, LLVM stringification,
  `BlockOwner`, or broad `NamedTuple`/`Tuple` behavior, stop and reclassify the
  slice before editing those surfaces;
- if a green H6-core result is used to claim old full-H6, generated `s2b`, or
  generated `s3b`, downgrade the claim: the command-call frontend guard and
  generated-stage evidence remain separate.

### Slice 0k-BL: Architecture execution ladder after WIP quarantine

Status:

- docs-only architecture checkpoint;
- the uncommitted TypeValue production WIP was moved out of the working tree
  before this slice and is not evidence of completion;
- no compiler behavior, parser behavior, materialization behavior, backend
  behavior, requested-name policy, ambient-map policy, `BlockOwner` carrier, or
  broad `NamedTuple`/`Tuple` rendering changes.

ProblemCard:

- signal: repeated frontier work keeps finding real bugs but also keeps
  re-entering local symptom loops after each guard turns green or moves;
- why now: the H6-core TypeValue lane is admitted, but an uncommitted WIP was
  already at risk of being continued as "the next thing" rather than as an
  architecture slice;
- bounded context: bootstrap architecture execution, not a new runtime feature;
- not merely: a request to stop forever or to abandon H6; the goal remains
  green `s2b`/`s3b` capable of compiling arbitrary programs;
- validation boundary: a future code slice must show owner-boundary migration
  and generated-stage relevance, not only focused guard output.

Execution ladder for every next production slice:

1. **Row selection.** Choose exactly one Active Architecture Board row and one
   tranche (`contract-owner-migration`, `semantic-service-extraction`,
   `cleanup/delete`, or `bootstrap-emergency-with-ledger`).
2. **Old authority edge.** Name the legacy authority being retired, shadowed,
   or refuted. Examples: nil `typeof` placeholders, `dot_class_literal?`
   stringification, ambient `@type_param_map`, rendered mangled names, bodyless
   function presence, or backend undefined-extern fallback.
3. **Owner fact or service.** Name the new owner fact/service and its lifetime.
   If the move cannot name one, it is a probe or SDD slice, not production
   architecture work.
4. **Producer/consumer map.** Enumerate producers and consumers before editing.
   A consumer may remain legacy only if it is named compatibility surface, not
   hidden authority.
5. **Measured-red baseline.** Run the smallest relevant falsifier in
   measured-red or strict-red mode before the patch. A stale stashed patch or
   old run is not baseline evidence.
6. **Focused DoD.** Run the row's focused guard after the patch and compare it
   to the baseline.
7. **Architecture DoD.** Run the source-shape or contract guard that proves the
   old authority edge is no longer the sole authority.
8. **Stage relevance.** State the generated-stage gate affected by the slice.
   If no generated-stage gate is run, state `not run` explicitly and do not
   claim `s2b`/`s3b` progress.
9. **Residual boundary.** Record any still-red guard in TODO/LANDMARKS before
   commit.

Immediate application to the quarantined TypeValue WIP:

- it may be resumed only as the H6-core `contract-owner-migration` row;
- before resuming, re-run the measured-red H6-core and B3 baselines on the
  current compiler;
- fix or explicitly scope `typeof` multi-argument behavior so the owner fact is
  not weaker than the source-visible contract it claims to represent;
- list every remaining `dot_class_literal?` and touched `type_literal?`
  consumer as either compatibility-only or still-authoritative;
- keep H7 command-call parsing measured-red and separate unless a new slice
  chooses parser `semantic-service-extraction` first.

Stop rules added by this slice:

- do not continue any stashed or local WIP by inertia;
- do not count focused guard green as architecture progress unless the old
  authority edge is migrated or explicitly refuted;
- do not start a second implementation loop in the same row if the first loop
  exposes a different owner boundary; stop and write the new boundary;
- do not use cleanup, report classification, or source-shape counters as
  substitutes for generated-stage relevance when the stated goal is green
  `s2b`/`s3b`;
- do not roll `BlockOwner` back to tuple or namedtuple owner metadata.

Next local track:

- either resume H6-core TypeValue through this ladder, or perform another
  docs-only consolidation that retires stale lanes before code resumes;
- no backend forwarder, target keepalive, materialization rescue, parser loop,
  global ambient-map policy change, or broad `NamedTuple`/`Tuple` rendering
  patch is admitted from this checkpoint.

### Slice 0k-BM: H6-core TypeValue owner-fact migration

Status:

- production behavior slice for the H6-core `contract-owner-migration` lane;
- implements a HIR-owned `RuntimeTypeIdentity` fact keyed by `ValueId`;
- updates the H6-core and B3 guards to include multi-argument `typeof`;
- adds a new measured-red residual guard for dynamic multi-variant union
  `.class`;
- does not change parser command-call behavior, generic materialization,
  requested-name policy, ambient-map policy, backend stub/forwarder behavior,
  `BlockOwner`, or broad `NamedTuple`/`Tuple` rendering.

Old authority edges retired or shadowed:

1. `typeof(...)` still lowers to a runtime nil placeholder, but direct output
   and interpolation no longer derive the source-visible type value from that
   placeholder shape. They consume `RuntimeTypeIdentity`.
2. Runtime `.class` still creates a type-literal value and marks the legacy
   `dot_class_literal?` side set, but H6-core stringification consumes
   `RuntimeTypeIdentity` first; `dot_class_literal?` remains a compatibility
   shim for still-legacy consumers.
3. Type-literal name/string query lowering marks the same owner fact for the
   emitted compile-time string.
4. Local/copy lowering propagates the fact for the H6-core local nilable rows.
5. Explicit type literals carry identity but stay non-stringifying by default;
   the `IO::ByteFormat::LittleEndian` adversary row is the regression guard for
   this boundary.

Producer coverage:

- `lower_typeof`, including multi-argument union construction;
- runtime `.class` lowering in member access;
- `lower_type_literal_from_name`;
- type-literal name/string query lowering.

Consumer coverage:

- string interpolation;
- direct `puts` / `print` interception;
- `<<` argument conversion;
- general call-argument conversion;
- local and assignment copy propagation needed by the core guard.

Guarded non-consumer boundary:

- explicit type literals such as `IO::ByteFormat::LittleEndian` are identity
  producers, but not string consumers. `materialize_runtime_type_identity_string`
  only fires when `runtime_stringification_required` is true, preventing format
  type/module values from becoming `String` call arguments.

Fresh evidence:

- clean-HEAD baseline:
  - `ADAMAS_EXPECT_TYPEVALUE_CORE_MISMATCH=1
    regression_tests/type_value_core_runtime_identity_contract.sh
    /tmp/adamas_0kbl_baseline` exits 0 with stage runtime rc 139 at
    `DIRECT_CLASS`;
  - `ADAMAS_EXPECT_ORIGINAL_STAGE_MISMATCH=1
    regression_tests/original_vs_stage_semantic_oracle_contract.sh
    /tmp/adamas_0kbl_baseline` exits 0 with blank `TYPE=` / `UNION=`;
  - `ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH=1
    regression_tests/command_call_member_access_preservation_contract.sh`
    exits 0, proving H7 remains separate.
- patched stage1:
  - `regression_tests/type_value_core_runtime_identity_contract.sh
    /tmp/adamas_0kbl_typevalue` exits 0;
  - `regression_tests/original_vs_stage_semantic_oracle_contract.sh
    /tmp/adamas_0kbl_typevalue` exits 0;
  - `regression_tests/p2_type_literal_name_query_no_stub.sh
    /tmp/adamas_0kbl_typevalue` exits 0;
  - `ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH=1
    regression_tests/command_call_member_access_preservation_contract.sh`
    exits 0;
  - `ADAMAS_EXPECT_DYNAMIC_UNION_CLASS_MISMATCH=1
    regression_tests/type_value_dynamic_union_class_residual.sh
    /tmp/adamas_0kbl_typevalue` exits 0, recording H8 as measured-red;
  - `regression_tests/test_byteformat_decode_u32.cr` compiled by
    `/tmp/adamas_0kbl_typevalue` and run through `scripts/run_safe.sh` prints
    `byteformat_u32_ok`, after a pre-fix falsifier showed the same row would
    abort at `String$Hencode$$UInt32_IO` if explicit type literals were
    stringified as generic call arguments;
  - `regression_tests/run_all_suites.sh /tmp/adamas_0kbl_typevalue 4` exits 0:
    `152/152` original tests and `36/36` combined tests pass.

Residual boundaries:

- H7 no-parens command-call member-access preservation is still measured-red
  and belongs to parser `semantic-service-extraction`.
- H8 dynamic multi-variant union `.class` is still measured-red: current stage
  prints the static union display `Int32 | String` where original Crystal
  prints runtime concrete `Int32`. This needs a runtime type-name service
  linked to the HIR-owned identity, not a backend-only stringification stub.
- Full `s2b` / `s3b` bootstrap has not been claimed by this slice.

Historical ledger resumes below. Entries after this point predate the current
Active Architecture Board / 0k-BG receipt unless they are explicitly referenced
by the board as current evidence.

Current selected implementation status: Slice 0k-AH is a behavior-neutral
consumer migration. Instance-method override, keepalive, and diagnostic
materialization-symbol consumers now read from `CallMaterializationTransaction`
fields instead of direct `MaterializationSymbolBinding` field reads.
`MaterializationSymbolBinding` remains a parity input to transaction
construction, not the downstream authority for the selected consumer group.
This is not a behavior flip and not a green bootstrap claim. It deliberately
pauses generated-stage crash-stack pursuit unless the next generated-stage run
answers a specific transaction-spine yes/no question. After 0k-AH, continuing
to reduce `residual_legacy_edge_count` without that generated-stage reachability
answer is classified as tail-chasing: it may make the source-shape metric
smaller while leaving the active `s2b`/`s3b` frontier untouched.

Architecture pacing checkpoint after Slice 0k-AH:

- Claim under review: another transaction-consumer migration is the best next
  move.
- Strongest hostile interpretation: this can become metric chasing. The current
  `residual_legacy_edge_count=20` is a useful source-shape debt counter, but it
  does not prove that the remaining generated-stage failure is still on the
  transaction path.
- Required falsifier before more production transaction work: a fresh generated
  s2 full-prelude classifier must report whether `[MAT_TX]` and `[MAT_EMIT]`
  are reached before the frontier. `scripts/materialization_transaction_report.sh`
  is the existing lower-level report; a wrapper script is admitted only if it
  builds/uses a fresh generated s2 through `scripts/run_safe.sh`, records
  reached/not-reached status, and deletes its temporary artifacts.
- Decision table:
  - `reached_tx_and_emit`: continue with a reached transaction consumer
    selection gate.
  - `tx_only_no_emit`: next owner is transaction-to-MIR/backend emission
    correlation, not another HIR consumer migration.
  - `no_tx_rows`: transaction lane is not currently reached; switch to the
    reached owner boundary or `CodePathStatus` cleanup.
  - `s2_build_fails`: do not infer transaction status; first restore the
    generated compiler build corridor.

Executed result after Slice 0k-AI: the classifier reported
`classification=reached_tx_and_emit`, `s2_build_rc=0`, `compiler_rc=139`,
`mat_tx_rows=615`, `mat_emit_rows=69`,
`transaction_bound_mat_emit_rows=29`, and `stub_rows=0` on a fresh generated s2
full-prelude `puts 42` corridor. The current failure is therefore after the
transaction spine is reached, not before it. The next production slice must
select a reached transaction/emission edge; it must not patch the segfault or
continue source-shape debt reduction without naming the reached edge.

Executed result after Slice 0k-AJ: the selector reported
`classifier_classification=reached_tx_and_emit`, `mat_tx_rows=604`,
`mat_emit_rows=69`, `transaction_bound_emit_rows=29`,
`candidate_selected_rows=4`, `candidate_selected_distinct_txs=3`,
`candidate_selected_owner_kinds=2`, `candidate_selected_branch_kinds=1`,
`source_shape=eligible_reached_edge`, and
`selection_status=eligible_reached_transaction_emission_edge`. The selected
edge is `call_materialization.wrapper_or_call_remap.extern_missing_body`, whose
old authority is backend extern emission from `call_symbol_hint` without a
body and whose owned transaction facts are `required_contract`, `body_symbol`,
and `call_symbol_hint`. Negative control: the same log with
`MAX_SELECTED_ROWS=3` is rejected as `selected_edge_too_wide`.

Slice 0k-AK checkpoint: an uncommitted behavior-neutral shadow-consumer WIP
that copied transaction contract facts from HIR to MIR call instructions and
printed them in backend `[MAT_EMIT]` rows was removed before commit. The WIP was
directionally aligned with Phase 2b, but it was not yet an admitted slice: it
made the previous 0k-AJ selected edge decay without first updating the board's
success semantics. The lesson is now part of the gate: after a consumer is
added, `REQUIRE_SELECTED=1` may legitimately stop proving the same thing. The
next slice must distinguish three states explicitly: `selected_not_consumed`,
`selected_consumed_by_contract_consumer`, and `selected_refuted_or_stale`.
Only `selected_not_consumed` authorizes implementing the old consumer as-is.
Only `selected_consumed_by_contract_consumer` authorizes selecting the next
edge. `selected_refuted_or_stale` returns to the architecture board and must
not be papered over by backend repair, row redefinition, or another diagnostic
wrapper.

Executed result after Slice 0k-AL: the selector now makes the 0k-AK state
machine executable. `scripts/generated_stage_transaction_edge_selection_report.sh`
prints `post_consumer_state` and accepts
`REQUIRE_POST_CONSUMER_STATE=<state>`. Synthetic ledger checks covered all three
states (`selected_not_consumed`,
`selected_consumed_by_contract_consumer`, and `selected_refuted_or_stale`).
A fresh generated-stage corridor using a freshly built stage1 reports
`classifier_classification=reached_tx_and_emit`, `mat_tx_rows=591`,
`mat_emit_rows=69`, `transaction_bound_emit_rows=29`,
`candidate_selected_rows=4`, `candidate_selected_distinct_txs=3`,
`contract_consumer_rows=0`, `candidate_contract_consumer_rows=0`,
`contract_mismatch_rows=0`, `selection_status=eligible_reached_transaction_emission_edge`,
and `post_consumer_state=selected_not_consumed`. This is executable permission
for the next behavior-neutral consumer slice, not permission for a behavior
fix.

Executed result after Slice 0k-AM: the behavior-neutral contract consumer is
implemented. The HIR module records `MaterializationTransactionContract` facts
by transaction id, HIR-to-MIR lowers them into `MaterializationContractFacts` on
transaction-bound `Call` and `ExternCall`, backend `[MAT_EMIT]` prints the
contract fields, and MIR optimizer call copies preserve both transaction id and
contract metadata. A fresh generated-stage corridor reports
`classifier_classification=reached_tx_and_emit`, `mat_tx_rows=735`,
`mat_emit_rows=173`, `transaction_bound_emit_rows=68`,
`candidate_selected_rows=0`, `contract_consumer_rows=2`,
`candidate_contract_consumer_rows=2`, `contract_mismatch_rows=0`,
`selection_status=eligible_contract_consumer_state`, and
`post_consumer_state=selected_consumed_by_contract_consumer`. The old selected
edge is therefore consumed. Remaining generated-stage residual includes
`other_missing_body_rows=14` exact-contract missing-body rows, which is too
broad for a behavior patch and requires a new selector.

Executed result after Slice 0k-AO: the existing generated-stage transaction edge
selector now also classifies the post-consumer exact-contract missing-body
residual. It creates `tmp/` before `mktemp` so cleanup of repo-local scratch does
not break future gates. Synthetic logs covered `eligible`,
`rejected_exact_missing_body_ambiguous`,
`rejected_exact_missing_body_too_wide`, and
`no_exact_missing_body_residual`. Fresh generated-stage evidence reports
`classifier_classification=reached_tx_and_emit`,
`post_consumer_state=selected_consumed_by_contract_consumer`,
`contract_mismatch_rows=0`, `other_missing_body_rows=14`,
`residual_exact_missing_body_rows=14`,
`residual_exact_missing_body_groups=9`,
`residual_exact_missing_body_root_sized_groups=9`, and
`residual_selection_status=rejected_exact_missing_body_ambiguous`. Negative
control: `REQUIRE_RESIDUAL_SELECTED=1` exits 9 on the same log. Decision: there
is no selected residual behavior-fix edge yet. The samples are routing evidence,
not a license to patch `Array`, `Slice`, `IO`, `Atomic`, `StaticArray`,
`String::Builder`, or `Int32` materialization paths directly.

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

Immediate stop rule after Slice 0k-AA: the next generated-stage crash stack
must not select the next fix by itself. If the stack points at `lower_super`,
inline-yield, block callbacks, or proc lowering, first choose the
`InvocationContext` authority edge and add a source-shape gate. Do not add
another env-gated context ledger unless the same slice records the decision
question, owner fact, consumer seam, cleanup rule, and red/green admission
command.

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

15. Transaction consumers cannot bypass the transaction.
    A `CallMaterializationTransaction` slice is not complete merely because a
    transaction record exists. The selected consumer must read the symbol, state,
    ABI, and wrapper/forwarder facts from that transaction record; direct reads
    from older local records such as `MaterializationSymbolBinding` may remain
    only inside the transaction constructor/helper as parity inputs. If a
    consumer still reads the older record directly, the transaction is a shadow
    observation, not the owner boundary for that decision.

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
- `BlockOwner` owner-cache materialization successor - the current
  `Hash(UInt64, BlockOwner)#[]=` carrier must not emit a call to a symbol whose
  body was materialized only under a different target symbol. The old
  `hash_named_tuple_index_assign_materialization_repro.sh` was retired because
  it targeted the obsolete `Hash(UInt64, NamedTuple)#[]=` shape.
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

### Slice 0k-Z: MaterializationSymbolBinding shadow seam

Status:

- behavior-neutral compiler source slice;
- the selected `MaterializationIdentity` /
  `lower_function_if_needed.symbol_binding` seam is now promoted in
  shadow/parity mode;
- emitted materialization symbols remain legacy-equivalent;
- no backend remangling, undefined-extern rescue, target keepalive behavior
  patch, `NamedTuple`/`Tuple` rendering change, ambient-map policy change,
  `BlockOwner` carrier change, or deletion behavior changed.

Source/spec:

- `src/compiler/hir/ast_to_hir.cr`;
- `scripts/materialization_symbol_binding_admission_report.sh`;
- SDD Slice 0k-X receipt and Slice 0k-Y source-shape gate.

Implementation:

- add `MaterializationSymbolBinding`, carrying requested symbol, target symbol,
  materialization state key, body symbol, call-symbol hint, override symbol,
  and override reason;
- replace the early inline `materialized_name = if ...` branch with
  `materialization_symbol_binding_state_key`;
- replace the instance-method inline `override = if ...` branch with
  `materialization_symbol_binding`;
- make `record_materialization_keepalive_candidate` consume
  `symbol_binding.requested_name`, `symbol_binding.target_name`, and
  `symbol_binding.body_symbol`;
- make instance-method, class-method, and top-level-def
  `log_materialization_identity_ledger` calls consume
  `MaterializationSymbolBinding` fields instead of separate symbol locals.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/adamas_symbind_stage1
  --error-trace` exits 0;
- `scripts/materialization_symbol_binding_admission_report.sh` and
  `REQUIRE_PROMOTED=1 scripts/materialization_symbol_binding_admission_report.sh`
  report `source_shape=already_promoted_shadow`,
  `old_materialized_branch_count=0`, `old_override_branch_count=0`,
  `direct_keepalive_count=0`, `direct_ledger_materialized_count=0`, and
  `direct_ledger_override_count=0`;
- `scripts/method_name_codec_admission_report.sh` and its
  `REQUIRE_PROMOTED=1` variant still report `already_promoted_shadow`;
- `scripts/materialization_transaction_report.sh
  /private/tmp/adamas_symbind_stage1` exits 0 with `rows=2513`,
  `malformed=0`, `malformed_emit=0`, and `owner_malformed=0`;
- `scripts/materialization_promotion_selection_report.sh
  /private/tmp/adamas_symbind_stage1` exits 0 with `malformed=0`,
  `invalid_owner=0`, `invalid_legacy_result=0`, `invalid_would_change=0`, and
  `lower_function_if_needed.override` still `already_promoted_shadow`;
- `scripts/semantic_decision_census.sh` and
  `scripts/codepath_status_census.sh` still run;
- `regression_tests/run_all_suites.sh /private/tmp/adamas_symbind_stage1 4`
  passes `152/152 + 36/36`;
- `scripts/run_safe.sh /private/tmp/adamas_symbind_stage1 300 4096
  src/adamas.cr -o /private/tmp/adamas_symbind_s2` exits 0;
- generated s2 no-prelude smoke compiles and runs `x = 1; puts x` with
  runtime output `1`.

Residual boundary:

- generated s2 full-prelude smoke still exits 139 after
  `pass3 after lower_main call`;
- therefore this slice is an architecture authority migration, not a green
  full-prelude generated-s2, `s2b`, or `s3b` claim.

Next local track:

- run a fresh generated-stage materialization/symbol-binding classification on
  the residual full-prelude crash, or select the next root-sized owner consumer
  from the active board with a red/green source-shape gate;
- do not treat `MaterializationSymbolBinding` parity promotion as permission to
  force requested-name behavior, add backend forwarders, change target
  keepalive behavior, normalize `NamedTuple`/`Tuple` display strings, change
  ambient-map policy globally, or roll back `BlockOwner`.

### Slice 0k-AA: InvocationContext gate after diagnostic scratch rejection

Status:

- design-sealed docs-only checkpoint after Slice 0k-Z;
- no compiler behavior, materialization behavior, super-call behavior,
  inline-yield behavior, backend behavior, cleanup behavior, or `BlockOwner`
  carrier is changed by this slice;
- a local `ADAMAS_SUPER_CALL_CONTEXT_LEDGER` / `SUPER_CTX` diagnostic WIP was
  removed as non-admitted report-surface growth because the SDD had not first
  named the decision question, owner fact, source-shape gate, or cleanup rule.

ProblemCard:

- signal: the residual generated-s2 full-prelude smoke still exits 139 after
  `pass3 after lower_main call`, after Slice 0k-Z moved the selected
  materialization symbol-binding seam to shadow/parity ownership;
- suspected class: invocation context is still stored in ambient mutable fields
  while inline-yield, proc, block, super, and previous-def lowering reuse the
  same `AstToHir` instance;
- strongest symptom-fix temptation: patch `lower_super`, argument forwarding,
  or inline-yield stacks at the latest crash point;
- why rejected: the repeated bootstrap pattern is not "one bad consumer"; it is
  ambient state being treated as semantic authority outside its valid lowering
  frame.

Old authority edge:

- direct reads of `@current_class`, `@current_method`,
  `@current_method_is_class`, `@current_super_source_module`, inline-yield
  depth/stacks, and current `LoweringContext` params at consumers such as
  `lower_super` / `lower_previous_def`;
- these values are phase-local process state, not an owned invocation identity
  for nested inline-yield/proc/block bodies.

Owned edge to design before code:

- an explicit `InvocationContext` / `InlineYieldFrame` record, name may vary,
  that carries the owner class/module, method name, class-vs-instance bit,
  source module, function name, self-param shape, block/proc/yield frame, and
  forwardable argument policy for the currently lowered body;
- consumers such as `lower_super` and `lower_previous_def` must read from this
  frame in shadow/parity mode before any emitted behavior changes.

Admitted next implementation:

1. Add a source-shape gate, for example
   `scripts/invocation_context_admission_report.sh`, that is red before code
   and green only when exactly one selected consumer seam no longer reaches
   directly for the legacy ambient invocation state as its sole authority.
2. Then add a behavior-neutral shadow/parity helper for that seam. The helper
   may compute owner-result context, but it must return legacy behavior until a
   would-change census is root-sized and tied to a generated-stage residual.

Rejected next moves:

- committing `ADAMAS_SUPER_CALL_CONTEXT_LEDGER` or any equivalent context
  report before the source-shape gate exists;
- patching `lower_super` directly from a crash stack;
- changing implicit `super` argument forwarding, parent lookup, or previous-def
  lookup without an `InvocationContext` owner record;
- resetting inline-yield/proc/block stacks as a consumer guard;
- using backend stubs, undefined externs, or runtime abort sites as the first
  semantic discovery point;
- rolling `BlockOwner` back to tuple/namedtuple metadata.

DoD for the next executable slice:

- `bash -n scripts/invocation_context_admission_report.sh`;
- the report identifies the selected seam and prints the old direct ambient
  reads that keep the gate red;
- `REQUIRE_PROMOTED=1 scripts/invocation_context_admission_report.sh` fails
  before implementation and passes only after the selected consumer reads the
  new owner/shadow helper;
- default compiler behavior remains unchanged;
- TODO/LANDMARKS record the generated-stage boundary and residual risk without
  claiming green `s2b`/`s3b`.

Residual boundary:

- generated s2 full-prelude still needs a fresh owner-boundary classification
  after this docs-only gate;
- this slice authorizes planning and a source-shape gate, not a behavior fix.

Next local track:

- implement the source-shape gate for `InvocationContext` / `InlineYieldFrame`,
  or explicitly choose another active-board owner row if a fresher generated
  stage run refutes invocation context as the active boundary.

### Slice 0k-AB: InvocationContext source-shape admission gate

Status:

- behavior-neutral source-shape gate;
- no compiler behavior, super-call behavior, inline-yield behavior, backend
  behavior, cleanup behavior, or `BlockOwner` carrier is changed by this slice;
- the selected seam is `lower_super.previous_def.invocation_context`.

Source/spec:

- `src/compiler/hir/ast_to_hir.cr`;
- `scripts/invocation_context_admission_report.sh`;
- Slice 0k-AA `InvocationContext` / `InlineYieldFrame` gate.

Implementation:

- add `scripts/invocation_context_admission_report.sh`;
- inspect only the source shape of `lower_super` and `lower_previous_def`;
- classify the current source as `legacy_ambient_context_edge` when those
  consumers still read ambient invocation state directly and no
  invocation-frame helper is present;
- classify future code as `already_promoted_shadow` only when both selected
  consumers read an `InvocationContext` / `InlineYieldFrame` style helper and
  no direct selected-seam ambient reads remain.

Measured-red evidence:

- `bash -n scripts/invocation_context_admission_report.sh` exits 0;
- `scripts/invocation_context_admission_report.sh` exits 0 with
  `preferred_source_shape=legacy_ambient_context_edge` and
  `selection_status=eligible_invocation_context_owner`;
- current counts: `ambient_owner_method_count=4`, `ambient_kind_count=2`,
  `ambient_super_source_count=9`, `direct_forward_policy_count=2`,
  `invocation_helper_count=0`;
- `REQUIRE_PROMOTED=1 scripts/invocation_context_admission_report.sh` exits 9,
  proving the selected seam has not been promoted yet.

Boundary:

- the gate is a source-shape falsifier, not a runtime proof and not a green
  `s2b`/`s3b` claim;
- it does not by itself prove that invocation context is the only remaining
  generated-stage residual. It only prevents a direct `lower_super` consumer
  patch before the owned frame exists.

Next local track:

- implement a behavior-neutral `InvocationContext` / `InlineYieldFrame`
  shadow/parity helper for exactly this selected seam;
- keep emitted behavior legacy until the source-shape gate is green and a later
  would-change/generated-stage check is root-sized.

### Slice 0k-AC: InvocationContext shadow seam

Status:

- behavior-neutral owner-consumption helper after Slice 0k-AB;
- no super-call lookup, previous-def lookup, argument-forwarding behavior,
  inline-yield behavior, backend behavior, cleanup behavior, or `BlockOwner`
  carrier changed;
- the selected seam remains `lower_super.previous_def.invocation_context`.

Source/spec:

- `src/compiler/hir/ast_to_hir.cr`;
- `scripts/invocation_context_admission_report.sh`;
- Slice 0k-AA / 0k-AB `InvocationContext` / `InlineYieldFrame` gate.

Implementation:

- add `InvocationContext`, carrying current owner class, method name,
  class-vs-instance bit, current super-source module, current function name,
  and legacy forwardable argument ids;
- add `invocation_context_for_current_method(ctx)` as the only selected-seam
  owner-fact constructor;
- add `with_invocation_super_source` so nested module-super lowering still
  scopes `@current_super_source_module` with the legacy save/restore behavior
  while the selected consumers no longer mutate the ambient field directly;
- update `lower_super` and `lower_previous_def` to consume the
  `InvocationContext` fields instead of direct reads of `@current_class`,
  `@current_method`, `@current_method_is_class`,
  `@current_super_source_module`, or `current_method_forward_arg_ids(ctx)`.

Evidence:

- `bash -n scripts/invocation_context_admission_report.sh`;
- `scripts/invocation_context_admission_report.sh` reports
  `preferred_source_shape=already_promoted_shadow` with
  `ambient_owner_method_count=0`, `ambient_kind_count=0`,
  `ambient_super_source_count=0`, `direct_forward_policy_count=0`,
  `lower_super_helper_count=9`, and `lower_previous_def_helper_count=4`;
- `REQUIRE_PROMOTED=1 scripts/invocation_context_admission_report.sh` exits 0;
- `scripts/materialization_symbol_binding_admission_report.sh` and
  `REQUIRE_PROMOTED=1 scripts/materialization_symbol_binding_admission_report.sh`
  still report `already_promoted_shadow`;
- `scripts/method_name_codec_admission_report.sh` and
  `REQUIRE_PROMOTED=1 scripts/method_name_codec_admission_report.sh` still
  report `already_promoted_shadow`;
- `scripts/semantic_decision_census.sh` and
  `scripts/codepath_status_census.sh` run;
- `crystal build src/adamas.cr -o /private/tmp/adamas_invctx_stage1
  --error-trace` exits 0;
- `regression_tests/run_all_suites.sh /private/tmp/adamas_invctx_stage1 4`
  passes `152/152 + 36/36`.

Boundary:

- this is a source-shape and broad-regression proof for the selected
  consumer-migration seam, not a runtime proof that invocation context is the
  only remaining generated-stage residual;
- it does not claim green full-prelude generated s2, `s2b`, or `s3b`;
- it does not authorize super/previous-def behavior changes, inline-yield
  stack resets, backend undefined-extern rescue, materialization-name flips,
  or `BlockOwner` carrier changes.

Next local track:

- either run a fresh generated-stage owner-boundary classification after this
  shadow migration, or select another active-board row with a red/green gate;
- do not add another `InvocationContext` report unless the SDD names the
  decision question, cleanup rule, and consumer edge it will reduce or refute.

### Slice 0k-AD: Call/Materialization Transaction Spine checkpoint

Status:

- docs-only architecture selection checkpoint after Slice 0k-AC;
- no compiler behavior, source code, report script, backend behavior,
  cleanup behavior, or `BlockOwner` carrier changed;
- selects the next correctness axis as a vertical
  `CallMaterializationTransaction` spine rather than another generated-stage
  crash-stack-local seam.

Problem:

- recent slices correctly promoted several small owner facts in shadow/parity
  mode, but the repeated expensive bootstrap frontiers still share one broader
  failure shape: call, selected definition, materialization, emitted call, state
  scope, name parsing, and ABI facts can disagree because no single transaction
  owns the decision end to end;
- continuing seam-by-seam shadow migration without a vertical transaction risks
  replacing symptom patches with shadow-seam tail-chasing.

Selected owned fact:

```text
CallMaterializationTransaction {
  request_name_parts
  requested_symbol
  selected_def
  selected_owner
  state_scope
  target_symbol
  materialization_key
  body_symbol
  emitted_call_symbol
  callsite_arg_types
  target_type_param_map
  abi_shape
  wrapper_forwarder_contract
  rejection_reason
}
```

Old authority edges to reduce:

- rendered-name parsing at individual materialization and lookup callsites;
- ambient `@type_param_map` / state-scope reads during naming decisions;
- split requested/target/body/call symbol locals in
  `lower_function_if_needed_impl`;
- backend undefined-extern or emitted-call state as the first authority for
  whether a body/call mismatch is valid;
- generated-stage crash stacks that select the next patch before the
  transaction identity question is named.

Next executable slice:

- Slice 0k-AE: add a red/green source-shape gate for this transaction spine;
- the gate must be red on current source until it proves that exactly one
  selected legacy consumer still obtains transaction facts from split locals,
  rendered strings, or ambient maps instead of from a single owner record;
- the future 0k-AF code slice may only add a behavior-neutral transaction
  record/helper if that 0k-AE gate exists and names the consumer to migrate.

Stop rules:

- a generated-stage report is not progress unless it answers a
  transaction-spine yes/no question such as "did requested, selected, target,
  body, and emitted call agree under one transaction id?";
- a source-shape report is not progress if it only prints existing ledger rows
  without selecting a consumer edge;
- a backend forwarder, requested-name force, target keepalive patch,
  `NamedTuple`/`Tuple` rendering change, or global ambient-map predicate change
  remains rejected until it consumes a transaction row and a would-change
  census proves the affected set is root-sized;
- `BlockOwner` remains the admitted owner-metadata carrier and must not be
  rolled back to tuple/namedtuple metadata as part of this slice.

DoD for 0k-AD:

- the Active Architecture Board names `CallMaterializationTransaction` as the
  selected next correctness axis;
- `TODO.md`, `LANDMARKS.md`, and
  `docs/compiler_refactor_architecture_plan.md` point the next executable work
  at Slice 0k-AE rather than at the latest generated-stage crash;
- no production code or report script changed in this slice.

Boundary:

- this is a plan/selection checkpoint, not an implementation and not a green
  full-prelude generated s2, `s2b`, or `s3b` claim;
- it does not refute the existing Active Board rows. It requires the next
  correctness move to connect the most relevant rows vertically before any
  behavior flip.

Next local track:

- implement the 0k-AE source-shape admission gate for one
  `CallMaterializationTransaction` consumer seam;
- the likely first seam is still in `lower_function_if_needed_impl`, but the
  gate must select it by authority edge and source shape, not by memory of the
  last stub or crash.

### Slice 0k-AE: CallMaterializationTransaction source-shape gate

Status:

- behavior-neutral source-shape gate after Slice 0k-AD;
- no compiler behavior, source code in `src/`, backend behavior, cleanup
  behavior, or `BlockOwner` carrier changed;
- the selected seam is
  `lower_function_if_needed.call_materialization_transaction`.

Source/spec:

- `src/compiler/hir/ast_to_hir.cr`;
- `scripts/call_materialization_transaction_admission_report.sh`;
- Slice 0k-AD `CallMaterializationTransaction` spine checkpoint.

Implementation:

- add `scripts/call_materialization_transaction_admission_report.sh`;
- inspect only the source shape of `lower_function_if_needed_impl`;
- classify current source as `legacy_split_transaction_edge` when the selected
  method has no `CallMaterializationTransaction` record/helper and still splits
  transaction facts across `target_name`, `materialized_name`, ambient
  state-scope consumers, legacy ledger calls, direct type-param scopes, body
  lowering calls, and `MaterializationSymbolBinding` field reads;
- classify future 0k-AF code as `already_promoted_shadow` when the selected
  ledger/state-scope consumer has a `CallMaterializationTransaction`
  type/helper, the selected consumer reads transaction fields, and the old
  split-argument `log_materialization_identity_ledger(...)` calls are gone;
- continue reporting residual split authority edges such as direct body lowering,
  direct type-param scopes, and `MaterializationSymbolBinding` field reads
  without treating them as proof that the selected consumer failed to migrate.

Measured-red evidence:

- `bash -n scripts/call_materialization_transaction_admission_report.sh` exits 0;
- `scripts/call_materialization_transaction_admission_report.sh` exits 0 with
  `preferred_source_shape=legacy_split_transaction_edge` and
  `selection_status=eligible_transaction_spine_owner`;
- current counts include `transaction_type_count=0`,
  `transaction_helper_count=0`, `split_state_key_count=1`,
  `split_target_count=1`, `ambient_state_scope_consumer_count=1`,
  `legacy_ledger_call_count=3`, `direct_type_param_scope_count=5`,
  `direct_body_lowering_count=12`, `symbol_binding_field_read_count=24`, and
  `transaction_field_read_count=0`;
- `REQUIRE_PROMOTED=1
  scripts/call_materialization_transaction_admission_report.sh` exits 9,
  proving the selected seam is not promoted yet.

Boundary:

- the gate is source-shape evidence only, not runtime proof and not a green
  full-prelude generated s2, `s2b`, or `s3b` claim;
- it does not prove every call/materialization bug is caused by this seam. It
  selects the first vertical transaction owner edge and blocks behavior patches
  until that edge has a shadow/parity owner record.

Next local track:

- Slice 0k-AF: implement a behavior-neutral `CallMaterializationTransaction`
  record/helper for exactly this selected seam;
- the next code slice must preserve emitted behavior and turn
  `REQUIRE_PROMOTED=1 scripts/call_materialization_transaction_admission_report.sh`
  green by making one selected consumer read the transaction record instead of
  split locals, rendered strings, or ambient maps.

### Slice 0k-AF: CallMaterializationTransaction ledger-consumer promotion

Status:

- behavior-neutral source/ledger consumer migration after Slice 0k-AE;
- no emitted symbol behavior, backend behavior, requested-name policy,
  target keepalive policy, `NamedTuple`/`Tuple` rendering behavior, ambient-map
  policy, cleanup behavior, or `BlockOwner` carrier changed;
- the selected consumer is the materialization identity/state-scope ledger path
  in `lower_function_if_needed_impl`.

Source/spec:

- `src/compiler/hir/ast_to_hir.cr`;
- `scripts/call_materialization_transaction_admission_report.sh`;
- `scripts/materialization_symbol_binding_admission_report.sh`;
- Slice 0k-AD/0k-AE `CallMaterializationTransaction` spine checkpoint.

Implementation:

- promote the old `MaterializationIdentityTransaction` debug record into a
  `CallMaterializationTransaction` owner record carrying request name parts,
  requested/target/body/call symbols, selected definition and owner, state
  scope, target map, callsite arg shape, ABI shape, wrapper/forwarder contract,
  and rejection reason;
- add `call_materialization_transaction(...)` as the single constructor for the
  selected ledger consumer;
- replace the three split-argument `log_materialization_identity_ledger(...)`
  calls with transaction construction plus
  `log_call_materialization_transaction_ledger(transaction)`;
- keep emitted behavior identical: body lowering, override selection, keepalive,
  and type-param scoping still use the legacy values;
- update the `MaterializationSymbolBinding` gate so the previously promoted
  binding seam remains green when its ledger consumer advances to the transaction
  helper instead of reading `symbol_binding.*` directly.

Measured-green evidence:

- `bash -n scripts/call_materialization_transaction_admission_report.sh` exits 0;
- `REQUIRE_PROMOTED=1
  scripts/call_materialization_transaction_admission_report.sh` exits 0 with
  `preferred_source_shape=already_promoted_shadow`,
  `transaction_type_count=3`, `transaction_helper_count=3`,
  `legacy_ledger_call_count=0`, `transaction_ledger_call_count=3`,
  `ledger_transaction_field_read_count=4`, and
  `residual_legacy_edge_count=26`;
- `REQUIRE_PROMOTED=1
  scripts/materialization_symbol_binding_admission_report.sh` exits 0 with
  `binding_transaction_count=3`, proving the older binding seam is still
  promoted through the new transaction consumer path;
- `crystal build src/adamas.cr -o /private/tmp/adamas_0kaf_stage1 --error-trace`
  exits 0;
- `scripts/materialization_identity_ledger_smoke.sh
  /private/tmp/adamas_0kaf_stage1` exits 0;
- `scripts/materialization_transaction_report.sh
  /private/tmp/adamas_0kaf_stage1` exits 0 with `malformed=0`,
  `owner_malformed=0`, and `unjoined_emit_rows=0`;
- `regression_tests/run_all_suites.sh /private/tmp/adamas_0kaf_stage1 4`
  passes `152/152 + 36/36`.

Boundary:

- this is a selected-consumer source-shape and default-off ledger migration, not
  full transaction-spine completion and not green full-prelude generated s2,
  `s2b`, or `s3b`;
- residual legacy edges remain visible in the transaction gate and require later
  slices before any behavior flip is admitted.

Next local track:

- either select the next transaction consumer to migrate with a red/green
  source-shape gate, or run a generated-stage classifier only if it answers the
  transaction yes/no question for requested, selected, target, body, emitted
  call, state-scope, and ABI agreement under one transaction id.

### Slice 0k-AG: Transaction consumer stop-rule and next-edge selection

Status:

- behavior-neutral source-shape selection after Slice 0k-AF;
- no compiler source, emitted symbol behavior, backend behavior,
  requested-name policy, target keepalive policy, `NamedTuple`/`Tuple`
  rendering behavior, ambient-map policy, cleanup behavior, or `BlockOwner`
  carrier changed;
- the selected next edge is
  `lower_function_if_needed.instance_symbol_consumers`.

Problem:

- 0k-AF introduced a `CallMaterializationTransaction` owner record, but only the
  materialization identity/state-scope ledger path consumes it;
- the instance branch still computes override, keepalive, and diagnostic
  materialization-symbol facts from `MaterializationSymbolBinding` fields
  directly;
- continuing code slices without a transaction-consumer stop-rule would risk
  converting the transaction into another shadow row while the real consumers
  keep treating the older binding record as authority.

Source/spec:

- `scripts/call_materialization_transaction_consumer_selection_report.sh`;
- `src/compiler/hir/ast_to_hir.cr`;
- Slice 0k-AF `CallMaterializationTransaction` ledger-consumer promotion.

Measured-red evidence:

- `bash -n
  scripts/call_materialization_transaction_consumer_selection_report.sh` exits
  0;
- `scripts/call_materialization_transaction_consumer_selection_report.sh`
  reports `preferred_source_shape=legacy_instance_symbol_consumers`,
  `transaction_constructor_count=3`, `transaction_field_read_count=0`,
  `instance_override_binding_count=2`, `keepalive_binding_count=3`,
  `regmat_binding_count=1`, and `selected_binding_consumer_count=6`;
- `REQUIRE_PROMOTED=1
  scripts/call_materialization_transaction_consumer_selection_report.sh`
  intentionally exits 9 until the selected consumers read the transaction
  record.

Admitted next code slice:

- migrate the selected instance-branch override, keepalive, and diagnostic
  materialization-symbol consumers to read from
  `CallMaterializationTransaction` fields in shadow/parity mode;
- keep emitted behavior identical: the transaction constructor/helper may still
  use the legacy `MaterializationSymbolBinding` values as parity inputs, but
  downstream selected consumers must stop reading `symbol_binding.*` directly;
- turn `REQUIRE_PROMOTED=1
  scripts/call_materialization_transaction_consumer_selection_report.sh` green
  without flipping requested/target/body/call symbols.

Rejected next moves:

- generated-stage crash classification that does not answer a
  transaction-spine yes/no question;
- backend undefined-extern rescue, backend forwarders, target keepalive as a
  standalone patch, requested-name forcing, or broad `NamedTuple`/`Tuple`
  rendering changes;
- another report that only prints existing transaction rows without selecting
  or migrating a consumer edge;
- treating the 0k-AF transaction constructor as sufficient while selected
  consumers still bypass it through `symbol_binding.*`.

Boundary:

- this slice selects a red implementation edge and strengthens the transaction
  stop-rule; it does not claim `s2b`/`s3b` progress;
- it is not a full transaction-spine completion claim because residual legacy
  edges remain outside the selected instance-symbol consumer group.

Next local track:

- implement the selected shadow/parity transaction-consumer migration, then run
  the existing transaction, symbol-binding, InvocationContext, MethodNameCodec,
  semantic census, and full-suite guards before any generated-stage bootstrap
  claim.

### Slice 0k-AH: Transaction instance-symbol consumer promotion

Status:

- behavior-neutral source/consumer migration after Slice 0k-AG;
- no emitted symbol behavior, backend behavior, requested-name policy,
  target keepalive policy, `NamedTuple`/`Tuple` rendering behavior, ambient-map
  policy, cleanup behavior, or `BlockOwner` carrier changed;
- the selected consumer group is the instance-method override, keepalive, and
  diagnostic materialization-symbol path in `lower_function_if_needed_impl`.

Implementation:

- add `override_symbol` to `CallMaterializationTransaction` so the selected
  instance-method body-lowering override can read the transaction record
  without converting the optional override into a non-null body symbol;
- construct the instance `CallMaterializationTransaction` before the selected
  consumers run;
- make the selected consumers read `instance_transaction.override_symbol`,
  `instance_transaction.override_reason`,
  `instance_transaction.requested_name`,
  `instance_transaction.target_name`, and
  `instance_transaction.body_symbol`;
- keep `MaterializationSymbolBinding` as the parity input inside
  `call_materialization_transaction(...)`;
- update `scripts/materialization_symbol_binding_admission_report.sh` so the
  older binding gate remains green when binding authority has moved forward into
  transaction construction and no selected downstream consumer reads
  `symbol_binding.*` directly.

Measured-green evidence:

- `REQUIRE_PROMOTED=1
  scripts/call_materialization_transaction_consumer_selection_report.sh` exits
  0 with `preferred_source_shape=already_promoted_shadow`,
  `transaction_constructor_count=3`, `transaction_field_read_count=6`,
  `instance_override_binding_count=0`, `keepalive_binding_count=0`,
  `regmat_binding_count=0`, and `selected_binding_consumer_count=0`;
- `REQUIRE_PROMOTED=1
  scripts/call_materialization_transaction_admission_report.sh` exits 0 with
  `symbol_binding_field_read_count=0`, `transaction_field_read_count=6`, and
  `residual_legacy_edge_count=20`;
- `REQUIRE_PROMOTED=1
  scripts/materialization_symbol_binding_admission_report.sh` exits 0 with
  `binding_keepalive_count=0`, `binding_ledger_count=0`, and
  `binding_transaction_count=3`;
- `REQUIRE_PROMOTED=1 scripts/invocation_context_admission_report.sh` exits 0;
- `REQUIRE_PROMOTED=1 scripts/method_name_codec_admission_report.sh` exits 0;
- `scripts/semantic_decision_census.sh` and
  `scripts/codepath_status_census.sh` run as broad source-shape guards;
- `crystal build src/adamas.cr -o /private/tmp/adamas_0kah_stage1 --error-trace`
  exits 0;
- `scripts/materialization_identity_ledger_smoke.sh
  /private/tmp/adamas_0kah_stage1` exits 0;
- `scripts/materialization_transaction_report.sh
  /private/tmp/adamas_0kah_stage1` exits 0 with `malformed=0`,
  `owner_malformed=0`, and `unjoined_emit_rows=0`;
- `regression_tests/run_all_suites.sh /private/tmp/adamas_0kah_stage1 4`
  passes `152/152 + 36/36`;
- `scripts/run_safe.sh /private/tmp/adamas_0kah_stage1 600 4096
  src/adamas.cr -o /private/tmp/adamas_0kah_s2/adamas` exits 0 and produces a
  fresh generated compiler;
- the fresh generated compiler compiles a no-prelude `x = 1; puts x` smoke, and
  the produced binary prints `1` through `scripts/run_safe.sh`.

Boundary:

- this is a selected-consumer source-shape and broad-regression migration, not a
  full transaction-spine completion and not green full-prelude generated s2,
  `s2b`, or `s3b`;
- residual legacy transaction edges remain (`residual_legacy_edge_count=20`);
- the full default-path transaction construction now carries more fields than
  before. The next transaction slice should consider whether another consumer
  migration needs a cheaper owner-core / debug-payload split before broadening
  the default transaction surface.

Next local track:

- select the next transaction consumer edge with a source-shape gate, or run a
  generated-stage classifier only if it answers a transaction-spine yes/no
  question; do not start from the latest generated-stage crash stack.

### Slice 0k-AI: Generated-stage transaction-spine classifier

Status:

- behavior-neutral executable classifier after Slice 0k-AH;
- no compiler source, emitted symbol behavior, backend behavior,
  requested-name policy, target keepalive policy, `NamedTuple`/`Tuple`
  rendering behavior, ambient-map policy, cleanup behavior, or `BlockOwner`
  carrier changed;
- answers whether a fresh generated s2 full-prelude corridor reaches the
  `CallMaterializationTransaction` spine before the current frontier.

Source/spec:

- `scripts/generated_stage_transaction_spine_classifier.sh`;
- `scripts/run_safe.sh`;
- `scripts/build_stage1_original_cached.sh`;
- existing `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER` / `[MAT_TX]` /
  `[MAT_EMIT]` ledger format.

Implementation:

- build a fresh stage1 compiler unless `STAGE1_COMPILER` is provided;
- build a fresh generated s2 compiler through `scripts/run_safe.sh` unless
  `GENERATED_S2` is provided;
- compile a full-prelude `puts 42` source through generated s2 with
  `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1`;
- classify the result as:
  - `reached_tx_and_emit` when `[MAT_TX]` rows and transaction-bound
    `[MAT_EMIT] tx != none` rows are both present;
  - `tx_only_no_emit` when transaction rows are present but no transaction-bound
    emitted-call rows are reached;
  - `no_tx_rows` when the compile frontier happens before `[MAT_TX]`;
  - `s2_build_fails` or `stage1_build_fails` when the build corridor itself is
    not available;
- clean the temporary directory by default; `KEEP_TMP=1` is the explicit debug
  escape hatch.

Measured evidence:

- `scripts/generated_stage_transaction_spine_classifier.sh` exits 0 on a fresh
  generated s2 run;
- reported `s2_build_rc=0`, `compiler_rc=139`, `mat_id_rows=615`,
  `mat_tx_rows=615`, `mat_emit_rows=69`,
  `transaction_bound_mat_emit_rows=29`, `stub_rows=0`, and
  `classification=reached_tx_and_emit`;
- `scripts/generated_stage_transaction_spine_classifier.sh --help` prints the
  classifier contract;
- `git diff --check` passes;
- no `tmp/generated-stage-tx-spine.*` directories remain after the default run.

Decision:

- the transaction spine is reached by the current generated-stage full-prelude
  frontier;
- the next executable production slice may stay on
  `CallMaterializationTransaction`, but it must select the next reached
  transaction/emission edge with a red/green gate before changing behavior;
- `compiler_rc=139` remains the active frontier and is not fixed by this slice.

Boundary:

- this is not a green generated s2, `s2b`, or `s3b` claim;
- the classifier proves reachability, not correctness of all transaction rows;
- do not use this result to add backend forwarders, force requested names,
  normalize `NamedTuple`/`Tuple`, change ambient-map policy globally, keep target
  bodies alive, or roll back `BlockOwner`.

Next local track:

- add a reached-edge selection gate for the transaction/emission rows observed
  by 0k-AI, then migrate exactly one selected reached edge in shadow/parity
  mode if the gate is root-sized;
- if that selection is not root-sized, pause production code and introduce a
  more precise classifier rather than patching the segfault directly.

### Slice 0k-AJ: Generated-stage transaction/emission edge selector

Status:

- behavior-neutral executable selector after Slice 0k-AI;
- no compiler source, emitted symbol behavior, backend behavior,
  requested-name policy, target keepalive policy, `NamedTuple`/`Tuple`
  rendering behavior, ambient-map policy, cleanup behavior, or `BlockOwner`
  carrier changed;
- selects the next reached `CallMaterializationTransaction` emission edge from
  the generated-stage `[MAT_TX]` / transaction-bound `[MAT_EMIT]` ledger.

Source/spec:

- `scripts/generated_stage_transaction_edge_selection_report.sh`;
- `scripts/generated_stage_transaction_spine_classifier.sh`;
- existing `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER`, `[MAT_TX]`, and
  `[MAT_EMIT]` ledger format.

Implementation:

- parse an existing `LOG_FILE` or run a fresh generated-stage spine classifier;
- join transaction-bound `[MAT_EMIT] tx != none` rows to their `[MAT_TX]`
  metadata;
- select `call_materialization.wrapper_or_call_remap.extern_missing_body`, the
  contract class where:
  - `required_contract=wrapper_or_call_remap`;
  - `symbol_relation=body_eq_target_call_eq_requested`;
  - `identity_status=rejected_mismatch`;
  - backend emit `kind=extern`;
  - backend emit `body_present=0`;
- accept the selected edge only when it is no wider than
  `MAX_SELECTED_ROWS` (default `8`) and has no malformed or unjoined ledger
  rows;
- clean wrapper/classifier temporary directories by default.

Measured evidence:

- `REQUIRE_SELECTED=1 CLASSIFIER_SAMPLE_ROWS=1 CLASSIFIER_TAIL_LINES=8
  scripts/generated_stage_transaction_edge_selection_report.sh` exits 0 on a
  fresh generated-stage corridor;
- reported `classifier_classification=reached_tx_and_emit`,
  `mat_tx_rows=604`, `mat_emit_rows=69`,
  `transaction_bound_emit_rows=29`, `candidate_selected_rows=4`,
  `candidate_selected_distinct_txs=3`, `candidate_selected_owner_kinds=2`,
  `candidate_selected_branch_kinds=1`, `source_shape=eligible_reached_edge`,
  and `selection_status=eligible_reached_transaction_emission_edge`;
- negative control: `MAX_SELECTED_ROWS=3 REQUIRE_SELECTED=1` on the same log
  exits `9` with `source_shape=selected_edge_too_wide` and
  `selection_status=rejected_selected_edge_too_wide`;
- `scripts/generated_stage_transaction_edge_selection_report.sh --help` prints
  the selector contract;
- `bash -n scripts/generated_stage_transaction_edge_selection_report.sh` passes.
- Superseded continuation: Slice 0k-AM consumes this selected edge in
  behavior-neutral metadata mode. After 0k-AM, the expected gate is
  `REQUIRE_POST_CONSUMER_STATE=selected_consumed_by_contract_consumer`, not
  old `REQUIRE_SELECTED=1`.

Decision:

- the next architecture production slice may target this selected
  transaction/emission edge in shadow/parity mode;
- the old authority edge is backend extern emission from `call_symbol_hint`
  when the transaction already says a wrapper/call-remap contract is required;
- the owned transaction facts to consume are
  `CallMaterializationTransaction.required_contract`, `body_symbol`, and
  `call_symbol_hint`;
- `compiler_rc=139` remains the active frontier and is not fixed by this slice.

Boundary:

- this is not a green generated s2, `s2b`, or `s3b` claim;
- this does not authorize backend forwarders, target keepalive, requested-name
  forcing, `NamedTuple`/`Tuple` normalization, global ambient-map changes,
  `BlockOwner` rollback, or direct segfault patching;
- adjacent wrapper-contract rows with `body_present=1` and exact missing-body
  rows are explicitly not selected by this gate.

Next local track:

- superseded by the 0k-AM consumer above: the selected contract class is now
  consumed by downstream emission metadata, and the next work is to select the
  next reached transaction/emission edge;
- do not reuse this historical selected edge as a behavior-fix license.

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
