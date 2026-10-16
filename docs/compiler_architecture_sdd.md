# Compiler Architecture SDD

> Status: ACTIVE spec; fresh B4-F and broad semantic promotion remain open.
> AN ordinary S1 -> S2 -> S3 -> S4 reaches a complete raw-IR and code/data
> fixed point; see bootstrap_an_verification.md (2026-10-13).
> T1 has an opt-in single-active-unit selected-definition consumer; broader
> identity continuity remains open (source-routing refresh 2026-09-04).
> Scope: target ownership architecture for the Adamas compiler
> (HIR -> MIR -> LLVM) and the migration contract toward it.
> The 2026-06-25..07-03 execution ledger (145 slices, ~11,600 lines) that
> previously occupied this file is preserved in git:
> `git show 95539f64:docs/compiler_architecture_sdd.md`.
> Rationale and process rules: `docs/sdd_process_review_2026_07_03.md`.

Document contract (hard rules):

- This document contains **no dated work-log entries**. The work log lives in
  `TODO.md` (active board) and git history.
- Section 0 is **replaced in place** on frontier movement, never appended to.
- An owner record is not "consumed" until section 6 describes it and its row
  in the section 0 state table is updated.
- Behavior changes are admitted by falsifiers (`docs/specs/05-falsifier-matrix.md`)
  and the regression gates, never by this document alone.
- Owner migrations are pull-based: extract an owner only when a concrete
  behavior fix needs that boundary. Neutral extractions are batched and do not
  each pay a full bootstrap verification cycle.

## 0. Current State (replace in place)

### 0.1 Frontier

Expected Proc inputs define callback ABI slots even when source block
bindings omit some or all arguments. Generated allocators consume the selected
initializer's input and declared Nil-result contracts before materializing the
callback; a registered self.new rejected by the known positional call shape
cannot supply that contract. Named, splatted and unknown shapes retain their
existing conservative selection boundary. A discarded body value can preserve
a captured Nil field only after the actual Proc inputs and return type match
the field exactly; incompatible inputs or actual non-Nil callbacks still fail.
Ignored/trailing inputs, side effects, explicit-new selection and negative
capture guards are the discriminators. Rollback is the bounded expected-input,
constructor-hint and normalized-Nil refinement changes. Mixed raw/retained
yield, Void-result erasure and full MT/application parity require separate
native evidence.

When a late nested declaration resolves a simple lexical return annotation,
the new type must reach the signature cache before later consumers use it.
Refresh only aliases whose explicit-return contract still owns that exact Def;
a same-name sibling cannot authorize replacement. Contextual type-parameter
substitutions must remain local to their specialization. The natural late-type
falsifier, sibling cache guard, and competing generic binding are the admitted
checks. Rollback is the bounded write-through in resolve_return_type_from_def.
Compound annotations and full MT/application startup remain separate frontiers.

Proc arrow punctuation is structural syntax in both signature scans and body
lowering. Resolve actual input/result type expressions in their lexical owner;
an empty input list cannot acquire the owner's name as a phantom input. The
declared result retains generic substitutions. Empty/explicit-Nil arrow,
canonical Proc, typed-input, grouped-arrow, and generic-result controls are
the discriminators. Rollback is the shared structural arrow-resolution branch;
full MT initialization and application parity require separate native evidence.

Tuple-union iteration dispatches on the runtime tag before expanding each
concrete Tuple#each macro arity. Admission requires an exhaustively known tuple
union with correct producer tags; unknown/generic alternatives retain their
existing lowering. Per-variant caller locals and next/break/nonlocal-return
edges merge only from live exits. Parsed top-level macro expression sequences
stop at the ordinary sequential-lowering boundary; empty inline-return exits
remain dead. Scalar includes?/any? shortcuts exclude callbacks and require the
existing homogeneous primitive contract. Custom scalar method overrides and
nested macro BlockNode sequences are outside this closure.

Admission: tuple_union_iteration_repro.sh CANDIDATE BASELINE uses external
stdlib, original-Crystal output parity, a mandatory baseline ASan READ4 when
supplied, and candidate normal/ASan controls (including separate-return empty
tuples). macro_sequence_return_repro.sh provides an NP baseline91/candidate0
falsifier plus conditional-fallthrough/dead-merge guards. A ternary joining
Tuple.new with a nonempty tuple still loses its producer tag before iteration;
nested captured accumulators and tuple-splat Path constructors also remain
separate boundaries. Rollback is this HIR dispatch/fallthrough/shortcut delta.
Fresh S2 builds and smokes; S3 now reaches a distinct union stack-slot width
mismatch in infer_type_from_expr_inner. Full S3 closure remains open.

MIR global registration consumes both class-owned and module-owned class
variables from the HIR registries. Module ownership does not imply ClassInfo;
a missing class entry must not erase a module variable's declared storage type.
The module registry supplies the same name, type, initial value and debug
metadata contract as class variables. Admission requires nullable Bool module
and class controls to retain union storage through initialization/read/write,
including an ASan red/green check. Backend unknown-global fallback is unchanged.
Rollback is the module registry exposure and CLI consumer; stdlib is untouched.

A call result authorizes unconditional ARC cleanup only when every return path
and every Copy/Cast/Phi origin proves owned. Missing parameter definitions and
unknown calls reject this proof; direct allocations and calls to already proven
owned producers are admitted. Mixed owned/borrowed producers remain conservative
and may retain new allocations longer. This is not a complete ownership ABI or
a bounded-memory claim. Admission: owned_return_provenance_repro.sh and adjacent
MIR cleanup/phi regressions. Rollback is the universal return-proof delta.

Explicit method return annotations use the owner-aware annotation resolver at
registration and selected-definition refresh. Composite names such as Info?
retain the declaration namespace; normalization cache entries also depend on
the declaration epoch so a later nested type can supersede an early lookup.
Admission: late_nested_return_namespace_repro.sh (bare, relative and absolute
nullable returns, present and Nil values), the late-registration cache spec,
and file_info_declared_return_namespace_repro.sh against external stdlib.
Do not promote the pre-lowering signature cache to a completed runtime contract:
the external registration-only probe still exposes a stale typed signature,
while selected annotation resolution and generated runtime are checked separately.
Rollback is this HIR resolver/cache delta; no stdlib or layout changes.

The Hash literal allocator recognizes both root-class spellings Hash(...) and
::Hash(...). Other namespaces merely ending in Hash remain rejected. Admission
still requires reference kind, a one-byte indices field beyond the type header,
an in-body field offset and a representable allocation size. The qualified-name
NP regression and backend invalid-kind/geometry/lookalike controls establish
this boundary; no class-registry or duplicate-field normalization is implied.

Nested callback parameter inference uses the selected callee's body, formal
parameters, local map and declaration namespace. Unannotated bare readers may
infer their result from concrete call arguments without populating a shared
base-method return cache. An active callsite key uses the definition, owner, positional and named
argument types, independently of substitution-cache generations. Re-entering
the same definition with a different specialization may add a return branch;
a node-only guard is rejected by the Int32-to-String recursive-call control.
Static calls resolve declared returns through the selected overload and its
namespace; explicit receiver ivars consume that receiver's registered fields.
Unknown positional arguments must not select among distinct static overloads.
Admission: nested_yield_callsite_inference_spec.cr and
nested_yield_callsite_return_repro.sh (both inline and raw callback modes).
Same-name locals/types, inherited declarations, alternating concrete calls,
nullable paths and conflicting overloads are controls. A recursive unknown
remains unknown; raw callback captured scalar mutation and S3 remain open.
Rollback is the scoped HIR delta and its tests; no layout or stdlib edits.

Parenthesized calls preserve spaced-colon type declarations as positional AST
arguments for arbitrary callees, including nested macro calls outside ternary
branches. Ternary branches reject spaced declarations before named fallback;
a separate depth counter preserves ordinary nested declarations. Reusing the
shared no_type_declaration counter is refuted because ordinary call arguments
also increment it. Interpolation subparsers inherit the ternary context and
surface their errors at the enclosing token; invalid initial/adjacent literal
results must not enter string merging or repeat parsing without progress.
Preserve adjacent-colon named calls and existing accessor compatibility.
Admission: parenthesized declaration, ternary/interpolation/restoration,
named/type/accessor specs and the NP imported-macro/yielded-constructor guard.
Rollback covers the spaced-colon admission, ternary depth propagation and
invalid interpolation/literal guards.
External thread_local expansion and File.tempname compilation now pass; the
separate Time::Location.local runtime stub and bootstrap propagation remain open.

Hash literal allocation consumes final MIR body size, type ID and indices-width
field offset. The field must be Int8 or UInt8 and lie after the type header and
inside the body. Preserve the8-byte GC prefix and initialize the complete body;
missing or invalid facts fail compilation rather than select a guessed size.
Admission: eight layout controls and hash_literal_allocation_repro.sh in both
NP byte forms and external --stdlib mode (empty/filled dup and copy mutation).
The exact predecessor is ASan-red; the backend-only successor passes these
host gates. Rollback is local to the helper and its ExternCall emission path.
Class-metadata refresh and constructor dispatch remain separate obligations.
The callback and root-qualified Hash repairs pass the prior emission blockers;
The namespace-repaired S2 builds in418s and compiles/runs the NP exit0 smoke. S3 reaches lower_main but segfaults139 after35s; bootstrap closure remains open.

Macro nil? evaluates the receiver as a MacroValue even in text conditions.
Absent values and explicit NilNode are nil-like; false, zero and empty strings
are not. Explicit nil retains the source spelling "nil", while absence emits
no text, allowing external record defaults to preserve their declaration.
Admission: predicate/condition specs and external_record_nil_predicate_repro.sh
with the external CRYSTAL_PATH, including the mandatory/no-default field.
Rollback is confined to macro_value.cr and the nil? member-access path in
macro_expander.cr. Host admission passes; bootstrap propagation is separate.

Bootstrap verification requires external original Crystal stdlib via
CRYSTAL_PATH=/Users/sergey/Projects/Crystal/crystal/src. Snapshot src/stdlib
results are diagnostic only. The macro and parenthesized declaration fixes pass the former Handler/Proc
and File.tempname boundaries. Callback inference and qualified Hash admission
permit S2 emission; declared-return namespace repair permits its NP smoke.
The current S3 runtime failure follows lower_main; localize that frame before
widening semantic or layout changes. Preserve the heterogeneous-return and bodyless-target guards.
Never edit stdlib. These host gates do not establish a produced S3.

Early union field sizing must recognize Proc carriers in canonical, top-level
arrow and parenthesized arrow syntax before falling back to reference storage.
A Proc lacks the runtime object header required for an all-reference union.
Nested nullable callback arguments do not change this rule; a reference class
containing a Proc type argument keeps its pointer representation. Admission
requires the early-layout spelling controls and the actual Hash re-registration
ASan regression (both nullable tuple key spellings and a String key control).
The host guards pass; matched S2 builds in 334s and emits the corrected ordinary
Hash allocation. S3 ASan advances to a distinct hardcoded Hash literal allocation
read; the produced full-prelude guard remains blocked. Rollback is
local to hir_union_ivar_storage_size. General unknown arms, callback ABI changes
and allocation padding are outside this repair.

Tuple/NamedTuple slots carry pointers for non-lib user structs of every size.
Read/write lowering must preserve that contract before ordinary parent-field
inlining or borrowed-address propagation. A64-byte Token coercion previously
read beyond a16-byte tuple; ASan and the NP runtime baseline distinguish the
producer/consumer mismatch. Both small-inline settings, Nil/repeat and ordinary
inline Holder guards now pass, plus99 ABI/backend examples. Rollback is confined
to HIR-to-MIR field access; tuple geometry and lib-struct policy are unchanged.
The active continuation uses union-wrap-work's retained HIR/macro composite
plus only the field-access correction; live-tree candidates are a different
source state. Matched S2 builds396s and passes the runtime contract; actual S3
traps133. ASan moves from the tuple read to a12-byte Hash initializer write
beyond the allocated object body. Stage3 remains unbuilt.

Synthesized allocator and initializer identities now preserve canonical named
shape when runtime argument types coincide. Host guards cover both discovery
orders, generic owners, ordinary named arguments, defaults, and explicit
`self.new` authority. The joint fresh stage2 repairs the observed initializer
name/context corruption. The named-only predicate now completes its safe scan
without a nonlocal break. An indexed union-specialization scan removes the
Pointer#any? iterator stub from allocator generation. All eight produced
constructor reducers compile and six pass runtime; generic and distinct
named-only initializer bodies remain incorrect.
A host-verified short-circuit join repair addresses the observed DefNode loss:
RHS-only narrowing no longer escapes onto the skipped path. Fourteen runtime
guards and HIR 575/0/2 pending pass. Fresh produced constructors improve
4/8 -> 6/8, including both positional/named discovery orders;
the standalone reducer hits a missing choose_or stub before its guards.
The two remaining constructor reducers keep broader selection open.
Raw-yield transport now preserves compatible known Proc formal ABIs using a
complete per-argument plan, with scalar/payload and mixed-argument controls.
Unknown/ambiguous signatures and unsupported layouts retain legacy behavior.
Untyped callback signature propagation remains open; a no-prelude actual-union
reducer is red on the host and green on original Crystal.

The [current execution plan](compiler_refactor_architecture_plan.md#0-current-execution-plan)
integrates reliability and architecture priorities. Grouped-union normalization
repairs literal defaults; the Phi cross-block pre-scan now uses the existing
indexed API and all six produced grouped-nullable runtimes pass. Nullable Tuple
multiple assignment now retains positional pointer types across captured-block
spills; the produced empty initializer compiles/runs. Explicit override now
stores the supplied value at the correct field offset. Absolute Pointer(self).null now uses the
static-member intrinsic and passes produced runtime controls. Plain compilation
still crashes: raw Tuple#reduce callback transport drops the Path | String tag.
The latest stage2 takes 319.63s under a 900s diagnostic allowance.
B-RAW-YIELD-CALLBACK-ABI, B-ALLOCATOR-NAMED-SHAPE, B-ABSOLUTE-POINTER-NULL,
B-NULLABLE-TUPLE-DESTRUCTURE,
B-GROUPED-NULLABLE and B-PHI-PRESCAN guard positional typing, type identity,
Proc/generic boundaries, and ARC input lifetime. This is not canonical
B4-F/resource promotion. Older R0
source/artifact rows below retain historical scope; their "current-source"
labels refer to those runs, not this checkout.

- **B4-H (historical generated artifact): HISTORICAL.** A previously generated
  `s2` passed the downstream full-prelude classifier and printed `42` under
  `scripts/run_safe.sh`. This remains useful compatibility evidence, but it
  does not prove that current source can produce a fresh `s2b`.
- **B4-F (fresh current source): UNMEASURED UNDER THE 300-SECOND POLICY.** A
  clean-output `s1 -> s2b` build from the reconciled source must finish in at
  most **300 seconds** on the recorded host/cache policy (<=180 seconds is the
  stretch target). The output directory is new and the manifest records
  fresh-output/source/output hashes
  plus `cache_policy`, `cache_dir_rel`, and `cache_directory_identity`; no generated stage is reused. Any external host cache is
  recorded and held constant, with cold and warm results reported separately.
  The exact plain/full-prelude and exact no-prelude semantic smokes
  are co-equal release gates; worker-only or emit-only success cannot mask
  either failure. This is a new acceptance target, not a recovered historical
  full-green certificate. The sealed current snapshot exhausted the former
  180-second cap at stage2 wall 182.54 seconds and produced no `cv2_s2`; it
  does not classify the current budget.
- **T8 (offline fresh-s2 decision): EXECUTABLE / NO CURRENT GREEN RECEIPT.**
  `scripts/validate_bootstrap_manifest.sh` rehashes a canonical B6/B7 receipt
  against current source, harness, and an explicitly trusted host, then
  enforces normal no-worker production, numeric resource coverage, both exact
  semantic smokes, and stage2 wall <=300 seconds. The validator exists; no
  fresh current-source receipt has passed it.
- **T1 (typed call identity): BOUNDED CONSUMER EXISTS / BROADER CONTINUITY OPEN.**
  Under opt-in semantic compilation with one active parsed unit, CLI analyzes
  the original arena and binds its selected-definition context to HIR.
  `semantic_call_target` consumes the exact owned `DefNode` before legacy
  overload selection; normal call emission guards selected/emitted continuity.
  Multiple active units retain the shadow aggregate without handing its
  identities to HIR. Generic receivers, generated nodes and early-return call
  shapes remain outside this bounded claim. No `ResolutionId` stream,
  cross-arena promotion, or default bootstrap coverage follows from it.
  See SDD07 section 2.1 for the full consumer boundary and recorded tests.
- **B5 (s2 self-build -> s3): BLOCKED BY B4-F / HISTORICAL LOCATOR ONLY.** The
  historical first bad stop was
  `ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED` inside the
  `AstToHir#lower_method` body loop (`body_size=44`) for
  `Adamas::Compiler::CLI#run$IO_IO`, at roughly 4.8 GB peak RSS. The R0
  locator cannot be refreshed until B4-F produces a stage2 artifact.

Current evidence is deliberately revision-scoped:

| Source/artifact | Current classification | Consequence |
|---|---|---|
| `548d29b1` clean baseline | Stage1 and host/no-prelude probes pass; fresh `s1 -> s2` timed out at 900 seconds | Control only; no fresh-s2 certificate. |
| `04b98b04` lineage | Direct `Object`/`Reference` method census 2085 -> 50 | Diagnostic demand-amplifier evidence; not a release certificate. |
| Historical fresh both-smoke green | 231.37 seconds strongest surviving certificate; 251.91/253.42 seconds corroborating | Within the <=300-second numeric budget but stale; not current-source admission. |
| Historical ~178-190-second runs | No-prelude or partial lanes only | Not full-green B4-F certificates. |
| 2026-07-14 fresh run | ~711 seconds; no-prelude green, plain/full-prelude red | Semantic split; release red. |
| G7 snapshot | 1962.79 seconds; both semantic smokes red | Refuted as release candidate. |
| G8 snapshot | 1791.78 seconds; both semantic smokes red | Refuted as release candidate. |
| G9 snapshot | 1768.73 seconds; both semantic smokes red | Diagnostic candidate only; not a release candidate. |
| `91ebe332` T0 | Same 900-second fresh-stage timeout as clean control; HIR provenance ON/OFF byte-identical | Guard-only provenance; no behavior promotion. |
| R0 sealed current-source snapshot | Base `c216b9ef...`, tree `1efb635...`, exactly seven tracked compiler/spec paths, patch `d7ad2cac...`; snapshot diff-check passes | Reproducible current-source certificate; manifest `/private/tmp/adamas_r0_current_c216_manifest.md`. |
| Host preflight and stage1 | Host spawn green; host build 14.13s; plain smoke `42` in 20.29s; exact no-prelude markers in 0.65s; `cv2_s1` SHA-256 `dfe3c0e8...` | Host-infrastructure blocker refuted; stage1 corridor green. |
| Fresh current-source B4-F | The last canonical attempt hit the former 180-second cap: stage2 timeout exit 143, stage wall 182.54s, externally sampled peak RSS 1361.03 MiB; outer chain exit 1 at 219.32s; no `cv2_s2` | Old-budget red; the current 300-second policy is unmeasured. Stage2 semantic smokes remain unavailable. |
| Sealed-current stats-on localization | Only `ADAMAS_PHASE_STATS=1` on sealed `cv2_s1`, safe-run timeout 180s/memory 12288 MB: wall 182.60s, exit 143, no `cv2_s2`; peak RSS unavailable. Completed `process_pending` 218 -> 591 (+373) in 555.2ms and `emit_tracked_sigs` 591 -> 604 (+13) in 235.0ms; open `lower_missing.initial` grew 604 -> 1535 -> 7422 -> 19238 -> 28234 before timeout. Log SHA-256 `1cc025cc...`. | Revalidates/evolves the historical 2026-04-29 locator. No completion/timing/top-prefix for the open phase; definitions differ from the old observation, and stats-on/uninstrumented timing is diagnostic-only. |
| Concrete-suffix overload fallback | A full-source trace showed `Hash(Int32, String)#==$Int32` borrowing `Hash(Int32, String)#==$Hash(Int32, String)` through `mangled_prefix_typed`. The resolver now treats fully decoded positional suffix types with no compatible candidate as authoritative negative evidence and reaches exact-name parent fallback instead; sparse `$arityN` and compacted marker shapes retain callsite-history fallback. The focused regression is RED when the rejection condition is ablated and GREEN when restored; the compiled cross-type Hash equality oracle returns `false` in both operand orders. | Closes the sibling positional-type ABI violation only. Block/splat/named shape selection remains outside this guard. The same bounded `lower_missing` census moved 13338 -> 13300 functions while `Hash#==` remained at 484 enqueue events, so this is not the B4-F fanout root and carries no bootstrap speed claim. |
| Concrete generic `Object#===` wrapper ownership | Exact lookup may resolve a generic `Reference` descendant's inherited `===` to `Object`; lowering that body with Object self turns `self == other` into Object-wide virtual fanout. The concrete primary is retained only for `===` when source provenance proves the Object wrapper and the source shape is one untyped required positional parameter with no default/splat/block, a single `self == parameter` body, and no explicit return other than `Bool`. Existing primaries must match receiver/right/Bool ABI; pending primaries must still be queued; Void callsite evidence fails closed. Negative fixtures cover indirect/unrelated self calls, extra defaults, unrelated RHS, typed params, explicit non-Bool return, and Void. The fresh full-stdlib reducer moves 198999 -> 190531 HIR lines and 157 -> 3 `#==$Int32` bodies; runtime controls print `0/1/1/1`; the full HIR suite is 376/0 with two existing pending. | Measured B4-F improvement, not closure. The fresh comparable gate remains 13300 functions; at `queue@iter2`, `Hash#==` demand falls 484 -> 63 (-87.0%), but 2048 unique missing targets and 137 `Object#===` occurrences remain. No method/type allowlist, registry, budget cap, full-stage timing, or produced-stage admission is claimed. |
| Enum case-equality semantic owner through late repair | Initial `===` lowering and late receiver repair share the retained per-function enum-value sidecar as the semantic receiver-owner proof. `lower_def` and `lower_method`, plus successful normal completion of synthetic `lower_main`, isolate, retain, and restore that sidecar; successful main lowering also restores the saved caller arena after packed multi-source expressions. Normal repair dispatches through the proven enum owner while retaining the original integer receiver value, descriptor, and wrapper receiver ABI. Cross-owner and same-owner-bodyful falsifiers poison an exact `CaseKind` function call; the durable source oracle additionally proves exact and nilable patterns both inside functions and directly in `__adamas_main`. A two-arena falsifier proves subsequent `lower_def` reads literal `11` from the caller function rather than aligned foreign literal `22`. No preservation bypass, new registry, fallback, cast, search heuristic, or name allowlist is admitted. The full HIR suite is 378/0 with two existing pending; the durable enum oracle remains green. | Closes the classified 137-occurrence function-body defect, the synthetic-main enum-ledger gap, and the demonstrated successful-path caller-arena leak only. At the same fresh `queue@iter2` boundary, `Object#===` is absent and is conserved as `NodeKind#===` 78, `Token::Kind#===` 47, and `DWARF::AT#===` 12; `Hash#==` is 55, functions 12854, and unique missing targets are 2052. Exception-safe `lower_main` cleanup remains unproven and unchanged. Therefore no B4-F closure, global fanout reduction, timing admission, fresh stage2, or produced-stage smoke is claimed. |
| Bare-generic runtime-return union compatibility | Original Crystal 1.21 rejects a demanded explicit return annotation containing a bare generic class or struct template, including nullable `T?` syntax, with `can't use ... in unions yet`; it still accepts bare generic parameter restrictions when concrete callsites specialize them, and leaves an uncalled definition semantically lazy. HIR validation now runs only at demanded method/top-level body lowering, before return-union construction. Paired positive/negative HIR falsifiers, fresh-compiler explicit/nullable diagnostics, the concrete-callsite runtime oracle, full HIR 382/0 with two existing pending, and MIR 37/0 pass. | Closes the demonstrated incomplete-dispatch miscompile by failing closed at the original semantic boundary. It does not add runtime bare-generic union composition, alter parameter restrictions, validate registration-only definitions eagerly, expand MIR candidate families, or change ABI/layout ownership. |
| T9 exact-target continuity | Stage1 from `6772e562` exposed concrete-request -> union-target canonicalization at `exact_lookup`; candidate SHA-256 `4d6c37ac...` preserves concrete requested/target/materialized `push$AstArena` through `instance_class_info_lower_method` at about 117 seconds. The focused HIR guard plus typed MIR/LLVM ABI spec check exact concrete/union `append -> << -> push` edges, MIR FunctionIds, receiver/value `TypeRef`s and operands, `ret self` bodies, and exact two-argument LLVM `<< -> push` calls/definitions; a wrong concrete/union MIR `TypeRef` expectation is RED. The 43 focused examples, 617 other fast HIR examples (2 existing pending), and union-value runtime storage also pass. | Current exact-target HIR lookup/body continuity and the focused downstream HIR-to-MIR-to-LLVM corridor are green. The historical full-source MIR diagnostic hit the former 180-second cap without an artifact, so full-source emitted-symbol continuity remains open behind B4-F. Phase-gate `_exit(0)` is not compile success, and the historical full-G9 symptom remains stale. |
| T0 same-source A/B | Not completed on the sealed snapshot | R0 promotion remains blocked independently of B4-F. |

The old `B4 GREEN` wording is therefore split into B4-H and B4-F rather than
silently reused. A diagnostic timeout is not an acceptance budget.

R0 also selected historical G9 only as a typed-materialization diagnostic.
For source `main_arenas << map_arena`, the minimal G9 HIR chooses
`push$AstArena` for the static value but the union target for an explicit
upcast. The upstream Crystal audit establishes both as lawful: concrete flow
through `Array(ArenaLike) << AstArena` specializes `<<`/`push` with `AstArena`,
while explicit `.as(ArenaLike)` and true union flow select union or lawful
reduced-union instances. At the original Crystal oracle boundary, instance
authority is `DefInstanceKey(def.object_id, actual typed args, block/named)`;
that `object_id` detail is not Adamas authority. Adamas requires `DefIdentity`
plus actual typed args, block, and named arguments; the mangled name is later
serialization. The minimal HIR/MIR/LLVM probe preserves two arguments.
Historical G9 `s2` LLVM was reported to contain a union `<<` path calling
zero-argument `push$AstArena()` plus a zero-argument unreachable stub. That
artifact is not retained in the current checkout, and no fresh current-source
reproduction has been obtained. Late HIR materialization or a missing selected
target therefore remains a hypothesis for the historical malformed body, not
a proven current creation mechanism. T9's focused HIR mode is green:
unknown-left `<<`/`>>` body inference fails closed, and receiver-layout fallback
preserves a concrete typed callsite only when it exactly re-serializes to the
selected symbol. A source-bound stage1 from `6772e562` then reached the exact
full-compiler child and exposed a current HIR mechanism: `exact_lookup` changed
requested concrete `push$AstArena` into the union target/body. The bounded
correction keeps the requested name only when the parsed base and actual typed
arguments exactly re-serialize to that name; concrete-request plus union-actual,
base mismatch, block mismatch, and splat forms fail closed. Candidate SHA-256
`4d6c37ac...` reached the post-body gate in about 117 seconds with concrete
requested, target, and materialized names and producer
`instance_class_info_lower_method`. The focused T9 HIR guard plus typed MIR/LLVM
ABI spec, 43 focused examples, 617 other fast HIR examples with two existing
pending cases, and the union-value runtime storage guard pass. The omitted
`as_question_try_spec` RED is identical
on clean `6772e562`; generated-runtime integration was not part of this bounded
run. The intentional gate's `_exit(0)` proves HIR phase continuity, not compile
success or full-source MIR/LLVM emission. The focused reducer separately proves
exact concrete and union MIR FunctionId/type/operand binding, `ret self` bodies,
and matching two-argument LLVM `<< -> push` definitions/calls; a deliberately
wrong concrete/union MIR `TypeRef` expectation is RED.
Full-source MIR-to-LLVM symbol continuity remains the next T9 falsifier behind
B4-F reachability, and the historical zero-argument symptom remains stale until
a current full-source emitted artifact reproduces it.

### 0.2 Authority-edge state table

| Edge | Owner record | Guard (script + env) | Status |
|---|---|---|---|
| function-list-inline | LLVMEmissionSession / LLVMEmissionFunctionPlan | `REQUIRE_SESSION=1 scripts/llvm_emission_session_source_shape_guard.sh` | consumed |
| worker-policy-inline | LLVMEmissionSession worker plan | `+ REQUIRE_WORKER_PLAN=1` | consumed |
| side-effect merge | LLVMEmissionSession side-effect contract | `+ REQUIRE_SIDE_EFFECT_CONTRACT=1` | consumed |
| lower_method body scope | MethodBodyLoweringScopeSnapshot | `REQUIRE_METHOD_BODY_SCOPE=1 scripts/method_body_lowering_scope_source_shape_guard.sh` | consumed |
| lower_def body scope | MethodBodyLoweringScopeSnapshot | `+ REQUIRE_LOWER_DEF_BODY_SCOPE=1` | consumed |
| lower_module_method body scope | MethodBodyLoweringScopeSnapshot | `+ REQUIRE_LOWER_MODULE_METHOD_BODY_SCOPE=1` | consumed |
| inline_callee_local_names scan scope | InlineCalleeLocalScanScopeSnapshot | `REQUIRE_INLINE_CALLEE_LOCAL_SCAN_SCOPE=1 scripts/inline_callee_local_scan_scope_source_shape_guard.sh` | consumed |
| LLVM output restore (parallel rescue) | LLVMOutputOwnershipContract | `REQUIRE_OUTPUT_OWNERSHIP=1 scripts/llvm_output_ownership_source_shape_guard.sh` | consumed |
| CLI output commit record | GeneratedStageExecutionOutcome | `REQUIRE_OUTPUT_OUTCOME=1 scripts/generated_stage_outcome_source_shape_guard.sh` | consumed |
| classvar scalar offsetof globals | none (producer behavior fix `ab0747d9`) | `REQUIRE_SELECTED=1 scripts/generated_stage_return_contract_mismatch_report.sh` L19 row | consumed, no owner type |
| non-void call result slots | none (backend behavior fix `aae7c0f8`) | `scripts/generated_stage_return_contract_mismatch_report.sh` (`normal_llc_type_mismatch=0`) | consumed; typed owner residual |
| zero struct sentinels | none (raw value storage `be44b058`) | `REQUIRE_SELECTED=1 scripts/generated_stage_zero_struct_sentinel_report.sh` | consumed |
| GC-aware realloc demand | LLVMEmissionSession `GRH` tag (`31cd6009`) | `scripts/generated_stage_gc_realloc_helper_report.sh` + `regression_tests/gc_aware_realloc_gating_repro.sh` | consumed |
| STABLE6 materialization replay shadow | none on main (`MaterializationReplayShadow` prototype only in `/private/tmp`) | in-process prototype discriminator; no admitted owner | REFUTED IN-PROCESS PROTOTYPE / NOT ADMITTED |
| same-arena selected definition -> ordinary HIR call | existing `DefInstanceKey` / `TypeContext` / `SelectedCallTarget` | `spec/semantic_cli_spec.cr`, `spec/semantic_cli_compile_contracts_spec.cr`; `ADAMAS_SEMANTIC_COMPILE=1` | consumed only for the admitted single-active-unit source-backed shapes; broader T1 open |

### 0.3 STABLE6 — refuted in-process prototype / not admitted

STABLE6 is **REFUTED IN-PROCESS PROTOTYPE / NOT ADMITTED**. The attempted
`MaterializationReplayShadow` used a typed numeric `CallSiteRef`, explicit
statuses (`Unjoined`, `HIRShapeAgree`, `HIRShapeMismatch`, `StaleCallSite`,
`UntrackedRequiredCallSite`, `StaleTransactionRef`, `AmbiguousHIRShape`, and
`NoMaterializationRequired`), a composite typed HIR request-shape index,
diagnostic logs with a ceiling (not a hard cap), owner-local scratch, and a
final read-only scan. Those local
shapes remain useful evidence, but no in-process owner is admitted and the
prototype has been removed from main code and preserved only in
`/private/tmp`.

Scoped local evidence remains: focused **17/0**, baseline HIR
**286/0 with two existing pending examples**, host build, and simple OFF/ON
HIR/runtime parity. The local adversary is **ROBUST** only for those bounded
parity checks. Full-prelude/union telemetry remains intentionally red/noisy
and separate from the similar plain run (about **2673 registered, 2568 agree,
404 mismatch, 1 stale, 199 untracked required, 225 unjoined, 1 ambiguous, and
11377 calls** in the audit reducer); these counters are proxy orientation only
and do not prove duplicate semantic instances or speed. A strict assertion is
not an admission path.

The system discriminator overrides that local result. On the frozen pre-shadow
base `c216b9ef...` plus patch `d7ad2cac...`, with phase stats as the only
instrumentation, the control timed out at 180 seconds (`run_safe` exit 143),
produced no `s2`, and grew **604 -> 1535 -> 7422 -> 19238 -> 28234
(+27630)** without stack overflow; the repeat-control log prefix is
`e568...`. With the STABLE6 source/executable in the same binary, both runtime
OFF and ON also produced no `s2` and hit exit 11 stack overflow in
`declared_type_match_score`/alias/type-name work during `lower_missing` p0
around item **#800** (ON about **141s**, OFF about **139s**), with identical
completed growth **604 -> 1544 -> 7430 -> 19246 -> 28369 (+27765)**. The ON
and OFF log prefixes are `18603d...` and `51146a...`; RSS was unavailable.
The ON final-scan-i4 orientation counters were
`registered=27363`, `agree=42801`, `mismatch=484`, `unjoined=4459`,
`ambiguous=300`, `no_mat=12864`, `calls=60909`, and `not_yet=1`.

This is not causal proof of the underlying compiler root, but admission is
rejected because runtime-OFF still changes the self-host source/workload and
failure class. Default-off is therefore not zero compile-time cost. The
whole-system Adversary verdict is **BROKEN for admission**, despite the local
parity verdict. T1 remains **MISSING** because HIR `TypeRef`/name shape is not
semantic identity, and B4-F (<=300 seconds) remains unmeasured/open with no speed
claim.

Pivot: do not add another large in-process callsite owner or new `AstToHir`
ivars. Reuse the existing materialization ledger and semantic
`DefIdentity`/`DefInstanceKey` only as a later join input; it lacks
`resolution_id`, so it cannot be joined deterministically today. The full path
requires a second versioned downstream correlation record/enrichment carrying
`resolution_id` through inline, materialization, body, and emission-terminal
states. Until that record exists, the external join remains pending and this
document does not claim that existing streams suffice. A future analyzer may
stream its inputs, but the current log ceiling is diagnostic unless a guard
hard-caps it; no bounded-memory or backpressure claim is admitted.

### 0.4 T1 identity-join boundary (broader continuity open)

T1 rejects the late `lower_function_if_needed` / MAT string ledger as the
semantic producer. That point is downstream of resolution and can also be
after semantic literal/autocast normalization, Adamas HIR/value/ABI coercion,
or inline materialization, so it cannot establish which semantic callsite
identity was selected. The authoritative producer boundary is **post-resolution,
after semantic literal/autocast normalization if applicable, before Adamas
HIR/value/ABI coercion**, analogous to the original Crystal
`Call#instantiate` boundary. This is an ownership placement, not a behavior
or performance claim.

The proposed future `ResolutionId` producer uses this versioned,
telemetry-only record shape, distinct from the existing opt-in single-active-unit
selected-definition consumer:

```text
[T1_IDENTITY_JOIN] schema=t1_identity_join_v1 case_id=<opaque-case-id> resolution_id=<u64> def_arena_id=<u64> def_expr_index=<i32> receiver_semantic_type_id=<u32|none> arg_semantic_type_ids=<ordered-u32-list|none> block_semantic_type_id=<u32|none> named_semantic_args=<ordered-NameId:SemanticTypeId-list|none> producer_phase=post_resolution_pre_hir_coercion
```

The producer and join operate on typed IDs and ordered fields. Strings are
serialization only: `case_id/correlation` is an opaque external correlation
token, and any rendered name is diagnostic/ABI text, never a semantic key or
owner decision. The record is not an in-process authority and must not be
used to silently route the legacy path. The existing MAT ledger cannot be
joined deterministically because it lacks `resolution_id`. Full correlation
therefore requires a second versioned downstream record/enrichment carrying
that ID through inline, materialization, body, and emission-terminal states;
until it exists, the external join is pending.

Current blockers are explicit and remain red:

- with multiple active units, semantic analysis owns an aggregate reparse
  arena while `AstToHir` consumes original per-file arenas; the existing
  single-active-unit consumer does not close this boundary;
- no owned callsite mapping or genuine downstream compiler consumer exists for
  a `ResolutionId`; inference-order ordinals and raw `ExprId` surrogates are
  rejected;
- `IdentityDryRunTracker` remains a definition-annotation/body-infer proxy, not
  the semantic callsite producer.

The ownership precursor and bounded local decision are complete:
`SemanticIdentityRegistry` owns canonical session-local names and types;
`DefInstanceKey` owns ordered positional, block, and `{NameId,
SemanticTypeId}` named components; and the private `LocalCallResolution` is
constructed and immediately revalidated for exact r1-r5 shapes before
unchanged legacy body inference. Parser-owned selected definitions and nominal
receiver symbols from an independent Analyzer/root table fail closed, while
canonical symbol re-export into a file-local table remains valid. Same-arena
class reopenings preserve one receiver identity across distinct selected Defs;
recollecting a shared symbol-table context from a distinct arena rejects stale
receiver and method symbols while admitting the replacement symbol.
Same-arena stale-`MethodSymbol` admission and exact duplicate-signature
redefinition ordering are guarded. Cross-arena `MethodSymbol` admission for
compiler lowering is rejected at the multi-active-unit boundary: the aggregate
semantic prepass has no semantic-object handoff to `AstToHir`, and the existing unit
offsets are only a structurally validated node map. LSP per-file symbol merging
belongs to a separate bounded context. This does not authorize a producer
stream, create a cross-arena consumer, or make T1 green.

The T1 guard is **availability/current-red only**: it can show whether the
current source/configuration emitted a row or exposed the current failing
boundary. It does not prove global absence of another producer, semantic
identity continuity, or equivalence of selected definition, coercion, body,
and emitted symbol. No rewrite, broad in-process owner, or performance claim
is admitted.

Named residuals (explicitly NOT migrated): method-pointer thunks, proc
literals, block-to-proc body lowering scopes (MethodBodyLoweringScopeSnapshot
family); `output-file-owned-by-cli` and `tail-stub-from-mutable-sets`
(LLVMEmissionSession family); `FunctionReturnAvailability` /
`LoweredFunctionReturnContract` as a typed record (paper-only; the L20 edge was
consumed as a behavior fix); `MaterializationAttemptResult` terminal-status
owner type (paper-only); vertical `MethodBodyLoweringContext` /
`SemanticStateScope` slice.
The static-union insertion target/materialization edge is also residual: T9's
focused HIR join is green, but a fresh full-G9 route must still reach and join
the selected target to the materialized body and emitted call before an owner
record can be marked consumed.

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

Bounded macro lookup correction (2026-10-12, host-built candidate verified): an explicitly
qualified type call must search that owner's macros and inherited macros,
without falling through to a Program-level macro of the same short name.
An owner method stops the search before an ancestor macro can intercept it;
an owner macro still takes precedence at that scope. Unqualified calls retain
their existing lexical/global lookup. The source
anchor is `Process#initialize` calling `Crystal::System::Process.spawn` with
seven positional arguments: the current lowering instead expands the global
`spawn` macro and reads a Fiber type id as a process id. A no-prelude collision
fixture returns 99 through the global macro and 42 with that macro removed.
The acceptance check is the paired original-Crystal/Adamas collision oracle,
plus qualified owner/inherited/included-macro, child-method shadowing, and
unqualified global-macro controls. All seven controls pass in
`regression_tests/qualified_macro_owner_lookup_repro.sh`; individual upstream
Crystal 1.21 empty-prelude LLVM oracles establish their expected values.
Missing qualified macros must continue to ordinary method resolution; they
must not authorize cross-owner expansion. This does not admit arbitrary macro
arity recovery or certify Process runtime initialization, fork, exec, or wait.
Rollback is the isolated lookup-policy delta. Source or lookup changes require
rerunning these controls and the Process fixture before reusing its evidence.

The direct `Object#tap` shortcut may bind a zero/one-parameter block to its
whole receiver. Blocks with multiple parameters must use ordinary yield
lowering so a single yielded tuple is destructured. The old shortcut bound
each parameter to the tuple itself and sent `close_on_finalize=` to the tuple
instead of its second element. The host-built S1E candidate passes
`regression_tests/tap_tuple_block_destructure_repro.sh` for two-parameter blocks
over two- and three-element tuples, plus a one-parameter whole-tuple control.
The original failing candidate aborts at the tuple setter stub; disabling yield
inlining passes the same fixture. The real Process fixture now passes that
site and reaches a separate runtime crash. Generic yield arity overflow remains
an existing compatibility gap; no general block-arity claim is admitted.
Rollback is the tap call-site gate. Refresh after tap dispatch, tuple binding,
or inline-yield lowering changes.

Two adjacent bounded corrections are admitted at the same host-built boundary.
An N-way branch merge may canonicalize an enum's integer carrier to the named
enum only when every incoming value proves the same enum identity and has
either the enum type or its exact declared integer base. Independent integer,
nil, and unrelated enum arms retain their union representation. The runtime
guard is `regression_tests/enum_carrier_branch_merge_repro.sh`; the structural
guards are `spec/hir/enum_carrier_branch_merge_spec.cr` (3/3). Both regex literal
regressions pass. This does not certify enum identity for all raw literal
assignment shapes, loops, or ternary merges.

Macro unary numeric evaluation retains the operand's kind for signed minus,
unary plus, and width-bounded integer complement. Float32 minus must narrow and
serialize through Float32's shortest decimal representation, matching Crystal's
`NumberLiteral.new(Number)`, before equality or further macro operations.
`regression_tests/macro_unary_numeric_equality_repro.sh` tests direct/nested
equality, kind distinctions, complements, arithmetic, interpolation, rounding,
and signed zero with complete result comparisons before process exit. The
original-Crystal valid-fixture oracle agrees. Unparseable i128/u128 values and
unsupported unary operands retain the existing opaque fallback; that fallback
is not a claim of Crystal compatibility. Source changes require rerunning the
paired oracles and these guards. Rollback is each isolated producer delta.

When the first yielded value is a tuple, a generic block annotation that has
not resolved to a Tuple must not suppress destructuring. Use the concrete
yielded value's Tuple type in that case, then retain the remaining yielded
arguments as their own bindings. The old path bound `memo` as void and emitted
an unspecialized setter. `regression_tests/generic_tuple_yield_receiver_repro.sh`
uses a Crystal-valid generic module producer and checks five writes, with
typed-tuple, concrete, whole-tuple, and scalar guards. Original Crystal 1.21 and
host-built S1F both exit 0; S1E loses a write and fails the HIR guard. A previous
free-`T` reducer was rejected by Crystal and has been replaced; it is not a
compatibility oracle. Rollback is the first-yield Tuple type fallback. Refresh
after block type substitution, destructuring, or yield binding changes.

An additional included-method shadowing boundary is measured red on S1L.
The original-valid `Flow(T)#carry(obj : U, & : T, U ->) forall U`, included by
`GenericFlow(U)`, must bind T from the include site and method U from the
positional Int32 argument even when the receiver is GenericFlow(Int64). The
same requirement applies with an explicit return annotation. Original Crystal
1.21 compiles and runs both forms with exit 0; S1L compiles them but exits 9,
with HIR casting the argument to Int64 and choosing the Int64 overload. The
ordinary receiver-generic control retains Int64 correctly. The include-chain
candidate is the selected DefNode, but the registered map is absent, so the
existing fallback skips exact include provenance. Parser consumption also
discards forall names when no return annotation is present.

The admitted repair retains parsed forall metadata in DefNode and transports
it through relevant node reconstruction and both AstCache directions. Bump
the cache schema version so pre-metadata caches cannot silently erase semantic
names; a round-trip guard must preserve the parsed names. Synthesized accessor
and C-function definitions retain empty metadata. Exact selected-DefNode identity and
the concrete receiver's include chain may establish module bindings without a
registered map. For positional calls, bare method-forall parameter annotations
bind from actual call types and exclude same-name receiver aliases. Positional calls
with repeated bare method-forall annotations use the first positional
occurrence, matching the paired original-Crystal order-sensitive controls;
an unknown first actual remains unbound rather than selecting a later type.
Named calls retain their existing guard. This slice does not establish
general reordered, splatted, or nested generic argument inference. A paired
static Tuple-splat control passes after positional expansion; the dynamic
Array-splat variant is rejected by upstream Crystal. Multiline headers and default strings are
guards against reconstructing semantic names from header text. Rollback is the
metadata transport and exact include-map/type-binding change together. The DoD
is the paired upstream/S1 fixture, typed HIR producer checks, the strengthened
generic yield regression, and the focused owner/type suite. Full regressions
and fresh bootstrap smokes remain separate propagation obligations. This is
CAUTION semantic work; no general compatibility or bootstrap closure is
admitted. At immutable S1M3, the current manifest passes 152/152 with 553
supervised child calls and no resource abnormality. The strengthened repeated
parameter test also passes separately; both stage smokes and all five enum-HIR
and AST-cache specs pass. The scoped read-only adversary verdict is ROBUST for
included-method callback input inference, including exact selected-definition
provenance and first-actual binding. Enclosing-call result typing remains a
separate path and is not certified by these checks. Refresh after parser, cache,
include-map, argument expansion, or block parameter inference changes.

The single-parameter Hash#each intrinsic is a separate measured-red boundary.
Original Crystal's `Hash#each(& : {K, V} ->)` yields a key/value Tuple, while
`lower_hash_each_dynamic` binds a one-parameter block to the key alone. Once
the exact Enumerable include-map and method-forall accumulator bindings are
restored in S1K, the nested Hash reject fixture therefore indexes a String key
as a Tuple and exits 139. The old memo-type guard also assumes an out-of-line
reject function; successful inlining requires an equivalent scoped guard,
not acceptance of the corrupted payload.

The bounded repair is design-sealed: materialize a Tuple(K, V) for a single
Hash#each block parameter and expose that same type to loop-local inference.
Keep two-parameter key/value destructuring and empty blocks consistent with
the existing iteration path. Seal with the original-valid nested Hash reject
runtime fixture, a whole-pair one-parameter control, two-parameter controls,
and mutable-loop/next/empty guards, followed by the focused and full manifests.
Rollback is the single-parameter intrinsic binding plus its regression guards.
This does not admit arbitrary yield-arity packing or raw Pointer(Struct) ABI.
Refresh after Hash iteration, tuple storage, inline block binding, or mutable
loop inference changes.

An exact, non-void TypeRef match for a collection-module argument is sufficient
before checking whether a concrete class includes that module. The old early
module gate rejected `Enumerable(String)` against the identical argument type,
so a nested constructor callback selected a competing String initializer.
`regression_tests/process_nested_callback_constructor_repro.sh` checks the
callback marker, the String initializer, and an unmatched scalar rejection;
the valid callback fixture agrees with original Crystal. This host-built fix
does not certify OS process creation. Rollback is the exact-match early return.
Refresh on collection-module restriction resolution or constructor selection.

An inherited method using macro `@type` must retain the concrete receiver for
that macro while resolving unqualified constants in its declaring namespace.
The first receiver-only correction failed the parent lexical-constant guard;
the corrected S1H path passes all 15 inherited-method controls and the valid
original-Crystal oracle. `regression_tests/inherited_macro_type_receiver_repro.sh`
covers receiver identity, lexical constants, ordinary inherited methods,
shadowing, and multi-level inheritance. Generic-parent method discovery is a
separate open boundary: direct generic-parent and child-owned calls pass,
but inherited calls from a generic child still reach an unresolved stub.
Rollback is the receiver/namespace context delta. Refresh after macro owner,
method discovery, arena, or lexical lookup changes.

S1K exposes a second lexical-namespace case after generic parent discovery is
restored. An ordinary inherited wrapper that calls an inherited type-aware
method returns 105 instead of original Crystal's 22: the receiver macro returns
the correct child value, but the wrapper resolves TOKEN to the child's 90
instead of the declaring parent's 7. The current namespace fallback is gated
on a direct macro type use in the body, so that ordinary wrapper has no lexical
override. The bounded repair uses the resolved declaring definition's owner
for a requested inherited instance wrapper when no explicit namespace override
exists, while retaining the concrete receiver for method dispatch. Seal with
the generic inherited-method fixture, a plain inherited constant control,
and a child-owned constant shadow control before focused/full regressions.
Rollback is that wrapper namespace fallback. This does not authorize guessing
the declaring owner from the receiver or a short method name.

Generic superclass applications are a measured-red boundary in S1J. The
upstream-valid inherited-method fixture aborts at a child method stub; parent
traces resolve `GenericChild(Int32) < GenericParent(V)` to bare `GenericParent`,
and `Grandchild` likewise loses its parent's arguments. The class-header parser
currently stores only the constant path in `ClassNode.super_name`, discarding
the generic application before concrete parent registration can substitute it.
Searching generic ancestor templates alone does not repair that loss.

The bounded repair is design-sealed: retain the explicit superclass type
application in arena-owned AST storage, substitute the concrete child's type
map, and register the resulting concrete parent edge before method discovery.
Do not infer parent arguments from the child's position or parameter names:
fixed, renamed, nested, and permuted applications must retain their source
meaning. Non-generic parents and `< self` remain guards. The executable seal is
`regression_tests/generic_ancestor_inherited_method_repro.sh`, expanded with
fixed and permuted parent arguments and compared with original Crystal, plus
the focused owner-resolution regressions and full regression manifest.
Rollback comprises the class-header AST/parser, concrete parent registration,
and ancestor-template lookup changes together. Arbitrary generic compatibility
and bootstrap usability remain non-guarantees until their own checks pass.

Multiple assignment from a concrete StaticArray must retain its element type,
matching direct indexing. The old tuple-only element lookup bound both file
descriptors from `StaticArray(Int32, 2)` as void and selected a FileDescriptor
allocator without the intended initializer. S1H passes
`regression_tests/static_array_multiple_assign_element_type_repro.sh`, including
Int64 width/overload and Tuple guards; original Crystal agrees. Fresh Process
HIR now selects the explicit Int32 FileDescriptor constructor. Process runtime
still crashes at Polling::Arena's raw Pointer(Entry)#value/SpinLock access; this
fix does not admit raw struct storage or OS process execution. Rollback is the
StaticArray element fallback. Refresh after tuple/array element inference or
constructor argument typing changes.

The raw Pointer(Struct) boundary is independently refuted by four valid
original-Crystal controls. Zeroed nested Entry reads and lock-alias mutation
exit 139 in S1H; wide direct writes and indexed stride fail byte-alias checks
with exits 33 and 32. All four upstream runs exit 0. A typed Pointer(DeltaWide)
control passes only because allocation and accesses agree on pointer slots:
LLVM allocates two 8-byte slots for a struct whose inline width is 32 bytes.
The same pointer-slot storage policy drives malloc, load/store, and indexing.
Normal struct fields also use heap carriers, so a pointer-only load change
would leave the nested field representation inconsistent. Coordinated size,
stride, raw conversion, alias mutation, and reference-ownership guards are
required before admitting a repair. The byte-alias probes establish behavior
without relying on allocator slack or sampled resource telemetry.

Bootstrap propagation remains separate. S1L passes 151/151 manifest scripts
with 550 supervised child calls and builds ordinary S2 from an immutable
1,919-file source snapshot (maximum observed RSS 6,106,288 KiB, FD count 21).
That S2 compiles and runs both the no-prelude exit fixture and a full-stdlib
puts/Array/arithmetic fixture with exact output. The previous S2F/S2H stdlib
compile crash is closed within these smokes. Their nested Hash setter received
an alloca i8/void memo; the earlier producer confused include-site and method
type parameters, and the one-parameter Hash iterator supplied a key instead
of its key/value Tuple. Correcting those producers changes S2L's generated
nested setter receivers to loaded Hash pointers. The earlier unresolved-only
yield-tail fallback failed the target and was removed rather than promoted.

Ordinary S2L to S3 is still red: run_safe terminates compilation for memory at
12,906,864 KiB under a 12,288 MiB cap (41.54s wall time). S2L already links
Boehm GC, so inspect the actual allocation/lifetime consumers before changing
an allocator or retrying the same cap. No unmodified S3 or fixed-point claim
is admitted. Raw Pointer(Struct) remains independently red, and the new
included-method forall shadowing fixture is outside the 151-script L manifest
until its repair passes. Refresh with an exact-source rebuild, the complete
manifest, and both stage smokes after dependent compiler changes.

The allocation-family discriminator now has paired runtime evidence. The same
full-prelude fixture reports GC membership for Pointer.malloc, Array storage,
an escaped class instance, explicit scanned/atomic GC allocations, and dynamic
String storage under original Crystal 1.21 (membership mask 63). S1L reports
only the explicit scanned GC allocation (mask 8). Explicit LibC.malloc stays
outside Boehm in both; zeroed Pointer/scanned allocations and a default ivar
agree. MemoryStrategy::GC currently calls the libc-backed managed allocation
helper and writes an immortal RC sentinel. That violates its reclamation
contract, but the measured mismatch alone does not establish how much of
S3's peak is unmanaged churn rather than deliberately retained arenas.

The proposed CAUTION repair is a coherent managed-heap boundary in GC-linked
full-prelude mode. Collector-visible storage must include the emitted owners,
their pointer-bearing container/tuple/closure buffers, and their managed
children together. Moving GC-strategy objects alone would leave references
hidden in native parents. Internal managed allocation helpers may use scanned
Boehm allocation; atomic byte storage uses the atomic family. Preserve the
existing zero-initialization and byte-buffer terminator allowance. Explicit
LibC allocation calls remain native. No-prelude/no-GC paths retain their
existing allocator boundary. Realloc and free must discriminate ownership;
GC-owned storage must never reach libc realloc/free. ARC header validation
must recognize a GC base without treating headerless or static pointers as
RC objects, and Slab's current individual blocks need the same visible-owner
and release contract. Audit direct native emitters before admitting the graph.

The first managed-heap candidate N passes all six membership families and the
realloc/value guards, but its original-valid raw-root graph still crashes.
Generated `build_graph_root` decrements the inferred ARC graph at scope exit;
its destructor releases both container fields and explicitly frees the Boehm
block before collection. Supervised LLDB then faults in
`container_liveness_mode + 572` while loading the released graph's Array.
A scanned raw root is sufficient under Crystal's collector semantics, so
compiler-inferred ARC ownership cannot override that root. Collector-owned
storage must bypass implicit RC destruction and release; explicit GC.free
remains an explicit release operation. The same rule must cover atomic RC and
implicit Slab release, while native/no-prelude/no-GC ownership remains native.
This is a conservative collector fallback: eager ARC reclamation of these
blocks is not admitted, and membership alone does not establish safe liveness
or actual collection. Candidate N is VULNERABLE until the graph and release
guards pass without adding an artificial typed keepalive.

Candidate O leaves collector-owned storage intact through all four RC helpers
and compiler-emitted Slab release. Its original-valid fixture now passes all
six membership families (mask 63), value/zero and realloc guards, headerless
interior storage, explicit GC.free completion, StringBuilder capacity edges,
and the raw-root Array/Hash graph after two collections. The same source
passed under original Crystal 1.21; N still faults at the final graph probe.
O also passes the no-prelude and full-prelude stage smokes, five enum/AST
cache examples, 90 backend examples, and 20 focused scripts. Its complete
153-script manifest passes with 555 supervised child calls and no resource
abnormality. The separate allocator-gating script passes all eight supervised
compiler/runtime calls: no-prelude programs, including the explicit no-GC
variant, emit no collector calls and run natively; a dynamic String::Builder remains atomic
collector storage in the GC-linked mode. Read-only adversary inspection finds
the four GC-owned RC release guards and implicit Slab no-op before header
mutation or destruction, while native RC and explicit GC.free remain active.
The verdict is ROBUST within this observed allocation/liveness boundary.

The backend Thread::Mutex unit test previously required a removed raw
initializer override and failed before the GC repair. It now places a distinct
MIR call in that initializer and requires the emitted body to preserve it;
the real inline pthread lock/unlock/neighbor-field regression also passes.
The same body-probe test fails on the historical raw-override backend because
the override discards that call. A separate MIR allocator-mode guard forces
collector demand in all three cases and proves the no-GC and no-prelude gates
independently; only the managed case calls Boehm allocation/realloc helpers.
The atomic RC test follows the managed-free helper and independently verifies
that its no-GC branch still calls libc free.

Ordinary S1O builds S2O from the same immutable 1,919-file source in 583.10s,
with maximum observed RSS 5,883,440 KiB and FD 21. Both exact-output S2 smokes
and the two allocator/native-gating scripts pass. Ordinary S2O-to-S3 is still
red after 444.72s: receiver repair leaves a bodyless
`Int32#includes?$Regex::MatchOptions` target in
`Regex#pcre2_match_options$Regex::MatchOptions`. Maximum observed RSS is
3,037,104 KiB under the unchanged 12,288 MiB cap (FD 8); the former early
memory failure is bypassed. Isolate the enum semantic/carrier boundary on
the same S1O and S2O binaries before another bootstrap attempt.
This is scoped liveness evidence,
not a proof of reclamation, finalizer completeness, raw Pointer(Struct)
compatibility, or S3 convergence. Fresh S1O reproduces all four original-valid
raw-pointer failures unchanged: nested read/alias 139, wide direct store 33,
and stride 32; its typed-pointer control remains green. A separate recursive
raw-pointee layout and alias-preserving access contract is required, including
method calls and reference ownership; widening the inline-container allowlist
does not reconcile nested carrier offsets with Crystal's native inline layout.

The remaining raw-struct receiver contract has a paired runtime discriminator.
In the installed original 1.21 host, direct pointer.value.bump_leaf mutates
the pointee, but snapshot = pointer.value followed by snapshot.bump_leaf
changes only the copied local. The nested-POD/wide-field fixture returns mask
15/exit 0 upstream and mask 13/exit 2 on S1Q: its nested local mutation changes
the pointee. Both an aliased outer carrier and an outer copy sharing the nested
field fit that observation; do not select one mechanism from this fixture.
The inspected upstream source checkout is 1.20.1-derived and must not be
presented as 1.21 source. This original-valid failure is a separate diagnostic,
outside the passing bootstrap manifest. A future repair must preserve direct
receiver mutation, recursively independent value copies, raw byte layout and
stride, and live reference ownership together. A scalar-only or carrier-only
control cannot certify that boundary. Evidence lives in raw_receiver_contract_q
under the session output directory.

A subsequent scalar-only receiver fixture removes the nested-sharing
ambiguity. Original Crystal 1.21 returns mask 7/exit 0; S1Q returns mask
3/exit 1. Direct pointer.value.bump! mutates the pointee in both, but a
mutation through snapshot = pointer.value changes the scalar pointee only
in S1Q. This is evidence of failed independent outer value copying in the
tested shape. Two separate wide fixtures use Pointer(Struct) allocation and
Array(Struct).to_unsafe, then inspect UInt64 offsets 0/24/32/56 through the
pointer address. Both return typed/raw masks 3/15 upstream and 3/0 in S1Q;
both report sizeof 32. Thus typed access can remain internally consistent
while raw storage disagrees with Crystal. These do not yet distinguish
backing storage from raw-address lowering. Evidence: raw_receiver_scalar_q
and raw_array_pointer_q, with source hashes and supervised child receipts.

The enum bootstrap frontier has a small discriminator. Four full-prelude
fixtures (Int32/UInt8 flag loops, Regex::MatchOptions iteration and actual
Regex#match) compile and run under original Crystal 1.21 and S1O, but fail
under ordinary S2O with the same integer-owned includes? target. Paired
diagnostic traces show the initial enum receiver is preserved; after a bitwise
update the S2 branch merge instead introduces Enum | Int32. The emitted S2
track_enum_operator_result guard compares String object addresses for
operator_name.in?(...). A directly constructed String equals the literal but
fails the same variadic in? call under S1O; original Crystal returns true.

The bounded P repair preserves exact String value equality in variadic and
concrete Tuple in? lowering, using the existing string-equality intrinsic.
S1P passes its 154-script snapshot suite; its ordinary S2 passes all four
enum/Regex fixtures and three exact-output stage smokes. These measurements
establish propagation of this enum guard repair. Ordinary S2P also builds
S3P from the same source without IR rewriting or GCX (exit 0, 674.69s,
maximum observed RSS 6,461,936 KiB). S3P passes all three exact-output stage
smokes. Final Q propagation remains a separate requirement.

P leaves a mixed primitive counterexample: a String and its UInt64 object_id
are unequal under the original 1.21 host, yet both raw membership shortcuts
compare their matching pointer/integer bits as equal. Independent P variadic
and Tuple runtime falsifiers exit 28 and 29. Q admits false equality for an
exact String receiver and a statically known Nil/Bool/Char/numeric primitive;
Void, unions and other reference types retain the existing path. The
String/String branch remains content equality, and an unequal primitive must
not stop a later equal String candidate. S1Q passes the expanded regression,
the three stage smokes and five HIR/cache examples, including genuine
enum/integer and enum/nil controls. Read-only adversary review is ROBUST within
the enumerated helper set; paired original/Q Symbol controls also agree,
though Symbol bypasses this explicit false guard. S1Q's selected 154-script
manifest passes with 559 supervised child calls, no abnormal resources and
no script drift. Ordinary S1Q builds S2Q from the same sealed source in 656.40s
(maximum observed RSS 5,823,200 KiB, FD 21). S2Q passes all four enum/Regex
fixtures, three exact-output stage smokes and all three managed/native/String
contract scripts (14 supervised child calls). Ordinary S2Q builds S3Q from the
same immutable source without IR rewriting or GCX (exit 0, 562.26s, maximum
observed RSS 6,434,832 KiB, FD 18). S3Q passes all four enum/Regex fixtures,
three exact-output stage smokes and all eight managed/native-gating child
calls. The same selected 154-script suite finishes 152/154 with 551 supervised
child calls and no resource abnormality. It is red on generic ancestor
inheritance and included-module parameter shadowing: successful compilation
produces incorrect runtime values, including 23 instead of 33 for the latter.
The corresponding S1Q passes do not certify their bootstrap propagation.
Reopen the concrete ancestor/include binding claims and require the exact
original-valid fixtures on each ordinary stage before closure. Rollback is
the HIR lowering delta and its fixture. DoD:
P must fail the colliding address controls, Q must pass both negatives and
later-String positives, and ordinary S2Q must pass the four enum/Regex fixtures.
These guards do not admit general custom or union equality dispatch or
certify S3 convergence. The trace-only S2 enables debug guards in LLVM; it is
diagnostic evidence only. Refresh this evidence after changes to membership
dispatch, String representation/equality, primitive classification or source
state; sealed stage receipts identify the tested source.

The next generic repair has two bounded source invariants. Deferred included
module parameters must be authoritative over same-named owner parameters
when store_function_type_param_map consumes a DeferredModuleContext snapshot.
Q's emitted/stored map T=UInt64 is observed wrong for include Cmp(self) on
Pt(UInt64); the intended snapshot binding is inferred from the include-site
producer. Preserve owner-method T and explicit module UInt64 controls.
The new deferred binding fixture returns status 97 on old S2Q (failed bits
1/32/64), while original Crystal, S1Q and S1R return 0. The bit-64 control
specifically includes Cmp(UInt64) on an Int64 owner, proving that same-name
owner filtering breaks an explicit binding too; same-type controls could
mask that failure. Evidence: regressions_s2_q_deferred_red/measured_receipt.json
and regressions_r_generics/verified_receipt.json in the session output directory.
For a generic ancestor source body using @type, a registered ancestor name
must not preempt the requested receiver's specialization. S1/S2 HIR shows
the first divergent call target before MIR, with the receiver type preserved;
the early exact-name return is a source-order hypothesis, not a measured
dynamic branch. Keep child-owned exact methods first and retain the ancestor
lexical namespace. Risk is CAUTION because lookup and binding affect other
methods. Rollback is only the two function hunks and owned regression additions.
DoD is the same original-valid generic fixture and opposite controls on fresh
S1/S2/S3 from one immutable source, plus the selected bootstrap regression
manifest. Passing host-stage evidence alone cannot close this transition.

R tests that limit directly. S1R passes 155/155 selected scripts with 561
supervised child calls, five HIR/cache examples and all three exact-output
smokes. Ordinary S1R builds S2R from one sealed source in 571.32s, exit 0
(maximum observed RSS 6,016,368 KiB, FD 21). Both included-module binding
scripts pass on S2R. The included-method forall-shadow and generic module
MRO guards also pass (five supervised calls, no resource abnormality or
script drift; s2_r_module_guards/verified_receipt.json). The generic ancestor
fixture remains red. Thus the
two guarded resolver early returns are refuted as a sufficient macro repair.
Do not infer that this call executes that resolver path from source order.
Fresh S2R LLDB resolves the measured call to DirectChild(Int32)#inherited_macro,
then observes lookup_function_def_for_call return the selected source tuple
GenericRoot(Int32)#inherited_macro. Late receiver repair adopts that parent
symbol. This refutes the prior resolver-return attribution for this call.
The ineffective R guards are removed. The initial replacement preserves the requested
receiver only for zero call arguments, no block, no named-call shape, an exact
selected definition with zero formals, and an @type body macro from a generic
ancestor. The selected DefNode and registered lexical source arena remain the
macro provenance; defaulted, splatted and block-formal signatures use their
normal selected symbol. The expanded ancestor fixture passes original Crystal
1.21.0 with system ld. Host-built S and T pass the expanded ancestor fixture
and the overload adversary; ordinary S2/S3 propagation remains unmeasured.
Evidence: generic_ancestor_q_audit_s3_r/s2_repair_entry.lldb,
s2_lookup_target2.lldb, s2_resolve_call_unfiltered.lldb, and
original_ancestor_s_oracle/receipt.json in the session output directory.
The overload adversary prints its full failure mask and exits 1 for any
nonzero mask, avoiding false green results from process-status truncation.
Original Crystal, S1R and S2R report mask 0; a forced high bit of 1024 exits 1.
No ordinary S3R
build is admitted as closure evidence until that failing runtime signal is
addressed. Evidence: regressions_r/verified_receipt.json, s2_r.receipt.json,
and s2_r_generics/results.json in the session output directory.

A separate original-valid control exposes an older same-name method-forall
gap: Flow(T)#echo(value : T) : T forall T, included with module T = UInt64
and owner U = Int64, must infer method T independently for Int32 and Float64.
Original Crystal 1.21.0 compiles and runs the fixture with exit 0; S1Q, S2Q,
S1R and S2R all reject its explicit arguments. This is not introduced by R.
Module and owner binding methods in the same fixture remain required controls.
A stronger original-valid body oracle also reads T.binding_code inside the
forall body: Int32 and Float64 must produce 11 and 12, while the module and
owner methods retain 20 and 40. Passing call admission without these body
bindings does not close this gap.
Evidence: module_forall_t_guard_r/attempt_bj0hni2h/results.json and its
source SHA-256 507b25b77e6c8cef1fdabe7411520b95a6be6fd20ce82bdbca629275aefa9d69
in the session output directory. A repair must distinguish selected-method
forall keys from module keys, preserve non-forall module bindings, and pass
the existing included-method, module-binding and MRO scripts on each ordinary
compiler stage. Until then this same-name formulation remains rejected.

Two host falsifiers narrow that repair. S excludes method-forall keys only
from the stored included-method map and remains red at explicit-argument
compatibility (6/7 focused scripts). T additionally excludes those keys from
the exact candidate's isolated compatibility map. T admits the call, but its
runtime aborts at tag$Int64 (6/7). Fresh T HIR shows echo$Int32 and
echo$Float64 already have the correct signatures and call-result types;
enclosing expression inference still selects tag$Int64 for both. The two
method_binding bodies independently call UInt64.binding_code and
Int64.binding_code instead of the method's actual Int32/Float64 binding.
Neither attempt closes the formulation. The non-forall module
UInt64/String mismatch remains rejected in original Crystal and T. A numeric
literal mismatch is not a valid rejection oracle because original Crystal
contextually converts the literal. The next discriminator is the actual
signature/body binding before materialization, including the case where
method-forall exclusion leaves no registered module key. Evidence:
regressions_s_generics/results.json, regressions_t_generics/results.json,
concrete_module_original_string/receipt.json, and
concrete_module_s1_t_string/receipt.json in the session output directory.

A host-only u_body probe isolates the next producer seam. Storing the
method-forall actual map on the exact selected target fixes both body calls:
method_binding$Int32 calls Int32.binding_code and the Float64 specialization
calls Float64.binding_code. Neighboring module/owner methods still select
UInt64 and Int64. The echo signatures and call-result types also remain
correct, while enclosing tag(...) inference still selects tag$Int64. No
additional body-map merge filter is justified by this observed state.
Evidence: source_hashes_s1_u_body.json, s1_u_body.receipt.json, and
forall_u_body_diagnostic/receipt.json plus repro.hir in the session output
directory. This HIR probe does not establish the complete runtime fixture or
ordinary bootstrap propagation.

U's runtime remains red (6/7 focused scripts). Safe LLDB breakpoints at the
new AST return helper and all three infer_arg_types_for_call overload entries
receive no hits for the exact fixture. The existing emit trace discriminates
the actual producer: lower_call initially emits both echo$Int32 and
echo$Float64 with return type Int64. Later HIR repair corrects those call
types, after both enclosing calls have already selected tag$Int64. The AST
pre-inference sees an unresolved owner local, so the proposed helper placement
cannot repair this formulation. Move authority to the exact selected included
method's call-specific return annotation before emission; do not infer that
late type correction also repairs an already chosen outer overload.
Evidence: forall_u_lldb/helper_entry.log, infer_args_entry.log,
echo_emit_trace.log and forall_u_diagnostic/repro.hir in the session output
directory. These observations refute the placement, not the separate body-map
repair or the ordinary ancestor/module fixes.

V removes that unused AST inference path. At final call emission it consumes
only the exact emitted specialization map, requires the selected, emitted and
include-origin DefNodes to be identical, and resolves the referenced method
forall return parameters from concrete stored bindings. Blocks, named calls,
splats, unresolved bindings and changed emit targets remain outside the
override. S1V passes all seven focused scripts (23 supervised child calls,
no resource abnormality); the strict non-forall UInt64/String rejection also
passes. This proves the host-stage runtime formulation, not propagation.
Evidence: source_hashes_s1_v.json, regressions_v_generics/verified_receipt.json,
concrete_module_s1_v_string/receipt.json and forall_v_diagnostic/receipt.json.

Ordinary S1U builds S2U from sealed U source in 580.70s, exit 0, maximum
observed RSS 6,441,792 KiB. S2U passes the five neighboring module/overload
guards but remains red on the expanded ancestor macro and same-name forall
scripts (5/7). The forall failure predates V's emission repair; the ancestor
failure refutes host-only evidence as sufficient for the macro replacement.
Identify the exact failing runtime assertions and branch before widening it.
Evidence: s2_u.receipt.json and s2_u_generics/results.json.

The S2U assertion-reporting oracle localizes the ancestor failure to checks
2, 4, 6-12 and 44-50 of the unchanged 58-check fixture. DirectChild(Int32)'s
zero-argument macro returns the parent's 10 instead of 15. S2U HIR targets
GenericRoot for the child calls and has no child wrappers; S1V HIR targets
DirectChild and materializes those wrappers. The replacement guard still
derived its requested owner from resolved_base, which S2U had already resolved
to the parent. Use the actual HIR receiver owner, retain the selected source
DefNode/arena, and preserve its selected overload contract. The defaulted call
already carries an explicit Int32 actual with the same receiver-plus-Int32
ABI on both stages. The splat call carries one Tuple(Int32): its parent
source-shaped suffix is Int32_splat, while the child wrapper is named for the
packed Tuple ABI. These forms require distinct target canonicalization checks.
Evidence: generic_ancestor_macro_s2u_diag/print_repro.cr, print_hir.hir,
s1_v_hir.hir and results. A failed diagnostic trace is not branch evidence.

The final forall override is narrowed further to nonvirtual calls. A concrete
base-class virtual probe has an included forall method and a child override
returning String. Original Crystal takes the String branch (exit 42); both
pre-final S1U and S1V incorrectly expose Int32 and exit 40. Thus this is an
existing virtual-return gap, not a demonstrated regression from V. Exact
static DefNode/map provenance does not establish the complete runtime target
set, and the override could replace a class-target union inferred earlier.
Exclude call_virtual from this bounded repair; do not promote that exclusion
to closure of virtual return inference. Evidence: virtual_return_adversary/
source and original/S1U/S1V logs, source SHA-256
293e15e8e3bb52d9f919b4d30a2f9b2c18714c946d12867c98903e6cecaae1e4.

The durable virtual-return reproducer is
regression_tests/virtual_included_forall_return_union_repro.sh. Its runtime
guard converts the expected route value 42 to exit 0 and all other values to
exit 1. A fresh paired run compiles/runs successfully under original Crystal
1.21; S1X compiles successfully but the runtime guard exits 1. Both supervised
child processes finish normally, so this is a semantic failure rather than a
resource-limit abort. This known-open script stays outside the selected green
manifest. Evidence: original_virtual_gap_boolean/receipt.json and
virtual_gap_s1_x/measured_receipt.json in the session output directory.

X replaces the resolved-base-derived requested owner with the actual HIR
receiver owner at the late inherited-macro seam. It requires the exact selected
source DefNode, its registered lexical arena, a generic ancestor in the actual
parent chain, and an @type reference in that source body. Ordinary positional
and defaulted signatures retain their selected suffix only after exact
call-shape compatibility. Packed splats additionally require the selected
splat signature and actual Tuple shape to agree; the child target is mangled
from the actual packed Tuple ABI rather than copying the source _splat suffix.
Own child overloads retain precedence. Macro receiver identity and lexical
constant namespace remain separate authorities.

The strengthened 64-check ancestor fixture consumes splat values for Tuple
lengths 1, 2 and 3, including both first and second elements, and passes both
the original Crystal 1.21 full-prelude oracle and S1X. A first strengthening
attempt used runtime Tuple#size and aborted at a no-prelude stub; that result
does not falsify the receiver repair or establish a full-stdlib Tuple failure.
The corrected fixture avoids that unrelated helper while retaining argument
consumption. S1X passes all seven focused generic scripts (23 supervised calls,
no resource abnormality or script drift) and the strict UInt64/String rejection.
Ordinary S2X and S3X from the same sealed source remain required evidence.
Evidence: source_hashes_s1_x.json, s1_x.receipt.json,
regressions_x_generics/verified_receipt.json,
concrete_module_s1_x_string/receipt.json,
macro_recheck_x_original/receipt.json and macro_recheck_x_s1x/ in the session
output directory. Fixture source SHA-256:
00ee48940bb907b1b6a348b376b7d2b0b97f5355eb57ba3fb2addf4cdba95211.

A further read-only adversary invalidates X's nonvirtual return-binding
claim for class actuals with a namespace collision. A top-level ::Token
passed to Scope::Flow(UInt64)#bounce(value : U) : U forall U must select
classify(::Token), even when Scope::Token exists. Original Crystal safely
compiles/runs with exit 0; the pre-guard S1V compiles but exits 1. Its HIR
calls Host#bounce$Token with result type Scope::Token and selects the wrong
classify overload. Both the current and pre-guard helper stringify the actual
TypeRef, substitute its short name, and re-resolve it under the source module
namespace. Exact DefNode/map provenance therefore does not prove preservation
of actual-type identity. Bare built-in examples remain useful but do not close
this class-actual formulation. The ordinary X S2 build was deliberately
stopped after this counterexample (exit 143, signal; not a compiler failure),
and no X S3 result is claimed. Repair actual-binding identity;
source-written return names must retain their lexical namespace. Add top-level,
namespaced and nested actual-type controls before rebuilding ordinary stages.
Probe source SHA-256:
2457638158d019b5e2a48239dffbf4171e372369814539448efdd55db96605ea.

Y preserves positional forall bindings in a parallel TypeRef map. Final
nonvirtual return reconstruction accepts a bare forall actual or recursively
composed Tuple; forall leaves use the original TypeRef, while ordinary source
leaves resolve under the exact include-origin namespace. Other forall-dependent
composites remain outside this bounded override. The legacy body map qualifies
bare root nominal names, without claiming generic-name serialization is safe.
Original Crystal 1.21 passes the new eight-check namespace fixture. Fresh S1Y
passes all seven neighboring scripts and the strict UInt64/String rejection,
but the namespace fixture still exits 1. A bounded eight-bit diagnostic returns
mask 4: only identity_marker(::Token.new) is wrong; both direct return identities,
both lexical Tuple cases and the module/owner controls pass.

The surviving body failure is a zero-argument member-access route, not the
ordinary CallNode or lower_path route. Z's absolute nominal literal helper and
AA's ordinary-call receiver helper both leave the diagnostic at mask 4; their
experimental hunks are removed. Unconditional marker-scoped tracing in a sealed
AA clone shows an Identifier receiver with map binding T=::Token and the correct
include-origin namespace. The initial static owner is nil; lowering the
identifier then recaptures Scope::Token, and the later type-literal dispatch
selects Scope::Token.marker. A separate T.marker() fixture passes original
Crystal, S1Y and S1AA, with positive ordinary-call trace output. Empty earlier
trace output only establishes that those instrumented branches were absent;
it does not establish their hypothesized static-owner normalization failure.

The repair therefore belongs to the MemberAccess Identifier branch, after its
runtime-local precedence check. AB preserved ::Token verbatim and still failed:
static lookup derived a rootless query name but passed the original ::Token to
the method resolver, which has Token.marker registered. AC strips only that
representation prefix after accepting the producer-backed absolute bare
Class/Struct/Module binding. It neither re-resolves the actual under the source
namespace nor changes ordinary lexical names or other mapped forms. The bare
name predicate is syntactic; nominal provenance comes from the actual-binding
producer. Generic, union, nullable, pointer and whitespace-bearing forms are
outside this receiver override.

The durable namespace regression checks both call forms and prints all ten
failure bits before returning only 0 or 1. Original Crystal 1.21 and fresh S1AC
pass it. S1AC passes all eight focused scripts (25 supervised child calls, no
resource abnormality or script drift), the strict UInt64/String rejection and
five HIR/AST-cache examples. A source-sealed diagnostic HIR also calls
Token.marker for the root actual and Scope::Token.marker for the scoped actual.
The read-only adversary returns ROBUST within the producer-backed bare nominal
route, supported by these paired controls. S1AC's full selected suite also
passes 158/158 (567 supervised calls, no abnormal resources or script drift).
Ordinary S1AC-to-S2AC compilation exits 0, but S2AC's focused suite is 7/8.
The generic ancestor fixture fails checks 50-56: an inherited wrapper calling
a self macro loses the requested child owner. A minimized twelve-control
fixture passes original Crystal and S1AC, but S2AC returns mask 382/exit 1.
All three self-call forms, additive wrappers and the Int32 macro overload fail;
the String overload and an unrelated parent-object call pass. Source-order
masking is refuted. Initial call-target logs match, but S1 materialization
requests Child#wrap_bare through inherited_bare_exact, while S2 already requests
Root#wrap_bare through direct lookup. The downstream direct @type predicate is
false for both source wrappers and cannot explain that stage difference.
Late owner selection/replay is the open diagnostic frontier; no transitive
predicate widening or S3AC result is admitted before it is resolved. The
existing ADAMAS_TRACE_REPAIR hook itself crashes S2 on this fixture; the
materialization ledger alone does not crash and is diagnostic evidence only.
An unconditional static-tag clone reproduces the same mask after an ordinary
S1-to-S2 build. Both stages reach the child receiver with nonvirtual calls,
type-literal false, a passing string-header guard and a different target owner.
Those gates are therefore refuted as the stage divergence in this fixture.
S1 enqueues six Child wrapper bodies with inherited_bare_exact and a concrete
U=Int32,T=Int32 map; S2 omits those requests while still materializing Child's
String overload and peer wrapper. A second sealed selection-corridor clone
refutes a different definition or generic-binding selection at that repair
boundary: both stages select GenericRoot(Float64)#inherited_macro with
T=Float64, identical positional shape and a true macro-receiver predicate.
Top-level child calls enqueue the same child wrapper. Inside the inherited
lexical-and-macro body, however, S1 reaches repair with a Child receiver and
Root target, while S2 already has a Root receiver and target and takes the
same-owner fast path. The open frontier is the earlier body materialization:
requested owner, captured substitutions and the self type passed to lower_def.
Repairing that downstream fast path without establishing its supplier would
not restore the lost receiver context.
The next paired materialization clone selects the same exact wrapper DefNode,
arena and concrete T/V/U=Float64 map, but S2 reports preserve_value=false where
S1 reports true. A consolidated owner-predicate clone changes that result to
true and passes the exact S2 runtime fixture. It also rewrites nested predicate
calls into local Booleans and adds predicate observations; this is a confounded
probe, not a production fix or proof of a return-carrier bug. A trace-free clone
changes only the outer call to a local Boolean: its ordinary S2 selfbuild exits
0, but the same fixture still exits 1. The normalized outer helper and all five
Enumerable#any? bodies match AC; the nested generic-source helper is byte-identical.
This refutes the local-Boolean/control-shape explanation for this case.
The nested helper instead calls Enumerable(T)#any?$block, whose reachable LLVM
path unconditionally returns false without invoking its predicate. The callback
itself tests the captured key/value bindings correctly.

Two selected-target rebase guards reject empty positional lists even when the
call has a block. The bounded repair admits arity zero only for block-bearing
included lookups; concrete receiver, known arguments, compatible source Def,
include-site bindings, lexical namespace and collision checks remain required.
A source-sealed AF scratch clone with only those guards changed compiles and
runs the six-control Hash.any? fixture with mask 0. Its HIR calls the concrete
Hash(String, String)#any?$block and iterates entries; older AC S1/S2 crash on the
same fixture. This is a host-stage discriminator, not yet a bootstrap closure.
Other zero-argument inference paths are outside this measured rebase scope.
Its ordinary S2 selfbuild reaches LLVM but exits 1 at llc: Array(String)#join_strings
contains an add i1 fed by an i32 extension and an i32 bytesize result. The
earlier Array(String)#additive_identity specialization calls
String::Formatter::Flags#zero after Reflect(Int32).type, whereas AC calls
Int32#zero. A paired original-valid Hash.any?-then-join_strings probe passes
original Crystal and aborts at the Int32#zero stub on S1; it does not select
Flags#zero. The immediate adjacent-block leakage hypothesis is refuted.
Type-literal/class-method receiver provenance remains the diagnostic frontier.
This is a measured build blocker, not S2 runtime evidence.
No owner-predicate widening is justified by the earlier confounded traces. Evidence:
ancestor_materialization_diag/trace_receipt.json and paired matdiag logs;
ancestor_materialization_diag/ownerpred_trace/generic_s2.hir and its compile
and runtime logs; ancestor_ownerpred_s2_final.resources.json under
/private/tmp/adamas-sol-review-20261013/.
Additional evidence: ancestor_materialization_diag/local_bool_shape/run/receipt.json,
its paired fixture IR, zero_block_rebase_probe/delta.json and host.receipt.json,
hash_any_zero_rebase_s1/receipt.json and capture.hir, source_hashes_s1_ag_any.json,
s2_ag_any.receipt.json and s2_ag_any.ll:4555946.
Evidence: source_hashes_s1_y.json, s1_y.receipt.json,
original_forall_namespace_y/receipt.json, regressions_y_generics/results.json,
namespace_y_diagnostic/receipt.json and capture.hir;
namespace_z_diagnostic/receipt.json, namespace_aa_diagnostic/receipt.json,
aa_member_trace_lineage.json, namespace_aa_member_trace_diagnostic/hir.log,
namespace_parenthesized_aa/receipt.json, namespace_parenthesized_y/receipt.json,
original_forall_namespace_ab/receipt.json, ab_member_trace_lineage.json,
namespace_ab_member_trace_diagnostic/hir.log, source_hashes_s1_ac.json,
s1_ac.receipt.json, regressions_ac_generics/verified_receipt.json,
concrete_module_s1_ac_string/receipt.json, ac_ast_specs.log,
namespace_ac_diagnostic/receipt.json and capture.hir,
regressions_ac_full/verified_receipt.json, s2_ac.receipt.json,
s2_ac_generics/results.json, ancestor_s2_ac_diagnostic/receipt.json,
ancestor_controls_original_ac/receipt.json, ancestor_controls_s1_ac/receipt.json,
ancestor_controls_s2_ac/receipt.json, ancestor_controls_s2_ac_ledger_only/.
Additional boundary evidence: ancestor_gate_diag/run_receipt.json,
ancestor_gate_diag/s1_fixture_compile_mat.log,
ancestor_gate_diag/s2_fixture_compile_mat.log and static-tag compile logs;
original_ancestor_wrapper_ac/receipt.json;
ancestor_gate_diag/selection_trace/selection_trace_setup.json,
ancestor_gate_diag/selection_trace/run/receipt.json and its paired generic
compile logs (instrumented HIR 791edb0e66b98e963372e4c014cae58d0ca55740c28d3b62bade056224cb5a2d).
Instrumented clones are
diagnostic evidence only, not production candidates.

Virtual included-forall return frontier (design-sealed, measured-red): fresh
S1AC and S2AC both compile the Boolean fixture but exit 1. HIR marks echo as
virtual while giving its result Int32 and choosing tag$Int32. LLVM dispatch
includes the child String implementation but bridges it through an i32 return
ABI. The existing MIR UnionWrap path already handles heterogeneous concrete
returns when the callsite carries the full union; changing target selection
is not indicated by this evidence.

The proposed bounded repair accepts an exact included-method forall origin,
plain positional concrete arguments, and a complete compatible concrete class
target set with known per-target returns. Infer the inner virtual result before
its enclosing overload is selected. Keep method-forall actual TypeRefs distinct
from include-site names, keep Nil when it is a real return, and keep each
concrete method's registered return contract separate from the callsite union.
Block, named, splat, unresolved/unsupported return forms, module/union receivers
and incomplete target evidence remain outside this widening. Existing VOID
fallback behavior is a separate legacy path, not evidence of complete coverage.
Current-owner enumeration alone is insufficient: generic class declarations
enter the template registry without a superclass edge; on-demand specialization
can publish that edge during body lowering, after an earlier Call TypeRef was
stored. Deferred macro output and nested class-body lowering can also register
new classes or templates after initial registration, so scanning the current
template registry cannot establish a closed world. Subclass-cache invalidation
only repairs future queries; it does not widen an existing call result. The
current-set-only guard and a registry-only ancestry guard are VULNERABLE by
source inspection; no runtime counterexample is claimed here.

The accepted revision records the early union as a provisional callsite
certificate: canonical receiver/method, exact actual TypeRefs and include
origin, and every concrete dispatch owner's selected target, parameter ABI and
return TypeRef. After type-parameter refresh, the final deferred allocator flush
and RTA pruning, but before MIR consumption, re-resolve that same contract
against the surviving HIR functions and require exact equality. The earlier
pending-function flush is not the final materialization boundary. A new,
missing or unresolved owner, changed target ABI or changed return set rejects
compilation with a specific LoweringError. This is a guard-only unsupported
case; repairing enclosing overload selection after hierarchy changes is outside
this patch. Only unchanged final certificates admit the early callsite union.

The first implementation seal AE builds with the original host, and nine of
ten focused controls pass. The strengthened virtual fixture fails early with
`cannot certify virtual return targets`: the include registers
Base#echo$UInt64, while the concrete forall call needs Base#echo$Int32. Exact
source-backed target materialization is still under repair; no virtual success
is claimed for AE. Final revalidation must remain read-only after RTA. For a
same-Def forall target, its emitted static return must equal the inferred
effective return before that return contributes to the dispatch union; MIR's
ABI wrappers do not establish semantic equality for mismatched returns.
An original-valid Flow/Base/Array(Base) oracle creates a later Late(String)
specialization and observes (Int32 | String) before and after insertion.
AE and AF reject that input explicitly; this supports the declared
generic-descendant guard boundary, not the missing capability. AF materializes
exact selected include targets only during provisional call lowering and
requires emitted/inferred return equality. Its host build exits 0, but the
strengthened virtual fixture still rejects before MIR: focused controls remain
9/10. Nine HIR/AST examples pass against sealed AF source, including the exact
Int32 | String certificate and rejection after a published descendant, changed
override return ABI, or a selected forall body whose static return differs from
the actual inferred binding. The strict UInt64/String incompatibility control still
rejects. Evidence: source_hashes_s1_af.json, s1_af.receipt.json,
s1_af_focused/results.json, af_static_return_spec_ast_specs.log and its source/spec
manifests, virtual_late_s1_af/receipt.json and
concrete_module_rejection_s1_af/receipt.json. No AF virtual runtime success or
ordinary AF bootstrap propagation is claimed.

Risk is CAUTION at HIR/MIR ABI composition. The strongest failure is a partial
return set that still emits an incompatible dispatcher; a second guard checks
that direct base/child calls retain their concrete result types. DoD: the same
original-valid virtual fixture passes original Crystal and every repaired
stage, with base/child, Nil, same-return and incompatible-overload controls, and HIR
exposes the heterogeneous return set before tag dispatch. Re-run the focused
generic suite and selected full bootstrap suites on the final source seal.
Rollback the virtual return-inference hunks and their regression changes
together; refresh after hierarchy, selected-def, actual binding or dispatch ABI
changes. Evidence: virtual_forall_s1_ac_control/receipt.json and capture.hir,
virtual_forall_s2_ac_control/receipt.json and capture.hir, and their repro.ll;
original_virtual_gap_boolean/receipt.json.

The installed Boehm 8.2.12 header is the API anchor: scanned malloc clears
storage, GC_base recognizes interiors, and GC_realloc/free require appropriate
GC-owned allocations. The strongest failure mode is premature collection of
a live nested reference, followed by allocator-family mixing or unsafe header
probes. DoD: the original-valid managed_gc_allocator_repro.sh must reproduce
the old membership failure and pass membership, zero/value, realloc/null,
interior/reference, Array/Hash, and exact-capacity StringBuilder guards after
the repair. Check generated allocation/release consumers and both existing
stage smokes, then run focused/full regressions. Rollback the coordinated
managed allocator, realloc/free, header-validation, and direct-owner changes
together. Ordinary S2-to-S3 under the unchanged cap remains a separate
propagation falsifier; no heap repair or bootstrap closure is admitted before
these checks execute. Refresh after allocator, ownership, collector startup,
linker demand, or reference-storage changes.

The semantic producer for this record is post-resolution, after semantic
literal/autocast normalization if applicable, and before Adamas HIR/value/ABI
coercion, analogous to Crystal `Call#instantiate`. A late
`lower_function_if_needed` or MAT string ledger is therefore a rejected
producer; it may only consume or serialize an already typed resolution.

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
  under only the target symbol is a failing state;
- `main_arenas << map_arena` and its explicit-upcast control may select
  distinct lawful concrete and union instances. Concrete, explicit-cast, and
  true-union flows must each preserve selected `Def`/`DefInstanceKey`,
  coercion/value type, receiver/value arity, materialized body, and emitted
  symbol through HIR/MIR/LLVM, and emit neither an orphan zero-argument
  `push$AstArena()` call nor a malformed zero-argument unreachable stub.

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

### 6.9 Built owner records (verified in code, 2026-07-03)

The records below exist in the codebase and are consumed by production paths.
Each entry names its defining location, the authority edge(s) it consumed, and
its guard. A record listed here and absent from the section 0 state table is a
documentation bug.

#### 6.9.1 LLVMEmissionSession (mir/llvm_backend.cr:648)

Owns the per-`generate` LLVM emission plan: which functions are emitted, under
what worker policy, and through which side-effect channel tags.

Fields: `function_plan : LLVMEmissionFunctionPlan` (original_count,
reachable_count?, skipped_ids, deduped_mangled_names, functions_to_emit;
derived final_count/pruned_count), `requested_worker_count`,
`effective_worker_count`, `worker_sequential_reason_code`, plus owned
side-effect tag constants (`STR/ZSG/EXT/CCF/EMF/ERT/MSG/GRH/DGF/SCN`).

Responsibilities: built once by `build_llvm_emission_session` before emission;
worker emission serializes side effects through
`write_worker_side_effects_with_contract` and the parent merges via
`merge_worker_side_effects_with_contract`; records sequential-fallback reason
as evidence, never silently.

Non-responsibilities: function body semantics, output/file ownership
(LLVMOutputOwnershipContract), tail-stub body-presence contract (residual),
resource acceptance gates.

Guard: `REQUIRE_SESSION=1 REQUIRE_WORKER_PLAN=1 REQUIRE_SIDE_EFFECT_CONTRACT=1
scripts/llvm_emission_session_source_shape_guard.sh`.
Edges consumed: `function-list-inline`, `worker-policy-inline`,
side-effect merge, GC-realloc helper demand (`GRH`).

#### 6.9.2 MethodBodyLoweringScopeSnapshot (hir/ast_to_hir.cr:2973)

Owns the method-body lowering scope for the three method-like seams:
`lower_method`, `lower_def`, `lower_module_method`. Replaces the raw
inline-yield/infer-body/current-return save-clear-restore blocks.

Fields (snapshot of ambient AstToHir state): `inline_yield_block_stack`,
`inline_yield_block_arena_stack`, `inline_yield_block_param_types_stack`,
`inline_yield_block_return_stack`, `inline_yield_name_stack`,
`inline_arenas?`, `infer_body_context?`, `current_def_return_type`.

Responsibilities: `enter_method_body_lowering_scope(return_type)` snapshots
all eight facts, resets the five inline-yield stacks, nils `inline_arenas`,
installs the callee return type; `restore_method_body_lowering_scope` restores
all eight. Exactly one enter/restore pair per owned seam.

Non-responsibilities: method lookup, materialization naming, parameter/self
binding, callee-local scanning (6.9.3), method-pointer thunks, proc literals,
block-to-proc body scopes (explicitly NOT migrated).

Guard: `scripts/method_body_lowering_scope_source_shape_guard.sh` with
`REQUIRE_METHOD_BODY_SCOPE=1 REQUIRE_LOWER_DEF_BODY_SCOPE=1
REQUIRE_LOWER_MODULE_METHOD_BODY_SCOPE=1`.

#### 6.9.3 InlineCalleeLocalScanScopeSnapshot (hir/ast_to_hir.cr:3017)

Owns the scanner/provenance scope of `AstToHir#inline_callee_local_names`:
the temporary switch from caller arena to callee arena plus inline-yield stack
clearing while collecting assigned and block-local names.

Fields: `arena`, `inline_yield_block_stack`, `inline_yield_block_arena_stack`,
`inline_yield_block_param_types_stack`.

Responsibilities: `enter_inline_callee_local_scan_scope(callee_arena)`
snapshots four facts, installs the callee arena, clears the three stacks;
`restore_inline_callee_local_scan_scope` restores stacks then arena.

Non-responsibilities: body lowering scope (6.9.2), name-collection semantics,
arena lifetime.

Guard: `REQUIRE_INLINE_CALLEE_LOCAL_SCAN_SCOPE=1
scripts/inline_callee_local_scan_scope_source_shape_guard.sh`.

#### 6.9.4 LLVMOutputOwnershipContract (mir/llvm_backend.cr:724)

Owns which IO the LLVM backend writes to: primary output vs parallel
parent/worker temporary outputs, and rescue-path restore. Consumed the
frontier where the parallel rescue restored a stale `saved_output` with
`pos=0`, nulling the final output.

Fields: `primary_output : IO`, `current_output : IO`. Operations:
`capture_primary_output`, `enter_temporary_output`, `restore_output`,
`restore_primary_output`.

Responsibilities: sole authority for the parallel save/restore-output pattern.

Non-responsibilities: finalization/`to_s` semantics, `.ll` file writing (CLI
owns the file; `output-file-owned-by-cli` residual), IO::Memory internals.

Guard: `REQUIRE_OUTPUT_OWNERSHIP=1
scripts/llvm_output_ownership_source_shape_guard.sh`.

#### 6.9.5 BlockCallReturnContract (hir/ast_to_hir.cr:919)

HIR-owned contract making the callsite block-return fact part of wrapper
identity for untyped `&` helpers whose method result is the yielded value
carried through an assigned tail local (`result = yield; ...; result`).
Deliberately narrower than all yield-containing helpers (a census refuted
global return-shape specialization: 208 multi-shape keys).

Fields: `block_return_name : String`, `block_return_type : TypeRef`. The
producer returns `BlockCallReturnContract?` — nil for ordinary iterators and
scoped helpers, protecting nil/non-returning callsites from
over-specialization.

Responsibilities: prevents a shared `$String_block` wrapper first lowered at a
void callsite from freezing `yield : Void` for later value-demanding
callsites.

Guard: `REQUIRE_CURRENT_CU_CONTRACT=1
scripts/hir_block_return_shape_census.sh`.

#### 6.9.6 GeneratedStageExecutionOutcome (cli.cr:615)

Owns the CLI output commit record: LLVM IR start/written and binary
compile-result rows for generated-stage transaction ledgers.

Fields: `ll_file`, `output_path`, `emit_mode`; mutable `llvm_ir_bytes`,
`binary_compile_result`. Serialized through the default-off `GSETX` ledger
(`ADAMAS_GSETX_ID` / `ADAMAS_GSETX_LEDGER`); rows must never affect compiler
semantics.

Guard: `REQUIRE_OUTPUT_OUTCOME=1
scripts/generated_stage_outcome_source_shape_guard.sh`.

#### 6.9.7 LLVMFunctionEmissionOutcome (mir/llvm_backend.cr:757)

Env-gated per-function emission transaction row connecting planned function
emission to output/side-effect growth. Produced when
`ADAMAS_GSETX_FUNCTION_EMISSION_OUTCOMES` is on plus GSETX ledger vars;
evidence only, never acceptance.

Fields: function/mangled name, mode, status (incl. `started`), index, totals,
`out_pos_before/after`, emitted/called/undefined before/after and deltas.

Consumers: `scripts/generated_stage_execution_transaction_report.sh`,
`scripts/generated_stage_mode_resource_lane_classifier.sh`,
`scripts/generated_stage_function_emission_attempt_classifier.sh`.

#### 6.9.8 CallMaterializationTransaction (hir/ast_to_hir.cr:2171)

Owner record for the vertical materialization spine in
`lower_function_if_needed_impl`: one transaction carrying request-through-body
identity instead of split locals/ambient maps.

Fields (24) include: `phase`, `requested_name`, `target_name`, `state_key`,
`body_symbol`, `call_symbol_hint`, `override_symbol?`, `lookup_branch`,
`ambient_map`, `target_map`, `call_arg_types`, `selected_def`,
`selected_owner`, `state_scope`, `materialization_action`,
`body_function_present`, `body_has_body`, `body_state`, `abi_shape`,
`wrapper_forwarder_contract`, `rejection_reason`. Derived: `identity_status`
(`exact` iff body_symbol == call_symbol_hint), `symbol_relation`, `debug_id`.

Responsibilities: answers "did requested, selected, target, body, and emitted
call agree under one transaction id"; feeds the `[MAT_TX]`/`[MAT_DONE]`
ledger.

Non-responsibilities: requested-name forcing, backend forwarders, ambient-map
policy, `BlockOwner` carrier changes.

Guards: `REQUIRE_PROMOTED=1
scripts/call_materialization_transaction_admission_report.sh`;
`scripts/materialization_transaction_report.sh`;
`scripts/call_materialization_transaction_consumer_selection_report.sh`;
`scripts/block_owner_materialization_transaction_availability_report.sh`.

#### 6.9.9 MaterializationSymbolBinding (hir/ast_to_hir.cr:2254)

Owns the symbol-binding seam of `lower_function_if_needed`:
requested/target/body/call symbol identity plus override decision, replacing
inline `materialized_name = if ...` / `override = if ...` branches.

Fields: `requested_name`, `target_name`, `state_key`, `body_symbol`,
`call_symbol_hint`, `override_symbol?`, `override_reason`.

Responsibilities: sole source for materialization keepalive candidates and the
identity-ledger symbol fields; wrapper/forwarder contract derivation.

Non-responsibilities: body lowering, state-scope selection, emitted-symbol
behavior changes (shadow/parity: emitted symbols remain legacy-equivalent).

Guard: `REQUIRE_PROMOTED=1
scripts/materialization_symbol_binding_admission_report.sh`.

#### 6.9.10 InvocationContext (hir/ast_to_hir.cr:670)

Owns the invocation frame for the `lower_super` / `previous_def` seam:
consumers read one owned frame instead of ambient `@current_class` /
`@current_method` / `@current_method_is_class` /
`@current_super_source_module` / forward-arg fields.

Fields: `class_name?`, `method_name?`, `method_is_class`,
`super_source_module?`, `function_name`, `forward_arg_ids`. Constructor:
`invocation_context_for_current_method(ctx)`; `with_invocation_super_source`
scopes nested module-super lowering with legacy save/restore semantics.

Guard: `REQUIRE_PROMOTED=1 scripts/invocation_context_admission_report.sh`.

#### 6.9.11 MaterializationCompletion ledger (methods, not a type)

Post-lowering completion authority for a materialization attempt. Not a
record: a default-off `[MAT_DONE]` row (`log_materialization_completion_ledger`,
hir/ast_to_hir.cr:2654) under `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER`.

Row fields: requested/target/materialized symbols, `has_function`,
`has_body`, final lowering `state`, owned terminal `status` and `reason`,
`created_function_count`, `producer_path`, `created_symbol_relation`,
`created_symbols`.

Responsibilities: distinguishes missing completion facts, completed attempts
without HIR functions/bodies, and MIR/backend visibility loss;
`created_body` / pre-lowering `InProgress` state is NOT body-present evidence.

Cautions: a `MaterializationAttemptResult` owner type remains a named future
slice (paper-only). Do not thread a trace object through production
`lower_method` (refuted: regressed generated-stage runs).

Guards: `scripts/generated_stage_created_body_visibility_classifier.sh`;
`scripts/generated_stage_lower_method_terminal_classifier.sh`.

#### 6.9.12 Shadow decision records (parity only)

`MaterializationDecisionRecord` (hir/ast_to_hir.cr:2856),
`SemanticStateScopeDecision` (:2901), `KeepRequestedNameDecision` (:2938) are
shadow/parity decision records; they must not become behavior authorities
without a would-change census. `DominanceInfo`
(mir/optimizations.cr:1681) is the lazy-dominance perf subowner for
CopyPropagation, not a contract record.

## 7. Execution order

### Phase 0: Bootstrap stabilization freeze

Do not start broad refactor while current `s2b`/`s3b` bug frontiers are moving.
Only add SDDs, probes, and small tactical fixes needed to restore the bootstrap
corridor. The active performance objective is fresh `s1 -> s2b` in <=300s
(with <=180s retained as a stretch target), not merely a downstream run of an
old generated artifact.

Additional stop-rule after the 2026-07-01 checkpoint: a tactical fix is allowed
only when it names the owning semantic boundary and either consumes an existing
ledger row or adds a new behavior-neutral ledger/falsifier that will survive the
fix. If a slice only moves the crash/RSS frontier without adding an owner
boundary, stop and route the work to Phase 1 census.

Exit signal:

- fresh B4-F `s1 -> s2b` reaches the <=300s budget and both exact
  plain/full-prelude and no-prelude smokes pass;
- `s3b` status is known;
- active frontiers have problem cards and reducers or smoke scripts.

### Phase 0a: R0 frontier reconciliation

R0 is the mandatory join before Slice 1B or any default-path semantic
promotion. It must be run from a disposable snapshot of the current dirty
frontier and must not stage, clean, or rewrite the user's main worktree.

1. Build an A/B pair from the same source snapshot: A without T0 provenance
   and B with `91ebe332` T0. Record revision, flags, cache policy, workers,
   wall time, peak RSS, and generated-artifact provenance. Use a new output
   directory, verify fresh-output/source/output hashes, and record
   `cache_policy`, `cache_dir_rel`, and `cache_directory_identity`; record any external host cache separately and hold it
   constant.
2. Run host/unit guards plus exact plain/full-prelude and exact no-prelude
   semantic smokes on both A and B under `scripts/run_safe.sh`. Both modes are
   co-equal gates; a timeout is non-discriminating rather than proof that T0 is
   the cause.
3. Run a fresh `s1 -> s2b` classifier with a diagnostic cap sufficient to
   leave an attributable artifact, then apply the B4-F acceptance budget of
   <=300s. Compare materialization requests, duplicate bodies, forced lowers,
   queue peaks, phase times, and RSS; no single function count or timeout is a
   value proxy.
4. Write an evidence manifest naming the first divergent owner or declaring
   the result non-discriminating. Only after this seal may Slice 1B introduce a
   real `ResolutionId`/materialization consumer.

The disposable snapshot/source-guard subgate and host preflight are complete.
The sealed current-source run classifies only the former 180-second cap as red:
stage2 timed out at 182.54 seconds with exit 143 and no `cv2_s2`. It does not
classify the current 300-second policy. Stage2 semantic smokes are unavailable
because no artifact exists; B5 remains historical/unrefreshed, and G9 remains
only a diagnostic candidate.

R0 as a promotion seal remains open until the same sealed source passes B4-F,
produces explicit stage2 semantic smoke results, and completes the fresh T0
A/B. Neither B4-H, G9, nor the manifest substitutes for those gates.

### Phase 0a.1: Reliability/architecture two-track join

The [execution-plan promotion policy](compiler_refactor_architecture_plan.md#03-order-of-work-and-promotion-policy)
distinguishes a targeted repair of the existing path from promotion of a
replacement path. A red B4-F does not prohibit a reducer-backed correction of
its cause. Such a repair needs the existing owner/consumer, relevant tests,
an adversary control, and a source-matched bootstrap classification when that
corridor changes; it does not require an unrelated T0 A/B or new owner ledger.

The reliability track owns the <=300s fresh-stage budget, generated-stage
provenance, exact plain/no-prelude smokes, and rollback. The architecture track
reuses the bounded selected-definition consumer and develops only the next
required typed resolution/materialization contract. Current observations
separate lost call facts, excessive admission, and the cost of correct repeated
scans; no single cause has been established for all three. A shadow can locate
a mismatch but cannot itself demonstrate reduced production work.

Replacement-path promotion and queue/shim deletion remain blocked until the
same source snapshot passes B4-F and both semantic gates. Local diagnostic
improvements may be reported with their measured scope, but cannot substitute
for that result or a matched performance comparison. Reliability fixes name
an owner boundary; replacement slices retain the legacy rollback path.

### Phase 0b: Architecture transition gate

Purpose: prevent the bootstrap loop from becoming a tail-chase while still
allowing evidence-producing fixes.

Admitted work:

- read-only or docs-only owner ledgers;
- scripts that census semantic decision sites without changing compiler output;
- focused reducers that prove a boundary before a behavior change;
- the bounded typed resolution-to-materialization queue payload/transaction
  guard and legacy shadow at final HIR emission plus `lower_missing` replay,
  with no default-path consumer;
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

### Phase 3a: T1 identity-join guard and first vertical slice

Keep this phase behavior-neutral and follow the canonical five-step slice in
`docs/specs/07-compiler-decomposition-and-semantic-replacement.md` section
13.3. Ownership/`NameId` and the exact r1-r5 local typed decision are complete.
The current consumer inventory refutes an immediate cross-arena handoff: no
semantic `MethodSymbol`, `DefIdentity`, `DefInstanceKey`, or
`LocalCallResolution` reaches per-file HIR. Pause this phase before minting
`ResolutionId`. Resume only when one named compiler consumer exists in the same
coherent slice; then prove its bounded aggregate-to-original callsite mapping
before streaming a producer record. Keep boundedness diagnostic until a guard
hard-caps it and the external join pending until downstream `resolution_id`
enrichment exists. Its first DoD remains identity continuity with zero
HIR/MIR/LLVM delta, not queue reduction or a speed claim.

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
- concrete `main_arenas << map_arena`, explicit `.as(ArenaLike)`, and true
  union flow preserve their lawful selected `Def`/instance, coercion/value
  type, receiver/value arity, matching body/symbol, and no orphan malformed
  stub,
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
- typed union-container insertion target/materialization reducer (T9): join
  selected `Def`/`DefInstanceKey`, coercion/value type, receiver/value arity,
  materialized body, and emitted symbol for lawful concrete, explicit-cast,
  and true-union flows. The
  [reducer](../regression_tests/union_static_generic_materialization_guard.cr)
  and [guard](../regression_tests/union_static_generic_materialization_guard.sh)
  now pass in focused HIR mode for the concrete, explicit-cast, and true-union
  corridors. A source-bound full-compiler HIR gate now also preserves the exact
  concrete `push$AstArena` request through body lowering after preventing
  `exact_lookup` from canonicalizing it to the union symbol. Current MIR/LLVM
  continuity is still open. A historical full-G9 artifact classified an orphan
  zero-argument call/stub as `MEASURED_RED`; that artifact is stale and has not
  been reproduced from current source.
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
- a union-container flow loses selected `Def`/instance, coercion/value type,
  receiver/value arity, body/emitted-symbol continuity, or creates/emits an
  orphan malformed zero-argument call/body/stub;
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

This document carries no dated entries. The division of truth:

- `TODO.md`: active working backlog and per-slice evidence (the work log).
- `LANDMARKS.md`: durable verified anchors and refuted branches.
- git history: everything else, including the retired 2026-06/07 execution
  ledger (`git show 95539f64:docs/compiler_architecture_sdd.md`).
- This file: target architecture, built owner records (section 6.9), the
  authority-edge state table and current frontier (section 0, replaced in
  place).

Sync rule: a slice that builds or extends an owner record updates section 6.9
and the section 0 table in the same commit. A slice that moves the frontier
rewrites section 0.1 in the same commit.

## 11. Migration slice boundaries

The four root migration slices. Each defines a boundary, not a schedule.

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

## 12. Status and admission

Status: ACTIVE. This document admits architecture-shape decisions (ownership
boundaries, record shapes, migration order). It does not admit behavior
changes by itself: behavior changes are admitted by the falsifier matrix
(`docs/specs/05-falsifier-matrix.md`), the regression gates, and the B4/B5
classifiers.

Retired process machinery (do not resurrect): `SliceReceipt`,
`BootstrapPotential`, per-slice admission checkpoints, dated board
refinements. Rationale: `docs/sdd_process_review_2026_07_03.md`.

The fresh lazy certificate regression skips eager module, class and top-level
definition lowering. Against frozen AF it rejects CertificateBase#echo$Int32
during a nested demand from lower_main; the previous eager fixture did not
exercise that seam. Evidence: af_lazy_demand_before_ast_specs.log and its
unchanged source/spec manifests. This is a pre-fix falsifier.

AG records exact-demand inherited-body provenance in a separate sidecar,
including the source Def/Arena, emitted Function identity, concrete self
and full parameter ABI. Source-only adversary review is ROBUST within that
path, but fresh AG tests still reject nested lazy demand: ten of eleven
focused scripts and nine of ten HIR/AST examples pass. Its UInt64/String
and late generic-descendant guards reject as expected. Increasing forced
lowering depth alone does not fix the rejection: AH must recognize the exact
registered direct override and materialize that Def through ordinary lookup.
AH passes the ten-example snapshot, but a fresh lazy unrelated-overload
control rejects the inherited Int32 target beside a child's String-only
overload. The requesting child also loses the supplying base owner's concrete
include bindings. These are distinct origin and overload-precedence seams;
the full virtual capability remains open. Evidence:
source_hashes_s1_ag.json, s1_ag.receipt.json, ag_ast_specs.log,
s1_ag_focused/results.json, concrete_module_rejection_s1_ag/receipt.json,
virtual_late_s1_ag/receipt.json, ah_ast_specs.log,
ah_other_overload_before_ast_specs.log, and s2_ag_any_audit/.

The AH direct type-return fixture is green, but ordinary S2AH still fails at
LLVM emission. The stdlib helper passes a type-valued Reflect(Int32) argument,
assigns reflect.type to a local, then chooses an instance zero method rather
than the Int32 class method. Source inspection finds literal flags on the
argument, module-method parameter and local-copy paths. Lazy return inference
does not merge the specialized owner's generic map, unlike concrete return
type inference. This is the next producer-side hypothesis; the LLVM excerpt
establishes the wrong selected target, not which inference attempt lost the
mark. Exact-selected overload provenance must also prevent a type-valued
sibling method from marking an instance-valued return. Evidence:
s2_ah.receipt.json and s2_ah_audit/receipt.json.

The small owner-generic argument/member/local controls, including a nested
included-module owner, pass both original Crystal and S1AH. They therefore do
not establish the missing-owner-map hypothesis as the selfbuild cause; a
trace-only full AH build uses DEBUG_TYPE_LITERAL_RETURN=Reflect to inspect
that actual context. In contrast, the sibling-definition falsifier is red:
pick(Int32) returns T, pick(String) returns T.new, and the latter is wrongly
followed by a class zero call. Removing only the type-returning sibling
restores the instance call and runtime result. Both combined call orders
fail AH and pass original Crystal. The name-only return cache admits a base
mark written by the sibling without checking the selected Def/Arena. A
provenance cache repair is admitted independently of the unproven owner-map
hypothesis; its DoD includes both call orders and the prior direct controls.

The expanded eleven-control fixture passes original Crystal and returns 1
with S1AH. Its fixture hash is
240dfa48ae211ef682200385dc8a73d853ad3bbe563de75d21512186baef7891;
paired receipts are in type_literal_overload_alias_probe/final_receipts/.
The repair keys each fact by the exact registered symbol, source Def identity
and arena identity. Def plus arena alone is insufficient because one source
body can be registered under different owner/include specializations. All
three eager registration sites and the lazy exact-target path record this
triple; stripped/base aliases cannot supply another overload's mark.
Source adversary review is ROBUST within that provenance boundary; runtime
verification against the combined candidate is pending. Reusing one exact
symbol, Def and arena under divergent maps remains a registry identity
boundary, not a separately verified cache capability.

The logging-only full AH build reports exact Reflect definitions present,
but lazy inference returns nil for both Enumerable::Reflect(Int32).type and
Enumerable(T)::Reflect(Int32).type. It then fails at the same join_strings
LLVM add. Evidence: s2_ah_literal_trace.receipt.json and its build log. This
confirms the loss at the actual selfbuild inference context. A separate
logging-only derivative records active, registered and receiver type maps;
it is diagnostic evidence and cannot substitute for an ordinary final build.

A direct original-valid MacroIf reducer now separates the hypotheses: its
Reflect-like generic type method tests X.union? and otherwise returns X.
Original Crystal builds/runs with 0; AH builds but aborts with 134. The exact
registered and receiver maps already contain X=Int32 or X=Float64, while the
tail is MacroIf and literal inference returns nil. The limited condition
evaluator has no union? arm; ordinary macro lowering already falls back to
the contextual interpreter. Admit the same contextual fallback only for
type-literal return inference, preserving an unevaluable result and inspecting
only the actually selected branch. No global condition semantics, stdlib or
backend coercion is changed. DoD adds the direct and argument/local forms to
the static-receiver regression, an instance-valued opposite branch, and the
ordinary frozen stage chain. Rollback is this inference hunk.
Evidence: reflect_macro_type_literal_original/receipt.json and
reflect_macro_type_literal_ah/receipt.json (fixture
a6afdf8684adf1f4948a99df9274fd65e9518d2f4c3d481d09b864ce3b5e63c0).

The logging-only full AH map probe confirms X=Int32 in both the registered
and receiver maps at the actual Enumerable Reflect call sites. Their tail is
MacroIf and literal inference is nil; the build repeats the same LLVM error.
Thus missing generic receiver bindings are refuted as the cause of those
measured occurrences. Do not widen owner-map propagation on that hypothesis.
Evidence: s2_ah_reflect_map.receipt.json, s2_ah_reflect_map.build.log and
ah_reflect_map.diagnostic_scope.json. The final static-receiver fixture adds
direct and argument/local MacroIf cases plus an instance-valued opposite
branch; all sixteen controls pass original Crystal. Its final fixture hash is
66ea0d34d3cc2ab9a5aa06f69ff950bba9bc732bb254c4f07e7bf6956bedcf3a;
receipt: type_literal_bootstrap_reduce/macro_if_final/receipt.json.

The virtual-origin scratch repair exposes a second counterexample: the HIR
return is correctly Nil | Int32 | String, but union-argument overload dispatch
drops Nil and emits only two arms. The full eight-control fixture then returns
failure bit 32; its Nil-only subfixture passes. Admit a bounded repair that
retains every registered variant, selects an applicable overload for every
arm before emission, evaluates receiver and arguments once, and joins the
actual branch return ABI. Preserve the existing block, splat and named-argument
guards and allocator restrictions. DoD is the original-valid full virtual
fixture plus explicit three-variant order and single-evaluation controls,
followed by the frozen HIR and stage suites. Until those checks pass this is
an observed runtime bug and a proposed repair, not virtual closure. Rollback
is the session-owned helper hunk; no stdlib change is admitted.

The complete virtual fixture now has fifteen controls: inherited and direct
owners, an unrelated child overload, same and differing returns, Nil in a
three-member union, mixed Int32/String/Nil return joins, typed plus untyped
fallback arms, and one evaluation of the source argument. Original Crystal
passes that exact fixture (hash
301e139525c7872f994d80799d551055d826e2624fa0de1e09f681b26e2a1015;
virtual_ai_original_15/receipt.json). The dispatcher preserves each resolver's
exact selected name, preflights every callable target and its actual return
type before CFG emission, then coerces branch values to a compatible complete
join. Named and block call forms remain on the ordinary call path. Source
AI is sealed at HIR hash
b45457fa23f4a90c4baebd0d6881c5f6fbeeb7baad739c6310b028e848abe325;
its ordinary host build passes. Runtime, HIR and same-source stage verification
are pending; no instrumented build or scratch compiler closes this claim.

AI refutes unconditional rejection of incomplete dispatch arms: ordinary
prelude programs reject Int32.from_io, and its S2 attempt rejects Parser.new
before LLVM emission. The full suite was stopped after this repeated
discriminator; it is not a completed suite. AJ instead declines unsupported
fanout before caller CFG creation and leaves ordinary resolution authoritative.
It also applies exact per-arm parameter coercion after unwrapping/packing.
Fifteen of sixteen focused/preflight scripts pass, including the sixteen
static-receiver controls, but the virtual fixture still aborts at the union
tag stub. Its emitted HIR lacks the required concrete Nil tag target, so a
safe decline is not capability closure. The active falsifier is exact selected
target materialization during nested demand, not removal of the preflight.
Evidence: s1_ai_full/cancellation.json, s2_ai.receipt.json,
s1_aj_preflight/results.json and virtual_aj_preflight_hir/receipt.json.

The virtual fixture additionally covers a String | Nil formal parameter whose
body tests nil? and String.size. All eighteen controls pass original Crystal
(fixture ea201030265709be5d2274e7053398cb694079442bb6d2463277f651bbd1d9e4;
virtual_aj_original_union_formal/receipt.json). A pre-CFG check that the current
argument HIR type equals the discriminator's union type is admitted as the
stale-tag guard; ordinary call coercion may have widened the argument after
the earlier arg_types snapshot. AK includes that narrow guard. Source-only
adversary review is ROBUST for the helper's admitted shapes and MacroIf
inference; the eighteen-control runtime capability remains open.

AL closes that host-stage runtime counterexample within the admitted fixture.
The logging-only AK derivative records all arm Defs present but nested lowering
at depth 1 deferring their bodies; preflight then declines at the missing Nil
target. Later queue processing cannot repair the already-emitted union call.
AL uses the existing guarded force-return lowering for only the already-resolved
targets whose bodies remain absent after normal demand. Force recursion,
inline-yield, helper suppression and depth limits remain authoritative; no
pending-queue deletion or caller CFG mutation is introduced before complete
body/return/ABI preflight. Its frozen HIR hash is
b2143931ebd7481688812b496440bb4274a390a83234aad3cbfde750f42c3e73.
The ordinary original-Crystal host build exits 0. All sixteen preflight scripts
pass with 53 supervised calls; the eighteen virtual and sixteen static controls
are included. Eleven HIR/AST examples and both explicit rejection guards pass.
The full S1 suite passes 162/162 with 577 supervised calls, no resource
abnormality and no script drift. Ordinary S2 and S3 build from this same sealed
source; their sampled peak RSS is 5,744,832 and 6,379,008 KiB respectively. S2
passes twelve focused scripts, three exact-output smokes and both explicit
rejection guards. S3 passes three exact-output smokes, four enum/Regex probes,
both rejection guards and the extra native-realloc contract. The completed full
S3 suite passes 161/162; its sole failure is an inherited struct-field call
returning 40 instead of the expected 7. The same script passes S1. This
stage-dependent gap remains open, so the built chain does not establish runtime
closure. Evidence:
virtual_dispatch_preflight_probe/
trace3.log, s1_al.receipt.json, s1_al_preflight/verified_receipt.json,
al_ast_specs.log, concrete_module_rejection_s1_al/receipt.json and
virtual_late_s1_al/receipt.json, s1_al_full/verified_receipt.json,
s2_al.receipt.json, s3_al.receipt.json, s2_al_focused/verified_receipt.json
and s3_al_full/failure_receipt.json.
Any source, target registry or guard change
invalidates this scoped result and requires the affected checks again.

The full AH definition imports plus Array(Int32)#sum and Array(String)#join
pass original Crystal and S1AK after the contextual MacroIf fix. Keeping
Hash#sum in that same fixture instead aborts at Pointer(Void).zero. This
discriminates a separate callback-return/type inference boundary and does not
restore the refuted missing Reflect receiver-map hypothesis. Evidence:
reflect_array_registration_no_hash_sum_original/receipt.json,
reflect_array_registration_no_hash_sum_s1ak/receipt.json and
reflect_full_registration_ak/receipt.json. No Hash or raw-pointer capability
closure is claimed from the array-only control.

The Hash failure does not require the full compiler-definition imports.
Standalone Hash(String, Int32).sum { |_, value| value } compiles and then aborts
at Pointer(Void).zero on S1AL and S2AL (fixture
bdc32a96af90ff66cdfb37c07896b6c6db36f57e16e441b6e73aba6f37441672).
Changing only the block to |entry| entry[1] passes S1AL and original Crystal.
Adding value + 1_i32 inside the destructured block also masks the failure;
keep post-sum arithmetic outside the identity-return regression. This is a
measured binding-shape boundary, not evidence for a broad Reflect or Hash
layout repair. Evidence: hash_sum_min_original/receipt.json,
hash_sum_min_s1al/receipt.json, hash_sum_min_s2al/receipt.json,
hash_sum_single_tuple_s1al/receipt.json and the original-valid paired fixtures
hash_sum_tuple_original_single/receipt.json and
hash_sum_tuple_original_destructured/receipt.json. The initial semantic-engine
binder hypothesis is not adopted: its filtered trace never fires for this pair.
A subsequent scratch trace follows the HIR typeof-yield inference path and
measures positional seeding of one Tuple(String, Int32) hint into multiple
block parameters, retaining a wrong Tuple binding for value. Runtime yield
lowering instead unpacks that tuple and binds value as Int32. A type-only
single-tuple, multiple-plain-parameter expansion is being tested in scratch;
no production correction has yet been admitted.


### 2026-10-13: AM ordinary bootstrap candidate

AL builds the ordinary chain but its S3 runtime suite exposes an inherited
class-method struct-ivar layout failure. The exact renamed PayloadBox fixtures
are original-valid: upstream compiles and returns 7, while S2AL compiles but
returns 40. DEBUG_IVAR_INFER shows the fields inferred as Void; dependent Outer
layout is fixed before later lowering supplies the missing Inner fields.
The early class-method guess had an exact-owner-only prescan fallback and
stopped registered ancestry on a name before checking the call's arity.
AM combines registered and prescanned defs across ordinary class ancestors,
retains each def's source arena, filters block/arity, and requires all annotated
returns to agree in their declaring namespaces. Generic owners remain excluded.
A nearest-applicable-owner stop was rejected: original Crystal's lookup_defs
collects applicable parent annotations too. initialize remains exact-owner;
new stays on the existing constructor path.

The separate Hash identity-return failure comes from HIR typeof-yield inference
binding one Tuple(String, Int32) hint to positional block params, while runtime
yield lowering expands the tuple. AM expands this one hint only for multiple
plain named unannotated required parameters, preserves fallback for other
shapes, and leaves Proc inference unchanged. It uses the mixed-storage TypeRef
array accessors. Their pointer classifier now returns valid zero-extended IDs
before dereferencing aligned values such as UInt16's ID 8, and rejects pointer
addresses below 4096. The block-inference ensure starts before arena switching
and param seeding, so setup and inference both restore context. S1AM passes the
Int32 and UInt16 identity-return/control pair; the new original-valid inherited
layout script and prior struct script also pass. An initial strict end-of-line
EXIT check in the new script was invalid because run_safe appends elapsed time;
the corrected script checks actual child status and the EXIT prefix.

AM HIR SHA:
9356c8debc5ac06277fec25a3e52ad6fe1d22c0cc35d735ed46c18cc8e4cf491.
The host build and eleven HIR/AST examples pass. The ordinary S2 build passes,
but its focused runtime suite is 13/15: both inherited-layout scripts still
return 40, while all four Hash cases and the twelve prior focused controls pass.
DEBUG_CLASS_PARENT_TRACE resolves Derived -> Base, yet DEBUG_IVAR_INFER still
shows Inner's fields as Void. This refutes stage propagation of the source fix.
The S3 build succeeds, but both inherited scripts still fail. The full S1
suite passes 164/164; a separate logging-only self-hosted guess-path probe
narrows the failed gate. Source-only adversary reviews are
ROBUST within these bounded ordinary annotation and plain-param tuple paths;
they do not certify general metaclass/module/generic inference or corrupted
carriers. Evidence: bootstrap_rescue_am_causal_capsule.json,
source_adversary_am.json, am_new_fixture_original_oracles.json,
am_before_inherited_s2al/receipt.json,
am_before_child_different_arity_s2al/receipt.json,
s1_am_struct_script_corrected/verified_receipt.json and am_ast_specs.log.
General block-splat and multiple-yield typeof inference remain separately red
(hash_sum_tuple_destructure_guards/evidence_capsule.json). Raw-pointer struct
storage/value-copy and collector/finalizer capabilities remain outside this
rescue. Any relevant source, registry, representation, arena or fixture change
reopens these scoped claims.

### 2026-10-13: AN recorded-parent lookup correction

AM's ordinary S3 build also succeeds, but both inherited-layout scripts still
return 40. Its S1 selected suite passes 164/164; this does not establish stage
propagation. The logging-only S2 probe reproduces the failure and measures the
actual annotation-guess consumption point: owner Derived, positional count 1,
no exact-owner registered/prescanned candidates, absent ClassInfo lookup, nil
parent and zero collected candidates. Earlier Derived registration messages
therefore did not certify retrievability in this path.

AN uses the existing parent_name_for_hierarchy_lookup(current), which falls
back from ClassInfo to recorded HIR class parents. The cycle guard, exact-owner
initialize rule, full ancestor collection, source arenas and annotation/arity
checks remain intact. The narrow expected signal is the exact original-valid
inherited pair changing from runtime 40 on S2AM to 7 on ordinary S2AN, followed
by the complete declared selected gates on the same immutable source.
The reason ClassInfo is unavailable here remains a separate lifecycle or
representation question; no generic loop, capture or tuple-carrier repair is
inferred. Synthetic controls for those mechanisms pass S1/S2, and the LLVM
parent field read and initializer agree on offset 40.

AN HIR SHA: df501fd7e6cf9ceb697705730eac351ffda60c8fd88413427eaa0290de61ac31.
The ordinary S1 -> S2 -> S3 chain builds from the same 1,919 sealed source
files without IR rewriting or GCX. Both inherited layout scripts pass S2AN;
the exact original-valid inherited pair now returns 7. S1/S3 pass all 164
selected scripts, S2 passes all fifteen focused scripts, and the eleven HIR/AST
examples pass. Both strict rejection guards pass each stage. S2/S3 pass three
exact-output smokes; S3 passes four enum/Regex checks and the extra native-
realloc contract. All binaries run through run_safe.sh. Scoped source review
is ROBUST; it remains correlated same-lineage evidence. This admits only the
declared selected bootstrap/runtime claim, with the exclusions above.
Evidence: .landmark/evidence/2026-10-13-claude-bootstrap-rescue.json,
source_adversary_an.json, bootstrap_rescue_an_causal_capsule.json,
s1_an_full/verified_receipt.json, s2_an_focused/verified_receipt.json,
s3_an_full/verified_receipt.json, s2_an_struct_gate/verified_receipt.json,
am_ivar_guess_trace_s2/receipt.json and build.log,
s2_am_ivar_trace.receipt.json, struct_ivar_am_loop_probe/evidence_capsule.json,
s2_am_focused/failure_receipt.json and s1_am_full/verified_receipt.json.
Rollback is the single parent-lookup replacement against the sealed AM source.
Any relevant hierarchy registry, source, runtime or fixture change reopens this
correction's measured scope.


### 2026-10-13: AN S3/S4 fixed point

The ordinary S3 compiler builds S4 from the unchanged AN source and runtime
seals with LLVM caching disabled, no IR rewriting and no GCX. The build exits
0 in 589.59 s. Complete raw emitted LLVM IR is byte-identical under both cmp
and full diff, without normalization. All 11 Mach-O sections match in layout
and contents; the only 53 differing executable bytes belong to UUID and
ad-hoc signature metadata. This admits the pair-specific raw-IR and code/data
fixed point. Strict whole-file executable identity remains false.

All three S4 exact-output runtime smokes pass. Commit preparation additionally
runs all six changed/new spec files successfully. The source and executable
adversary checks are ROBUST within their bounded scopes and remain correlated
same-lineage evidence. General Crystal compatibility, collector/finalizer
capability and the previously stated raw-pointer/typeof exclusions remain open.
Evidence: bootstrap_an_verification.md and
../.landmark/evidence/2026-10-13-an-s4-fixed-point.json. Relevant source, runtime,
toolchain, environment or fixture changes reopen the affected certificate.

### 2026-10-15: ordered require roots and shard layouts

An unqualified require searches the ordered CRYSTAL_PATH roots, including
Crystal's flat, namespaced and nested shard source layouts. Relative paths
remain relative to the requiring file. Prelude selection uses the same roots.
An existing empty wildcard directory succeeds; recursive wildcard traversal
visits sorted files before sorted subdirectories and follows directory symlinks.
A missing active RequireNode or macro-literal dependency raises a lowering
error rather than leaving an incomplete declaration registry.

Native157 passes sixteen focused CLI examples and the original-first
shard_require_search_path_repro.sh guard: eleven output lines match, including
load order and symlink traversal, and both compilers reject the missing active
require. Native155's unchanged LavinMQ spec build advances from the absent
AMQP client method to unsupported SelectNode. This admits the tested loader
contract only. Parser-recovery source fallback misses and cross-target C-binding
selection remain open. Rollback is the isolated CLI loader delta; changes to
search roots, loader traversal or macro branch admission reopen these checks.


### 2026-10-15: Tuple hash intrinsic allocator materialization

The tuple hash result intrinsic creates `Crystal::Hasher` with both `UInt64`
seed arguments. A direct mangled call did not ensure that exact full-arity
allocator body existed beside the default-filled initializer wrappers. The
intrinsic now requests the exact allocator through the shared generator and
selected-overload naming path. Its dedicated HIR regression verifies the body
and one emitted two-argument call; the sealed171 spec overlay passes. Both
tuple-hash entry paths use this helper, while the existing-hasher intrinsic
does not allocate. This remains scoped to tuple hash. Other synthesized
constructor calls need their own exact-signature evidence. The subsequent MT
startup probe reaches a separate bodyless `Scheduler#spawn` target, so the HIR
result does not certify full-prelude startup. Changes to tuple hashing,
allocator selection, or the intrinsic's call shape reopen this check.

### 2026-10-15: authenticated raw Proc pair construction

The selected stdlib `Proc.new(Void*, Void*) : self` overload must preserve both
the callback pointer and its closure-context pointer when the resulting Proc
escapes the constructor call. HIR lowers only that exact, source-authenticated
stdlib definition to `MakeProc`; same-shaped user overloads and definitions
with different parameter, return, or block shape stay on ordinary call
lowering.

The focused HIR guard passes five cases, including the authenticated stdlib
shape and four negative shape/ownership controls. The original Crystal and the
matching no-prelude compiler both pass the runtime guard for null context with
`void(void)` and non-null context with `void(void*)`; both report two calls,
one null-context call, one expected non-null context call, and no unexpected
context. This does not certify captured-context lifetime/GC retention,
repeated calls after owner collection, or other raw Proc constructor
signatures. Changes to selected-Def provenance, Proc carrier layout, or
callback ABI reopen this bounded contract.

### Cached generic descriptor materialization (2026-10-15)

When concrete declaration registration reuses a Generic placeholder, it must
publish the declaration's Class or Struct kind through stable-ID type
interning. The same TypeRef and type parameters must remain visible to cached
annotations and union arms. This promotion is admitted only after a concrete
ClassNode has been selected; it must not turn unknown generic owners into
classes or change Array/Hash descriptors. The three-case regression is
`regression_tests/concrete_generic_placeholder_kind_repro.sh`. A manually
interned placeholder without an annotation cache entry has a separate lookup
obligation; this rule does not certify that producer.


### Shared module yield bodies on union receivers (2026-10-15)

For a zero-argument block call selected from a module, HIR may branch over a
union receiver only after all arms resolve to concrete class/struct descriptors
and the exact selected included-module Def. Direct overrides and distinct source
Defs reject this transformation before any dispatch instruction. Nested generic
owners retain every namespace component. Each admitted branch unwraps self,
registers the source-backed target for that concrete includer, and recomputes
block parameter types before inlining. The shared tuple-union merger preserves
caller locals, inline caller locals, result phis, and nonlocal exits.

DoD: shared_module_union_yield_spec.cr (3 passing examples) and
regression_tests/shared_module_union_yield_repro.sh with the atomic258 compiler
(original and candidate exit 0). Nonzero/named/splat calls and unresolved arms
need separate admission proofs. Full LavinMQ compilation and runtime parity are
not established by this local contract. Refresh the guards after namespace,
module-origin, union-layout, or yield-inlining changes.


### Block forall precedence and numeric generic macro kinds (2026-10-15)

The selected block's inferred result has priority over synthetic receiver
aliases and a same-named generic owner parameter only when the selected Def
declares that result as a method forall. Apply this priority both when recording
the call and after owner registration during materialization. Concrete block
annotations do not introduce method forall bindings.

Numeric generic arguments entering macro context are NumberLiteral values,
preserving their source integer kind. They support numeric equality and
arithmetic rather than TypeNode comparison. The sort279 contract covers decimal,
hexadecimal, and explicit Int64 literals plus a wrong-value rejection. Bare
boolean generic literals are not admitted by this change.

DoD: block_forall_receiver_binding_spec.cr plus the existing concrete-kind and
shared-union contracts (13 passing examples), and the original-first
block_forall_receiver_binding_repro.sh (both runtimes exit 0, six calls).
Refresh after call-map ordering, selected block signature, owner registration,
or macro numeric parsing changes. Full LavinMQ compilation/parity and multiple
block-result specialization identity remain open.


### NamedTuple union indexing and structural arguments (2026-10-15)

Admitted: preserve each key/value boundary through complete union-owner
normalization; literal Symbol/String `[]` and `[]?` over concrete NamedTuple
unions; target-order reconstruction with compatible field coercion; exact
union member priority followed by first-compatible selection; final direct-call
argument repair when deferred HIR publication changes the required layout.
Rejected: a required key absent from any arm, or an incompatible structural
NamedTuple conversion. A mixed NamedTuple/non-NamedTuple receiver remains on
the existing general call path rather than a partially emitted intrinsic path.

DoD: named_tuple_union_field_owner_spec.cr,
named_tuple_union_literal_index_spec.cr, and
named_tuple_structural_coercion_spec.cr plus block-forall, concrete-kind, and
shared-union neighbors (31 passing examples); original-first
named_tuple_union_literal_index_repro.sh (22 value checks and missing-key
rejection). The deferred repair is idempotent and inserts reconstruction before
the call. Virtual calls, union-to-union fields, returns/casts, rooted field
names, and full LavinMQ parity require separate evidence.


### NamedTuple field context resolution (2026-10-15)

Admitted: resolve each field value through body/signature lexical lookup, keeping
keys intact, including nested generic containers, self/type-parameter keys, and
qualified alias identities. Top-level union members resolve before root-prefix
stripping. Alias qualification likewise treats NamedTuple keys as syntax.
DoD: named_tuple_type_context_spec.cr and seven neighboring suites (47 examples),
plus named_tuple_type_context_repro.sh (three original/candidate native checks).
This closes the rooted-field and generic-owner alias obligations recorded above;
virtual structural transport and complete LavinMQ outcome parity remain open.


#### Recursive macro receiver graph validation (2026-10-15)

- Admitted: registered recursive aliases through unions and Array/Hash/ordinary
  generics, including NamedTuple field values, terminate receiver validation.
- Rejected: unknown generic bases, unbound generic arguments, and unknown union
  or field values remain invalid even after an accepted recursive back-edge.
- Guard: the active set is scoped to the current validation path and is removed
  on return; a cycle does not publish a global known-type cache entry.
- Falsifiers: macro_recursive_type_receiver_spec.cr (eight cases) plus the
  original-first macro_recursive_type_receiver_repro.sh. Isolated macro315 has
  55/55 HIR examples and three native macro observations passing.
- Open: the separate generic-module WIP may reset validation context. No global
  recursive-type or full LavinMQ parity claim follows from this boundary.


#### Terminal block-argument call boundary (2026-10-15)

- Admitted: a shorthand/captured block finishes a no-parentheses call; commas
  remain available to its enclosing collection or call, including trailing
  commas in multiline NamedTuples.
- Guard: binary `&` expressions still allow later positional arguments;
  parenthesized argument parsing retains its own boundary.
- Falsifiers: parser_multiline_named_tuple_body_spec.cr (16 cases) and
  block_argument_collection_boundary_repro.sh (three original-first native
  checks). Isolated parser325 has 90 parser examples passing.
- Open: parenthesized extra-block diagnostics, shorthand newline handling, and
  the separate nested do-block WIP are not widened by this change.


#### Per-arm instance-body selection for union block calls (2026-10-15)

- Admitted: zero-positional-argument instance block calls whose concrete class,
  struct, collection, tuple, or NamedTuple arms each supply a callable source
  Def/arena. Select all arms before emitting CFG; each receives narrowed self.
- Guards: missing methods, unresolved receivers, missing source arenas, and
  unsatisfied required named arguments do not authorize partial dispatch.
  Existing tuple and shared included-module routes remain first.
- Evidence: distinct_owner_union_yield_spec.cr plus 55 neighboring HIR cases
  (59 total) and distinct_owner_union_yield_repro.sh (four original-first
  native value/non-local-return checks) pass on isolated union335.
- Open: positional block arguments, distinct included-module bodies, and
  impossible case branches are separate obligations. Generic-union virtual
  return guards remain unchanged; LavinMQ runtime parity is not established.


#### Case body instantiation after comparison admission (2026-10-15)

- Admitted: a body is skipped when all emitted comparisons are constant false
  or every known union member is provably disjoint from its IsA target.
- Guards: unknown descendants, matching generic bases, predefined builtin
  ancestors and effectful value comparisons keep their existing lowering.
  Builtin TypeRefs need nominal reasoning because they lack descriptors.
- DoD: case_unreachable_body_spec.cr and ten committed neighboring suites
  (65 examples), plus case_unreachable_body_repro.sh's original-first runtime
  comparison and explicit dead-HIR rejection, pass on isolated case341.
- Open: builtin ancestor proof completeness, unrelated fallback method lookup,
  recursive macro value projection and full LavinMQ runtime/test parity.


### Finite recursive macro TypeNode projection (2026-10-15)
Admitted: concrete generic reflection retains recursive AliasType identity at
the declaration-order graph back-edge, resolves ordinary aliases in their
declaration namespace, and projects canonical union members and Nil acceptance.
Union display names are distinct from HIR specialization identity. Generic
formal names remain MacroIds; concrete type arguments become reflected values.
Receiver validation consumes the same finite projection and an active graph
guard. Alias cache invalidation is required for every changed registration.

Rejected: treating nominal `Name -> Name` entries as alias recursion, eagerly
hydrating recursive generic arguments, or restarting eager expansion during
receiver validation. Unknown nested types still fail validation. Guard-only:
these checks do not establish arbitrary recursive Proc/pointer projection or
LavinMQ execution. Rollback is this atomic commit; source358's 27 focused cases
and the original-first native projection regression are the DoD. The strongest
observed falsifiers are the old hydration stack overflow and a namespaced alias
resolving through a global same-name alias. Both have dedicated regression
coverage. Refresh when alias resolution or macro value construction changes.


### Generic receiver fallback signature preservation (2026-10-15)
Admitted: once the existing owner-definition check authenticates a receiver
repair fallback, specialize the exact target's bare generic owner and retain
its concrete argument suffix. Rejected: applying a foreign receiver owner to
an unrelated ancestor fallback. Existing concrete-target fallback behavior is
unchanged. DoD: source360's 29 focused examples and original-first native
Pointer::Appender outputs pass. The prior HIR fallback-selection assertion
fails without the one-hunk change. Native agreement alone does not prove that
the fallback seam ran. Rollback is this atomic commit; refresh on owner lookup
or mangling changes. Full-prelude/LavinMQ runtime remains outside this slice.


### Semantic typeof over already-lowered locals (2026-10-15)
Admitted: nested receiver inference uses current lexical HIR binding types,
including the payload of an owner-matched capture. Rejected: evaluating typeof
arguments, borrowing a shadowed binding's box, or reusing cached inference
across temporary local-type contexts. Existing direct-identifier fallback and
runtime type-identity handling remain in place. DoD: atomic source368 passes
16 focused cases and the original-first native typeof_bound_locals script;
prior full359 fails four of five new context cases. Rollback is this atomic
commit; refresh on local binding/boxing or inference epoch changes. Type-valued
local provenance and flow-widened closure-cell unions remain untested here.
LavinMQ compilation and runtime equivalence remain separate open obligations.


### Generated getter identity beside source overloads (2026-10-15)
Admitted: a declared getter retains its visibility and FieldGet body beside a
same-named source overload that requires arguments. A source definition that
admits the actual call arity retains its visibility. Rejected: borrowing a
positive-arity family alias's private visibility or lowering its body under a
zero-argument getter symbol. Ordinary private/protected access rules remain.
DoD: atomic source378 passes 13 focused HIR cases and the original-first native
accessor_overload_identity regression. Visibility-only source375 fails the
lazy-body falsifier and exits 81 on the native getter control. Rollback is the
atomic commit; refresh after registration or call/body resolution changes.
Setter collisions, lazy defaults, and inherited/class accessor combinations
remain separate untested surfaces; this does not close LavinMQ runtime parity.


### Attached Enum self return contract (2026-10-15)
Admitted: an exact source Enum instance or class method annotated `: self`
projects to the concrete receiving enum's declared physical carrier before its
body is lowered. The existing semantic enum ledger retains nominal identity
for overload selection. Both immediate and batch attachment apply the same
projection and refresh the bare base return cache. Rejected: copying the root
Enum physical return into a concrete enum demand. Explicit Enum and numeric
return annotations, unrelated owners, and user overrides retain their source
contracts. No generic rule for nullable or composite self returns is admitted.
DoD: atomic source389 passes eight HIR cases and the original-first native
inherited-enum regression; the baseline fails the latter. Rollback is the
atomic commit. Refresh after attachment, lazy return-cache, or enum ABI changes.


### Selected super default source ownership (2026-10-15)
Admitted: omitted arguments of a selected super definition are lowered under
that exact definition's resolved AST arena. Explicit argument expressions stay
in the caller arena. Previous, direct included-module, module-super, and
ancestor lookup paths carry their selected source arena to the shared helper;
ancestor module discovery must retain its returned arena. No inference from
numeric ExprId equality is allowed across files. Required-argument and source
visibility behavior are unchanged. DoD: source399 passes the two-arena HIR
falsifier, existing ancestor-loop guard, and original-first native class/module/
ancestor-module checks. Rollback is the atomic commit. Refresh on arena or
super target registration changes. This contract covers source ownership,
not additional lexical/default-parameter binding rules.


### Literal Tuple range indexing contract (2026-10-15)
Admitted: concrete Tuple instance IndexNode ranges with literal Int32 or omitted
endpoints preserve element types/order and evaluate the receiver once. Negative
bounds normalize to the Tuple size, the end clamps, empty results retain Tuple(),
and an invalid start raises the original category of diagnostic. Runtime and
non-Int32 ranges retain ordinary source dispatch. Both scalar Tuple IndexGet and
Range-to-Int32 overload repair must honor the index's semantic Range type.
DoD: source432 passes 16 HIR examples and original-first native values/rejection
checks; full source433 passes the native checks with full prelude. Baseline
source399 fails literal HIR cases; source422 independently fails the typed-Range
guard. Full sources407/416/423 pass humanize.cr's authenticated yield_result[0..1]
and reach the separate pointer-union blocker. Rollback is the atomic commit;
refresh on AST, Tuple layout/descriptors, or index dispatch changes. Tuple
metaclass indexing, []?, constant-held ranges, union receivers, and broker parity
remain separate obligations.


### Concrete signature on authenticated raw Proc construction (2026-10-15)
The authenticated Proc.new(Void*, Void*) : self lowering retains the concrete
Proc type named on the call's type-literal receiver. A generic selected Def's
bare Struct Proc return metadata must not erase explicit argument/result types.
The existing source authentication and exact parameter/return/block guards
remain prerequisites. No ordinary user constructor or instance receiver gains
intrinsic treatment. DoD: source432 fails both new descriptor checks; atomic
source440 passes seven HIR checks and original-first native null/non-null
callback-context checks. Rollback is the atomic commit. Refresh after receiver
AST or selected-Def/type registration changes. Consumer-side raw callback ABI,
lifetime, MT startup, and whole-broker parity require their own evidence.


### Direct null-environment Proc at a selected raw-yield formal (2026-10-15)
The non-heap Yield block ABI receives a raw callback address. Normalize that
formal in its MIR stub, then adapt a direct typed MakeProc only after proving
null environment, exact selected formal/Yield use, and callback signature.
Opaque Proc/Pointer formals must agree with every targeted Yield; a direct
FuncPointer must also agree with its function definition. Accept only the
pointer sentinel or Pointer(Void) as transparent raw pointer carriers.
Heap, captured, non-null, copied-object, unknown, and mismatched cases are
excluded from adaptation. This guard does not implement captured raw-yield
transport or lifetime management. Rollback is this atomic MIR change.
DoD observed: source440 has six failures in 18 MIR cases; source450 has zero,
with original-first native null/non-null context compatibility controls.
Full-prelude checkpoints pass only in composed source457; atomic source450
has a separately traced PCG32/Secure.rand overload-identity startup defect.
LavinMQ startup and upstream parity remain open. Refresh on block ABI,
MakeProc/Yield, pointer provenance, or selected-callee representation changes.


### Lexical alias expansion at block-signature consumers (2026-10-15)
Admitted: normalize a non-literal block annotation in the selected declaration's
lexical namespace before reading its Proc input list or Nil-result contract.
Included-module source namespace overrides outrank the receiving class namespace.
Restore both current class and namespace override after expansion. Use that same
declaration owner when resolving the resulting input names. Literal Proc/arrow
signatures keep their existing path; retain the Nil ABI reader's yield exclusion.
DoD: source492 passes 16 HIR cases and original-first native indexed dispatch;
source450 aborts at Pointer#[]?. Source488 passes the same HIR suite plus the
full-prelude stored-router callback. Strong guards cover conflicting receiver
aliases, alias chains, empty and omitted inputs, and concrete annotations.
General generic/union alias semantics, raw-yield lifetimes, and whole LavinMQ
parity remain separate obligations. Rollback is the atomic HIR change; refresh
after selected declaration context, alias/signature parsing, or block ABI changes.


### Proc syntax and call-key boundaries (2026-10-15)
Admitted: parse a concrete Proc type only when the balanced full expression has
base Proc. Outer unions belong to union parsing even if their text starts with
`Proc(` and ends in `)`. Retain inputs/results when a typed Proc descriptor crosses
into a specialization suffix; the display/owner name `Proc` is insufficient to
recover its call representation. Unknown/bare Proc descriptors retain their path.
DoD: atomic source510 passes 21 HIR examples and original-first native direct and
aliased dispatch with true/false/true/false. The parser-only source496 fails the
Proc-positive native cases, demonstrating why the call-key companion is required.
Signature scans, alias chains, reversed arms, nested containers, and genuine
inner Proc unions are structural guards. Proc literal result inference and its
demand materialization require separate runtime evidence. Refresh after Proc parsing,
specialization, or union ABI changes; rollback is the bounded atomic HIR change.


### Proc result inference precedes branch pruning (2026-10-15)
Admitted: retain a source-inferred union result for an unannotated Proc literal
when every emitted return and the actual last value are members of that union.
Normalize the emitted returns to that result ABI. Unknown or incompatible
inference retains the previous lowering path; concrete and explicit signatures
are not widened. Branch pruning remains enabled and creates no dead-code demand.
DoD: atomic source533 passes 28 HIR examples and seven native outputs equal to
Crystal, including Nil/Int32 and Int32/String payloads through typed formals.
This preserves the literal's inferred signature; it does not admit covariance
between distinct Proc instances. Signature predicates, explicit-return joins,
and ordinary local typing remain separate obligations. Refresh on inference,
pruning, or return-ABI changes; rollback is the bounded HIR change.


### Proc predicates and union branch intersections (2026-10-15)
Admitted: identical concrete Proc input/result TypeRefs satisfy is_a?; different
signatures do not. Bare Proc accepts every Proc signature. For a union subject,
resolve all statically decidable matching arms using the descriptor sidecar,
combine their tags, and retain their full intersection during branch narrowing.
A missing concrete Proc does not fall back to the erased Proc generic name.
Guard-only: undecidable class pairs retain existing runtime checks. Multiple
matching arms use the existing reference-copy/tag-remap path; one arm unwraps.
DoD: sealed source554 passes 69 HIR examples and a 23-output original-first native
regression, including calls after narrowing. Source533 fails that same regression.
This scope excludes explicit-return inference, arbitrary Proc covariance, numeric
export identity, and LavinMQ parity. Refresh on type/union/narrowing changes;
rollback is the bounded HIR change.


### NamedTuple IndexNode inference boundary (2026-10-15)
Admitted: a single literal key on a NamedTuple receiver contributes that exact
field TypeRef while inferring its enclosing expression, including a mapped
NamedTuple block result. Use the same key/element helpers as ordinary lowering.
Rejected: inventing a field type for a missing key. Guard-only: ordinary Array
and Hash index inference remain on their existing paths; unresolved fields and
nonliteral keys retain existing fallback.
DoD: nt576 passes 14 focused HIR cases; source554 fails four field/result cases.
The minimal native generic-block guard matches Crystal; it also passes on the
parent. Whole Hash-map/full-prelude and LavinMQ result transport remain open.
Refresh on expression, alias, or generic-block inference changes; rollback the
bounded IndexNode hunk.


### Char#ord through a union receiver (2026-10-15)
Admitted: the Char arm of a tagged union uses the ordinary primitive Int32 cast
for zero-argument, block-free ord calls in either CFG position. Calls with
arguments or blocks retain ordinary dispatch. The custom receiver arm remains
an ordinary method call. DoD: 33 HIR cases pass on atomic char590; both primitive
cases fail on the parent. Dynamic ASCII/Unicode/custom-arm results match Crystal
while the parent aborts in a bodyless Char#ord stub. Other primitive methods and
heterogeneous return unions are outside this certificate. Refresh on dispatch,
conversion, or ABI changes; rollback the bounded two-arm hunk.


### Ordinary root ownership (2026-10-15)
A parser-owned ordinary main root remains a root independent of indentation.
The collector must not reinterpret whitespace as syntactic nesting. Admitted:
constants, assignments, definitions and calls with spaces/tabs, while class
members retain their parser-assigned owner. Sealed root605 passes root608 HIR
and root611 Crystal/native comparison; parent root607 silently loses all output.
Generated/recovered macro roots and their arena transport remain separate
obligations. Refresh on parser/collector changes; rollback the bounded CLI hunk.


### Generated main arena transport (2026-10-16)
A valid expansion's generated main ExprId must carry the index of its actual
parser arena. Collector recursion preserves runtime versus declaration mode,
registers generated arenas by identity, and rebinds HIR after collection extends
the arena list. Only error-free parsed roots may enter main; incomplete recovery
fragments remain declaration-only. Malformed complete expansions are rejected.
Sealed root614 passes root625's eight HIR guards (including generated class
ownership and malformed output) and root624/root617's native ABCDE comparison.
Parent root629 prints only E. Refresh after parser/collector/main binding changes;
rollback the bounded CLI transport. Absolute module-macro ownership, arbitrary
array loops, shared begin bindings and full-prelude startup remain unclosed.


### Macro require scanner consumption invariant (2026-10-16)
Every scanner iteration must consume its current piece or complete raw tag
before any branch-stack continuation. Unmatched else/elsif fragments do not
revisit input or re-emit consumed control tags. This recovery behavior only
supports dependency discovery and does not admit malformed programs. Sealed
root626 passes seven scanner guards plus the bounded portable regression;
active conditional imports preserve Crystal/native output A. Parent root631
hangs and root632 duplicates raw input. Refresh on cursor/stack changes;
rollback the bounded CLI hunk. Unknown branches and skip_file remain separate.


### Compile-time flag ownership boundary (2026-10-16)
For a CLI invocation, the admitted flag set is copied host target flags plus
explicit -D/--define values and release when requested. Declaration collectors,
semantic contexts and all HIR macro expanders receive this set. HIR stores its
own copy. Shared Runtime.target_flags must remain unchanged across compilations.
Hardcoded HIR release/optional defaults are rejected. flags640 executes 30
combined guards; flags639 compares five native modes against pinned Crystal
1.21, while flags638 rejects the define on the parent. Refresh on option parsing,
context construction or expansion changes; rollback CLI/HIR together. LSP flag
configuration, cross-target semantics and runtime capabilities need their own
evidence. This boundary alone does not certify LavinMQ compilation or parity.


### Numeric restriction to carrier body boundary (2026-10-16)
An abstract numeric source restriction within a generic must not overwrite the
concrete call-site carrier used by the specialized body. For matching generic
constructors/arity, exactness analysis recurses through arguments. Before
refining the whole carrier, a recursive guard requires every sibling to match
its source numeric restriction, including signedness. This guard uses primitive
membership, exact leaves, aliases, unions and nested matching generic shapes.
It does not replace overload admission: same-base and arity-only fallbacks need
separate rejection evidence. range659 checks 26 HIR cases; range660/662 compare
native range behavior with Crystal 1.21; startup661 establishes ordinary prelude
startup. Parent startup642 raises in a wrong-width Random::Secure range body.
Refresh on restriction normalization, overload or carrier layout changes;
rollback HIR and its regression as one unit. Nested forall/module covariance,
multithreaded startup and whole-application parity remain outside this evidence.


### Enum identity to module dispatch boundary (2026-10-16)
An exact registered enum identity outranks unrelated modules sharing its final
namespace component. Known enum receivers bypass recovery intended for missing
class metadata and module-typed dispatch. Genuine module values retain those
paths; an explicit Enum#value conversion retains integer semantics. enum674
checks this boundary with 23 HIR examples; enum678/680 establish native AABIC
against Crystal 1.21, while the parent emits IAIIC. Missing/stale enum provenance
still requires its existing compatibility checks; these guards do not invent it.
Refresh on enum, namespace or dispatch changes. Full-prelude hashing currently
has a separate uninitialized seed failure, outside this certificate.


### Uninitialized values at the classvar storage boundary (2026-10-16)
Crystal can reserve inline global aggregate storage without running a value
initializer. HIR uses pointers for these aggregates, so deferred uninitialized
expressions must still lower through the ordinary allocation path and store
the pointer. Lazy guard handling remains unchanged; eager initialization uses
the same value lowering. uninit689/690 and uninit692 exercise wide elements,
local/inferred/declared storage, repeat writes and both modes; uninit691 covers
Hasher.new and enum hashing with the unchanged stdlib. Contents before a write
remain outside this contract. Refresh after representation or init changes.
Executable class-body statements and random seed entropy need separate evidence.


### Source macro projection versus canonical runtime union arms (2026-10-16)
Runtime descriptors and macro TypeNodes have different representation duties.
Canonical union arms remain authoritative for flattening, deduplication and
abstract-value expansion. For macro reflection, recover a source arm spelling
only when its resolved TypeRef equals the canonical member TypeRef. This keeps
recursive Array(AliasType) and Hash(String, AliasType) projections finite without
replacing runtime type identity with textual equality. The original compiler's
AliasType#remove_alias_if_simple retains recursive aliases at this boundary.
macro714 tests five materialization orders, canonical duplicate arms and an
explicit expanded-union generic argument (17 examples with existing controls).
macro712 and portable macro716 exercise generated native output against Crystal.
Scoped adversary verdict: ROBUST for these concrete recursive projections.
Eight broader failures are unchanged in the macro713 paired baseline. Nullable
source forms, unresolved-type identity and top-level macro-for omission remain
separate obligations. Refresh on alias registration or representation changes.


### Block lexical namespace is owner metadata (2026-10-16)
A block lowered inside a yielding callee retains its caller's lexical access
scope. BlockOwner carries namespace_override alongside class, method and class
method status. Registration captures it; inline block entry and standalone Proc
lowering restore it and then restore their enclosing namespace. A nil caller
override clears a callee override rather than inheriting it. Visibility checking
continues to prefer the lexical namespace for included-module access; no access
check is bypassed or reordered.
Full-prelude native checks protected726/727 match Crystal for class and included
module owners. protected729 rejects a foreign owner on both compilers. Portable
protected732 checks combined AB output and that negative guard. Scoped adversary
verdict: ROBUST for these nested collection/method-reference boundaries.
The paired protected734 HIR controls retain one existing Proc-forwarding failure;
this does not certify all callback lowering. Refresh on owner/context changes.


### Module receiver category survives resolution and fallback (2026-10-16)
A module-typed runtime value resolves instance methods on its includers and
extend-self implementations. A type-literal receiver resolves module class
methods, including methods exported by extend. The value resolver must not
prefer a same-named module class method; the late qualified fallback is admitted
only for a type literal. Explicit receiver context remains authoritative over
the shared method-name spelling. Selected Def/arena identity checks remain.
module758/759 and portable module764 provide native Crystal parity across
nullable module values, concrete overrides, generic class methods, extend,
extend self and reversed call order; module761 passes eight HIR controls.
Scoped adversary: ROBUST for those boundaries. Random.thread_default still
returns null without a store (module757/760); no RNG or application parity claim
is admitted. Refresh this certificate when receiver classification or dispatch
fallbacks change.


### Named hash construction and operand timing (2026-10-16)
Non-empty named hash literals admit a concrete receiver, an explicit generic
receiver, or a bare two-parameter generic with separately inferred key/value
sets. Lowering captures complex keys then values in source entry order before
T.new; simple locals, instance/class variables and simple literals remain at
setter time. Every entry invokes ordinary []= even when keys repeat; the final
value is the constructed container. This matches the original compiler's
literal_expander.cr complex_elem_temp_vars contract without bypassing normal
constructor/setter dispatch. Malformed arena references reject before expansion.
Evidence named772/774 covers native HTTP::Headers, order, duplicate keys,
constructor mutation, container result and generic inference; named773 has four
passing HIR controls. Scoped adversary ROBUST; full application parity, empty
concrete receivers and early constant inference are outside this certificate.
Refresh when operand classification, generic inference or ordinary call lowering
changes.


### Module macro classvar registration boundary (2026-10-16)
Module output registration admits ClassVarDeclNode and adjacent ClassVarNode /
type-expression pairs in BeginNode or BlockNode bodies. Use the same annotation,
literal initialization and deferred initializer registrar as class macro output;
consume a split pair once, and retain the existing extend-self prepass. Method
lowering must observe the registered nullable type rather than Void. Evidence:
random792 is RED (missing module declarations), random794 passes three HIR
examples; native random793 AA versus Crystal NAA becomes matched NAA in
random795. Scoped adversary ROBUST; absolute emitted classes, owner reflection,
thread-local execution and general Proc alias normalization remain outside this
certificate. Refresh when AST declaration shapes, arenas, registration or nil?
lowering changes.


### Absolute class names in module macro output (2026-10-16)
For a generated ClassNode the module-output registrar must pass ::Name when its
absolute flag is set, otherwise ModuleOwner::Name. The existing class-definition
resolver consumes that root marker. The output arena remains unchanged. Admit
root reopenings and actual relative nested classes at this boundary; do not infer
closure for other declaration forms or class-body macro registration.
random805/806 are RED before this line change; random807 and native original-first
random808 are GREEN, including root method registration, relative shadowing,
stdlib thread_local construction and Array#sample. Scoped adversary ROBUST.
Owner reflection and class macro root routing remain open. Refresh on AST name
flags, macro registration routing, definition naming or constant lookup changes.
