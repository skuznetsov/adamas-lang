# LANDMARKS

Updated: 2026-07-13
Context: compiler/bootstrap/stage2-stability

This file is the active working set only. Historical landmarks before this
checkpoint remain recoverable from git history, especially:

- `15e448b9:LANDMARKS.md`
- archived full-file SHA256:
  `d43826fdcc2277b6075026244764a84d0069d1a30b675642b603f3511b14a1e5`

## Active Bootstrap Gate

[LM-S2-CONSTRUCTOR-NAMED-CALL-IDENTITY|root-cause CLOSED, successor OPEN 2026-07-13 {F:0.94 G:0.70 R:0.91}]:
Allocator materialization previously received only `has_named_args`, not the
actual names. Same-typed constructor overloads therefore collapsed to one call
shape, and source order could make a protected `using_hash : Int32` initializer
replace the public `initial_capacity : Int32` initializer for `Set(T).new`.
The accepted boundary carries exact named-argument names through direct,
pending, and lazy allocator generation and checks them during `.new` overload
compatibility. The adversarial host spec intentionally declares the protected
overload first; the named public call still selects its distinct body. Host HIR
passes 235 examples, 0 failures/errors, 2 existing pending. A fresh s1-produced
s2 builds successfully; static generated LLVM routes String and UInt32 Set
constructors through their public Int32 initializers and contains zero exact
bare `$ExprId` type occurrences. Scope: constructor call identity is closed,
not s2b. The minimal produced consumer now reaches a distinct fail-loud
`AstArena | PageArena | VirtualArena` optional-index operation. Decay trigger:
the order-adversarial spec fails, a generated Set constructor selects
`using_hash`, an exact bare `$ExprId` returns, or a source-fingerprint-matched
s2 rebuild changes the routing.

[LM-S2-YIELD-TARGET-AUTHORITY-TRANSPORT|root-cause CLOSED, successor OPEN 2026-07-12 {F:0.90 G:0.62 R:0.86}]:
The produced-stage `br i1 null` in `Hash(Void, Void)#any?$block` and
`Range(Int32, Int32)#bsearch$block` was not an LLVM Bool bug and not an
`Array#find` helper-result bug. Untraced HIR contained a valid Yield/Branch, but
`lower_method` copied parameter names/types while dropping `Parameter#is_block`;
`lower_yield` consequently left `Yield#target` nil. MIR late inference depended
on metadata and String operations that the generated compiler could not
reliably use, returned nil, and lowered the Yield to `const_nil`. The accepted
ownership change preserves the block bit while constructing HIR parameters and
stores the marked parameter id directly on HIR Yield. Fresh generated HIR now
shows `%1 [block]` and `yield via %1` in both independent target families; fresh
s1 and s2 compiler builds are green. Host HIR: 194 examples, 0 failures,
2 pending. Scope: the old null-branch floor is closed, not s2b. Both target
families now reach a shared exit-133 Trace/BPT successor before LLVM; HIR-only
and MIR stops are green. Fresh stop gates prove `lower_main` returns to its
caller and cover HIR flush, refresh, RTA, final HIR, MIR registration, prepare,
body lowering, and final MIR with exit 0. The uninterrupted default-worker and
workers=1 paths still trap before the first observable LLVM-entry marker. Since
each stop flag changes control flow and can perturb self-hosted inference, the
current successor is only the post-MIR-to-LLVM-entry corridor; a specific
statement/root still needs a non-perturbing owner-edge falsifier. Disabling
synthesized exit flush does not move it. LLDB is blocked by missing `debugserver`. Decay
trigger: a fresh produced HIR loses `[block]`/`yield via`, the old `br i1 null`
returns, or the focused authority-transport spec fails.

[LM-BOOTSTRAP-COMPARATOR-IDENTITY-GATE|test hardening 2026-07-12 {F:0.94 G:0.78 R:0.92}]:
The old normalizer erased every SSA id, generated callback/cell id, typed id,
and hexadecimal constant to one placeholder. It could therefore report
semantic equality for different producers or callbacks. Bootstrap comparison
now normalizes path noise only and preserves identity/def-use structure; focused
specs prove `%1` versus `%2`, distinct block procs, and numeric constants remain
different. Early two-stage comparison is supported through
`BOOTSTRAP_COMPARE_STAGE_COUNT=2`. Exact equality may expose harmless ordering
noise; if that happens, use a bijective alpha-renamer that preserves equality
partitions, never a many-to-one token replacement.

[LM-RUN-SAFE-NESTED-DESCENDANT-LEAK|test infrastructure OPEN 2026-07-12 {F:0.92 G:0.45 R:0.90}]:
The captured-pipe/watchdog false-green is fixed, but nested supervisor cleanup
is not. A five-run heartbeat falsifier remained active after outer `run_safe`
return in every run, refuting the zombie-only explanation. Group-first TERM,
longer grace, a `set +m` wrapper, and PID-preserving Perl `setsid` were falsified
and reverted; the latter cannot call `setsid` because the background launcher is
already a process-group leader. Full-suite claims remain blocked until a real
session supervisor or equivalent descendant authority is verified.

[LM-B5-ENSURE-SKIPPED-ON-EARLY-RETURN|root-cause FIXED `76f3f279` 2026-07-04 {F:0.92 G:0.85 R:0.90}]:
B5 root cause: HIR lowering emitted `ensure` bodies only on the CFG
fall-through path; `return` inside begin/ensure (plain returns AND
inline-return jumps out of inlined yield callees) skipped every active
ensure. Every stage1-emitted binary therefore RAN with ensure-on-early-return
cleanups dropped — a family generator for s2/s2b/s3b state-leak weirdness.
B5 concrete instance (lldb on unmodified cv2_s2, zero rebuilds): the
key→def→arena triple at the crash was CORRECT (def = stdlib info.cr:53
`Crystal::DWARF::Info#each`, arena = info.cr AstArena; the 2026-07-03
three-Hash-lookup suspects are EXONERATED; wrong-owner framing REFUTED —
the inline is legitimate, prelude CallStack code). HW watchpoint on the
`@arena` ivar (self+0x10): switch to callee arena fired (90158), then
`inline_block_return_type_name` switched to the block arena (49760) and its
`ensure` restore (49803) never executed — early `return` inside `begin`.
Def body ExprIds (101,108,162) then resolved in exception.cr's arena →
garbage node → SuperNode dispatch → lower_super null+4.
10-line falsifier: `begin; return 1; ensure; @tag = "x"; end` — pre-fix
stage1 skips the ensure; host crystal runs it. Fix `76f3f279`:
EnsureLoweringContext stack + emit_pending_ensure_bodies at both
lower_return exits (LIFO, function_id-filtered, inline-marker-scoped,
with_arena around bodies). Oracle: `regression_tests/ensure_early_return_repro.sh`
(green fixed / red pre-fix; plain, nested-LIFO, non-local block return,
return-in-rescue, fall-through-once). run_all_suites fully green.
Known gaps documented at EnsureLoweringContext: break/next crossing ensure,
exception unwind through ensure-only begin, pre-existing post-yield code on
NLR path. Debug knob: ADAMAS_ENSURE_RET_SKIP (substring list / `*`)
suppresses the new emission per compiled function for bisection.

[LM-B5-SUCCESSOR-ENSURE-EMISSION-FOREIGN-LOCALS|root-cause FIXED `6ec62e0d` 2026-07-04 {F:0.90 G:0.70 R:0.90}]:
First successor layer closed. s2 built with `76f3f279` crashed at enum
register: the re-lowered ensure body at a non-local-return site ran under
the CALLER block's locals, so the inlined with_arena restore
`@arena = old_arena` (shape: `return` inside `with_arena(...) { ... }`,
ast_to_hir.cr:20107 in infer_concrete_return_type_from_body) bound
`old_arena` to garbage and stored a STACK ADDRESS into @arena (writer
caught by HW watchpoint value-range condition; NB on this platform the
main-thread stack ~0x16f_dxxxxxxx is BELOW the GC heap ~0xb_xxxxxxxxx).
15-line falsifier: `with_mark("inner") { return 42 }` where the helper's
ensure does `@mark = old` → ivar garbage pre-fix, "init" post-fix.
Fix: EnsureLoweringContext snapshots scope-open locals; emission overlays
snapshot on site locals (snapshot wins for known names; begin-body-declared
names flow from the site — pure snapshot-replacement broke those, oracle
case F). Known limit: locals reassigned between begin and the exit are
seen at push-time values. Oracle cases E+F in
regression_tests/ensure_early_return_repro.sh; run_all_suites green.
Methodology: A/B ivar+class-only s2 build exonerated type-id/ivar-offset
renumbering; normalized per-function IR fingerprint diff of 287MB .ll pairs
found the true emission deltas (most "changed" fns were dispatch-switch /
.str/.stub_name renumber noise). ADAMAS_ENSURE_RET_SKIP knob exists but its
substring match against ctx.function.name (HIR names) was never validated —
bisection rounds R1/R2 with LLVM-mangled names were likely no-ops; verify
name format before trusting it.

[LM-B5-SUCCESSOR2-S2-RESOLVER-SET-INCONSISTENT|frontier OPEN 2026-07-04 {F:0.6 G:0.4 R:0.8}]:
Next layer: s2 (cv2_s2_v3, both ensure fixes) fails compiling `puts 42`
with `error: Empty enumerable` (mostly deterministic; one run in four
segfaulted in ClassNode#body null-self on the v2 binary). Raise bt:
Set(String)#first inside resolve_class_name_in_signature_context
(`return candidates.first if candidates.size == 1` at ~ast_to_hir.cr:48100)
— size==1 yet iteration yields nothing => Set/Hash internal state
inconsistent in s2, OR the resolver reaches a state old-s2 never reached
(correct ensure restores of @current_class/@current_namespace_override now
run on early returns — legit behavior change exposing a latent miscompile
on a fresh path). Not yet classified. Iteration oracle: s2 self-build of
`puts 42` (~3s). Artifacts: tmp/b5_fix_bootstrap/cv2_s2_v3 (current),
tmp/ab_ivar_only/ (A/B worktree + .ll), tmp/b5_s2_ir.ll (pre-fix baseline).

[LM-ARCH-B5-INLINE-CALLEE-LOCAL-SCAN-SCOPE-OWNER|owner-migration 2026-07-03 {F:0.88 G:0.40 R:0.86}]:
`AstToHir#inline_callee_local_names` now has a behavior-neutral owner helper for
its scanner/provenance scope. The old direct authority edge was the raw
save/switch/clear/restore block for `@arena`,
`@inline_yield_block_stack`, `@inline_yield_block_arena_stack`, and
`@inline_yield_block_param_types_stack` while scanning a callee body for local
names. It is now owned by `InlineCalleeLocalScanScopeSnapshot` plus
`enter_inline_callee_local_scan_scope` /
`restore_inline_callee_local_scan_scope`. The pre-slice source-shape baseline
was `inline_scan_enter=0`, `inline_scan_restore=0`, and
`inline_scan_legacy=8`; the current guard with
`REQUIRE_INLINE_CALLEE_LOCAL_SCAN_SCOPE=1
scripts/inline_callee_local_scan_scope_source_shape_guard.sh` reports
`source_shape=inline_callee_local_scan_scope_consumed`, one enter call, one
restore call, and zero legacy scanner saves. Evidence: `crystal build
src/adamas.cr -o tmp/adamas_inline_callee_scan_scope_stage1 --error-trace`
exits 0; `scripts/build_bootstrap_stages.sh --out
tmp/bootstrap_inline_callee_scan_scope --stages 2 --timeout 900 --mem 12288`
builds and smokes through `cv2_s2` clean (`cv2_s2` wall 231.37s, peak RSS about
3362 MB); the B4 guard with that `cv2_s2` remains
`classification=clean_both_modes`; the B5 target-only classifier with that
`cv2_s2` still reports
`classification=self_build_hir_pending_target_lower_method_body_lowered_boundary`
with first bad `ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED`;
and the regression surface reports `152/152` full regressions plus `36/36`
combined. Scope: this consumes the scanner/provenance residual for
`inline_callee_local_names`, not a green B5/s3b claim. It does not migrate
method-pointer thunks, proc literals, or block-to-proc body scopes. Decay
trigger: the inline-callee scan source guard no longer reports the consumed
shape, B4 regresses from `clean_both_modes`, the B5 target classifier moves to
an earlier boundary, or a later `SemanticStateScope` slice supersedes this
helper.

[LM-ARCH-B5-LOWER-MODULE-METHOD-BODY-SCOPE-OWNER|owner-migration 2026-07-03 {F:0.88 G:0.43 R:0.86}]:
The `MethodBodyLoweringScopeSnapshot` owner helper now also owns the
`AstToHir#lower_module_method` body-lowering seam. The pre-slice source-shape
baseline for `lower_module_method` reported no owner-helper enter/restore calls
and 15 legacy body-scope saves. The current guard with
`REQUIRE_METHOD_BODY_SCOPE=1 REQUIRE_LOWER_DEF_BODY_SCOPE=1
REQUIRE_LOWER_MODULE_METHOD_BODY_SCOPE=1
scripts/method_body_lowering_scope_source_shape_guard.sh` reports
`lower_method_source_shape=method_body_scope_owner_consumed`,
`lower_def_source_shape=method_body_scope_owner_consumed`, and
`lower_module_method_source_shape=method_body_scope_owner_consumed`, each with
one enter call, one restore call, and zero selected legacy saves. Evidence:
`crystal build src/adamas.cr -o
tmp/adamas_lower_module_method_body_scope_stage1 --error-trace` exits 0;
`scripts/build_bootstrap_stages.sh --out
tmp/bootstrap_lower_module_method_body_scope --stages 2 --timeout 900 --mem
12288` builds and smokes through `cv2_s2` clean (`cv2_s2` wall 251.91s, peak
RSS about 3388 MB); the B4 guard with that `cv2_s2` remains
`classification=clean_both_modes`; the B5 target-only classifier with that
`cv2_s2` still reports
`classification=self_build_hir_pending_target_lower_method_body_lowered_boundary`
with first bad `ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED`;
and the regression surface reports `152/152` full regressions plus `36/36`
combined. Scope: this is a third method-like body-scope owner-consumption
checkpoint, not a green B5/s3b claim. It does not migrate
`inline_callee_local_names`, method-pointer thunks, proc literals, or
block-to-proc body scopes. Decay trigger: the source guard no longer reports all
three method-like seams consumed, B4 regresses from `clean_both_modes`, the B5
target classifier moves to an earlier boundary, or a later
`MethodBodyLoweringContext` / `SemanticStateScope` slice supersedes this helper.

[LM-ARCH-B5-LOWER-DEF-BODY-SCOPE-OWNER|owner-migration 2026-07-03 {F:0.88 G:0.44 R:0.86}]:
The `MethodBodyLoweringScopeSnapshot` owner helper now also owns the
`AstToHir#lower_def` body-lowering seam. The pre-slice source-shape baseline for
`lower_def` reported no owner-helper enter/restore calls and 14 legacy
body-scope saves. The current guard with `REQUIRE_METHOD_BODY_SCOPE=1
REQUIRE_LOWER_DEF_BODY_SCOPE=1
scripts/method_body_lowering_scope_source_shape_guard.sh` reports
`lower_method_source_shape=method_body_scope_owner_consumed` and
`lower_def_source_shape=method_body_scope_owner_consumed`, each with one enter
call, one restore call, and zero selected legacy saves. Evidence:
`crystal build src/adamas.cr -o tmp/adamas_lower_def_body_scope_stage1
--error-trace` exits 0; `scripts/build_bootstrap_stages.sh --out
tmp/bootstrap_lower_def_body_scope --stages 2 --timeout 900 --mem 12288` builds
and smokes through `cv2_s2` clean (`cv2_s2` wall 253.42s, peak RSS about
3207 MB); the B4 guard with `tmp/bootstrap_lower_def_body_scope/cv2_s2` remains
`classification=clean_both_modes`; the B5 target-only classifier with that
`cv2_s2` still reports
`classification=self_build_hir_pending_target_lower_method_body_lowered_boundary`
with first bad `ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED`;
and the regression surface reports `152/152` full regressions plus `36/36`
combined. Scope: this is a second body-scope owner-consumption checkpoint, not a
green B5/s3b claim. At this checkpoint it did not yet migrate
`lower_module_method`, `inline_callee_local_names`, or proc-body scopes. Decay
trigger: the source guard no longer reports both `lower_method` and `lower_def`
consumed, B4 regresses from `clean_both_modes`, the B5 target classifier moves
to an earlier boundary, or a later `MethodBodyLoweringContext` /
`SemanticStateScope` slice supersedes this helper.

[LM-ARCH-B5-METHOD-BODY-SCOPE-OWNER|owner-migration 2026-07-03 {F:0.88 G:0.46 R:0.86}]:
The selected B5 `AstToHir#lower_method` body-lowering lifetime edge now has a
behavior-neutral owner helper. The old direct authority edge was the raw
save/clear/restore block for `@inline_yield_block_stack`,
`@inline_yield_block_arena_stack`, `@inline_yield_block_param_types_stack`,
`@inline_yield_block_return_stack`, `@inline_yield_name_stack`,
`@inline_arenas`, `@infer_body_context`, and `@current_def_return_type` inside
`lower_method` body lowering. It is now owned by
`MethodBodyLoweringScopeSnapshot` plus `enter_method_body_lowering_scope` /
`restore_method_body_lowering_scope`. Evidence: `REQUIRE_METHOD_BODY_SCOPE=1
scripts/method_body_lowering_scope_source_shape_guard.sh` reports
`source_shape=method_body_scope_owner_consumed`, one enter call, one restore
call, and zero selected-`lower_method` legacy saves; `crystal build
src/adamas.cr -o tmp/adamas_method_body_scope_stage1 --error-trace` exits 0;
`scripts/build_bootstrap_stages.sh --out tmp/bootstrap_method_body_scope
--stages 2 --timeout 900 --mem 12288` builds and smokes through `cv2_s2` clean
(`cv2_s2` wall 240.70s, peak RSS about 3114 MB); the B5 target-only classifier
with `tmp/bootstrap_method_body_scope/cv2_s2` still reports
`classification=self_build_hir_pending_target_lower_method_body_lowered_boundary`
with clean gates through body-loop start and first bad
`ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED`; the B4 guard
reports `classification=clean_both_modes`; and the regression surface reports
`152/152` full regressions plus `36/36` combined. Scope: this is an
architecture owner-consumption checkpoint, not a green B5/s3b claim. At that
checkpoint, raw body-scope save/restore sites outside the selected
`lower_method` path were residual debt, not silently migrated. Decay trigger:
source-shape guard no
longer reports `method_body_scope_owner_consumed`, a fresh B5 classifier moves
to an earlier boundary, B4 regresses from `clean_both_modes`, or a later
`MethodBodyLoweringContext` slice supersedes this helper.

[LM-ARCH-B5-LOWER-METHOD-BODY-FRONTIER|frontier 2026-07-03 {F:0.90 G:0.50 R:0.86}]:
B5 is now narrowed inside the selected `AstToHir#lower_method` invocation for
the queued missing-sweep demand `Adamas::Compiler::CLI#run$IO_IO`. The fresh
target-only classifier using `tmp/bootstrap_b5_lower_method_localizer/cv2_s2`
reports
`classification=self_build_hir_pending_target_lower_method_body_lowered_boundary`.
Clean lower-method gates: enter, base ready, suffix done, early terminals done,
scope ready, params collected, name ready, function created, self bound, params
bound, auto-assign done, body setup, arena ready, and body loop start. The first
bad gate is
`ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED`, which exits
139 at about 4809 MB without safe-wrapper memory or timeout kill. The body-loop
start row records `body_size=44`, `entry_boxes=0`, `arena_size=27174`, and
`from_stored=1`. Scope: this is a behavior-neutral diagnostic checkpoint and
red B5/s3b evidence, not a green bootstrap claim. It refutes lookup,
call-arg recovery, materialization naming, function creation, self/parameter
binding, auto-assign, method arena setup, and entry-box setup as first-bad
transitions for this target. Stop rule: do not continue with another generic
`lower_method` body or `lower_expr` marker unless a new SDD receipt names the
owner/authority edge that body-lowering is expected to migrate or refute.
Otherwise return to the SDD Current Execution Board. Decay trigger: a fresh
target-only classifier no longer reports
`self_build_hir_pending_target_lower_method_body_lowered_boundary`, a concrete
owner-edge receipt admits a body-lowering slice, or a fresh 3-stage bootstrap
succeeds.

[LM-ARCH-B5-PENDING-TARGET-LOWER-METHOD-FRONTIER|frontier 2026-07-03 {F:0.90 G:0.58 R:0.86}]:
B5 is now narrowed from the pending item loop into the selected
`lower_method` body for the queued missing-sweep demand
`Adamas::Compiler::CLI#run$IO_IO`. New default-off target gates inside
`lower_function_if_needed` show the target reaches lower-function enter, direct
lookup completion (`found=1, branch=direct`), resolved DefNode
(`abstract=1`), call-arg recovery, materialization decision (`wrapper=0,
shape=0`, materialized name equal to the target), and the stop immediately
before instance `lower_method` with `owner=Adamas::Compiler::CLI`,
`producer=instance_class_info_lower_method`, and
`reason=target_materialization`. The first bad target gate is
`ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_FUNC_AFTER_INSTANCE_LOWER_METHOD`,
which exits 139 at about 4806 MB without safe-wrapper memory or timeout kill.
Evidence: `crystal build src/adamas.cr -o
tmp/adamas_b5_target_localizer_stage1 --error-trace` exits 0;
`scripts/build_bootstrap_stages.sh --out tmp/bootstrap_b5_target_localizer
--stages 2 --timeout 900 --mem 12288` builds and smokes `cv2_s1` and `cv2_s2`
clean (`cv2_s2` wall 243.53s, peak RSS about 3362 MB);
`PENDING_TARGET_ONLY=1
STAGE1_COMPILER=tmp/bootstrap_b5_target_localizer/cv2_s2
REQUIRE_CLASSIFICATION=1 STOP_TIMEOUT=900 STOP_MEM_MB=12288
HIGH_RSS_MB=12288 scripts/generated_stage_self_build_hir_boundary_classifier.sh`
exits 0 with
`classification=self_build_hir_pending_target_lower_func_after_instance_lower_method_boundary`;
and `GENERATED_S2=tmp/bootstrap_b5_target_localizer/cv2_s2 REQUIRE_CLEAN=1
scripts/generated_stage_llvm_entry_classifier.sh` reports
`classification=clean_both_modes`. Regression surface:
`regression_tests/run_all_suites.sh tmp/adamas_b5_target_localizer_stage1 4`
reports all suites passed (`152/152` full regressions and `36/36` combined).
Scope: B5 remains red; this is a
behavior-neutral diagnostic narrowing, not green `s3b`. The next first-bad
search is inside `AstToHir#lower_method` for
`Adamas::Compiler::CLI#run$IO_IO`, not lookup, call-arg recovery,
materialization naming, pending queue mechanics, the old pending prefix gates,
B4/L17-L22 LLVM, stale `NamedTuple` / `Tuple`, ambient-map, or `BlockOwner`
evidence. Decay trigger: a narrower classifier pins a different first-bad
transition inside that `lower_method` body, the target-only classifier no
longer reports
`self_build_hir_pending_target_lower_func_after_instance_lower_method_boundary`,
or a fresh 3-stage bootstrap succeeds.

[LM-ARCH-B5-PENDING-ITEM-LOOP-FRONTIER|frontier 2026-07-03 {F:0.90 G:0.57 R:0.86}]:
B5 is now narrowed inside `process_pending_lower_functions` when owned by the
initial `lower_missing_call_targets` sweep. The missing sweep queues 28 targets,
then the pending processor cleanly reaches context enter, repeated lazy-RTA
initialization, pass start, first item read, first RTA keep decision, first
lower-ready, and first lower-done gates. The first bad gate is now
`ADAMAS_STOP_AFTER_HIR_PENDING_PASS_ITEMS_DONE`, which exits 139 at about
4803 MB without safe-wrapper memory kill. Evidence: `crystal build
src/adamas.cr -o tmp/adamas_b5_pending_phase_stage1 --error-trace` exits 0;
`scripts/build_bootstrap_stages.sh --out tmp/bootstrap_b5_pending_phase
--stages 2 --timeout 900 --mem 12288` builds and smokes `cv2_s1` and `cv2_s2`
clean (`cv2_s2` wall 240.92s, peak RSS about 3295 MB); and
`STAGE1_COMPILER=tmp/bootstrap_b5_pending_phase/cv2_s2
REQUIRE_CLASSIFICATION=1 STOP_TIMEOUT=900 STOP_MEM_MB=12288 HIGH_RSS_MB=12288
scripts/generated_stage_self_build_hir_boundary_classifier.sh` exits 0 with
`classification=self_build_hir_pending_pass_items_done_boundary`. The failing
gate tail reaches `idx=19`, target `Adamas::Compiler::CLI#run$IO_IO`, and
crashes after `first_lower_ready` but before the corresponding
`first_lower_done`, so the next first-bad search is inside
`lower_function_if_needed` / `lower_method` for that queued missing-sweep
demand. B4 remains clean:
`GENERATED_S2=tmp/bootstrap_b5_pending_phase/cv2_s2 REQUIRE_CLEAN=1
scripts/generated_stage_llvm_entry_classifier.sh` reports
`classification=clean_both_modes`, combined regressions pass 36/36, and full
regressions pass 152/152. Scope: B5 remains red; this is behavior-neutral
diagnostic narrowing, not green `s3b`. Do not reopen pending context enter,
lazy-RTA init, pass start, first item/keep/lower-ready/lower-done, missing
scan/uniq/queue, fun-main scan/lower, tracked signatures, MIR, LLVM
finalization/helper, stale `NamedTuple` / `Tuple`, ambient-map, or `BlockOwner`
evidence. Decay trigger: a narrower classifier pins a different first-bad
transition inside the `CLI#run` pending-lower path, the refined classifier no
longer reports `self_build_hir_pending_pass_items_done_boundary`, or a fresh
3-stage bootstrap succeeds.

[LM-ARCH-B5-MISSING-PROCESS-PENDING-FRONTIER|frontier 2026-07-03 {F:0.90 G:0.56 R:0.86}]:
B5 is now narrowed inside the initial `lower_missing_call_targets` sweep reached
from top-level `fun main` flush. Missing-call scanning, uniquing, and queue
insertion are clean: the sweep finds 28 missing targets, queues them, and then
crashes during the `process_pending_lower_functions` call owned by that sweep.
Evidence: `crystal build src/adamas.cr -o tmp/adamas_b5_missing_phase_stage1
--error-trace` exits 0; `scripts/build_bootstrap_stages.sh --out
tmp/bootstrap_b5_missing_phase --stages 2 --timeout 900 --mem 12288` builds
and smokes `cv2_s1` and `cv2_s2` clean (`cv2_s2` wall 253.17s, peak RSS about
3249 MB); and `STAGE1_COMPILER=tmp/bootstrap_b5_missing_phase/cv2_s2
REQUIRE_CLASSIFICATION=1 STOP_TIMEOUT=900 STOP_MEM_MB=12288 HIGH_RSS_MB=12288
scripts/generated_stage_self_build_hir_boundary_classifier.sh` exits 0 with
`classification=self_build_hir_missing_process_boundary`. Clean lower-missing
gates: start, scan (`missing=28`), uniq (`missing=28`), and queue
(`pending=28`). First bad gate: `ADAMAS_STOP_AFTER_HIR_MISSING_PROCESS` exits
139 at about 4804 MB without safe-wrapper memory kill. B4 remains clean:
`GENERATED_S2=tmp/bootstrap_b5_missing_phase/cv2_s2 REQUIRE_CLEAN=1
scripts/generated_stage_llvm_entry_classifier.sh` reports
`classification=clean_both_modes`, combined regressions pass 36/36, and full
regressions pass 152/152. Scope: B5 remains red; the next first-bad search is
inside
`process_pending_lower_functions` when entered with the 28 targets queued by
the initial missing-target sweep, not missing scan/uniq/queue, reachability
seeding, lazy RTA init, initial pending lowering, tracked signatures, fun-main
scan/lower, RTA pruning, MIR, LLVM finalization/helper, stale `NamedTuple` /
`Tuple`, ambient-map, or `BlockOwner` evidence. Decay trigger: a narrower
classifier pins a different first-bad transition inside that pending processor
call, the refined classifier no longer reports
`self_build_hir_missing_process_boundary`, or a fresh 3-stage bootstrap
succeeds.

[LM-ARCH-B5-FLUSH-MISSING-INITIAL-FRONTIER|frontier 2026-07-03 {F:0.90 G:0.55 R:0.86}]:
B5 is now narrowed inside `AstToHir#flush_pending_functions` on the top-level
`fun main` path. The new flush subphase gates show reachability seeding, lazy
RTA initialization, the initial pending drain, and tracked-signature emission
are clean; the first bad transition is the initial `lower_missing_call_targets`
safety-net sweep. Evidence: `crystal build src/adamas.cr -o
tmp/adamas_b5_flush_phase_stage1 --error-trace` exits 0;
`scripts/build_bootstrap_stages.sh --out tmp/bootstrap_b5_flush_phase --stages
2 --timeout 900 --mem 12288` builds and smokes `cv2_s1` and `cv2_s2` clean
(`cv2_s2` wall 253.37s, peak RSS about 2962 MB); and
`STAGE1_COMPILER=tmp/bootstrap_b5_flush_phase/cv2_s2 REQUIRE_CLASSIFICATION=1
STOP_TIMEOUT=900 STOP_MEM_MB=12288 HIGH_RSS_MB=12288
scripts/generated_stage_self_build_hir_boundary_classifier.sh` exits 0 with
`classification=self_build_hir_flush_missing_initial_boundary`.
`ADAMAS_STOP_AFTER_HIR_FLUSH_MISSING_INITIAL` exits 139 at about 4803 MB
without safe-wrapper memory kill. B4 remains clean:
`GENERATED_S2=tmp/bootstrap_b5_flush_phase/cv2_s2 REQUIRE_CLEAN=1
scripts/generated_stage_llvm_entry_classifier.sh` reports
`classification=clean_both_modes`, combined regressions pass 36/36, and full
regressions pass 152/152. Scope: B5 remains red; the next first-bad search is
inside
`lower_missing_call_targets`, not reachability seeding, lazy RTA init, initial
pending lowering, tracked signatures, fun-main scan/lower, normal post-branch
flush, RTA pruning, MIR, LLVM finalization/helper, stale `NamedTuple` /
`Tuple`, ambient-map, or `BlockOwner` evidence. Decay trigger: a narrower
classifier pins a different first-bad transition inside `lower_missing_call_targets`,
the refined classifier no longer reports
`self_build_hir_flush_missing_initial_boundary`, or a fresh 3-stage bootstrap
succeeds.

[LM-ARCH-B5-FUN-MAIN-FLUSH-PENDING-FRONTIER|frontier 2026-07-03 {F:0.90 G:0.54 R:0.86}]:
B5 is now narrowed inside the post-`lower_main` pending-flush corridor. The
refined classifier's new fun-main gates show `fun_main_entry` is taken, the
scan is clean, and `hir_converter.lower_def(fun main)` is clean, but the
pending-function flush invoked from that branch crashes before returning.
Evidence: `crystal build src/adamas.cr -o tmp/adamas_b5_flush_split_stage1
--error-trace` exits 0; `scripts/build_bootstrap_stages.sh --out
tmp/bootstrap_b5_flush_split --stages 2 --timeout 900 --mem 12288` builds and
smokes `cv2_s1` and `cv2_s2` clean (`cv2_s2` wall 243.30s, peak RSS about
3346 MB); and `STAGE1_COMPILER=tmp/bootstrap_b5_flush_split/cv2_s2
REQUIRE_CLASSIFICATION=1 STOP_TIMEOUT=900 STOP_MEM_MB=12288 HIGH_RSS_MB=12288
scripts/generated_stage_self_build_hir_boundary_classifier.sh` exits 0 with
`classification=self_build_hir_fun_main_flush_boundary`. Clean gates:
compile-entry 7 MB, parse 1263 MB, lower-main 4738 MB, lower-main bookkeeping
4738 MB, fun-main scan 4738 MB with `hir_fun_main_entry_status=taken`, and
fun-main lower 4740 MB. First bad gate:
`ADAMAS_STOP_AFTER_HIR_FUN_MAIN_FLUSH` exits 139 at about 4802 MB without
safe-wrapper memory kill. Scope: B5 remains red; the next first-bad search is
inside `AstToHir#flush_pending_functions` reached from top-level `fun main`,
not fun-main scan, `lower_def(fun main)`, normal post-branch flush, RTA, MIR,
LLVM finalization/helper, stale `NamedTuple` / `Tuple`, ambient-map, or
`BlockOwner` evidence. Decay trigger: a narrower classifier pins a different
first-bad transition inside `flush_pending_functions`, the refined classifier
no longer reports `self_build_hir_fun_main_flush_boundary`, or a fresh 3-stage
bootstrap succeeds.

[LM-ARCH-B5-HIR-FLUSH-PENDING-FRONTIER|frontier 2026-07-03 {F:0.89 G:0.55 R:0.86}]:
The coarse B5 `self_build_hir_boundary` has been refined. New diagnostic-only
post-`lower_main` gates and
`scripts/generated_stage_self_build_hir_boundary_classifier.sh` show that
produced `cv2_s2` can self-build `src/adamas.cr` through compile-entry, parse,
`ADAMAS_STOP_AFTER_LOWER_MAIN`, and
`ADAMAS_STOP_AFTER_HIR_LOWER_MAIN_DONE`, but not through
`ADAMAS_STOP_AFTER_HIR_FLUSH_PENDING`. Evidence:
`crystal build src/adamas.cr -o tmp/adamas_b5_hir_gates_stage1 --error-trace`
exits 0; `scripts/build_bootstrap_stages.sh --out tmp/bootstrap_b5_hir_gates
--stages 2 --timeout 900 --mem 12288` builds and smokes `cv2_s1` and `cv2_s2`
clean (`cv2_s2` wall 252.39s, peak RSS about 3363 MB); and
`STAGE1_COMPILER=tmp/bootstrap_b5_hir_gates/cv2_s2 REQUIRE_CLASSIFICATION=1
STOP_TIMEOUT=900 STOP_MEM_MB=12288 HIGH_RSS_MB=12288
scripts/generated_stage_self_build_hir_boundary_classifier.sh` exits 0 with
`classification=self_build_hir_flush_pending_boundary`. The clean refined gates
peak at `6`, `1263`, `4737`, and `4738` MB; the first bad gate exits 139 at
about `4801` MB without safe-wrapper memory kill. Scope: B5 remains red, but
the first bad interval is now the post-`lower_main` pending-flush corridor
(fun-main scan/lowering versus `flush_pending_functions`), not `lower_main`
itself, RTA, MIR, LLVM finalization/helper, stale `NamedTuple` / `Tuple`,
ambient-map, or `BlockOwner` evidence. Decay trigger: a narrower classifier
pins a different first-bad transition inside that corridor, the refined
classifier no longer reports `self_build_hir_flush_pending_boundary`, or a
fresh 3-stage bootstrap succeeds.

[LM-ARCH-B5-S3-SELF-BUILD-FRONTIER|frontier 2026-07-03 {F:0.88 G:0.58 R:0.86}]:
After Slice 0k-ET, the current bootstrap distance is no longer the old B4 tiny
produced-s2 LLVM-entry gate. `scripts/build_bootstrap_stages.sh --out
tmp/bootstrap_l22_demand --stages 3 --timeout 900 --mem 12288` builds and
smokes `cv2_s1` and `cv2_s2` clean, then fails `cv2_s3` build with exit 139
after `[STAGE2_DEBUG] pass3 after lower_main call` at about 4801 MB peak RSS.
Using the same `cv2_s2`,
`STAGE1_COMPILER=tmp/bootstrap_l22_demand/cv2_s2 REQUIRE_CLASSIFICATION=1
STOP_MEM_MB=12288 HIGH_RSS_MB=12288
scripts/generated_stage_self_build_boundary_classifier.sh` exits 0 with
`classification=self_build_hir_boundary`: compile-entry and parse are clean,
while HIR/MIR stop-gate runs both exit 139 after lower_main. Scope: `s2b`
builds and smokes; `s3b` remains red. Residual boundary: produced `cv2_s2`
self-build fails during/after HIR lower-main execution, not from the consumed
L17-L22 post-`to_s` LLVM-validity ladder. Decay trigger: a fresh 3-stage
bootstrap succeeds, the boundary classifier no longer reports
`self_build_hir_boundary`, or a narrower classifier pins a different first-bad
transition.

[LM-ARCH-0K-ET-GC-REALLOC-DEMAND-CONSUMED|implemented 2026-07-03 {F:0.90 G:0.55 R:0.88}]:
The L22 runtime-helper declaration frontier is consumed. Root boundary:
LLVM helper-call producers could emit calls to `@__adamas_gc_aware_realloc`
from `GC_realloc` redirects / bulk extern lowering, but the helper-definition
epilogue only knew about the shared reachable function list and could miss
worker-produced helper demand. The production slice adds a producer-owned
`@gc_aware_realloc_helper_needed` flag, serializes it through the existing
worker side-effect channel, merges it before helper emission, and emits the
GC-aware realloc wrapper when either that demand or the legacy shared-MIR scan
requires it. Evidence with `tmp/adamas_l22_demand_stage1`: stage1 build exits
0; `regression_tests/gc_aware_realloc_gating_repro.sh
tmp/adamas_l22_demand_stage1` exits 0, proving the GC-free negative and the
positive wrapper/redirect case; and
`STAGE1_COMPILER=tmp/adamas_l22_demand_stage1
scripts/generated_stage_gc_realloc_helper_report.sh` exits 0 with
`selection_status=rejected`, `reason=undefined_gc_realloc_helper_error_missing`,
`gc_realloc_helper_call_count=2`, and `gc_realloc_helper_define_count=1`.
Generated-stage evidence moves beyond L22: the finalize classifier builds
`adamas_s2`, full-prelude `normal_out` prints `42` under `scripts/run_safe.sh`,
and `STAGE1_COMPILER=tmp/adamas_l22_demand_stage1
GENERATED_S2=<kept>/adamas_s2 REQUIRE_CLEAN=1
scripts/generated_stage_llvm_entry_classifier.sh` reports
`classification=clean_both_modes`. Broader regression surface remains green:
`regression_tests/run_combined.sh tmp/adamas_l22_demand_stage1 4` reports
36/36 and `regression_tests/run_all.sh tmp/adamas_l22_demand_stage1 4` reports
152/152. Scope: produced `s2b` tiny full-prelude LLVM-entry is green in both
default and workers=1 modes; full `s3b`/arbitrary-program bootstrap remains
open. Decay trigger: the helper selector selects again, the GC-free negative
over-links `GC_base`/`GC_realloc`, `generated_stage_llvm_entry_classifier.sh
REQUIRE_CLEAN=1` stops reporting `clean_both_modes`, or regression suites fail.

[LM-ARCH-0K-ES-GC-REALLOC-HELPER-GATE|diagnostic 2026-07-03 {F:0.86 G:0.47 R:0.84}]:
The post-0k-ER residual now has an executable selector instead of only the
generic `post_to_s_frontier` row. New script:
`scripts/generated_stage_gc_realloc_helper_report.sh`. It requires the
generated-stage classifier to preserve the consumed L19/L20/L21 rows:
`normal_string_header_size_global_shape=i32_12`,
`raw_dump_classification=raw_dump_before_to_s_buffer_valid`,
`normal_llc_type_mismatch=0`, raw Slice stack storage, and raw Slice zero
sentinel storage. It then selects only when generated `normal_out.ll` calls
`@__adamas_gc_aware_realloc`, the helper has no declaration or definition in
that IR, and the `llc` error line matches one of those helper calls. Evidence
with `tmp/adamas_l22_selector_stage1`: `bash -n
scripts/generated_stage_gc_realloc_helper_report.sh` exits 0, and
`STAGE1_COMPILER=tmp/adamas_l22_selector_stage1 REQUIRE_SELECTED=1
scripts/generated_stage_gc_realloc_helper_report.sh` exits 0 with
`classification=runtime_helper_gc_realloc_missing_declaration_frontier`,
`selection_status=eligible_gc_realloc_helper_missing_declaration`,
`gc_realloc_helper_call_count=2`, `gc_realloc_helper_define_count=0`,
`gc_realloc_helper_declare_count=0`, `gc_realloc_decl_count=1`,
`gc_base_decl_count=1`, and `gc_realloc_helper_error_matches_call=1`. Scope:
diagnostic selector only, not green `s2b`/`s3b` and not a root fix. Residual
boundary: runtime-helper call demand and runtime-helper definition emission are
owned by separate ad hoc checks; the next production slice must make those
producers agree without over-linking GC-free programs. Decay trigger: the
selector no longer reports `runtime_helper_gc_realloc_missing_declaration_frontier`,
L19/L20/L21 consumed rows regress, or fresh evidence shows the helper error is
a downstream proxy.

[LM-ARCH-0K-ER-RAW-VALUE-STORAGE-CONSUMED|implemented 2026-07-03 {F:0.88 G:0.51 R:0.86}]:
The L21 zero-struct/value-storage LLVM validity edge is consumed. The root was
not a missing late typedef ledger: V2 value storage is consumed through
byte-level GEPs and pointer carriers, but stack `Alloc` and zero-filled struct
sentinels still emitted named aggregate LLVM storage (`%Slice$LUInt8$R`) that
can be absent from the initial type-definition sweep. The production slice
introduces raw stack storage for concrete value types and emits zero-filled
struct sentinels as raw `[size x i8] zeroinitializer, align N` globals.
Evidence with `tmp/adamas_l21_raw_storage_stage1`:
`scripts/generated_stage_zero_struct_sentinel_report.sh` exits 0 with
`selection_status=rejected`, `reason=invalid_null_constant_error_missing`,
`upstream_classification=post_to_s_frontier`,
`normal_string_header_size_global_shape=i32_12`,
`raw_dump_classification=raw_dump_before_to_s_buffer_valid`, and
`normal_llc_type_mismatch=0`. Kept-IR inspection from the same code shape
shows `%r2 = alloca [16 x i8], align 8` for `Slice(UInt8).new` and
`@__zero.Slice$LUInt8$R = internal global [16 x i8] zeroinitializer, align 8`.
Adjacent guards pass: `REQUIRE_OUTPUT_OWNERSHIP=1
scripts/llvm_output_ownership_source_shape_guard.sh`, the three L19 P2 guards,
`regression_tests/run_combined.sh tmp/adamas_l21_raw_storage_stage1 4` (36/36),
and `regression_tests/run_all.sh tmp/adamas_l21_raw_storage_stage1 4` (152/152).
Scope: moved generated-stage frontier only, not green `s2b`/`s3b`. Residual
boundary: generated LLVM now fails later on an undefined runtime helper
reference, `@__adamas_gc_aware_realloc`. The next slice must select that
runtime-helper declaration edge before changing helper emission, tail
declarations, backend undefined externs, output ownership, scalar globals,
function-return slots, `NamedTuple` / `Tuple`, ambient maps, or `BlockOwner`.
Decay trigger: the old L21 selector selects again, L19/L20 rows regress, or a
fresh focused selector proves the runtime-helper error is only a downstream
proxy.

[LM-ARCH-0K-EQ-ZERO-STRUCT-SENTINEL-GATE|diagnostic 2026-07-03 {F:0.86 G:0.48 R:0.84}]:
The post-0k-EP residual now has an executable selector rather than only a
generic `post_to_s_frontier` row. New script:
`scripts/generated_stage_zero_struct_sentinel_report.sh`. It requires the
upstream generated-stage classifier to preserve consumed rows from L19 and L20:
`normal_string_header_size_global_shape=i32_12`,
`raw_dump_classification=raw_dump_before_to_s_buffer_valid`, and
`normal_llc_type_mismatch=0`. It then selects only when `llc` reports
`invalid type for null constant` on the exact zero-filled struct sentinel
declaration
`@__zero.Slice$LUInt8$R = internal global %Slice$LUInt8$R zeroinitializer`.
Evidence: `bash -n scripts/generated_stage_zero_struct_sentinel_report.sh`
exits 0; a synthetic positive fixture reports
`classification=zero_struct_sentinel_invalid_initializer_frontier`, while a
stale `ptr_null` negative exits 9 with
`reason=string_header_size_scalar_global_not_preserved`; and
`STAGE1_COMPILER=tmp/adamas_l21_selector_stage1 REQUIRE_SELECTED=1
scripts/generated_stage_zero_struct_sentinel_report.sh` exits 0 with
`upstream_classification=post_to_s_frontier`, `normal_llc_type_mismatch=0`,
`invalid_null_error_line=9136`, `zero_struct_decl_line_no=9136`,
`zero_struct_error_matches_decl=1`, and
`classification=zero_struct_sentinel_invalid_initializer_frontier`. Scope:
diagnostic selector only, not green `s2b`/`s3b` and not a root fix. Residual
boundary: zero-filled struct sentinels are emitted by
`LLVMIRGenerator#emit_hoisted_allocas` for struct-typed pointer slots and
serialized through the zero-struct side-effect merge path; the next production
slice must name the declaration/type-availability authority edge before
editing backend emission. Decay trigger: the selector no longer reports
`zero_struct_sentinel_invalid_initializer_frontier`, L19/L20 consumed rows
regress, or fresh evidence shows the `@__zero.Slice(UInt8)` line is a
downstream proxy.

[LM-ARCH-0K-EP-FUNCTION-RETURN-CONTRACT-CONSUMED|implemented 2026-07-03 {F:0.88 G:0.46 R:0.86}]:
The L20 function-return contract mismatch is consumed. A temporary probe before
cleanup showed the defining MIR instruction for
`IO#read_char_with_bytesize` inside `IO#gets_slow` already had a non-void tuple
type and the emitted call ABI was `ptr`, but hoisted cross-block slot
preparation saw stale prepass `Void` for the same value, allocated the slot as
`i64`, and `emit_instruction` classified the `Call` as resultless. The
production slice makes current-function defining instructions visible during
slot preparation and makes ordinary MIR `Call` resultlessness require both the
prepass type and the MIR instruction type to be void; `ExternCall` and
`IndirectCall` keep the older conservative rule. Evidence with
`tmp/adamas_l20_contract_stage1`: `scripts/generated_stage_return_contract_mismatch_report.sh`
exits 0 with `normal_llc_type_mismatch=0`,
`upstream_classification=post_to_s_frontier`,
`normal_string_header_size_global_shape=i32_12`, and
`raw_dump_classification=raw_dump_before_to_s_buffer_valid`; generated IR shows
`%r18.slot = alloca ptr`, `store ptr %r18, ptr %r18.slot`, and
`%r18.fromslot.* = load ptr`. Adjacent guards pass:
`REQUIRE_OUTPUT_OWNERSHIP=1 scripts/llvm_output_ownership_source_shape_guard.sh`,
`p2_constant_globals_no_prelude_ok`, `p2_prescan_complex_constants_frontier_ok`,
`p2_macro_number_parsed_literals_no_prelude_ok`,
`regression_tests/run_combined.sh tmp/adamas_l20_contract_stage1 4` (36/36),
and `regression_tests/run_all.sh tmp/adamas_l20_contract_stage1 4` (152/152).
Scope: moved generated-stage frontier only, not green `s2b`/`s3b`. Residual
boundary: post-`to_s` LLVM validity now fails at
`@__zero.Slice$LUInt8$R = internal global %Slice$LUInt8$R zeroinitializer` with
`llc` reporting `invalid type for null constant`. Decay trigger: the L20 report
again selects `function_return_contract_mismatch_frontier`, the `%r18` slot
returns to `i64`, the L19 `i32_12` row regresses, or broader regression suites
fail.

[LM-ARCH-0K-EO-FUNCTION-RETURN-CONTRACT-MISMATCH-GATE|diagnostic 2026-07-03 {F:0.86 G:0.50 R:0.84}]:
The post-0k-EN generated-stage residual now has an executable selector rather
than only a prose next-step claim. New script:
`scripts/generated_stage_return_contract_mismatch_report.sh`. It requires the
upstream generated-stage classifier to preserve the consumed L19 row
(`normal_string_header_size_global_shape=i32_12` and buffer-valid raw dump) and
then selects only the current `%r18.fromslot.1` LLVM mismatch shape: `i64`
defined, `ptr` expected, inside `IO#gets_slow`, with
`IO#read_char_with_bytesize` in the local generated-IR window. Evidence:
`bash -n scripts/generated_stage_return_contract_mismatch_report.sh` exits 0;
a synthetic positive fixture reports
`classification=function_return_contract_mismatch_frontier`, while a stale
`ptr_null` negative exits 9 with
`reason=string_header_size_scalar_global_not_preserved`; and
`REQUIRE_SELECTED=1 scripts/generated_stage_return_contract_mismatch_report.sh`
exits 0 on current HEAD with
`upstream_classification=post_to_s_llc_type_mismatch_frontier`,
`normal_string_header_size_global_shape=i32_12`,
`raw_dump_classification=raw_dump_before_to_s_buffer_valid`,
`normal_llc_error_line=6123`, `normal_llc_error_value=%r18.fromslot.1`,
`normal_llc_error_defined_type=i64`,
`normal_llc_error_expected_type=ptr`,
`bad_function_symbol=IO$Hgets_slow$$Char_Int32_Bool_String$CCBuilder`, and
`callee_candidate=IO#read_char_with_bytesize`. Scope: diagnostic selector only,
not green `s2b`/`s3b` and not a root fix. Residual boundary:
FunctionReturnAvailability / LoweredFunctionReturnContract must make finalized
function return facts authoritative before HIR calls, MIR calls, and LLVM calls
consume them; backend ptr-use patches or HIR-to-MIR consumer fallbacks are
symptom fixes until this edge is consumed. Decay trigger: the selector no
longer reports `function_return_contract_mismatch_frontier`, the consumed L19
`i32_12` row regresses, or fresh evidence pins a different producer for the
same i64-vs-ptr value.

[LM-ARCH-0K-EN-CLASSVAR-SCALAR-GLOBAL-PRODUCER-CONSUMED|implemented 2026-07-03 {F:0.88 G:0.46 R:0.84}]:
The L19 `String::HEADER_SIZE` scalar-global producer edge is consumed. A
temporary trace before cleanup pinned two producer hazards: direct
`OffsetofNode` constants could be sealed by source fallback before class layout
was complete, and the generated compiler mis-stored
`MacroNumberValue.new(Int64)` through the broad numeric-union constructor
(`size_i64=12` but `literal=0`). The production slice queues direct `offsetof`
constants for pending re-evaluation before source fallback, shares one
`macro_value_for_offsetof` evaluator between macro literal evaluation and
runtime `lower_offsetof`, and adds exact scalar `MacroNumberValue`
constructors while preserving the existing union fallback. Evidence:
`crystal build src/adamas.cr -o tmp/adamas_l19_macro_number_stage1
--error-trace` exits 0; `KEEP_TMP=1
STAGE1_COMPILER=tmp/adamas_l19_macro_number_stage1 REQUIRE_RAW_DUMP=1
REQUIRE_CLASSIFICATION=1 scripts/generated_stage_finalize_to_s_classifier.sh`
exits 0 and reports `normal_string_header_size_global_shape=i32_12`,
`normal_string_header_size_global_line=@String__classvar__HEADER_SIZE = global
i32 12`, `raw_dump_classification=raw_dump_before_to_s_buffer_valid`, and
`classification=post_to_s_llc_type_mismatch_frontier`. Adjacent guards pass:
`p2_constant_globals_no_prelude_ok`, `p2_prescan_complex_constants_frontier_ok`,
and `p2_macro_number_parsed_literals_no_prelude_ok` with the same stage1;
`regression_tests/run_combined.sh tmp/adamas_l19_macro_number_stage1 4` reports
36/36, and `regression_tests/run_all.sh tmp/adamas_l19_macro_number_stage1 4`
reports 152/152. Scope: moved generated-stage frontier only, not green
`s2b`/`s3b`. Residual boundary: post-`to_s` LLVM validity now fails after the
scalar-global producer is correct; current `llc` mismatch is `%r18.fromslot.1`
defined as `i64` but expected as `ptr`. Decay trigger: a fresh classifier no
longer emits `String::HEADER_SIZE` as `i32 12`, adjacent macro/constant guards
regress, or the next residual is shown to be caused by this constructor/offsetof
change.

[LM-ARCH-0K-EM-POST-TO-S-CLASSVAR-SCALAR-GLOBAL-FRONTIER|diagnostic 2026-07-03 {F:0.88 G:0.48 R:0.84}]:
The post-0k-EL residual is narrower than generic post-`to_s` LLVM validity.
`scripts/generated_stage_finalize_to_s_classifier.sh` now inspects the normal
generated `.ll` for `@String__classvar__HEADER_SIZE` and the last `llc`
defined-vs-expected type mismatch. Focused evidence before cleanup used this
generated compiler:
`GENERATED_S2=tmp/generated-stage-finalize-to-s.bVJp2w/adamas_s2
REQUIRE_RAW_DUMP=1 REQUIRE_CLASSIFICATION=1
scripts/generated_stage_finalize_to_s_classifier.sh` exits 0 and reports
`classification=post_to_s_classvar_scalar_global_frontier`,
`normal_finalize_to_s_done_rows=1`,
`raw_dump_classification=raw_dump_before_to_s_buffer_valid`,
`normal_string_header_size_global_shape=ptr_null`,
the global line `@String__classvar__HEADER_SIZE = global ptr null`, and
`normal_llc_type_mismatch=1` at `normal_out.ll:5799:17` where
`%binop7.left_ext` is defined as `i64` but expected as `i32`. Scope:
behavior-neutral diagnostic split only, not green `s2b`/`s3b`. Residual
boundary: pin the producer of the `String::HEADER_SIZE` classvar scalar global
type/value contract before changing binary arithmetic emission, `llc` mismatch
consumers, output ownership, finalization, generic `IO::Memory`, tail,
metadata, DWARF, type-name, `NamedTuple`/`Tuple`, ambient maps, or
`BlockOwner`. Decay trigger: a fresh classifier no longer reports
`post_to_s_classvar_scalar_global_frontier`, `String::HEADER_SIZE` is emitted
as a concrete scalar value, or `llc` fails first for an unrelated producer
after the classvar global contract is proven correct.

[LM-ARCH-0K-EL-OUTPUT-OWNERSHIP-CONSUMED-POST-TO-S-FRONTIER|implemented 2026-07-03 {F:0.91 G:0.54 R:0.86}]:
The output-restore authority edge selected by 0k-EJ is consumed by a minimal
`LLVMOutputOwnershipContract` production slice. Strict source-shape evidence:
`REQUIRE_OUTPUT_OWNERSHIP=1 scripts/llvm_output_ownership_source_shape_guard.sh`
reports
`output_ownership_shape=output_ownership_contract_consumed_by_parallel_restore`,
`parallel_saved_output_snapshot_count=0`,
`parallel_direct_saved_output_restore_count=0`, and
`parallel_output_ownership_reference_count=3`. Generated-stage evidence with
`tmp/adamas_output_owner_stage1`:
`STAGE1_COMPILER=tmp/adamas_output_owner_stage1 REQUIRE_RAW_DUMP=1
REQUIRE_CLASSIFICATION=1 scripts/generated_stage_finalize_to_s_classifier.sh`
exits 0 and reports `classification=post_to_s_frontier`,
`normal_finalize_to_s_done_rows=1`,
`normal_parallel_rescue_current_pos_before_restore=147519`,
`normal_parallel_rescue_saved_output_pos=147519`,
`normal_parallel_rescue_restored_output_pos=147519`, and
`raw_dump_classification=raw_dump_before_to_s_buffer_valid`. Scope: moved
frontier only, not green `s2b`/`s3b`. Residual boundary: generated LLVM IR is
now materialized as a valid final buffer before the remaining failure, so the
next local track is post-`to_s` IR validity / downstream LLVM handling. Decay
trigger: a fresh classifier no longer reports `post_to_s_frontier`, the rescue
restore positions diverge again, or raw dump ceases to be buffer-valid.

[LM-ARCH-0K-EK-OUTPUT-OWNERSHIP-PRECODE-GATE|design-sealed 2026-07-03 {F:0.82 G:0.58 R:0.82}]:
The next production slice for the 0k-EJ rescue restore edge now has an
executable source-shape gate rather than only prose. New guard:
`scripts/llvm_output_ownership_source_shape_guard.sh`. Current source reports
`output_ownership_shape=legacy_ambient_output_restore`,
`parallel_saved_output_snapshot_count=1`,
`parallel_direct_saved_output_restore_count=3`, and
`parallel_output_ownership_reference_count=0`; strict mode
`REQUIRE_OUTPUT_OWNERSHIP=1 scripts/llvm_output_ownership_source_shape_guard.sh`
exits 1. Scope: pre-code contract gate only, not a behavior fix. Residual
boundary: a future `OutputOwnershipContract` production slice must make strict
source shape green and then move or preserve the 0k-EJ generated-stage
classifier. Decay trigger: source shape becomes green without moving the
generated-stage rescue-saved-output classification, or the active L18 frontier
no longer involves `emit_functions_parallel` output restore.

[LM-ARCH-0K-EJ-PARALLEL-RESCUE-SAVED-OUTPUT-BINDING-FRONTIER|implemented 2026-07-03 {F:0.90 G:0.52 R:0.84}]:
The L18 finalization-null boundary is a proxy for an earlier
`emit_functions_parallel` rescue fallback output-restore edge. The classifier
now records default-off `parallel_rescue_before_output_restore` and
`parallel_rescue_after_output_restore` rows around the existing
`parallel_rescue_fallback_sequential` row. Fresh evidence with
`tmp/adamas_0kej_stage1`:
`STAGE1_COMPILER=tmp/adamas_0kej_stage1 REQUIRE_RAW_DUMP=1
REQUIRE_CLASSIFICATION=1 scripts/generated_stage_finalize_to_s_classifier.sh`
reports `classification=select_parallel_rescue_saved_output_binding_frontier`.
The normal run records
`normal_parallel_rescue_current_pos_before_restore=147447`,
`normal_parallel_rescue_saved_output_present=1`,
`normal_parallel_rescue_saved_output_pos=0`, and
`normal_parallel_rescue_restored_output_pos=0`. Scope: behavior-neutral
discriminator only, not green `s2b`/`s3b`. Residual boundary: the produced
compiler's current `@output` is still populated immediately before rescue
restore, but the rescue-local `saved_output` binding is already an empty output
object; restoring it erases the final output and causes the later
finalization-null symptoms. Next local track: `OutputOwnershipContract` /
scoped output-restore ownership for `LLVMIRGenerator.@output`, parallel
parent/worker temp outputs, and fallback restore. Decay trigger: the classifier
no longer selects a parallel rescue output-restore classification, a fresh run
shows a nonempty `saved_output_pos`, or finalization remains null after output
restore is proven not to zero the buffer.

[LM-ARCH-0K-EI-FINAL-OUTPUT-RECEIVER-NULL-FRONTIER|implemented 2026-07-03 {F:0.89 G:0.50 R:0.84}]:
The L18 final-output boundary is sharper than the 0k-EH
`IO::Memory#bytesize` claim. The default-off raw final-buffer split now records
the pre-cast `LLVMIRGenerator.@output.object_id`, raw header checkpoints, cast
receiver identity, registry-backed `@bytesize` field-offset lookup, raw ivar
load, and getter entry under `ADAMAS_DUMP_LLVM_FINAL_BUFFER_BEFORE_TO_S=<path>`.
Fresh evidence with `tmp/adamas_l18_output_stage1`: the focused user-runtime
guard `regression_tests/io_memory_final_materialization_repro.sh` still reports
`io_memory_final_materialization_repro_ok`; the generated-stage classifier
preserves `classification=select_finalize_to_s_stringification_frontier` and
reports
`raw_dump_classification=select_finalize_raw_dump_output_null_frontier`. The
raw run logs `finalize_raw_dump_output_object_id_done` and
`finalize_raw_dump_output_null`, while output raw-header, cast receiver,
field-offset, raw-bytesize, and getter checkpoints are not reached. Scope:
behavior-neutral discriminator only, not green `s2b`/`s3b`. Residual boundary:
the produced compiler's `LLVMIRGenerator.@output` reference is already null at
finalization; split the producer of that null output state before changing
`IO::Memory#bytesize`, final-output field layout, `as(IO::Memory)`, generic
`IO::Memory`/`String`, fd/raw output, tail, metadata, DWARF, type-name,
`NamedTuple`/`Tuple`, ambient maps, or `BlockOwner`. Decay trigger: the raw
split reports a nonzero output object and reaches output raw-header/receiver
checks, the user-runtime guard fails, or L18 no longer selects finalization
stringification.

[LM-ARCH-0K-EH-FINAL-IO-MEMORY-BYTESIZE-FRONTIER|implemented 2026-07-03 {F:0.88 G:0.50 R:0.84}]:
The L18 finalization boundary is now narrower than `IO::Memory#to_s`. A
default-off raw final-buffer split in `LLVMIRGenerator#generate` checks
`ADAMAS_DUMP_LLVM_FINAL_BUFFER_BEFORE_TO_S=<path>` and records
`finalize_raw_dump_*` phases before raw buffer dumping. The classifier
`scripts/generated_stage_finalize_to_s_classifier.sh` now supports
`REQUIRE_RAW_DUMP=1` and reports `raw_dump_classification`. Fresh evidence
with `tmp/adamas_l18_rawdump_stage1`: the focused user-runtime guard
`regression_tests/io_memory_final_materialization_repro.sh` still reports
`io_memory_final_materialization_repro_ok`; the generated-stage classifier
preserves `classification=select_finalize_to_s_stringification_frontier` and
reports `raw_dump_classification=select_finalize_raw_dump_bytesize_frontier`.
The raw-dump run reaches `finalize_raw_dump_env_lookup_done`,
`finalize_raw_dump_cast_done`, and `finalize_raw_dump_enter`, then exits 139
before `finalize_raw_dump_bytesize_done`; no raw dump file is produced. Scope:
behavior-neutral discriminator only, not green `s2b`/`s3b`. Residual boundary:
split the produced compiler's final `IO::Memory` object field read / receiver
validity at `bytesize`; do not patch fd/external output, raw dump writing,
generic `String.new(buffer, bytesize)`, generic user-runtime `IO::Memory`, or
tail/metadata/DWARF/type-name from this evidence. Decay trigger: the raw split
reaches `bytesize_done`, the user-runtime guard fails, or the L18 classifier no
longer selects finalization stringification.

[LM-ARCH-0K-EG-IOMEM-GENERIC-MATERIALIZATION-REFUTED|refuted 2026-07-03 {F:0.86 G:0.48 R:0.82}]:
The L18 `IO::Memory#to_s` generated-stage frontier is not explained by a
generic small/medium user-runtime `IO::Memory` materialization failure. The
refuted `generate_to_fd` / `finalize_to_fd` WIP was removed, restoring the
committed L18 path. New focused guard:
`regression_tests/io_memory_final_materialization_repro.sh <compiler>`.
Fresh evidence with `tmp/adamas_l18_iomem_stage1` reports
`io_memory_final_materialization_repro_ok`; the generated user binary
successfully materializes both tiny and resize-heavy (~2MB) `IO::Memory`
buffers through `to_s`, `to_slice`, `String.new(slice)`, and
`String.new(buffer, bytesize)`. A fresh generated-stage L18 classifier with
the same stage1 still reports
`classification=select_finalize_to_s_stringification_frontier`: normal
produced-s2 exits 139 at `finalize_to_s_enter`, stop-before-to-s exits 0, and
both probes emit 150/150 functions and reach tail/metadata/type-name/DWARF.
Scope: negative control only, not a fix and not green `s2b`/`s3b`. Decay
trigger: the focused guard fails, the L18 classifier no longer selects
finalize-to-s, or a final-output-shape reducer reproduces the crash outside
the produced compiler.

[LM-ARCH-0K-EF-FINALIZE-TO-S-STRINGIFICATION-FRONTIER|implemented 2026-07-03 {F:0.90 G:0.56 R:0.86}]:
The post-function-emission L17 boundary is now classified as in-memory LLVM
output stringification. `ADAMAS_STOP_BEFORE_LLVM_FINALIZE_TO_S=1` is a
default-off generated-stage stop gate in `LLVMIRGenerator#generate`; it logs
`llvm.generate_phase=finalize_to_s_stop_before`, logs an `llvm.finalization`
memory phase, and exits before `IO::Memory#to_s`. The focused classifier
`scripts/generated_stage_finalize_to_s_classifier.sh` builds/uses a generated
`s2` and runs normal plus stop-before probes. Fresh evidence reports
`classification=select_finalize_to_s_stringification_frontier`: normal exits
139 after `finalize_to_s_enter`, with `finalize_to_s_done_rows=0`;
stop-before exits 0 with `finalize_to_s_stop_before_rows=1`. Both runs emit
150/150 sequential functions and reach `tail_done`, `metadata_done`,
`type_name_table_done`, and `dwarf_done`. Scope: discriminator only, not green
`s2b`/`s3b`. Decay trigger: normal reaches `finalize_to_s_done`, stop-before
crashes, or the next evidence shows the crash is caused by a prior emitted IR
corruption rather than the final `IO::Memory#to_s` materialization edge.

[LM-ARCH-0K-EE-PHI-EMISSION-NEXT-SHAPE-CONSUMES-L15|implemented 2026-07-03 {F:0.84 G:0.58 R:0.78}]:
The late LLVM/function-emission resource cliff selected by L15 is consumed by a
source-equivalent `emit_phi` control-flow rewrite. The bool and int
mismatched-incoming loops now use an explicit `if/else` around
`phi_incoming_ref` instead of early `next`; this preserves the emitted incoming
choice while avoiding a self-hosted loop shape that repeatedly re-entered the
same incoming pair. Focused evidence before cleanup: the old #87
`__vdispatch__IO::FileDescriptor#system_write$Slice(UInt8)` int phi advanced to
`int_emit`, function #87 emitted, the next #92 bool phi was exposed, and after
the bool-loop rewrite a clean generated `s2` emitted all planned sequential
functions (149 in the fresh 0k-EE gate). With
`tmp/adamas_0kee_stage1` / `tmp/adamas_0kee_s2`, a full-prelude `puts 42` run under
`ADAMAS_GSETX_FUNCTION_EMISSION_OUTCOMES=1` exited 139 after reaching
`llvm.generate_phase=finalize_to_s_enter`, with peak RSS about 1.25 GB and no
late function-emission memory kill. Combined regressions pass `36/36`.
Original-suite verification is partial: a 900s run produced 139 PASS rows, the
13 missing tests were run individually with 12 PASS and `test_rescue_nested`
exit 139; an isolated HEAD baseline shows `test_rescue_nested` was already
exit 139. Scope: this is bootstrap movement, not green `s2b`/`s3b` and not a
full-suite green claim. Decay trigger: a clean generated-stage run again dies
inside function emission, the no-`next` loop shape changes emitted LLVM
semantics, or the next frontier is shown to be caused by this rewrite rather
than pre-existing finalize/tail behavior.

[LM-ARCH-0K-ED-FUNCTION-ATTEMPT-EDGE-SELECTED|implemented 2026-07-03 {F:0.90 G:0.53 R:0.86}]:
The active L15 function-emission edge is now selected over pre-attempt retained
state. A debug-only `ADAMAS_STOP_BEFORE_LLVM_FUNCTION_INDEX=<n>` gate logs
`sequential_stop_before`, `llvm.sequential_stop_before`, and a
`llvm.function_emission_outcome` row with `status=stop_before`, then exits
cleanly before emitting the requested function. The new
`scripts/generated_stage_function_emission_attempt_classifier.sh` uses that
gate with OS RSS evidence. Evidence with `tmp/adamas_l15_stop_stage1`:
`STAGE1_COMPILER=tmp/adamas_l15_stop_stage1 STAGE2_BUILD_TIMEOUT=600
TAIL_LINES=20 REQUIRE_CLASSIFICATION=1
scripts/generated_stage_function_emission_attempt_classifier.sh` reports
`classification=select_active_function_attempt_edge`. Both modes stop before
function #87 with no memory kill and low RSS
(`default_workers_peak_rss_mb=1180`, `workers1_peak_rss_mb=1183`), and both
last outcome rows are `status=stop_before`, `index=87`, function
`__vdispatch__IO::FileDescriptor#system_write$Slice(UInt8)$T122`. The same
stage1 preserves the gate-off L15 baseline:
`scripts/generated_stage_mode_resource_lane_classifier.sh` reports
`classification=select_default_late_llvm_resource_lane` and final outcome
`status=started`, `index=87`. Full suites pass `152/152 + 36/36`; semantic and
codepath census guards pass. Scope: behavior-neutral discriminator only. It
refutes retained output/resource state before function #87 as the first owner
for the current edge, but does not prove a method-specific fix and does not
admit patching `system_write` by name. Decay trigger: stop-before #87 becomes
high/memory-killed, the expected function/index changes under the L15 gate, or
a later inside-function split proves the edge is a reusable emission subowner
outside this function.

[LM-ARCH-0K-EC-ACTIVE-FUNCTION-EMISSION-ATTEMPT|implemented 2026-07-02 {F:0.89 G:0.55 R:0.85}]:
The L15 default late LLVM/function-emission outcome fact now distinguishes the
last completed function from the active in-flight emission attempt at the
resource kill. `emit_functions_sequential` logs a default-off
`llvm.function_emission_outcome` row with `status=started` before calling
`emit_function`, while preserving the existing `emitted` and `index_error`
rows. Evidence with `tmp/adamas_l15_attempt_stage1`:
`STAGE1_COMPILER=tmp/adamas_l15_attempt_stage1 STAGE2_BUILD_TIMEOUT=600
TAIL_LINES=20 REQUIRE_CLASSIFICATION=1 REQUIRE_LANE_SELECTION=1
scripts/generated_stage_mode_resource_lane_classifier.sh` preserves
`classification=select_default_late_llvm_resource_lane`, clean produced-s2
HIR/MIR stop gates in both modes, joined transaction residuals at
`reached_function_emission`, and reports
`transaction.default_function_emission_outcome_rows=173`,
`transaction.workers1_function_emission_outcome_rows=173`,
`transaction.last_function_emission_outcome_status=started`,
`transaction.last_function_emission_outcome_index=87`, and
`transaction.last_function_emission_outcome_function=__vdispatch__IO::FileDescriptor#system_write$Slice(UInt8)$T122`.
Full suites pass `152/152 + 36/36`; semantic and codepath census guards pass.
Scope: behavior-neutral owner-fact movement only. It names the active
function-emission edge, but it does not prove that `system_write` itself is the
root resource owner and does not admit a per-method patch. Decay trigger:
outcome rows stop joining, the last row no longer identifies an in-flight
attempt under L15, or a later discriminator proves the active function edge is
only a proxy for earlier retained output/resource state.

[LM-ARCH-0K-EB-FUNCTION-EMISSION-OUTCOME-OWNER|implemented 2026-07-02 {F:0.88 G:0.56 R:0.84}]:
The L15 default late LLVM/function-emission residual now has a code-owned
per-function outcome fact. `LLVMFunctionEmissionOutcome` records function
identity, index/total, mode, status, output-position delta, and
emitted/called/undefined side-effect deltas. The row is default-off and emitted
only for generated-stage transaction evidence via
`ADAMAS_GSETX_FUNCTION_EMISSION_OUTCOMES=1`. The transaction report enables and
consumes `llvm.function_emission_outcome`; the mode resource lane classifier
passes through the row counts and last outcome. Evidence with
`tmp/adamas_l15_outcome_stage1`: focused transaction report with
`REQUIRE_JOINED=1 REQUIRE_FUNCTION_EMISSION_SPLIT=1
REQUIRE_FUNCTION_EMISSION_OUTCOMES=1` reports
`runtime.function_emission_outcome_rows=172`,
`default/workers1_function_emission_outcome_rows=86/86`, and last completed
function
`__vdispatch__IO::FileDescriptor#unbuffered_write$Slice(UInt8)$T121`. The
broader mode selector still selects
`classification=select_default_late_llvm_resource_lane`, preserving L15/L16.
Full suites pass `152/152 + 36/36`. Scope: behavior-neutral owner-fact
movement, not a resource fix and not green `s2b`/`s3b`. Decay trigger: outcome
rows disappear under the transaction report, L15 no longer selects default late
LLVM/function emission with a valid generated `s2`, or the next slice proves
the outcome fact is the wrong owner boundary.

[LM-ARCH-0K-EA-ACCELERATION-CHECKPOINT|design-sealed 2026-07-02 {F:0.78 G:0.62 R:0.80}]:
The current architecture bottleneck is not missing SDD text; it is report churn
without an immediately consumable production receipt. The next code movement
must either enter the `PhaseAuthority` / `GeneratedStageExecution` L15 default
late LLVM/function-emission residual through a focused `SliceReceipt`, or
retire/refute an older report surface with a protecting falsifier. Phase 1/1b
static censuses remain guard/planning inputs only: they do not mark paths dead,
delete-ready, or root-owned. The required pre-edit mini-Quadrum for every next
slice is: claim, hardest falsifier, owner edge, and DoD. Scope: this is a
process/architecture acceleration seal, not a compiler behavior fix and not
green `s2b`/`s3b`. Decay trigger: a later current-board update selects a
different active lane, or a production slice proves a narrower receipt can move
the generated-stage gate without preserving L15/L16 controls.

[LM-ARCH-0K-DZ-SELF-BUILD-GUARD-REESTABLISHES-L15|implemented 2026-07-02 {F:0.88 G:0.54 R:0.82}]:
A hostile revalidation of post-0k-DY `L15` found a one-shot strict
mode-selector generated-s2 build failure, but controls show it is not enough to
retire the default late LLVM/function-emission lane. A direct full self-build
with a fresh `tmp/adamas_l16_stage1` succeeds under the strict 4GB cap:
`/usr/bin/time -l scripts/run_safe.sh tmp/adamas_l16_stage1 600 4096
src/adamas.cr -o tmp/l16_full_s2` exits 0 with peak RSS 3396 MB. The new
`scripts/generated_stage_self_build_boundary_classifier.sh` reports
`classification=self_build_after_mir_boundary`: compile-entry, parse, HIR, and
MIR stop gates are clean (`4`, `330`, `1722`, and `2328` MB respectively).
Using the resulting `tmp/l16_full_s2` as `GENERATED_S2`, the mode resource
classifier re-establishes `classification=select_default_late_llvm_resource_lane`
with clean produced-s2 HIR/MIR stop gates in both modes, joined transaction
rows, `default_mode_boundary=reached_function_emission`,
`workers1_mode_boundary=reached_function_emission`, and both modes
memory-killed after lower_main. Scope: this preserves 0k-DY/L15 as the active
production frontier while adding an executable guard for generated-s2
self-build variance. It does not admit worker, memory-budget, backend rescue,
`NamedTuple`/`Tuple`, ambient-map, `BlockOwner`, or consumed CopyPropagation
dominance changes. Decay trigger: the self-build classifier selects an earlier
boundary, direct full self-build fails reproducibly under the strict cap, or a
fresh mode selector with a valid generated `s2` no longer selects the late
LLVM/function-emission lane.

[LM-ARCH-0K-DY-LAZY-DOMINANCE-CONSUMES-COPYPROP-RESOURCE-LANE|implemented 2026-07-02 {F:0.91 G:0.58 R:0.86}]:
The selected 0k-DX `CopyPropagationPass#compute_dominance_info` resource lane
is consumed by replacing eager full-dominator construction with exact lazy
dominance queries for cross-block replacement checks. The query is exact: a
definition block dominates a use block iff no path from the function entry to
the use block can avoid the definition block; same-block checks still use
instruction order. Evidence: `crystal build src/adamas.cr -o
tmp/adamas_lazy_dom_stage1 --error-trace` passes. The old strict dominator
classifier no longer reaches the old lane: with
`STAGE1_COMPILER=tmp/adamas_lazy_dom_stage1 REQUIRE_CLASSIFICATION=1
REQUIRE_DOMINATOR=1 TAIL_LINES=30
scripts/generated_stage_workers1_copyprop_dominator_classifier.sh`, the nested
pass classifier reports `classification=workers1_mir_opt_pass_lane_decayed`,
`subphase.classification=workers1_mir_subphase_clean`,
`subphase.s2_mir_opt_peak_rss_mb=1177`, and
`subphase.s2_mir_opt_memory_kill=0`. The broader mode selector reports clean
produced-s2 HIR/MIR stop gates in both modes
(`s2_default_mir_peak_rss_mb=1173`, `s2_workers1_mir_peak_rss_mb=1177`) and
selects `classification=select_default_late_llvm_resource_lane`, with joined
transaction residuals at `reached_function_emission` and both modes still
memory-killed after lower_main. Full suites pass with
`regression_tests/run_all_suites.sh tmp/adamas_lazy_dom_stage1 4`: `152/152`
original and `36/36` combined. Scope: this is a resource-lane movement, not
green `s2b`/`s3b`; it moves the active frontier to default late
LLVM/function-emission. Decay trigger: the old dominator classifier again
selects `compute_dominance_info`, lazy dominance causes semantic regression, or
the mode selector stops selecting the late LLVM/function-emission residual.

[LM-ARCH-0K-DX-LOCAL-ONLY-CP-REFUTED|refuted 2026-07-02 {F:0.82 G:0.42 R:0.78}]:
A candidate production fix that made `CopyPropagationPass#apply_replacements`
return without applying dominance-dependent replacements is rejected. It did
not produce an acceptable movement of the selected 0k-DX lane: with
`STAGE1_COMPILER=tmp/adamas_cp_local_stage1 REQUIRE_CLASSIFICATION=1
TAIL_LINES=30 scripts/generated_stage_workers1_copyprop_phase_classifier.sh`,
the nested classifier failed before the current MIR optimization frontier:
`classification=workers1_copyprop_phase_classifier_build_failed`,
`subphase.classification=workers1_hir_resource_boundary`,
`nested.classification=pre_llvm_entry_failure`, `s2_hir_rc=139`,
`s2_mir_opt_rc=139`, and RSS stayed low (`306` MB, no memory kill). The edit
was reverted. Scope: this refutes the broad local-only/fail-closed policy as
the next 0k-DX fix. Future work should target a memory-safe dominance
construction/query or a narrower replacement-demand policy, not disabling all
cross-block/dominance-dependent CopyPropagation.

[LM-ARCH-0K-DX-LOCAL-SAFE-SUBSET-CP-REFUTED|refuted 2026-07-02 {F:0.83 G:0.44 R:0.78}]:
A narrower candidate that preserved only same-block/order-safe CopyPropagation
replacements and dropped the dominance-needed subset is also rejected. With
`STAGE1_COMPILER=tmp/adamas_cp_filter_stage1 REQUIRE_CLASSIFICATION=1
TAIL_LINES=30 scripts/generated_stage_workers1_copyprop_phase_classifier.sh`,
the generated compiler again failed before the current 0k-DX resource frontier:
`classification=workers1_copyprop_phase_classifier_build_failed`,
`subphase.classification=workers1_hir_resource_boundary`,
`nested.classification=pre_llvm_entry_failure`, `s2_hir_rc=139`,
`s2_mir_opt_rc=139`, and RSS stayed low (`306` MB, no memory kill). The edit
was reverted. Scope: this refutes dropping the dominance-needed replacement
subset as a bootstrap fix; the next viable direction is memory-safe dominance
construction/query or a much more specific dominance-dependent replacement
class with its own generated-stage proof.

[LM-ARCH-0K-DX-WORKERS1-COPYPROP-COMPUTE-DOMINANCE-RESOURCE-LANE|implemented 2026-07-02 {F:0.91 G:0.55 R:0.86}]:
`scripts/generated_stage_workers1_copyprop_dominator_classifier.sh` splits the
0k-DW workers=1 `CopyPropagationPass#apply_build_dominators` corridor by
inner substep. It uses new debug-only `ADAMAS_CP_DOM_THROUGH_STEP=<step>` with
`ADAMAS_CP_THROUGH_PHASE=apply_build_dominators`,
`ADAMAS_MIR_OPT_THROUGH_PASS=copy_propagation`,
`ADAMAS_STOP_AFTER_MIR_OPT`, and `ADAMAS_LLVM_WORKERS=1`. Fresh
`STAGE1_COMPILER=tmp/adamas_copyprop_dom_stage1 REQUIRE_CLASSIFICATION=1
REQUIRE_DOMINATOR=1 TAIL_LINES=30` evidence first re-confirms 0k-DW:
`phase.classification=select_workers1_copyprop_apply_build_dominators_resource_lane`,
full `apply_build_dominators` peak `4329` MB, memory-kill. Substep cutoffs are
clean for `build_def_maps=1175` MB and `skip_check=1174` MB. The selected
first bad substep is `compute_dominance_info=4364` MB with memory-kill
(`memory_kill_kb=4467872`), yielding
`classification=select_workers1_copyprop_dom_compute_dominance_info_resource_lane`.
Scope: this is a subowner selector, not a resource fix. It selects dominance
construction frequency/scope/representation or replacement-demand policy as the
next production target, while refuting `build_def_maps` and the skip predicate
as first resource owners for the current lane. Decay trigger: the dominator
classifier stops selecting `compute_dominance_info`, 0k-DW precondition stops
selecting `apply_build_dominators`, or CopyPropagation dominance construction
is redesigned.

[LM-ARCH-0K-DW-WORKERS1-COPYPROP-DOMINATORS-RESOURCE-LANE|implemented 2026-07-02 {F:0.90 G:0.57 R:0.86}]:
`scripts/generated_stage_workers1_copyprop_phase_classifier.sh` splits the
0k-DV workers=1 `CopyPropagationPass` lane by phase-level OS RSS cutoff. It
uses new debug-only `ADAMAS_CP_THROUGH_PHASE=<phase>` together with
`ADAMAS_MIR_OPT_THROUGH_PASS=copy_propagation` and
`ADAMAS_STOP_AFTER_MIR_OPT`. Fresh
`REQUIRE_CLASSIFICATION=1 REQUIRE_PHASE=1` evidence first re-confirms 0k-DV:
`pass.classification=select_workers1_mir_opt_copy_propagation_resource_lane`,
copy-propagation memory-kill `4345` MB. Phase cutoffs are clean for
`run_collect_state=1173` MB, `run_find_replacements=1174` MB, and
`apply_collect_affected_blocks=1175` MB. The broad `run_apply_replacements`
cutoff is high (`4264` MB), but the first inner high is
`apply_build_dominators=4237` MB with memory-kill; later apply phases remain
high (`apply_build_block_sizes=4196` MB, `apply_rewrite_blocks=4181` MB).
Scope: this is a phase-level selector, not a resource fix. It selects the
`apply_build_dominators` corridor (`build_def_maps`,
`can_skip_dominators_for_local_replacements?`, and/or
`compute_dominance_info`) as the next production target. Decay trigger: the
phase classifier stops selecting `apply_build_dominators`, an earlier CP phase
becomes high, the 0k-DV precondition decays, or CopyPropagation phase structure
changes.

[LM-ARCH-0K-DV-WORKERS1-MIR-OPT-COPY-PROP-RESOURCE-LANE|implemented 2026-07-02 {F:0.90 G:0.59 R:0.86}]:
`scripts/generated_stage_workers1_mir_opt_pass_classifier.sh` splits the 0k-DU
workers=1 MIR optimization resource lane by pass-level OS RSS cutoff. It uses
new debug-only `ADAMAS_MIR_OPT_THROUGH_PASS=<pass>` in
`MIR::OptimizationPipeline`, then stops after the whole serial MIR optimization
loop with `ADAMAS_STOP_AFTER_MIR_OPT`. Fresh
`REQUIRE_CLASSIFICATION=1 REQUIRE_PASS=1` evidence first re-confirms 0k-DU:
`subphase.classification=select_workers1_mir_optimization_resource_lane`,
stage1 control `334` MB, produced-s2 MIR bodies `1173` MB, produced-s2 MIR opt
memory-kill `4334` MB. Pass cutoffs are clean through `rc_elision`
(`constant_folding=1174` MB, `local_cse=1175` MB, `rc_elision=1174` MB), then
`copy_propagation` memory-kills at `4218` MB. Later cutoffs remain high:
`peephole=4166` MB, `lock_elision=4248` MB, `dce=4232` MB, and `dce_2=4334`
MB. Scope: this is a pass-level selector, not a resource fix. It selects
`CopyPropagationPass` state/resource growth as the next production target and
forbids further generic optimizer selectors unless this result decays. Decay
trigger: the pass classifier stops selecting copy propagation, an earlier pass
becomes high, the stage1 or MIR-bodies controls become high, or MIR pass order
/ optimizer routing changes.

[LM-ARCH-0K-DU-WORKERS1-MIR-OPT-RESOURCE-LANE|implemented 2026-07-02 {F:0.91 G:0.62 R:0.88}]:
`scripts/generated_stage_workers1_mir_subphase_classifier.sh` splits the 0k-DT
workers=1 HIR-to-MIR resource lane by OS RSS stop gates. It uses new
debug-only gates `ADAMAS_STOP_AFTER_MIR_TYPE_REGISTRATION`,
`ADAMAS_STOP_AFTER_MIR_PREPARE`, `ADAMAS_STOP_AFTER_MIR_BODIES`, and
`ADAMAS_STOP_AFTER_MIR_OPT`, plus `/usr/bin/time -l` and `scripts/run_safe.sh`.
Fresh `REQUIRE_CLASSIFICATION=1 REQUIRE_SUBPHASE=1` evidence reports
`classification=select_workers1_mir_optimization_resource_lane`. Controls:
`stage1_mir_peak_rss_mb=345`; produced-s2 workers=1 HIR, MIR type
registration, MIR prepare, and MIR bodies stop gates remain below threshold
(`1167`, `1170`, `1170`, and `1172` MB). The first high selected stop gate is
MIR optimization (`s2_mir_opt_peak_rss_mb=4149`,
`s2_mir_opt_memory_kill=1`); the full MIR stop gate also memory-kills
(`s2_mir_peak_rss_mb=4408`, `s2_mir_memory_kill=1`). Scope: this is a subphase
selector, not a resource fix. It selects workers=1 MIR optimization resource
growth as the next production resource target; HIR, type registration,
function-stub prepare, and body lowering are clean controls for this lane.
Decay trigger: the subphase classifier stops selecting MIR optimization, an
earlier MIR stop gate becomes high, stage1 control becomes high, or generated
MIR optimization routing changes.

[LM-ARCH-0K-DT-MODE-RESOURCE-LANE-SELECTOR|implemented 2026-07-02 {F:0.90 G:0.61 R:0.87}]:
`scripts/generated_stage_mode_resource_lane_classifier.sh` selects the next
mode-local `GeneratedStageExecution` resource lane using OS RSS stop-gate
evidence, not GC `non_gc`. Fresh
`REQUIRE_CLASSIFICATION=1 REQUIRE_LANE_SELECTION=1` evidence reports
`classification=select_workers1_hir_to_mir_resource_lane`. Controls:
`stage1_workers1_mir_peak_rss_mb=343`; produced-s2 HIR stop gates are clean in
both modes (`s2_default_hir_peak_rss_mb=1168`,
`s2_workers1_hir_peak_rss_mb=1167`); produced-s2 default MIR stop gate is clean
(`s2_default_mir_peak_rss_mb=1172`). The produced-s2 workers=1 MIR stop gate
fails by resource pressure (`s2_workers1_mir_rc=1`,
`s2_workers1_mir_peak_rss_mb=4105`, `s2_workers1_mir_memory_kill=1`). The
joined transaction report in the same classifier still records
`transaction.default_mode_boundary=reached_function_emission`,
`transaction.default_function_emission_rows=13`,
`transaction.workers1_mode_boundary=after_hir_final_before_mir_final`, and
both mode memory-kill flags. Scope: this is a lane selector, not a resource
fix. It selects workers=1 HIR-to-MIR resource growth as the next production
resource target and preserves default late LLVM/function-emission as residual
evidence. Decay trigger: the mode classifier stops selecting workers=1
HIR-to-MIR, the workers=1 MIR stop gate becomes clean below threshold, the
default MIR stop gate becomes high, transaction rows stop joining, or
generated-stage worker-mode semantics change.

[LM-ARCH-0K-DS-STARTUP-RESOURCE-BASELINE-CLASSIFIER|implemented 2026-07-02 {F:0.89 G:0.58 R:0.86}]:
`scripts/generated_stage_startup_resource_baseline_classifier.sh` resolves the
startup/process-baseline question opened by 0k-DR. It uses the debug-only
`ADAMAS_STOP_AFTER_COMPILE_ENTRY` gate plus existing parse/HIR/MIR stop gates
and `/usr/bin/time -l` OS RSS, not GC `non_gc`, as the owner signal. Fresh
`REQUIRE_CLASSIFICATION=1` evidence reports
`classification=llvm_or_later_resource_boundary`,
`stage1_compile_entry_peak_rss_mb=4`, `s2_compile_entry_peak_rss_mb=6`,
`s2_parse_peak_rss_mb=305`, `s2_hir_peak_rss_mb=1168`,
`s2_mir_peak_rss_mb=1171`, `nested.classification=llvm_entry_failure_after_lower_main`,
`nested.default_workers_memory_kill=1`, and
`nested.workers1_memory_kill=1`. Scope: this is a baseline classifier, not a
resource fix. It refutes startup, parse, HIR, and MIR retention as the first
actual OS RSS owner edge and also refutes 0k-DR GC `non_gc` as process-start RSS.
Next movement may re-enter late `GeneratedStageExecution` resource work only
with OS RSS / stop-gate evidence naming a mode-local owner edge. Decay trigger:
compile-entry or parse/HIR/MIR stop-gate RSS crosses the high threshold, nested
full generated-stage no longer memory-kills after lower_main, or stop-gate
semantics change.

[LM-ARCH-0K-DR-PRE-HIR-MEMORY-SPLIT-LANE-REFUTATION|implemented 2026-07-02 {F:0.90 G:0.58 R:0.86}]:
`scripts/generated_stage_pre_hir_memory_split_classifier.sh` consumes the L9
no-more-selector-chain gate for the default-lane memory surface. Fresh
`REQUIRE_SPLIT=1` evidence reports
`classification=pre_hir_pressure_compile_entry`, `terminal_status=terminal`,
`default_memory_rows=33`, `default_first_phase=cli.compile_entry`,
`default_first_high_owner=cli.compile`,
`default_first_high_non_gc=4323300568`, `default_max_phase=cli.compile_entry`,
and `default_last_phase=llvm.sequential_start`. Stage1 workers=1 control on the
same source remains clean: `stage1_control_rc=0`, `stage1_control_run_rc=0`,
stdout `42`, `stage1_memory_rows=35`, and `stage1_max_non_gc=0`. Scope: this is
a lane refutation, not a behavior fix. It shows the old 0k-DQ
`pre_function_pressure_hir_owned` result was late-row aliasing: produced-s2
non-GC pressure is already present at compile entry and does not select
parse/source/prelude/HIR/LLVM pipeline retention as a first owner edge. Next
movement must return to the SDD Current Execution Board, or open a separate
generated-stage startup/process-baseline problem card if resource pressure stays
active. Decay trigger: first high moves after compile entry, stage1-control
non-GC becomes high, `memory.phase` rows disappear, or generated-stage startup
initialization is redesigned.

[LM-ARCH-0K-DQ-PRE-FUNCTION-MEMORY-OWNER-SELECTOR|superseded-by-0k-DR 2026-07-02 {F:0.88 G:0.40 R:0.84}]:
Default-off `memory.phase` rows in `src/compiler/cli.cr` and
`src/compiler/mir/llvm_backend.cr` plus
`scripts/generated_stage_pre_function_memory_owner_classifier.sh` select the
owner boundary for the 0k-DP pre-existing non-GC pressure. Fresh
`REQUIRE_OWNER=1` evidence reports
`classification=pre_function_pressure_hir_owned`,
`default_first_phase=cli.hir_final`,
`default_first_non_gc=4314198280`,
`default_first_high_phase=cli.hir_final`,
`default_first_high_owner=cli.hir`,
`default_first_high_non_gc=4314198280`, and
`default_last_phase=llvm.sequential_start` with the same non-GC level. Stage1
workers=1 control on the same source reports `stage1_control_rc=0`,
`stage1_control_run_rc=0`, stdout `42`, `stage1_memory_rows=19`, and
`stage1_max_non_gc=0`. Scope: this is an owner selector, not a behavior fix. It
refutes LLVM output/session/function-emission ownership as the first default
edge for the current pressure; the next selector must move before HIR final and
distinguish parse/source/prelude/HIR-lowering retention from produced-stage
GC/non-GC accounting. The active SDD adds a no-more-selector-chain gate for this
surface: the L9 pre-HIR split is the only admitted next selector unless it
terminates in an owner-edge receipt, lane refutation, board pivot, explicit
impasse, or retirement/deletion of this report surface through a protecting
falsifier. Decay trigger: the owner classifier reports missing `memory.phase`
rows, high stage1-control non-GC, first high later than HIR final, or a changed
mode boundary. Supersession: 0k-DR added earlier rows and showed this was
late-row aliasing; keep DQ as historical evidence that LLVM function emission
was not the first owner, not as an active HIR-owner receipt.

[LM-ARCH-0K-DP-FUNCTION-EMISSION-MEMORY-DISCRIMINATOR|implemented 2026-07-02 {F:0.88 G:0.55 R:0.86}]:
`scripts/generated_stage_function_emission_memory_discriminator.sh` makes the
default-mode function-emission memory-shape discriminator executable. Fresh
`REQUIRE_CURRENT=1` evidence preserves the current transaction boundary:
`report.default_mode_boundary=reached_function_emission`,
`report.workers1_mode_boundary=after_hir_final_before_mir_final`,
`report.default_memory_kill=1`, and `last_index=80/150`, but classifies
`function_emission_preexisting_non_gc_pressure`. Produced s2 default snapshots
already have `default_first_non_gc=4353564448` at `idx=11/150`, unchanged at the
last snapshot, while incremental text/state counters are small
(`default_first_emit_raw_out=157628`, `default_last_emit_raw_out=239160`,
`default_first_func_state=7220`, `default_last_func_state=18452`). Stage1
workers=1 control on the same source compiles/runs with `stage1_first_non_gc=0`,
`stage1_last_non_gc=0`, `stage1_snapshot_rows=314`, and stdout `42`. Scope:
this refutes incremental function-output/state growth and external sinks as the
next default-lane resource edge; the next selector should classify pre-existing
produced-stage non-GC pressure before/at function emission. Decay trigger: a
fresh strict discriminator reports low first-snapshot non-GC, large incremental
output/state growth, missing snapshots, or a changed mode boundary.

[LM-ARCH-0K-DO-EXTERNAL-SINK-PREFLIGHT-REFUTED|design-refuted 2026-07-02 {F:0.89 G:0.58 R:0.88}]:
Slice 0k-DO selects the default-mode LLVM function-emission sink boundary as a
`PhaseAuthority` / `GeneratedStageExecution` receipt, but the direct
external-sink behavior slice is refuted before landing. New executable guard:
`REQUIRE_REFUTED=1 scripts/generated_stage_external_sink_preflight.sh`. The
guard copies `src/`, injects `llvm_gen.generate(file_io)` behind
`ADAMAS_LLVM_EXTERNAL_SINK_PROBE` only in the temp copy, builds both temp stage1
and temp generated s2 from that copy, and cleans temp artifacts by default.
Fresh evidence reports `host_compile_rc=0`, `host_run_rc=0`, `host_stdout=42`,
`host_ll_size>0`, `s2_build_rc=0`, and
`classification=external_sink_preflight_refuted_empty_ir`. The generated-stage
part reports
`report.default_mode_boundary=after_output_start_before_llvm_generate`,
`report.join_status=phase_local_only`,
`report.default_llvm_generate_phase_rows=0`, `report.default_memory_kill=0`,
`report.output_commit_record=binary_compile_rc:1`,
`default_workers_ll_size=0`, and `default_workers_missing_main=1`. Scope:
external `LLVMIRGenerator` sinks remain rejected as a resource fix until a
future slice owns and falsifies produced-stage external-sink entrypoint/main
emission; otherwise the default lane must choose another function-emission
resource edge. The workers=1 residual remains
`after_hir_final_before_mir_final`. Decay trigger: a future generated-stage
external-sink guard emits non-empty LLVM IR with `_main`, joins
`llvm.generate_phase` rows, and preserves output/link semantics.

[LM-ARCH-0K-DN-WORKER-MODE-BOUNDARY-SPLIT|implemented 2026-07-02 {F:0.91 G:0.64 R:0.90}]:
The 0k-DM workers=1 missing function-emission rows are now classified from
existing per-mode `GSETX` rows instead of treated as an ambiguous observability
gap. `scripts/generated_stage_execution_transaction_report.sh` adds
`REQUIRE_WORKER_MODE_BOUNDARY=1`, mode-local row counts for HIR final, MIR
final, output start, LLVM generate, and function emission, plus
`resource.default_mode_boundary` / `resource.workers1_mode_boundary`. Evidence:
`STAGE1_COMPILER=/tmp/adamas_worker_boundary_stage1 TAIL_LINES=30 REQUIRE_JOINED=1 REQUIRE_POST_CU_RESOURCE=1 REQUIRE_RESOURCE_PHASE_SPLIT=1 REQUIRE_FUNCTION_EMISSION_SPLIT=1 REQUIRE_WORKER_MODE_BOUNDARY=1 scripts/generated_stage_execution_transaction_report.sh`
exits 0 with `final_classification=abort_resource_after_lower_main`,
`resource.default_mode_boundary=reached_function_emission`,
`resource.workers1_mode_boundary=after_hir_final_before_mir_final`,
`runtime.default_mir_final_rows=1`, `runtime.workers1_mir_final_rows=0`,
`runtime.default_llvm_generate_phase_rows=2`,
`runtime.workers1_llvm_generate_phase_rows=0`,
`runtime.default_function_emission_phase_rows=13`, and
`runtime.workers1_function_emission_phase_rows=0`. Scope: behavior-neutral
report/classifier movement only. It proves the current B4/L6 residual is
mode-divergent: default workers reach LLVM function emission, while workers=1
dies after HIR finalization and before MIR finalization. A later fix must not
claim both-mode bootstrap progress from a single-mode edge. Decay trigger: a
fresh strict report joins workers=1 MIR final rows, reaches workers=1 function
emission, or changes either mode boundary.

[LM-ARCH-0K-DM-FUNCTION-EMISSION-SUBPHASE-SPLIT|implemented 2026-07-02 {F:0.91 G:0.63 R:0.90}]:
The 0k-DL `during_function_emission` resource corridor is now split by
default-off `llvm.function_emission_phase` rows. `LLVMIRGenerator#generate`
logs dispatch rows, `emit_functions_sequential` logs coarse progress every 10
functions, and `emit_functions_parallel` logs plan/fork/parent/wait/merge,
cleanup, and fallback rows. The transaction report adds
`REQUIRE_FUNCTION_EMISSION_SPLIT=1` plus mode-aware default/workers=1 row counts.
Evidence:
`STAGE1_COMPILER=/tmp/adamas_function_phase_stage1 TAIL_LINES=30 REQUIRE_JOINED=1 REQUIRE_POST_CU_RESOURCE=1 REQUIRE_RESOURCE_PHASE_SPLIT=1 REQUIRE_FUNCTION_EMISSION_SPLIT=1 scripts/generated_stage_execution_transaction_report.sh`
exits 0 with `final_classification=abort_resource_after_lower_main`,
`resource.function_emission_split=during_sequential_function_emit`,
`resource.function_emission_last_phase=sequential_progress`,
`resource.function_emission_last_index=80`,
`resource.function_emission_last_total=150`,
`resource.function_emission_mode_join_status=default_only`,
`runtime.function_emission_phase_rows=13`,
`runtime.default_function_emission_phase_rows=13`, and
`runtime.workers1_function_emission_phase_rows=0`. Scope: behavior-neutral
evidence only. The default worker mode reaches the known parallel rand fallback
and then dies during sequential function emission around function 80/150; the
workers=1 mode still reports after-`lower_main` memory kill through classifier
logs but has no joined function-emission runtime rows. This does not admit
worker policy, memory budget, rand fallback, output, tail, metadata, or backend
semantic changes. Decay trigger: a fresh strict report reaches
`sequential_done`, joins workers=1 function-emission rows, or changes the
resource phase away from `during_sequential_function_emit`.

[LM-ARCH-0K-DL-LLVM-GENERATE-PHASE-SPLIT|implemented 2026-07-02 {F:0.91 G:0.64 R:0.90}]:
The post-0k-DK `PhaseAuthority` / `GeneratedStageExecution` resource corridor
is now split by default-off LLVM generate phase rows. `LLVMIRGenerator#generate`
emits `llvm.generate_phase` rows only under the existing `GSETX` transaction,
and `scripts/generated_stage_execution_transaction_report.sh` adds
`REQUIRE_RESOURCE_PHASE_SPLIT=1` plus
`resource.llvm_generate_last_phase`,
`resource.llvm_generate_last_out_pos`, and
`resource.llvm_generate_phase_split`. Evidence:
`STAGE1_COMPILER=/tmp/adamas_phase_stage1 TAIL_LINES=30 REQUIRE_JOINED=1 REQUIRE_POST_CU_RESOURCE=1 REQUIRE_RESOURCE_PHASE_SPLIT=1 scripts/generated_stage_execution_transaction_report.sh`
exits 0 with `final_classification=abort_resource_after_lower_main`,
`join_status=joined`, `resource.default_memory_kill=1`,
`resource.workers1_memory_kill=1`,
`output.commit_record=llvm_ir_started_without_commit:file`,
`resource.llvm_generate_last_phase=function_emission_start`,
`resource.llvm_generate_last_out_pos=147350`,
`resource.llvm_generate_phase_split=during_function_emission`, and
`runtime.llvm_generate_phase_rows=2`. Scope: behavior-neutral evidence only.
This refutes tail/stub/metadata/type-name/DWARF/final `IO::Memory#to_s` as the
first observed boundary for the current post-`lower_main` resource residual. It
does not admit worker-policy, memory-budget, output-file, tail-stub, rand
fallback, or backend semantic changes. Decay trigger: a fresh current-source
transaction report with `REQUIRE_RESOURCE_PHASE_SPLIT=1` stops reporting
`during_function_emission`, or the generated-stage gate reaches
`function_emission_done`.

[LM-ARCH-0K-DK-POSTCU-RESOURCE-TX-CLASSIFIED|implemented 2026-07-02 {F:0.90 G:0.62 R:0.90}]:
After 0k-CU, the generated-stage execution transaction report now classifies the
new joined resource residual directly. The old report treated
`b4.classification=llvm_entry_failure_after_lower_main` as
`abort_joined_unclassified`; the updated
`scripts/generated_stage_execution_transaction_report.sh` recognizes joined
post-`lower_main` resource kills as
`final_classification=abort_resource_after_lower_main` and adds
`REQUIRE_POST_CU_RESOURCE=1`. Evidence:
`STAGE1_COMPILER=/tmp/adamas_postcu_stage1 TAIL_LINES=30 REQUIRE_JOINED=1 REQUIRE_POST_CU_RESOURCE=1 scripts/generated_stage_execution_transaction_report.sh`
exits 0 with `join_status=joined`, `resource.default_memory_kill=1`,
`resource.workers1_memory_kill=1`, `resource.workers1_exit139=0`,
`output.commit_record=llvm_ir_started_without_commit:file`,
`tail.semantic_vs_input_split=tail_not_reached_after_output_start`, and
`admission_status=rejected_no_root_sized_consumer`. Scope: behavior-neutral
classifier/receipt movement only. It does not admit memory-budget increases,
forced worker policy, rand fallback patches, output/tail/backend behavior, or a
green `s2b`/`s3b` claim. Decay trigger: the transaction report stops joining
runtime rows or the post-0k-CU residual no longer reports resource kills after
`lower_main`.

[LM-ARCH-0K-CU-BLOCK-CALL-RETURN-CONTRACT-IMPLEMENTED|implemented 2026-07-02 {F:0.92 G:0.60 R:0.91}]:
Slice 0k-CU implements the HIR `BlockCallReturnContract` for assigned-tail
yield-passthrough helpers. The wrapper materialization key gains a block-return
dimension only when the source helper is proven to return a local assigned from
`yield` and the callsite has a non-nil/non-void block return; ordinary untyped
block helpers remain governed by the existing argument-shape path. Evidence:
`crystal build src/adamas.cr -o /tmp/adamas_0kcu_stage1 --error-trace` exits 0;
`regression_tests/block_call_return_contract_assigned_tail_no_prelude.sh /tmp/adamas_0kcu_stage1`
passes; `REQUIRE_CURRENT_CU_CONTRACT=1 scripts/hir_block_return_shape_census.sh`
reports `classification=current_0k_cu_block_call_return_contract_applied`,
`candidate_multi_shape_keys=207`, `candidate_additional_return_shape_bodies=224`,
`assigned_tail_multi_shape_keys=0`, `timed_cp_phase_keys=5`,
`timed_cp_phase_nil_value_coexist_keys=0`,
`timed_cp_phase_assigned_tail_passthrough_keys=1`, and
`timed_cp_phase_set_return_keys=1`. The generated-stage pressure gate moved
past the old O1 `affected_block_ids` / `Set(UInt32)#includes?` frontier:
`STAGE1_COMPILER=/tmp/adamas_0kcu_stage1 REQUIRE_CURRENT_O1=1 scripts/mir_optimization_container_frontier_classifier.sh`
exits at the expected non-current boundary with
`b4_classification=llvm_entry_failure_after_lower_main` and `workers1_exit139=0`.
A kept B4 run classifies the residual as `llvm_entry_failure_after_lower_main`:
both worker modes reach `pass3 after lower_main call` and then RSS-kill near
4.3-4.5GB, with the default worker mode still showing the parallel rand
fallback. Full regression suites pass `152/152 + 36/36`. Scope: this is a
frontier move and consumes the current breakglass lane; it is not green
`s2b`/`s3b`. Decay trigger: the post-fix CP contract gate stops reporting the
timed phase split, or a fresh generated-stage gate reintroduces the
`affected_block_ids` Set crash.

[LM-ARCH-0K-DJ-BLOCK-CALL-RETURN-CONTRACT-READMITTED|design-sealed 2026-07-02 {F:0.90 G:0.66 R:0.90}]:
After Slice 0k-DI, the active generated-stage pressure gate was remeasured and
the B4/O1 `bootstrap-emergency-with-ledger` lane is re-admitted only through the
existing 0k-CU `BlockCallReturnContract` receipt. Fresh
`REQUIRE_CURRENT_CP_BROAD=1 scripts/hir_block_return_shape_census.sh` evidence
still rejects broad untyped-`&` return-shape specialization:
`candidate_multi_shape_keys=208` and `candidate_additional_return_shape_bodies=228`.
The same run preserves the root-sized assigned-tail discriminator:
`assigned_tail_multi_shape_keys=1`, `assigned_tail_additional_return_shape_bodies=4`,
and `timed_cp_phase_assigned_tail_passthrough_keys=1`. Scope: this admits one
CAUTION-tier production slice that makes assigned-tail yield-passthrough block
wrappers return-shape dependent through a HIR-owned contract. It does not admit
CopyPropagation guards, `timed_cp_phase` special-cases, backend block-return
rescue, broad return-shape specialization, `BlockOwner` rollback, or a green
`s2b`/`s3b` claim. Decay trigger: the CP census no longer shows a root-sized
assigned-tail discriminator, or O1/B4 evidence stops pointing at the
`affected_block_ids` block-return wrapper path.

[LM-ARCH-0K-DI-MATERIALIZATION-SCOPE-ENTRY-IMPLEMENTED|implemented 2026-07-02 {F:0.91 G:0.62 R:0.90}]:
The Slice 0k-DH materialization scope-entry contract is implemented for the
instance materialization path. The path now applies `merged_params` and
`namespace_override` in an explicit scope-entry block after
`CallMaterializationTransaction` logging and before arity repair /
`lower_method`, so the old authority edge is no longer hidden inside nested
`with_isolated_type_param_map` / `with_namespace_override_or_clear` helpers. The
temp-source `scripts/generated_stage_lower_method_terminal_classifier.sh` was
updated to instrument the explicit shape. Evidence:
`STAGE1_COMPILER=/tmp/adamas_scope_entry_stage1 REQUIRE_REACHED=1 SAMPLES=8 scripts/generated_stage_lower_method_terminal_classifier.sh`
reports `completion_classifier_classification=reached_tx_and_emit`,
`method_call_rows=266`, `precall_rows=1330`, `method_entry_rows=356`,
`method_name_rows=310`, `method_exit_rows=666`, `residual_rows=3`,
`terminal_cause_kinds=1`, `terminal_groups=2`,
`terminal_root_sized_groups=2`,
`selected_cause=lower_method_terminal_abstract_method`, `selected_rows=3`, and
`classification=eligible_lower_method_terminal_edge`. This consumes/refutes the
old selected six-row `lower_method_terminal_no_exact_after_tx_no_call` bucket:
residual rows now reach the full pre-call chain and `[MAT_METHOD_CALL]`, then
terminate as abstract methods. Scope: focused `MaterializationTransaction`
authority-edge migration only; no backend rescue, no sampled method patch, no
requested-name forcing, no ambient-map or `NamedTuple`/`Tuple` policy change, no
`BlockOwner` rollback, and no green `s2b`/`s3b` claim. Decay trigger: a later
generated-stage classifier reintroduces after-tx-only rows, `[MAT_EMIT]`
reachability regresses, or the Current Execution Board selects a different owner
spine for exact body availability.

[LM-ARCH-0K-DH-MATERIALIZATION-SCOPE-ENTRY-RECEIPT|design-sealed 2026-07-02 {F:0.86 G:0.66 R:0.86}]:
Slice 0k-DH adds the pre-code receipt required by 0k-DG in
`docs/compiler_architecture_sdd.md`. The selected old authority edge is the
implicit body-lowering scope entry after `CallMaterializationTransaction`
logging: `with_isolated_type_param_map` and
`with_namespace_override_or_clear` are still responsible for reaching arity
repair / `lower_method`, but 0k-DG selected rows reach `after_tx` and do not
reach `inside_type_params`. The admitted next production movement is therefore
a `contract-owner-migration` where existing `CallMaterializationTransaction`
plus `SemanticStateScope` own the materialization scope-entry contract. Focused
DoD: remove or root-size the six-row `after_tx_no_call` class while preserving
generated-stage `[MAT_EMIT]` reachability and abstract-method controls. If that
cannot be done, this `MaterializationTransaction` row is not root-sized enough
and the next movement must return to the Current Execution Board. Scope:
docs/design receipt only; no production behavior changed and no green
`s2b`/`s3b` claim.

[LM-ARCH-0K-DG-PRECALL-AFTER-TX-BOUNDARY|implemented 2026-07-02 {F:0.92 G:0.67 R:0.90}]:
Slice 0k-DG extends the temp-source
`scripts/generated_stage_lower_method_terminal_classifier.sh` with
`[MAT_PRECALL]` checkpoints around the exact region between
`CallMaterializationTransaction` logging and the actual `lower_method` call:
`after_tx`, `inside_type_params`, `inside_namespace`, `before_arity`, and
`after_arity`. Fresh evidence using
`REQUIRE_REACHED=1 SAMPLES=8 scripts/generated_stage_lower_method_terminal_classifier.sh`
reports `completion_classifier_classification=reached_tx_and_emit`,
`method_call_rows=242`, `precall_rows=1628`, `method_entry_rows=338`,
`method_name_rows=285`, `method_exit_rows=623`, `residual_rows=14`,
`terminal_cause_kinds=4`, `terminal_groups=12`, and
`terminal_root_sized_groups=12`. The selected broad class is
`lower_method_terminal_no_exact_after_tx_no_call` (6 rows): sampled
`Array(String)`, `Slice(UInt8)`, and `Atomic(Bool)` rows repeatedly log
`after_tx` but do not reach `inside_type_params`, while abstract controls such
as `IO#read` and `String::Builder#write` traverse all pre-call checkpoints and
join to `[MAT_METHOD_CALL]` rows. This refutes namespace override and arity
repair as the first boundary for the selected six rows. Scope:
read-only/temp-source classifier only; no production compiler behavior changed
and no green `s2b`/`s3b` claim. The next valid movement must not be another
generic pre-call marker. It must name the owner edge at the scoped
type-param/block-yield boundary after transaction logging (for example a
`MaterializationTransaction` scoped-isolation contract or a block-yield owner
contract), or refute this row and return to the Current Execution Board.
Rejected moves remain backend rescue, forwarders, sampled-method patches,
requested-name forcing, broad rendering/ambient-map policy, `BlockOwner`
rollback, and production `lower_method` trace-object plumbing. Decay trigger:
a root-sized owner-edge receipt supersedes this after-tx boundary, or newer
generated-stage evidence refutes the after-tx-only rows.

[LM-ARCH-0K-DF-MATERIALIZATION-PRECALL-GAP|implemented 2026-07-02 {F:0.92 G:0.69 R:0.90}]:
Slice 0k-DF adds a temp-only `[MAT_METHOD_CALL]` probe at the
`instance_class_info_lower_method` call site in the copied source used by
`scripts/generated_stage_lower_method_terminal_classifier.sh`. Fresh evidence
using `REQUIRE_REACHED=1 SAMPLES=8 scripts/generated_stage_lower_method_terminal_classifier.sh`
reports `completion_classifier_classification=reached_tx_and_emit`,
`method_call_rows=242`, `method_entry_rows=338`, `method_name_rows=285`,
`method_exit_rows=623`, `residual_rows=14`, `terminal_cause_kinds=4`,
`terminal_groups=12`, and `terminal_root_sized_groups=12`. The broad class is
now `lower_method_terminal_no_exact_no_call` (6 rows); its samples have
`call_body_rows=0` and `call_requested_rows=0`, while abstract controls such as
`IO#read` and `String::Builder#write` have matching call rows. This proves the
coarse producer path can reach transaction/completion logging as
`instance_class_info_lower_method` without reaching the actual `lower_method`
call for those exact symbols. Scope: read-only/temp-source classifier only; no
production behavior changed and no green `s2b`/`s3b` claim. The next valid
movement is to split the pre-call control gap between transaction logging and
`lower_method` invocation: type-param isolation, namespace override, arity
fallback, or another pre-call edge. Rejected moves remain backend rescue,
sampled-method patches, requested-name forcing, forwarders, broad rendering or
ambient-map policy, `BlockOwner` rollback, and production `lower_method`
trace-object plumbing. Decay trigger: a finer generated-stage classifier
selects a root-sized pre-call sub-branch or newer evidence refutes the
zero-call rows.

[LM-ARCH-0K-DE-NO-EXACT-LOWER-METHOD-SPLIT|implemented 2026-07-02 {F:0.91 G:0.70 R:0.90}]:
Slice 0k-DE refines the 0k-DD temp-source classifier instead of changing
production compiler behavior. `scripts/generated_stage_lower_method_terminal_classifier.sh`
now injects `[MAT_METHOD_ENTRY]`, `[MAT_METHOD_NAME]`, and a final
`completed_method` terminal row into copied source only. This corrects the
previous proxy weakness where `created_hir_function` was treated like a
terminal state. Fresh evidence using
`REQUIRE_REACHED=1 SAMPLES=8 scripts/generated_stage_lower_method_terminal_classifier.sh`
reports `completion_classifier_classification=reached_tx_and_emit`,
`method_entry_rows=338`, `method_name_rows=285`, `method_exit_rows=623`,
`residual_rows=14`, `terminal_cause_kinds=4`, `terminal_groups=12`, and
`terminal_root_sized_groups=12`. The buckets are
`lower_method_terminal_no_exact_no_entry` (6 rows),
`lower_method_terminal_abstract_method` (4 rows),
`lower_method_terminal_no_exact_matching_full_name_without_exit` (3 rows), and
`lower_method_terminal_completed_method` (1 row). Scope: read-only/temp-source
classifier only; no production behavior changed and no green `s2b`/`s3b`
claim. The next valid movement is to split the still-broad
`no_exact_no_entry` class by the actual lower_method call input, selected
DefNode/source owner, and requested/target/body symbol relation. Rejected moves
remain backend rescue, sampled-method patches, requested-name forcing,
forwarders, broad rendering/ambient-map policy, `BlockOwner` rollback, and
production `lower_method` trace-object plumbing. Decay trigger: a finer
generated-stage classifier selects a root-sized `no_exact_no_entry` sub-branch
or newer evidence refutes these entry/name/terminal buckets.

[LM-ARCH-0K-DD-LOWER-METHOD-TERMINAL-SPLIT|implemented 2026-07-02 {F:0.91 G:0.72 R:0.90}]:
Slice 0k-DD adds `scripts/generated_stage_lower_method_terminal_classifier.sh`,
a temp-source classifier for the 0k-DC residual. The script copies `src/`,
injects default-off `[MAT_METHOD_EXIT]` probes only into the temporary
`ast_to_hir.cr`, builds a generated probe compiler by running current stage1 on
that temporary source, then runs the existing created-body completion
classifier with `GENERATED_S2=<probe>`. This avoids the refuted production
`lower_method` trace-object path and keeps tracked compiler source behavior
unchanged. Fresh evidence using
`REQUIRE_REACHED=1 SAMPLES=8 scripts/generated_stage_lower_method_terminal_classifier.sh`
reports `completion_classifier_classification=reached_tx_and_emit`,
`method_exit_rows=338`, `residual_rows=14`, `terminal_cause_kinds=3`,
`terminal_groups=9`, and `terminal_root_sized_groups=9`. The terminal buckets
are `lower_method_terminal_no_exact_method_exit` (9 rows),
`lower_method_terminal_abstract_method` (4 rows), and
`lower_method_terminal_created_hir_function` (1 row); classification is
`rejected_mixed_lower_method_terminals`. Scope: read-only/temp-source
classifier only; no compiler production behavior changed and no green
`s2b`/`s3b` claim. The next valid movement must pick and split one terminal
class, with the broad `no_exact_method_exit` class the likely highest-value
target, by source identity / resolved DefNode / full-name derivation. Rejected
moves remain sampled method patches, backend rescue, forwarders,
requested-name forcing, broad rendering/ambient-map policy, `BlockOwner`
rollback, and production trace-object plumbing through `lower_method`. Decay
trigger: a finer generated-stage classifier selects a root-sized
`lower_method` terminal sub-branch, or newer evidence refutes these terminal
buckets.

[LM-ARCH-0K-DC-MATERIALIZATION-PRODUCER-PATH-BROAD|implemented 2026-07-02 {F:0.91 G:0.72 R:0.90}]:
Slice 0k-DC splits the 0k-DB terminal cause at the outer HIR producer branch
without adding a new result or consumer surface. `src/compiler/hir/ast_to_hir.cr`
now enriches the existing default-off `[MAT_DONE]` row with `producer_path`,
`created_symbol_relation`, and capped `created_symbols`; the generated-stage
classifier consumes those fields. Fresh current-source evidence using
`STAGE1_COMPILER=/tmp/adamas_producer_path_stage1 SAMPLES=8 scripts/generated_stage_created_body_visibility_classifier.sh`
reports `classifier_classification=reached_tx_and_emit`,
`mat_tx_rows=717`, `mat_done_rows=787`, `mat_emit_rows=173`,
`created_body_missing_completion_rows=14`, `completion_cause_kinds=1`,
`selected_cause=attempt_lowering_returned_no_hir_function__producer_instance_class_info_lower_method__created_none`,
`selected_rows=14`, `classification=rejected_completion_class_too_wide`, 9
root-sized groups, and zero malformed/unjoined rows. The result is a verified
refutation of the outer materialization branch as the missing discriminator:
every residual goes through `instance_class_info_lower_method`, creates no HIR
function, and still has no exact body. A deeper optional `lower_method`
terminal trace object was preflight-refuted during the slice because it caused
generated-stage runs to stop before backend emission (`classifier_classification=tx_only_no_emit`,
`mat_tx_rows=2`, `mat_done_rows=1`, `mat_emit_rows=0`) and was reverted. Scope:
behavior-neutral default-off ledger/classifier only; no production compiler
behavior changed and no green `s2b`/`s3b` claim. The next valid movement must
split the `instance_class_info_lower_method` / `created_none` class inside or
immediately around `lower_method` using a self-host-safe producer observation
(for example a temp-source classifier), and must stop if that class remains
broad. Rejected moves remain backend undefined-extern rescue, forwarders,
requested-name forcing, sampled method patches, broad `NamedTuple`/`Tuple`
rendering, global ambient-map policy, `BlockOwner` rollback, and optional
trace-object plumbing through `lower_method`. Decay trigger: a finer
generated-stage classifier selects a root-sized `lower_method` terminal branch,
or newer evidence refutes this producer-path shape.

[LM-ARCH-0K-DB-MATERIALIZATION-TERMINAL-DONE|implemented 2026-07-02 {F:0.91 G:0.72 R:0.90}]:
Slice 0k-DB refines 0k-DA by adding terminal-status evidence to the existing
default-off `[MAT_DONE]` completion row instead of introducing a new result
storage surface. `src/compiler/hir/ast_to_hir.cr` now reports `status`,
`reason`, and `created_function_count` after each materialization attempt, and
`scripts/generated_stage_created_body_visibility_classifier.sh` classifies
those fields. Fresh current-source evidence using
`STAGE1_COMPILER=/tmp/adamas_mat_done_terminal_stage1 SAMPLES=8 scripts/generated_stage_created_body_visibility_classifier.sh`
reports `classifier_classification=reached_tx_and_emit`,
`mat_tx_rows=735`, `mat_done_rows=805`, `mat_emit_rows=173`,
`created_body_missing_completion_rows=14`,
`completion_cause_kinds=1`,
`selected_cause=attempt_lowering_returned_no_hir_function`,
`selected_rows=14`, `classification=rejected_completion_class_too_wide`, 9
completion groups, and zero malformed/unjoined rows. This verifies the
terminal refinement is self-host safe at the generated-stage classifier level
and proves the residual class is still too broad for behavior changes.
Refuted during preflight: a separate `MaterializationAttemptResult` row/storage
surface and a HIR-to-MIR consumer ledger caused generated-stage tx-only runs
with `mat_emit_rows=0` before backend emission, so they are not admitted as the
next architecture move. The next valid movement must split
`attempt_lowering_returned_no_hir_function` at the HIR producer boundary that
returns from lowering without registering the exact materialized function, or
return to the Current Execution Board. Rejected moves remain backend
undefined-extern rescue, forwarders, requested-name forcing, sampled method
patches, broad `NamedTuple`/`Tuple` rendering, global ambient-map policy, and
`BlockOwner` rollback. Scope: default-off ledger/classifier only; no compiler
production behavior changed and no green `s2b`/`s3b` claim.

[LM-ARCH-0K-DA-MATERIALIZATION-COMPLETION-BROAD|implemented 2026-07-02 {F:0.90 G:0.72 R:0.90}]:
Slice 0k-DA adds the executable post-lowering completion fact required by
0k-CZ. `src/compiler/hir/ast_to_hir.cr` emits default-off `[MAT_DONE]` rows
under `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER` after the materialization
attempt finishes, and
`scripts/generated_stage_created_body_visibility_classifier.sh` now joins
`[MAT_TX]`, `[MAT_DONE]`, and `[MAT_EMIT]`. Fresh current-source evidence using
`STAGE1_COMPILER=/tmp/adamas_mat_done_stage1 SAMPLES=8 scripts/generated_stage_created_body_visibility_classifier.sh`
reports `classifier_classification=reached_tx_and_emit`,
`mat_tx_rows=724`, `mat_done_rows=794`,
`created_body_missing_completion_rows=14`,
`completion_cause_kinds=1`,
`selected_cause=lowering_completed_without_hir_function`,
`selected_rows=14`, `classification=rejected_completion_class_too_wide`, 9
completion groups, `missing_completion_rows=0`, and zero malformed/unjoined
ledger rows. This confirms the current residual survives post-lowering
completion and is not merely a missing completion observation. It is still too
broad for a behavior patch. The next admitted movement must turn the
materialization attempt into an owned terminal-status contract such as
`MaterializationAttemptResult`, then split the broad
`lowering_completed_without_hir_function` class by named terminal reason before
any consumer or emitted behavior changes. Rejected moves remain backend
undefined-extern rescue, forwarders, requested-name forcing, sampled method
patches, broad `NamedTuple`/`Tuple` rendering, global ambient-map policy, and
`BlockOwner` rollback. Scope: default-off ledger/classifier only; no compiler
production behavior changed and no green `s2b`/`s3b` claim.

[LM-ARCH-0K-CZ-PRELOWERING-VISIBILITY-CORRECTION|design-sealed 2026-07-02 {F:0.90 G:0.72 R:0.90}]:
Slice 0k-CZ is a docs-only hostile correction to the active 0k-CY
interpretation. Direct source inspection of
`src/compiler/hir/ast_to_hir.cr` shows the 0k-CY `[MAT_TX]` body visibility
fields are computed and logged after
`@function_lowering_states[materialized_name] = FunctionLoweringState::InProgress`
but before `lower_method(...)` creates or completes the materialized body; the
`ensure` block updates the lowering state to `Completed` or deletes it only
after the lowering attempt finishes. Therefore the current
`state_in_progress_without_hir_function` classifier output is a pre-lowering
visibility fact, not a proven root cause and not evidence that lowering
completed without creating a function. The retained verified fact is narrower:
`materialization_action=created_body` is only a lowering-state label and must
not be treated as body-present evidence. The next admitted executable movement
is still read-only/behavior-neutral under `MaterializationTransaction`, but it
must measure post-lowering completion: add a completion ledger fact after the
materialization attempt finishes and join it with `[MAT_TX]` / `[MAT_EMIT]`.
Only that completion fact may split true body absence, HIR-to-MIR visibility,
backend emission visibility, or missing completion observation. Rejected next
moves remain backend lookup/emission fixes, undefined-extern rescue,
forwarders, requested-name forcing, sampled method patches, broad
`NamedTuple`/`Tuple` rendering, global ambient-map policy, and `BlockOwner`
rollback. Scope: docs/control-plane correction only; no compiler production
behavior changed and no green `s2b`/`s3b` claim. Decay trigger: a
post-lowering completion ledger/classifier supersedes the pre-lowering 0k-CY
evidence, or newer generated-stage evidence refutes the exact-body residual.

[LM-ARCH-0K-CY-INPROGRESS-WITHOUT-HIR-FUNCTION|design-sealed 2026-07-02 {F:0.87 G:0.70 R:0.87}]:
Slice 0k-CY refines 0k-CX with self-applying body lifecycle and backend
visibility facts in `[MAT_TX]` / `[MAT_EMIT]`, plus the read-only classifier
`scripts/generated_stage_created_body_visibility_classifier.sh`. Fresh
current-source stage1 evidence:
`crystal build src/adamas.cr -o /tmp/adamas_visibility_ledger_stage1 --error-trace`
succeeded, and
`STAGE1_COMPILER=/tmp/adamas_visibility_ledger_stage1 SAMPLES=8 scripts/generated_stage_created_body_visibility_classifier.sh`
reports `classifier_classification=reached_tx_and_emit`,
`created_body_missing_visibility_rows=14`, `visibility_cause_kinds=1`,
`selected_cause=state_in_progress_without_hir_function`, `selected_rows=14`,
`classification=rejected_visibility_class_too_wide`, 9 visibility groups, and
`missing_visibility_field_rows=0`. The residual samples all show
`materialization_action=created_body`, but the stronger facts are
`body_function_present=0`, `body_has_body=0`, `body_state=in_progress`,
`lookup=0`, `module=0`, `plan=0`, `emitted_present=0`, and `undefined=1`.
This corrects the prior 0k-CX reading: `created_body` is only an in-progress
lowering-state label for this residual, not proof that a HIR function body was
present. Scope: behavior-neutral ledger fields plus a read-only classifier; no
compiler production behavior changed and no green `s2b`/`s3b` claim. The next
executable movement must split the HIR producer boundary that can leave exact
`body_symbol` rows with `function_state=InProgress` while
`@module.has_function?=false` (state set before `create_function`, symbol-key
mismatch, early return/reentrant defer, or another named transition), and must
stop if the class remains broad. Rejected next moves: backend lookup/emission
fixes, undefined-extern rescue, forwarders, requested-name forcing, sampled
Array/Slice/IO/Atomic/String::Builder/Int32 patches, broad `NamedTuple`/`Tuple`
rendering, global ambient-map policy, and `BlockOwner` rollback. Decay trigger:
a post-lowering completion classifier supersedes this pre-lowering visibility
fact, the exact residual disappears, or newer generated-stage transaction
evidence refutes the `state_in_progress_without_hir_function` shape.

[LM-ARCH-0K-CX-CREATED-BODY-BACKEND-MISSING|design-sealed 2026-07-02 {F:0.86 G:0.70 R:0.86}]:
Slice 0k-CX implements the read-only exact-body lifecycle classifier selected
by 0k-CW as `scripts/generated_stage_exact_body_availability_classifier.sh`.
Fresh current-source stage1 evidence:
`crystal build src/adamas.cr -o /tmp/adamas_exact_body_classifier_stage1 --error-trace`
succeeded, and
`STAGE1_COMPILER=/tmp/adamas_exact_body_classifier_stage1 SAMPLES=8 scripts/generated_stage_exact_body_availability_classifier.sh`
reports `classifier_classification=reached_tx_and_emit`,
`residual_exact_missing_body_rows=14`,
`residual_body_lifecycle_cause_kinds=1`,
`selected_cause=created_body_backend_missing`, `selected_rows=14`,
`classification=rejected_body_lifecycle_class_too_wide`, and 9 lifecycle
groups. This refutes "HIR materializer never created the bodies" for the
current exact/all-equal residual: self-applying `[MAT_TX]` rows already record
`materialization_action=created_body`. A source-level HIR/MIR availability dump
hook was rejected during the same slice because the produced `s2` did not
self-apply the HIR/MIR env-gated dump reliably; the committed classifier uses
the existing self-applying `[MAT_TX]` / `[MAT_EMIT]` ledger instead. Scope:
script/docs/control-plane only; no compiler production behavior changed and no
green `s2b`/`s3b` claim. The next executable movement must split
`created_body_backend_missing` by the next self-applying producer boundary
(HIR body still visible after materialization, HIR/RTA prune before MIR, MIR
function missing, backend lookup/emitted-set miss, or legitimate extern/runtime
helper) and stop if the selected class remains broad. Rejected next moves:
sampled Array/Slice/IO/Atomic/String::Builder/Int32 patches, backend rescue,
forwarders, requested-name forcing, broad `NamedTuple`/`Tuple` rendering,
global ambient-map policy, and `BlockOwner` rollback. Decay trigger: a finer
classifier selects a root-sized producer edge, the exact residual disappears,
or newer generated-stage transaction evidence refutes the
`created_body_backend_missing` shape.

[LM-ARCH-0K-CW-MATERIALIZATION-EXACT-BODY-AVAILABILITY|design-sealed 2026-07-02 {F:0.87 G:0.72 R:0.86}]:
Slice 0k-CW selects the architecture-burn-down target after 0k-CV. Fresh
source-shape evidence shows the obvious semantic-state and symbol-binding seams
are already promoted or guard-only:
`SOURCE_SHAPE_ONLY=1 scripts/semantic_state_scope_admission_report.sh` reports
`state_model_redesign_complete=1`,
`scripts/materialization_symbol_binding_admission_report.sh` reports
`already_promoted_shadow`, and
`scripts/call_materialization_transaction_admission_report.sh` reports the
main transaction seam `already_promoted_shadow` while still showing residual
legacy edges. Fresh generated-stage transaction evidence from
`scripts/generated_stage_transaction_edge_selection_report.sh` reports
`post_consumer_state=selected_consumed_by_contract_consumer`,
`contract_mismatch_rows=0`, `residual_exact_missing_body_rows=14`,
`residual_exact_missing_body_groups=9`,
`residual_exact_missing_body_root_sized_groups=9`, and
`residual_selection_status=rejected_exact_missing_body_ambiguous`. The selected
owner spine is `MaterializationTransaction` exact body availability: for
transaction rows where requested, target, body, and call symbols are all equal,
the compiler needs a transaction-owned proof of body availability before
HIR/MIR/LLVM falls back to `ExternCall`, backend `@undefined_externs`, or stub
emission. The next executable movement is read-only: classify the exact
missing-body residual by producer cause (HIR body absent, HIR body present but
not lowered to MIR, MIR function absent, backend emitted-set miss, or
legitimate extern/runtime helper) and stop if the selected class remains broad
or ambiguous. Rejected next moves: backend undefined-extern rescue, forwarder
rescue, requested-name forcing, per-method patches for the sampled
Array/Slice/IO/Atomic/String::Builder/Int32 rows, broad `NamedTuple`/`Tuple`
rendering, global ambient-map policy, `BlockOwner` rollback, or another report
that does not retire/refute this selection. Scope: docs/control-plane
selection; no compiler production behavior changed and no green `s2b`/`s3b`
claim. Decay trigger: the exact missing-body residual disappears, a classifier
selects a root-sized producer edge, or a newer generated-stage transaction
report refutes the residual shape.

[LM-ARCH-0K-CV-WIP-QUARANTINE-ARCHITECTURE-PAUSE|design-sealed 2026-07-02 {F:0.86 G:0.76 R:0.88}]:
Slice 0k-CV is an architecture-pause checkpoint after reviewing and removing
an unfinished local 0k-CU source WIP in `src/compiler/hir/ast_to_hir.cr`. The
WIP began to add a HIR `BlockCallReturnContract` helper and assigned-tail
passthrough classification, but it had not threaded the callsite
`block_return_name` fact through the wrapper-materialization callsites, had not
run generated-stage evidence, and had not satisfied the 0k-CU focused or
architecture DoD. It is therefore not completion evidence and must not be
resumed by inertia. Production compiler source is paused again. The 0k-CU
breakglass lane remains documented, but the active selector is architecture
burn-down: choose one durable owner spine plus one producer-to-consumer
authority edge, retire/refute a stale report surface, or promote a missing
contract falsifier from `docs/specs/05-falsifier-matrix.md`. Rejected next
moves: fresh crash-stack classifier by default, classifier-only patch, local
helper around the current failing value, source-shape-only progress claim,
broad return-shape specialization, direct CopyPropagation guard,
`timed_cp_phase` special-case, MIR/LLVM/backend rescue, broad
`NamedTuple`/`Tuple` or ambient-map policy, and `BlockOwner` rollback. Scope:
docs/control-plane pause plus source-WIP quarantine; no compiler production
behavior changed and no green `s2b`/`s3b` claim. Decay trigger: a future
source slice lands with a fresh receipt that explicitly re-admits a behavior
lane and moves a generated-stage gate, or the architecture board is superseded
by a newer SDD slice.

[LM-ARCH-0K-CU-ASSIGNED-TAIL-BLOCK-RETURN-RECEIPT|design-sealed 2026-07-02 {F:0.88 G:0.68 R:0.88}]:
Slice 0k-CU is the pre-code `SliceReceipt` required by 0k-CT for the only
currently admitted `bootstrap-emergency-with-ledger` behavior lane. Fresh
baseline evidence still matches the breakglass assumptions. Strict census
`REQUIRE_CURRENT_CP_BROAD=1 scripts/hir_block_return_shape_census.sh` reports
the broad rejected shape scope (`classification=current_0k_cp_hir_block_return_shape_broad`,
`candidate_multi_shape_keys=208`,
`candidate_nil_value_coexist_keys=206`,
`candidate_additional_return_shape_bodies=228`) and the root-sized
assigned-tail discriminator (`assigned_tail_multi_shape_keys=1`,
`assigned_tail_additional_return_shape_bodies=4`,
`timed_cp_phase_assigned_tail_passthrough_keys=1`). Strict O1 classifier
`REQUIRE_CURRENT_O1=1 scripts/mir_optimization_container_frontier_classifier.sh`
reports `b4_classification=current_0k_bn_frontier`,
`classification=current_0k_ck_mir_cp_container_frontier`, and
`bad_container_candidate=affected_block_ids`. The admitted future production
slice is CAUTION-tier and must implement a HIR `BlockCallReturnContract` for
assigned-tail yield-passthrough helpers, then use that owner fact to
materialize non-nil block-return-specific wrappers only inside the root-sized
contract. It must keep nil/non-returning `timed_cp_phase` callsites and
ordinary iterator/scope helpers as negative controls, and it must run
generated-stage evidence. Scope: pre-code receipt only; no compiler production
behavior changed and no green `s2b`/`s3b` claim. Decay trigger: assigned-tail
census grows beyond the root-sized current class, O1 no longer reports
`affected_block_ids`, the behavior slice lands/fails/widens, or B4 reaches
`REQUIRE_CLEAN=1`.

[LM-ARCH-0K-CT-CURRENT-EXECUTION-BOARD|design-sealed 2026-07-02 {F:0.84 G:0.74 R:0.86}]:
Slice 0k-CT is a docs-only active-board compression checkpoint after hostile
review of the post-0k-CS route. It adds an operator-facing
`Current Execution Board` near the top of `docs/compiler_architecture_sdd.md`
and makes that board the required entry point for future non-doc source slices.
The 0k-CR assigned-tail passthrough plus return-shape wrapper-materialization
slice remains allowed only as `breakglass bootstrap-emergency-with-ledger`, not
as the default plan. Before any behavior code, a `SliceReceipt` must name the
board lane, tranche, old authority edge, owner fact or service, producers,
consumers, measured-red baseline, focused and architecture DoD,
generated-stage gate, negative controls, rejected shortcuts, and residual
boundary. If that receipt cannot identify a root-sized producer-to-consumer
authority edge, the movement is a probe or SDD update, not production
architecture work. Scope: control-plane/docs only; no compiler production
behavior changed and no green `s2b`/`s3b` claim. Decay trigger: a future
source slice lands with a valid receipt and fresh B4/O1 evidence, the board is
superseded by a newer SDD slice, or B4 reaches `REQUIRE_CLEAN=1`.

[LM-ARCH-0K-CS-POST-CR-BOARD-FREEZE|design-sealed 2026-07-02 {F:0.84 G:0.72 R:0.86}]:
Slice 0k-CS is a docs-only architecture-board consolidation after hostile
review of the post-0k-CR route. It preserves the 0k-CR admission but narrows
its interpretation: one paired `bootstrap-emergency-with-ledger` behavior slice
may implement assigned-tail yield-passthrough classification plus
return-shape-specific wrapper materialization for the current root-sized class.
After that slice, or if the implementation widens beyond the assigned-tail
discriminator, production source movement must return to the Active
Architecture Board before another crash-stack classifier or local fix is
selected. The next non-emergency movement must select a durable owner spine,
retire or refute a stale report surface, or promote a missing contract
falsifier from `docs/specs/05-falsifier-matrix.md`. Scope: control-plane/docs
only; no compiler production behavior changed and no green `s2b`/`s3b` claim.
Decay trigger: 0k-CR behavior lands and a fresh B4/O1 result selects a new
owner spine, or the board is superseded by a newer SDD slice.

[LM-ARCH-0K-CR-ASSIGNED-TAIL-YIELD-PASSTHROUGH|implemented 2026-07-02 {F:0.88 G:0.66 R:0.87}]:
Slice 0k-CR extends `scripts/hir_block_return_shape_census.sh` with a
read-only assigned-tail yield-passthrough discriminator for helpers shaped like
`result = yield; ...; result`. Strict evidence from
`REQUIRE_CURRENT_CP_BROAD=1 scripts/hir_block_return_shape_census.sh` preserves
the broad 0k-CQ classification but reports
`assigned_tail_multi_shape_keys=1`,
`assigned_tail_nil_value_coexist_keys=1`,
`assigned_tail_value_shape_multi_keys=1`,
`assigned_tail_additional_return_shape_bodies=4`, and
`timed_cp_phase_assigned_tail_passthrough_keys=1`. Interpretation:
`contains_yield` remains too broad, but assigned-tail passthrough is root-sized
for the current B4 frontier and selects exactly
`Adamas::MIR::CopyPropagationPass#timed_cp_phase$String_block`. The selected
helper still has current `yield_return_function?=0`, which confirms that the
existing classifier misses this pattern. Scope: executable classifier
extension only; no compiler production behavior changed and no green
`s2b`/`s3b` claim. Next admitted movement is a paired behavior slice that both
classifies assigned-tail yield passthrough as block-return-dependent and uses
that fact to materialize return-shape-specific wrappers. A classifier-only
patch remains rejected if a wrapper body can still lower `yield : Void`. Decay
trigger: assigned-tail multi-shape keys grow beyond the root-sized current set,
the helper no longer matches the assigned-tail pattern, or B4 reaches
`REQUIRE_CLEAN=1`.

[LM-ARCH-0K-CQ-HIR-BLOCK-RETURN-SHAPE-CENSUS|implemented 2026-07-02 {F:0.88 G:0.72 R:0.88}]:
Slice 0k-CQ adds executable read-only census
`scripts/hir_block_return_shape_census.sh` after the 0k-CP design gate. The
script does not edit tracked compiler source: it copies `src/` into `tmp`,
injects default-off `[BRC_CENSUS]` probes into the temporary `ast_to_hir.cr`,
builds a temporary probe compiler, runs it through `scripts/run_safe.sh`, and
removes temp source/probe/HIR/log artifacts unless `KEEP_TMP=1`. Current
evidence reports `probe_build_rc=0`, `probe_run_rc=0`,
`total_census_rows=109692`, `wrapper_keys_total=18217`,
`multi_shape_keys=229`, `candidate_multi_shape_keys=208`,
`nil_value_coexist_keys=220`, `candidate_nil_value_coexist_keys=206`,
`value_shape_multi_keys=17`,
`candidate_value_shape_multi_keys=5`,
`candidate_additional_return_shape_bodies=228`,
`timed_cp_phase_multi_shape_keys=1`, and
`classification=current_0k_cp_hir_block_return_shape_broad`. Interpretation:
the current `CopyPropagationPass#timed_cp_phase$String_block` row remains real
and observes nil plus `Int32`, `Set(UInt32)`,
`Nil | Adamas::MIR::CopyPropagationPass::DominanceInfo`, and
`Hash(UInt32, Int32)` shapes behind one untyped-yield wrapper key, but it is
not unique enough to admit global block-return-shape specialization. Naive
specialization of every untyped `&` helper that contains `yield` would be
broad (208 candidate keys / 228 additional bodies). The next admitted movement
is a read-only return-demand / yield-passthrough discriminator that separates
helpers whose own return value depends on `yield` from ordinary iteration or
scope helpers. Scope: executable census only; no compiler production behavior
changed and no green `s2b`/`s3b` claim. Decay trigger: a future census reports
a root-sized narrowed set, a source rewrite invalidates `ast_to_hir.cr`
instrumentation anchors, or B4 reaches `REQUIRE_CLEAN=1`.

[LM-ARCH-0K-CP-HIR-BLOCK-CALL-RETURN-CONTRACT|design-sealed 2026-07-02 {F:0.82 G:0.64 R:0.86}]:
Slice 0k-CP is a docs-only architecture design gate after the 0k-CO
producer-order classifier. It selects the next owner direction without
changing production compiler behavior: a HIR-owned
`BlockCallReturnContract` / block-call materialization shape must carry the
callsite block-return fact for untyped `&` helpers that can return `yield`.
Evidence carried forward from strict 0k-CO:
`classification=current_0k_co_hir_timed_phase_shared_wrapper_order_frontier`,
`first_fallback_nil_line=108`, `first_set_record_line=117`,
`first_set_yieldret_zero_line=118`, `early_void_before_set=1`, and
`set_yield_return_not_classified=1`. Additional producer trace shows the same
shared `CopyPropagationPass#timed_cp_phase$String_block` name is associated
with several legitimate callsite block returns (`nil`, `Int32`, `Set(UInt32)`,
`Nil | Adamas::MIR::CopyPropagationPass::DominanceInfo`, and
`Hash(UInt32, Int32)`), so "delay one shared wrapper until facts exist" is not
the first valid fix. A pure `yield_return_function_for_block_call?` patch is
also insufficient unless the wrapper body itself materializes a non-void
`yield`. The next admitted movement is a read-only return-shape census that
tests whether specialization by `(callee shape, arg shape, block-return shape)`
is root-sized and keeps nil/non-returning callsites out of value-returning
wrappers. Scope: no green `s2b`/`s3b` claim and no production behavior change.
Decay trigger: a future census shows the specialization space is broad, a HIR
probe refutes the multi-return shared-wrapper shape, or B4 reaches
`REQUIRE_CLEAN=1`.

[LM-ARCH-0K-CO-HIR-TIMED-PHASE-PRODUCER-ORDER|implemented 2026-07-02 {F:0.89 G:0.55 R:0.88}]:
Slice 0k-CO adds executable read-only producer-order classifier
`scripts/mir_timed_phase_hir_producer_order_classifier.sh` after the 0k-CN HIR
source-seam boundary. The script does not edit tracked compiler source: it
copies `src/` into `tmp`, injects default-off probes into the temporary
`ast_to_hir.cr`, builds a temporary probe compiler, runs it through
`scripts/run_safe.sh`, and removes the temp source/probe/HIR artifacts unless
`KEEP_TMP=1`. Strict evidence:
`REQUIRE_CURRENT_CO=1 scripts/mir_timed_phase_hir_producer_order_classifier.sh`
reports
`classification=current_0k_co_hir_timed_phase_shared_wrapper_order_frontier`,
`first_fallback_nil_line=108`, `first_set_before_record_line=115`,
`first_set_record_line=117`, `first_set_yieldret_zero_line=118`,
`early_void_before_set=1`, `set_recorded_later=1`, and
`set_yield_return_not_classified=1`. Interpretation: the shared
`CopyPropagationPass#timed_cp_phase$String_block` wrapper is first lowered for
an earlier callsite with `block_return=nil`; `infer_yield_fallback_return_type`
sees `block_ret=nil`, `candidate=Void`, and returns nil, so `lower_yield`
emits `yield : Void`. Later the `apply_collect_affected_blocks` callsite
discovers and records `block_return=Set(UInt32)` for the same
`timed_cp_phase$String_block` name, but `yield_return_function_for_block_call?`
still reports `result=0`, and the already-materialized shared wrapper remains
void-yielded. Scope: executable classifier only; no compiler production
behavior changed and no green `s2b`/`s3b` claim. The next admitted movement is
a pre-code fix design for HIR block-return specialization / wrapper
materialization ownership for untyped `&` helpers. Decay trigger: the
classifier stops reporting current 0k-CO, a future HIR producer-order probe
shows the Set-return callsite records before wrapper materialization, or B4
reaches `REQUIRE_CLEAN=1`.

[LM-ARCH-0K-CN-HIR-TIMED-PHASE-SOURCE-SEAM|implemented 2026-07-02 {F:0.90 G:0.55 R:0.90}]:
Slice 0k-CN adds executable read-only source-seam classifier
`scripts/mir_timed_phase_source_seam_classifier.sh` after the 0k-CM
block-return frontier. Strict evidence:
`REQUIRE_CURRENT_CN=1 scripts/mir_timed_phase_source_seam_classifier.sh`
reports `classification=current_0k_cn_hir_timed_phase_source_seam`,
`timed_wrapper_return_type=2698`, `wrapper_yield_void=1`,
`wrapper_wraps_void_to_return=1`, `collect_proc_return_type=1268`,
`collect_block_builds_set=1`, `collect_block_proc_returns_set=1`,
`apply_collect_uses_timed_phase=1`, `apply_collect_call_type=2698`,
`affected_block_ids_local_type=2698`, `apply_collect_result_nil_void=1`, and
`call_differs_from_collect_proc=1`. Interpretation: the HIR dump already
contains `__crystal_block_proc_1756` returning the `Set(UInt32)` type id seen
at `Set(UInt32).new`, while
`CopyPropagationPass#timed_cp_phase$String_block` contains `yield : Void`, wraps
that void result into its `Nil|Void` return type, and the
`apply_collect_affected_blocks` call/local are also `Nil|Void`. This moves the
first-bad boundary above HIR->MIR and LLVM backend return handling for this
frontier. Scope: executable classifier only; no compiler production behavior
changed and no green `s2b`/`s3b` claim. The next admitted movement is a
read-only producer pin inside HIR block/call return typing: distinguish
`block_return_name`, `yield_return_function_for_block_call?`,
`record_block_return_type_for_call`, and `infer_yield_return_type` fallback for
untyped `&` helpers. Decay trigger: the classifier stops reporting current
0k-CN, a fresh HIR dump shows the wrapper/call return types are no longer
`Nil|Void`, or B4 reaches `REQUIRE_CLEAN=1`.

[LM-ARCH-0K-CM-TIMED-PHASE-BLOCK-RETURN-FRONTIER|implemented 2026-07-02 {F:0.91 G:0.56 R:0.90}]:
Slice 0k-CM adds executable read-only producer-localization classifier
`scripts/mir_timed_phase_return_frontier_classifier.sh` after the 0k-CL O1
container classifier. Strict evidence:
`REQUIRE_CURRENT_CM=1 scripts/mir_timed_phase_return_frontier_classifier.sh`
reports `classification=current_0k_cm_timed_cp_phase_block_return_frontier`,
`o1_classification=current_0k_ck_mir_cp_container_frontier`,
`can_skip_affected_block_ids_x3_zero=1`, `timed_calls_block=1`,
`timed_zeroes_after_block=1`, `timed_enabled_branch_returns_zero=1`,
`apply_collect_uses_timed_phase=1`, `apply_collect_result_is_nil_void=1`,
`collect_block_builds_set=1`, and `collect_block_returns_set_slot=1`.
Interpretation: the `apply_collect_affected_blocks` block
`__crystal_block_proc_1756` constructs a `Set(UInt32)`, adds block ids through
`Set#<<`, and returns the Set slot, but the produced `s2b`
`CopyPropagationPass#timed_cp_phase(String, &)` wrapper calls the block and
then zeroes the return value; its timing-enabled branch also returns zero
without yielding. `apply_replacements` then treats the collect result as
`Nil|Void`, stores null into the closure cell consumed as `affected_block_ids`,
and `can_skip_dominators_for_local_replacements?` receives `x3=0`. Scope:
executable classifier only; no compiler production behavior changed and no
green `s2b`/`s3b` claim. The next admitted movement is read-only source-seam
localization for why a bare `&` / `yield` helper is materialized as a
void-return `String_block` wrapper. Decay trigger: classifier no longer
reports current 0k-CM, a fresh source-seam probe proves the void wrapper is
downstream of a different materialization decision, or B4 reaches
`REQUIRE_CLEAN=1`.

[LM-ARCH-0K-CL-MIR-OPT-CONTAINER-CLASSIFIER|implemented 2026-07-02 {F:0.90 G:0.58 R:0.90}]:
Slice 0k-CL adds executable read-only classifier
`scripts/mir_optimization_container_frontier_classifier.sh` for the O1
frontier selected by 0k-CK. The script reuses the generated-stage B4
classifier, keeps the produced `s2b` only for the run, executes the workers=1
path under `lldb`, parses the backtrace/register evidence, and removes
repo-local temp artifacts including `tmp/llvm_cache` unless `KEEP_TMP=1`.
Strict evidence:
`REQUIRE_CURRENT_O1=1 scripts/mir_optimization_container_frontier_classifier.sh`
reports `classification=current_0k_ck_mir_cp_container_frontier`,
`b4_classification=current_0k_bn_frontier`, `workers1_after_lower_main=1`,
`workers1_exit139=1`, `has_set_uint32_includes=1`,
`has_copyprop_affected=1`, `has_copyprop_can_skip=1`,
`has_optimize_with_potential=1`, `register_x0_zero=1`,
`register_x8_zero=1`, `set_load_from_x8=1`,
`affected_method_includes_count=1`,
`bad_container_state=set_receiver_base_register_null`, and
`bad_container_candidate=affected_block_ids`. Scope: executable classifier
only; no compiler production behavior changed and no green `s2b`/`s3b` claim.
The next admitted movement is still read-only producer localization for the
null `affected_block_ids` Set value returned by
`CopyPropagationPass#apply_replacements`' `apply_collect_affected_blocks`
timed block. Decay trigger: classifier no longer reports current O1, B4
reaches `REQUIRE_CLEAN=1`, or a producer-localization slice names a different
first bad transition before `affected_blocks_use_only_local_replacements?`.

[LM-ARCH-0K-CK-MIR-OPT-CONTAINER-ROOT-SPINE|design-sealed 2026-07-02 {F:0.86 G:0.60 R:0.88}]:
Slice 0k-CK is a docs-only architecture pause after the 0k-CJ
`GeneratedStageExecutionOutcome` checkpoint. Fresh B4 evidence on HEAD
`b9b1457f` preserves the known classifier shape:
`KEEP_TMP=1 STAGE1_COMPILER=bin/adamas TAIL_LINES=120
REQUIRE_CURRENT_FRONTIER=1 scripts/generated_stage_llvm_entry_classifier.sh`
reports `classification=current_0k_bn_frontier`, default-worker
`parallel_rand=1` plus `memory_kill=1`, and workers=1 `exit139=1` after
`pass3 after lower_main call`. A fresh workers=1 `lldb` run narrows the
actual crash stack to `Set(UInt32)#includes?` from
`Adamas::MIR::CopyPropagationPass#affected_blocks_use_only_local_replacements?`
via `can_skip_dominators_for_local_replacements?`,
`apply_replacements`, `OptimizationPipeline#run`, and
`Function#optimize_with_potential`; registers show `x0=0` and `x8=0` at the
`Set#includes?` null load. Scope: this is not a compiler behavior fix and not
a green `s2b`/`s3b` claim. It decreases `BootstrapPotential` by reducing the
plausible owner-spine count: `GeneratedStageExecutionOutcome`,
worker/resource/output/tail, and local LLVM-emission edges are demoted to
pressure/proxy surfaces for the next slice. The admitted next movement is a
read-only `MIROptimizationInvariant` / compiler-runtime-container classifier
that distinguishes malformed CopyPropagation local-replacement state from a
self-hosted `Set`/`Hash` constructor or namespace-initialization failure.
Decay trigger: B4 reaches `REQUIRE_CLEAN=1`, the workers=1 crash stack moves
away from MIR optimization / `Set(UInt32)#includes?`, or a future classifier
proves the null Set/Hash state is only a downstream symptom of a named
semantic owner spine.

[LM-ARCH-0K-CJ-GENERATED-STAGE-OUTCOME-SOURCE-CHECKPOINT|implemented 2026-07-02 {F:0.90 G:0.52 R:0.90}]:
Slice 0k-CJ implements the 0k-CH `cli.output_commit_record` owner migration
under the 0k-CI anti-proxy gate. `src/compiler/cli.cr` now creates one
`GeneratedStageExecutionOutcome` for the produced-compiler output corridor and
serializes `output.llvm_ir_start`, `output.llvm_ir_written`, and
`output.binary_compile_result` through outcome helper methods. New guard
`scripts/generated_stage_outcome_source_shape_guard.sh` strict mode reports
`source_shape=outcome_serializes_output_commit_rows`,
`start_helper_calls=2`, `written_helper_calls=2`,
`compile_helper_calls=1`, and zero direct output rows outside outcome helpers.
Verification: `crystal build src/adamas.cr -o bin/adamas --error-trace`
passes; the existing `LLVMEmissionSession` source-shape guard passes; the G6
`BlockOwner` availability guard reports `body_present_rows=7`, `real_defs=1`,
and `stub_defs=0`; the joined B4/L6 report preserves the measured-red state
with `b4.classification=current_0k_bn_frontier`,
`final_classification=abort_resource`, `join_status=joined`, and
`admission_status=rejected_no_root_sized_consumer`; full regression suites pass
`152/152 + 36/36`. Scope: behavior-neutral output-row owner checkpoint only;
no worker/resource/tail/backend behavior, output semantics, materialization,
parser, ambient-map, broad `NamedTuple`/`Tuple`, physical extraction, or
`BlockOwner` behavior changed. BootstrapPotential impact: only the
`unmigrated authority-edge count` component decreased, so the next source
movement remains barred unless it decreases B4/L6 phase, plausible owner-spine
count, or live proxy-surface count, or is an explicit
`bootstrap-emergency-with-ledger` behavior slice. Decay trigger: the guard
fails, row format changes, B4/L6 reaches `REQUIRE_CLEAN=1`, or a future slice
refutes `GeneratedStageExecutionOutcome` as the output-row authority.

[LM-ARCH-0K-CI-BOOTSTRAP-POTENTIAL-GATE|design-sealed 2026-07-02 {F:0.84 G:0.72 R:0.86}]:
Slice 0k-CI adds a docs-only anti-proxy gate after hostile review of the
repeated behavior-neutral owner/guard pattern. It does not replace the 0k-CH
`cli.output_commit_record` edge; it prevents the architecture track from
automatically selecting another nearby `GeneratedStageExecution` edge after the
current implementation candidate. Future source slices must state
`BootstrapPotential = (B4/L6 phase, plausible owner-spine count, live
proxy-surface count, unmigrated authority-edge count)` before edits and name
the lexicographic component they decrease. A slice that only lowers the last
component while B4/L6, owner-spine ambiguity, and proxy surfaces remain
unchanged is bookkeeping rather than bootstrap progress. Admitted immediate
actions are limited to finishing the already-selected output-owner candidate as
a checkpoint with DoD evidence, reverting or retiring it if it is helper
theater, or writing a new SDD/root-localization slice that decreases one of the
first three components. This keeps `BlockOwner`, materialization, parser,
ambient-map, broad `NamedTuple`/`Tuple`, worker/resource/tail/backend, and
physical extraction changes rejected unless a fresh SDD slice proves a
bootstrap-potential descent. Scope: docs/control-plane only; no compiler source
behavior changed and no green `s2b`/`s3b` claim. Decay trigger: a future slice
proves B4/L6 reaches `REQUIRE_CLEAN=1`, refutes the potential components, or
commits a source slice that explicitly decreases one of the first three
components with evidence.

[LM-ARCH-0K-CH-GENERATED-STAGE-OUTCOME-PRECODE|design-sealed 2026-07-02 {F:0.86 G:0.68 R:0.87}]:
Slice 0k-CH completes the 0k-CG pre-code requirement without changing compiler
source. It selects B4/L6 under `PhaseAuthority` / `GeneratedStageExecution`,
declares `contract-owner-migration`, and names the first old authority edge:
`cli.output_commit_record`. Today `src/compiler/cli.cr` directly logs
`output.llvm_ir_start`, `output.llvm_ir_written`, and
`output.binary_compile_result` rows from scattered output locals, while
`scripts/generated_stage_execution_transaction_report.sh` reconstructs
`output.commit_record` and folds it into `final_classification`,
`join_status`, and `admission_status`. The next admitted source slice is only a
behavior-neutral owner migration: introduce a code-owned
`GeneratedStageExecutionOutcome` helper/record with one produced-compiler
invocation lifetime and make the CLI output row producer serialize from it
while preserving the existing `GSETX` row format and current B4/L6 measured-red
state. A source-shape guard must prove the output rows are no longer emitted
directly from scattered CLI locals. Worker/resource/tail/backend behavior,
output semantics, side-effect semantics, memory-budget acceptance,
materialization, parser behavior, broad `NamedTuple`/`Tuple` rendering, global
ambient-map changes, physical extraction, and `BlockOwner` rollback remain
rejected. Scope: docs/control-plane only; no compiler production source changes,
no new scripts, and no green `s2b`/`s3b` claim. Decay trigger: a committed
behavior-neutral `GeneratedStageExecutionOutcome` output-row owner migration
lands, B4 reaches `REQUIRE_CLEAN=1`, or fresh evidence refutes
`cli.output_commit_record` as a root-sized phase-outcome edge.

[LM-ARCH-0K-CG-GENERATED-STAGE-PLANNING-RESET|design-sealed 2026-07-02 {F:0.84 G:0.70 R:0.86}]:
Slice 0k-CG is a docs-only architecture reset after the 0k-CF G6 guard. It
tightens the post-G6 route: B4/L6 remain active `PhaseAuthority` /
`GeneratedStageExecution` pressure gates, but production compiler edits are
paused until a pre-code `GeneratedStageExecutionOutcome` / phase-outcome
authority plan exists. The old wording "select a root-sized consumer edge" is
not a license for another selector/report loop or a patch selected from local
joined-row symptoms. The next valid movement must name B4/L6 as the selected
board row, choose `contract-owner-migration`, identify one old authority edge,
define the owner fact/service and lifetime, enumerate producers and consumers,
state the measured-red baseline and generated-stage gate, and record residual
rejected surface. Worker forcing, memory-limit acceptance, output/tail/backend
fixes, side-effect semantic changes, materialization behavior, parser behavior,
broad `NamedTuple`/`Tuple` rendering, global ambient-map changes, physical
extraction, and `BlockOwner` rollback remain rejected. Scope: docs/control-plane
only; no production source changes, no new scripts, and no green `s2b`/`s3b`
claim. Decay trigger: a committed `GeneratedStageExecutionOutcome` pre-code plan
lands, B4 reaches `REQUIRE_CLEAN=1`, or fresh evidence refutes B4/L6 as the
active pressure gate.

[LM-ARCH-0K-CF-G6-AVAILABILITY-GUARD|implemented 2026-07-02 {F:0.88 G:0.64 R:0.88}]:
Slice 0k-CF adds executable guard
`scripts/block_owner_materialization_transaction_availability_report.sh` for
the 0k-CE G6 invariant. Fresh evidence with `bin/adamas` reports
`tx_rows=1`, `exact_tx=1`, `all_equal_tx=1`, `instance_tx=1`,
`body_eq_call_tx=1`, `emit_rows=7`, `joined_emit_rows=7`,
`body_present_rows=7`, `body_missing_rows=0`, `real_defs=1`, and
`stub_defs=0`; the older
`regression_tests/block_owner_index_assign_materialization_repro.sh bin/adamas`
also passes. This closes G6 as the active implementation selector for the
current stage1 compiler unless the guard regresses. It is not a green
`s2b`/`s3b` claim: fresh B4/L6 pressure evidence still reports
`b4.classification=current_0k_bn_frontier`, `final_classification=abort_resource`,
`join_status=joined`, and
`admission_status=rejected_no_root_sized_consumer`. Next movement is therefore
GeneratedStageExecution root-sized consumer selection; worker/resource/backend
patches remain rejected until a transaction-owned behavior edge is selected.
Slice 0k-CG tightens this historical route: selection must first become a
pre-code phase-outcome owner-edge plan, not another standalone report.
Scope: one behavior-neutral script plus docs/control-plane updates; no compiler
production source changed. Decay trigger: the G6 guard fails, `BlockOwner`
setter write-path changes, or B4 reaches `REQUIRE_CLEAN=1`.

[LM-ARCH-0K-CE-G6-MATERIALIZATION-PRECODE-PLAN|design-sealed 2026-07-02 {F:0.86 G:0.68 R:0.87}]:
Slice 0k-CE converts the 0k-CD pause into a concrete pre-code
`MaterializationTransaction` plan. Live source inspection pins the G6 producer
as the `lower_assign` index-target setter path that resolves `[]=` and calls
`remember_callsite_arg_types`, `lower_function_if_needed`, and
`Call.with_receiver`; the materialization owner is the existing
`CallMaterializationTransaction` / HIR `MaterializationTransactionContract`
chain; the downstream consumers are HIR-to-MIR contract attachment and backend
call/extern-call body visibility. The old authority edge is split because
materialization completion is checked under the selected/body symbol while MIR
and backend execution are keyed by the call-visible symbol. The next production
slice may only add a transaction-owned demanded-setter availability proof and a
root-sized behavior flip after the ledger proves the same semantic setter flows
through demand, selected identity, body symbol, HIR body presence, MIR call
resolution, and backend body visibility. Backend undefined-extern rescue,
forwarders, requested-name forcing, broad `NamedTuple`/`Tuple` rendering,
global ambient-map policy changes, parser changes, and rolling `BlockOwner`
back to tuple/namedtuple remain rejected. Scope: docs/control-plane only; no
compiler production behavior changed and no green `s2b`/`s3b` claim. Decay
trigger: superseded by LM-ARCH-0K-CF-G6-AVAILABILITY-GUARD, the setter
write-path changes, or B4 reaches `REQUIRE_CLEAN=1`.

[LM-ARCH-0K-CD-G6-PRECODE-PAUSE|design-sealed 2026-07-02 {F:0.84 G:0.66 R:0.86}]:
Slice 0k-CD is a docs-only hostile review checkpoint that pauses production
compiler edits before the G6 implementation. G6 remains the selected
`MaterializationTransaction` lane, but the current focused falsifier is not
enough by itself: a local patch could make
`Hash(UInt64, BlockOwner)#[]=` appear as a non-stub self-IR body without proving
that call demand, selected semantic identity, materialized body, HIR/MIR body
presence, and backend visibility are one transaction-owned semantic function.
The next movement is therefore a pre-code G6 `MaterializationTransaction` plan
gate. It must name the old authority edge, owner record or consumer, producer
and consumer chain, invariant, negative controls, and residual generated-stage
pressure before any `ast_to_hir.cr`, `hir_to_mir.cr`, or `llvm_backend.cr`
production edit. Rejected repeats remain backend undefined-extern rescue,
forwarders, requested-name forcing, broad `NamedTuple`/`Tuple` rendering,
global ambient-map policy changes, parser changes, and `BlockOwner` rollback.
Scope: docs/control-plane only; no compiler production behavior changed and no
green `s2b`/`s3b` claim. Decay trigger: superseded by
LM-ARCH-0K-CE-G6-MATERIALIZATION-PRECODE-PLAN, G6 falsifier changes shape, or
B4 reaches `REQUIRE_CLEAN=1`.

[LM-ARCH-0K-CC-OWNER-SPINE-CONSOLIDATION|design-sealed 2026-07-02 {F:0.84 G:0.68 R:0.85}]:
Slice 0k-CC executes the 0k-CB reset by classifying active frontier rows under
owner spines and selecting the next implementation lane without using the latest
LLVM crash stack as the selector. B4 and L6 remain
`PhaseAuthority`/`GeneratedStageExecution` guard-only pressure gates; they do
not admit resource, output, tail, worker, or backend behavior. H7 and H8 remain
`SemanticIdentity` pre-s2-clean residuals and do not move the active generated
LLVM-entry frontier. G6 is selected as the next admitted implementation lane
under `MaterializationTransaction`: `Hash(UInt64, BlockOwner)#[]=` must have a
real materialized body under the call-visible identity. The next code slice must
start from `regression_tests/block_owner_index_assign_materialization_repro.sh`,
keep `BlockOwner` as the owner carrier, and replace or shadow the
producer-to-consumer authority edge for call demand -> body materialization ->
HIR/MIR/backend body presence. Rejected repeats: backend undefined-extern
rescue, forwarders, `NamedTuple`/`Tuple` rendering normalization, global
ambient-map policy changes, parser changes, or `BlockOwner` rollback. Scope:
docs/control-plane only; no compiler production behavior changed and no green
`s2b`/`s3b` claim. Decay trigger: the G6 lane lands, G6 repro changes shape, or
B4 reaches `REQUIRE_CLEAN=1`.

[LM-ARCH-0K-CB-ARCHITECTURE-RESET|design-sealed 2026-07-02 {F:0.83 G:0.70 R:0.84}]:
Slice 0k-CB records a docs-only architecture reset after hostile review of the
post-0k-CA route. The reset does not discard the 0k-CA joined transaction
evidence; it downgrades the next selector from implementation driver to
guard-only unless it chooses a durable owner-spine decision. Current joined B4
facts (`final_classification=abort_resource`,
`tail.semantic_vs_input_split=tail_not_reached_after_output_start`, and
`output.commit_record=llvm_ir_started_without_commit:file`) are too close to the
latest LLVM symptom to admit `ResourceEvidence`, worker, tail, output,
memory-budget, backend-forwarder, parser, ambient-map, `NamedTuple`/`Tuple`, or
`BlockOwner` behavior changes. The next movement is an owner-spine consolidation
slice: classify active architecture work under `SemanticIdentity`,
`MaterializationTransaction`, or `PhaseAuthority`/`GeneratedStageExecution`,
retire or stale-mark lanes that no longer move bootstrap, and admit production
implementation only when a producer-to-consumer authority edge is named with a
falsifier. Scope: docs/control-plane only; no compiler production behavior
changed and no green `s2b`/`s3b` claim. Decay trigger: a future owner-spine
slice selects one producer-to-consumer authority edge with executable evidence,
or B4 reaches `REQUIRE_CLEAN=1`.

[LM-ARCH-0K-CA-RUNTIME-TRANSACTION-ROWS|implemented 2026-07-02 {F:0.88 G:0.48 R:0.88}]:
Slice 0k-CA implements the default-off runtime transaction rows selected by
0k-BZ. The classifier now passes `GSETX_TRANSACTION_ID` and `GSETX_LEDGER` only
to produced-s2 smoke runs and labels them `default_workers` / `workers1`; stage1
and s2-build phases do not inherit the compiler-facing ledger variables. The
compiler writes `GSETX` rows only when `ADAMAS_GSETX_ID` and
`ADAMAS_GSETX_LEDGER` are set: CLI rows for HIR module identity, MIR module
identity, LLVM output start/write/compile result, and backend rows for
`LLVMEmissionSession` id/function plan, side-effect runtime counts, and tail
semantic-vs-input state. Fresh current-frontier evidence:
`STAGE1_COMPILER=bin/adamas REQUIRE_CURRENT_FRONTIER=1 REQUIRE_JOINED=1
scripts/generated_stage_execution_transaction_report.sh` reports
`b4.classification=current_0k_bn_frontier`, `join_status=joined`,
`final_classification=abort_resource`, runtime HIR/MIR/session ids,
`side_effect.runtime_row_counts=phase:session_start,emitted:0,called:0,undefined:0`,
`tail.semantic_vs_input_split=tail_not_reached_after_output_start`, and
`output.commit_record=llvm_ir_started_without_commit:file`. Negative evidence:
with `GENERATED_S2=bin/adamas`, `REQUIRE_ADMIT_BEHAVIOR=1` still exits 9 and
reports `admission_status=rejected_no_root_sized_consumer`; joined evidence is
not behavior admission. Scope: default-off instrumentation/report join only;
no worker behavior, side-effect semantics, tail stubs, output behavior,
resource limits, backend forwarders, `NamedTuple`/`Tuple` rendering,
ambient-map policy, parser behavior, or `BlockOwner` changed. No green
`s2b`/`s3b` claim. Next movement: a selector/falsifier must choose exactly one
root-sized transaction-owned old authority edge or refute
`GeneratedStageExecution` before any behavior fix. Decay trigger: report schema
changes, B4 changes to a different first-bad boundary, or a selector admits a
root-sized behavior edge.

[LM-ARCH-0K-BZ-RUNTIME-ROWS-STOP-RULE|design-sealed 2026-07-02 {F:0.83 G:0.60 R:0.84}]:
Slice 0k-BZ records a docs-only hostile Quadrumvirate checkpoint over the
post-0k-BY path. The reviewed risk is not lack of another local compiler fix;
it is report inflation: adding more generated-stage rows without producing a
transaction-owned decision that can admit or reject a behavior slice. Current
evidence remains the 0k-BY report state:
`final_classification=abort_unjoined_evidence`,
`join_status=phase_local_only`, and
`admission_status=rejected_unjoined_evidence`. The next executable movement is
still default-off runtime transaction-row production, but its completion signal
is narrowed: either the report reaches `join_status=joined` and selects exactly
one root-sized transaction-owned old authority edge, reaches `joined` and
explicitly refutes `GeneratedStageExecution` as the wrong owner boundary, or
stops with a named missing runtime row that cannot be produced without changing
compiler semantics. Rejected repeats: worker fixes, tail-stub fixes,
side-effect semantic changes, output/resource behavior changes, backend
forwarders, `ADAMAS_LLVM_WORKERS=1`, broad `NamedTuple`/`Tuple` rendering,
ambient-map policy changes, parser behavior changes, or `BlockOwner` rollback
before joined transaction evidence. Scope: docs/control-plane only; no compiler
production behavior changed and no green `s2b`/`s3b` claim. Decay trigger: the
transaction report reaches `joined`, refutes the owner boundary, or B4 changes
to a different first-bad boundary.

[LM-ARCH-0K-BY-GENERATED-STAGE-TRANSACTION-REPORT|implemented 2026-07-02 {F:0.86 G:0.50 R:0.86}]:
Slice 0k-BY implements the first executable
`GeneratedStageExecutionTransaction` report:
`scripts/generated_stage_execution_transaction_report.sh`. The report wraps the
B4 generated-stage LLVM-entry classifier, runs the `LLVMEmissionSession`
source-shape guard, and emits exactly one transaction row set for the produced
compiler invocation. Current evidence with
`STAGE1_COMPILER=bin/adamas REQUIRE_CURRENT_FRONTIER=1` reports one
`transaction_id`, `b4.classification=current_0k_bn_frontier`,
`setup.source_shape=session_consumes_function_plan`,
`setup.worker_shape=session_consumes_worker_plan`,
`setup.side_effect_contract_shape=session_consumes_side_effect_merge_contract`,
`final_classification=abort_unjoined_evidence`,
`join_status=phase_local_only`, and
`admission_status=rejected_unjoined_evidence`. The report also prints stable
SHA1s for source/stage1/generated-s2 inputs so evidence is not only a cleaned
tmp path. Negative evidence: `REQUIRE_JOINED=1` exits 9 even when
`GENERATED_S2=bin/adamas` classifies as `clean_both_modes`, because runtime
transaction rows are still missing. Scope: guard/report only; no compiler
production behavior changed and no green `s2b`/`s3b` claim. Next movement:
produce default-off runtime transaction rows for HIR/MIR module identity,
`LLVMEmissionSession` id, runtime side-effect row counts,
tail semantic-vs-input split, and output commit record. Decay trigger: the
report reaches `join_status=joined`, B4 changes to a different first-bad
boundary, or a later transaction owner supersedes this report.

[LM-ARCH-0K-BX-GENERATED-STAGE-EXECUTION-TRANSACTION|design-sealed 2026-07-02 {F:0.84 G:0.66 R:0.86}]:
Slice 0k-BX is a docs-only `GeneratedStageExecutionTransaction` checkpoint
after 0k-BW. It records that three useful local `LLVMEmissionSession` ownership
migrations did not narrow B4: the produced compiler still reports
`classification=current_0k_bn_frontier`, default LLVM workers still expose the
parallel-rand/RSS path, and `ADAMAS_LLVM_WORKERS=1` still exits 139 after
`lower_main`. New stop rule: the next movement is not another local
`LLVMEmissionSession` edge hoist by default. Before any production compiler
edit to tail declarations/stubs, output ownership, resource evidence, worker
policy, side-effect semantics, backend stubs, or resource limits, an executable
generated-stage transaction report must join one produced-compiler invocation's
setup facts, function plan, worker/fallback facts, side-effect contract facts,
tail declaration/stub inputs, output ownership, resource evidence, and B4
commit/abort classification under one transaction identity. The report must
fail closed on malformed, unjoined, or phase-local-only rows. A later code slice
is admitted only if that report selects a root-sized old authority edge or
refutes the current `LLVMEmissionSession` boundary with fresh generated-stage
evidence. Scope: docs/design only; no compiler behavior changed and no green
`s2b`/`s3b` claim. Decay trigger: a committed transaction report lands, B4
changes to a different first-bad boundary, or generated-stage execution reaches
clean `REQUIRE_CLEAN=1`.

[LM-ARCH-0K-BW-SIDE-EFFECT-MERGE-CONTRACT|implemented 2026-07-02 {F:0.88 G:0.42 R:0.88}]:
Slice 0k-BW implements the behavior-neutral `SideEffectMergeContract`
consumer migration. `LLVMEmissionSession` now owns the worker side-effect tag
vocabulary; `LLVMIRGenerator#generate` passes the session into
`emit_functions_parallel`; worker `.se` writing delegates to
`write_worker_side_effects_with_contract`; and parent side-effect merging
delegates to `merge_worker_side_effects_with_contract`. The current `.se` file
format and merge policy are preserved: strings dedupe/alias by value, zero
struct globals dedupe by struct key when possible, undefined externs use
`record_undefined_extern`, called Crystal functions keep first-seen call info,
emitted functions are unioned, emitted return types keep first entry, module
singleton globals keep first entry per type, debug files route through the
debug context, malformed rows still skip via size checks, and string counters
use the max worker high-water mark. Verification: prepatch B4 was
`classification=current_0k_bn_frontier`; prepatch side-effect source-shape
guard was red with `parallel_raw_side_effect_writer_tags=10` and
`parallel_raw_side_effect_merge_tags=9`; postpatch
`REQUIRE_SESSION=1 REQUIRE_WORKER_PLAN=1 REQUIRE_SIDE_EFFECT_CONTRACT=1
scripts/llvm_emission_session_source_shape_guard.sh` reports
`side_effect_contract_shape=session_consumes_side_effect_merge_contract`,
`parallel_contract_writer_call_count=1`,
`parallel_contract_merge_call_count=1`, and raw writer/merge counts `0/0`;
`crystal build src/adamas.cr -o bin/adamas --error-trace`,
`regression_tests/type_value_core_runtime_identity_contract.sh bin/adamas`,
`regression_tests/original_vs_stage_semantic_oracle_contract.sh bin/adamas`,
and `regression_tests/p2_stage2_static_call_named_llvm_no_prelude.sh
bin/adamas` all pass. Postpatch B4 remains `classification=current_0k_bn_frontier`
with the same default-worker rand+RSS symptom and workers=1 exit 139. Scope:
behavior-neutral side-effect contract ownership only; no side-effect semantics,
tail declarations/stubs, output ownership, resource acceptance, worker
fallback, parser, materialization, or `BlockOwner` behavior changed. Per 0k-BV,
because all generated-stage convergence-vector rows were preserved unchanged,
the next movement is a `GeneratedStageExecution` transaction redesign
checkpoint, not another session edge hoist by default. Decay trigger: B4
changes to a different first-bad boundary, side-effect merge semantics change,
or a later generated-stage transaction owner supersedes this contract.

[LM-ARCH-0K-BV-GENERATED-STAGE-CONVERGENCE-GATE|design-sealed 2026-07-02 {F:0.84 G:0.62 R:0.86}]:
Slice 0k-BV adds a convergence checkpoint before the next
`GeneratedStageExecution` / `LLVMEmissionSession` production edit. Hostile
review found a new tail-chasing risk: the project can keep consuming local
`LLVMEmissionSession` authority edges while B4 remains at the same
`current_0k_bn_frontier`. The selected 0k-BU `SideEffectMergeContract` remains
admitted, but implementation is moved to then-future Slice 0k-BW and must carry a
generated-stage convergence vector: B4 before/after, default-worker versus
`ADAMAS_LLVM_WORKERS=1` split, side-effect writer/merge source shape,
tail-input versus semantic-failure classification, output/resource evidence
boundary, and post-edge routing. Fresh source-shape evidence for the side-effect
guard is intentionally red on current source:
`REQUIRE_SESSION=1 REQUIRE_WORKER_PLAN=1 REQUIRE_SIDE_EFFECT_CONTRACT=1
scripts/llvm_emission_session_source_shape_guard.sh` reports
`side_effect_contract_shape=legacy_parallel_side_effect_merge`,
`parallel_raw_side_effect_writer_tags=10`, and
`parallel_raw_side_effect_merge_tags=9`, then exits non-zero. Stop rule: if
0k-BW preserves B4 and all convergence-vector rows unchanged, the next movement
is a higher-level `GeneratedStageExecution` transaction redesign checkpoint,
not another session field/edge hoist. Scope: docs/guard only; no compiler
production behavior changed and no green `s2b`/`s3b` claim. Decay trigger:
0k-BW lands, B4 changes to a different first-bad boundary, or fresh evidence
refutes `LLVMEmissionSession` as the active generated-stage owner boundary.

[LM-ARCH-0K-BU-SIDE-EFFECT-MERGE-CONTRACT-PLAN|design-sealed 2026-07-01 {F:0.84 G:0.55 R:0.87}]:
Slice 0k-BU selects `SideEffectMergeContract` as the next
`GeneratedStageExecution` / `LLVMEmissionSession` vertical contract plan. Source
anchors: `src/compiler/mir/llvm_backend.cr` worker `.se` writer in
`emit_functions_parallel` writes raw `STR/ZSG/EXT/CCF/EMF/ERT/MSG/DGF/SCN` rows;
the parent merge switch in the same method parses those raw tags and mutates
backend fields; tail declaration/stub emitters later read `@undefined_externs`,
`@called_crystal_functions`, and `@emitted_functions`. Old authority edge:
`parallel-side-effect-file-merge`. New owner surface: a session-owned
side-effect merge contract that defines the row schema, producer set, duplicate
policy, malformed-row policy, semantic-failure vs tail-input classification, and
parent merge consumer. Required next code shape: extend
`scripts/llvm_emission_session_source_shape_guard.sh` with
`REQUIRE_SIDE_EFFECT_CONTRACT=1`, red on current source and green only when
`emit_functions_parallel` delegates worker side-effect writing and parent merge
through the contract rather than owning raw row tags/switches inline. Scope:
docs/design only; no compiler behavior changed and no green `s2b`/`s3b` claim.
Decay trigger: the side-effect contract implementation lands, B4 changes to a
different first-bad boundary, or prepatch guard evidence shows this edge is not
root-shaped.

[LM-ARCH-0K-BT-LLVM-EMISSION-VERTICAL-CONTRACT-CHECKPOINT|design-sealed 2026-07-01 {F:0.82 G:0.60 R:0.86}]:
Slice 0k-BT pauses production compiler edits after hostile review of the
post-0k-BS `LLVMEmissionSession` path. A local WIP that moved only worker `.se`
side-effect tag vocabulary into `LLVMEmissionSession` was saved in git stash as
`wip: llvm emission side-effect tag owner micro-slice before architecture
checkpoint`; it is not completion evidence and must not be committed as a
standalone architecture slice without re-review. The reviewed failure mode is
architecture metric drift: a tag/getter-only session migration can satisfy the
letter of "consume one edge" while leaving the real authority in mutable backend
fields, ad-hoc worker side-effect files, parent merge switches, tail extern/stub
sets, and CLI output ownership. New stop rule: the next
`GeneratedStageExecution` / `LLVMEmissionSession` production slice must move a
vertical contract boundary such as `SideEffectMergeContract`,
`TailDeclarationPlan`, `OutputOwnership`, or `ResourceEvidence`, and must prove a
downstream consumer no longer treats the old field/file/fallback source as sole
authority. Field-only, tag-only, getter-only, and report-only session changes are
rejected unless paired with that consumer movement and fresh B4 evidence. Scope:
docs/control-plane only; no compiler behavior changed, no `BlockOwner` rollback,
and no green `s2b`/`s3b` claim. Decay trigger: a committed vertical
`LLVMEmissionSession` contract slice lands, B4 reaches a different first-bad
boundary, or fresh evidence refutes `LLVMEmissionSession` as the active owner
boundary.

[LM-ARCH-0K-BS-LLVM-EMISSION-SESSION-WORKER-PLAN|implemented 2026-07-01 {F:0.86 G:0.34 R:0.88}]:
Slice 0k-BS implements the second behavior-neutral `LLVMEmissionSession`
owner migration. It consumes exactly the `worker-policy-inline` authority edge:
`LLVMIRGenerator#generate` now reads `effective_worker_count` from the session
instead of calling `parallel_llvm_workers` and applying the debug-info
sequential override inline. The session carries requested worker count,
effective worker count, and a compact sequential reason code; `emit_functions_parallel`
and its fallback-to-sequential behavior are unchanged. Guard:
`REQUIRE_SESSION=1 REQUIRE_WORKER_PLAN=1 scripts/llvm_emission_session_source_shape_guard.sh`
reports `worker_shape=session_consumes_worker_plan`,
`generate_inline_worker_count=0`, and
`generate_inline_debug_override_count=0`. Adversary refutation: a separate
`LLVMEmissionWorkerPlan` class made B4 fail during stage1->s2 build under the
4096MB gate, so the committed shape keeps worker-plan scalars inside
`LLVMEmissionSession`. Fresh B4 evidence returns to
`classification=current_0k_bn_frontier`. Scope: behavior-neutral worker-policy
ownership only; no side-effect merge, tail stub, output-file, resource
acceptance, materialization, parser, or `BlockOwner` behavior changed. B4
remains measured-red and no green `s2b` or `s3b` claim is made. Decay trigger:
`LLVMEmissionSession` moves another authority edge, B4 reaches a different
first-bad boundary, or worker/fallback behavior changes.

[LM-ARCH-0K-BR-LLVM-EMISSION-SESSION-FUNCTION-PLAN|implemented 2026-07-01 {F:0.86 G:0.36 R:0.88}]:
Slice 0k-BR implements the first behavior-neutral `LLVMEmissionSession`
owner migration. It consumes exactly the `function-list-inline` authority edge:
`LLVMIRGenerator#generate` now builds an `LLVMEmissionSession` and reads
`functions_to_emit` from it, while reachability selection, unresolved-pattern
skip propagation, return-type precompute, and mangled-name dedup live in
`build_llvm_emission_function_plan`. New guard:
`scripts/llvm_emission_session_source_shape_guard.sh`; with
`REQUIRE_SESSION=1` it reports `source_shape=session_consumes_function_plan`,
`generate_inline_reachability_count=0`, `generate_inline_skip_set_count=0`,
and `generate_inline_dedup_count=0`. Adversary refutation: implementing the
owner with Crystal `record` macros changed B4 to
`STUB CALLED: Adamas::MIR::LLVMEmissionFunctionPlan#functions_to_emit`; the
committed shape uses explicit private classes/methods and fresh B4 evidence
returns to `classification=current_0k_bn_frontier`. Scope: behavior-neutral
function-plan ownership only; no worker policy, fallback, side-effect merge,
tail stub, output-file, resource-acceptance, materialization, parser, or
`BlockOwner` behavior changed. B4 remains measured-red and no green `s2b` or
`s3b` claim is made. Decay trigger: `LLVMEmissionSession` moves another
authority edge, B4 reaches a different first-bad boundary, or the guard no
longer distinguishes session-owned plan construction from inline locals.

[LM-ARCH-0K-BQ-LLVM-EMISSION-SESSION-CONTRACT|design-sealed 2026-07-01 {F:0.84 G:0.58 R:0.88}]:
Slice 0k-BQ design-seals `LLVMEmissionSession` as the first concrete
`PhaseAuthority` owner record for the B4 generated-stage corridor. Source
inventory names the old authority edges: `src/compiler/cli.cr:2873-2979`
constructs/configures the backend, assigns HIR extern maps and constant
initializers, and owns `.ll` output file writing; `src/compiler/mir/llvm_backend.cr:2932-3044`
selects, filters, precomputes, dedups, and emits the function list;
`src/compiler/mir/llvm_backend.cr:17414-17776` chooses worker assignments,
forks workers, serializes side effects, merges side-effect tables, and silently
falls back to sequential emission on parallel failure; `src/compiler/mir/llvm_backend.cr:2087-2133`
holds emitted/called/undefined/string/function-index state as mutable backend
fields; `src/compiler/mir/llvm_backend.cr:3125-3144`, `3493-3638`, and
`3705-3798` derive tail extern declarations and missing-body stubs from those
sets. The next production code slice is admitted only as behavior-neutral
`contract-owner-migration`: introduce an `LLVMEmissionSession` record carrying
setup facts, function plan, worker plan, side-effect merge contract, tail plan,
output ownership, resource evidence, and generated-stage gate linkage, plus a
source-shape guard proving at least one old authority edge is consumed by the
record. Rejected in the first slice: changing emitted LLVM semantics, worker
defaults, fallback behavior, undefined extern declarations, missing-body stubs,
output-file behavior, resource acceptance thresholds, or `BlockOwner`. Scope:
docs/design only; B4 remains measured-red and no green `s2b`/`s3b` claim is
made. Decay trigger: a committed `LLVMEmissionSession` implementation slice
lands, B4 reaches a different first-bad boundary, or a stronger
`PhaseAuthority` owner contract supersedes this record.

[LM-ARCH-0K-BP-PHASE-AUTHORITY-FREEZE|design-sealed 2026-07-01 {F:0.83 G:0.62 R:0.87}]:
Slice 0k-BP freezes production symptom fixes after hostile review of the
post-0k-BO decision. `scripts/generated_stage_llvm_entry_classifier.sh`
remains the active B4 bootstrap pressure gate, but B4 is no longer treated as
permission to patch the latest LLVM-entry symptom. The next architecture
movement must first define the `PhaseAuthority` / `GeneratedStageExecution`
owner contract: which facts crossing stage1, produced `s2b`, LLVM emission,
and later generated stages are semantic, phase-local, emission-session-owned,
or debug/probe-only. Required fact families before behavior edits are
function-list identity, worker/fallback policy, side-effect table merge,
output-buffer lifetime, resource-budget accounting, and generated-stage
evidence. A future classifier extension is admitted only when it answers one
of those owner-boundary questions; a production behavior slice is admitted only
after the owner contract and focused guard name the old authority edge being
replaced, shadowed, or refuted. Rejected repeats: patching
`emit_functions_parallel` from the rand symptom, raising memory limits as
acceptance evidence, forcing `ADAMAS_LLVM_WORKERS=1`, backend undefined-extern
rescue, target keepalive/forwarders, another diagnostic report without an
owner question, H7/H8 bootstrap claims that do not move B4, or rolling
`BlockOwner` back to tuple/namedtuple metadata. Scope: docs/frontier control
only; no compiler behavior changed and no green `s2b`/`s3b` claim is made.
Decay trigger: a committed `PhaseAuthority` / `GeneratedStageExecution` owner
contract lands, B4 `REQUIRE_CLEAN=1` passes with generated-stage evidence, or
fresh evidence proves a different active bootstrap pressure gate.

[LM-ARCH-0K-BO-GENERATED-STAGE-LLVM-ENTRY-CLASSIFIER|measured-red 2026-07-01 {F:0.84 G:0.48 R:0.87}]:
Slice 0k-BO adds executable classifier
`scripts/generated_stage_llvm_entry_classifier.sh` for the 0k-BN / B4
generated-stage LLVM-entry frontier. The script builds or accepts a stage1
compiler, builds or accepts a produced `s2b`, and then compiles a full-prelude
tiny source twice with the produced compiler: default LLVM workers and
`ADAMAS_LLVM_WORKERS=1`. It is behavior-neutral and exposes two gates:
`REQUIRE_CURRENT_FRONTIER=1` asserts the current measured-red pattern, while
`REQUIRE_CLEAN=1` is the future green gate. Fresh evidence:
`REQUIRE_CURRENT_FRONTIER=1 scripts/generated_stage_llvm_entry_classifier.sh`
exits 0 with `classification=current_0k_bn_frontier`, `stage1_build_rc=0`,
`s2_build_rc=0`, `default_workers_after_lower_main=1`,
`default_workers_parallel_rand=1`, `default_workers_memory_kill=1`,
`workers1_after_lower_main=1`, `workers1_parallel_rand=0`, and
`workers1_exit139=1`. The classifier therefore turns the manual 0k-BN command
pair into a reproducible stop gate: next behavior work must name the first bad
owner boundary within the produced-stage LLVM emission entry path before
patching worker scheduling, memory limits, fallback behavior, output buffers,
or backend emission state. Scope: script + ledgers only; no compiler behavior
changed. Decay trigger: the classifier stops reproducing the current frontier,
`REQUIRE_CLEAN=1` passes, or a narrower `LLVMEmissionSession` owner-boundary
guard supersedes it.

[LM-ARCH-0K-BN-GENERATED-STAGE-LLVM-ENTRY-FRONTIER|measured-red 2026-07-01 {F:0.78 G:0.42 R:0.84}]:
Slice 0k-BN records the post-0k-BM generated-stage checkpoint. A fresh stage1
compiler built `src/adamas.cr` into a produced `s2b` through
`scripts/run_safe.sh`, so the H6-core `RuntimeTypeIdentity` owner fact does
not by itself block producing the next compiler. The produced `s2b` is not
clean: compiling a full-prelude `puts 42`/hello source with default LLVM
workers reports `parallel emission failed: Invalid bound for rand: 0`, falls
back to sequential emission, and is killed by `scripts/run_safe.sh` at the
4096MB RSS limit. Re-running the same produced compiler with
`ADAMAS_LLVM_WORKERS=1` removes the parallel-rand message and memory kill, but
still exits 139 immediately after `pass3 after lower_main call`. Boundary:
the current bootstrap blocker is a generated-stage transition into LLVM
emission after HIR/MIR setup, not H6-core TypeValue, not the H7 no-parens
parser guard, and not the H8 dynamic union `.class` guard. The next admitted
movement is a docs/falsifier-first `LLVMEmissionSession` classification slice
that names the first bad owner boundary across MIR setup, function emission
scheduling, worker/fallback policy, side-effect tables, output buffering, and
backend memory/resource ownership before behavior changes. Rejected repeats:
patching `emit_functions_parallel` from the rand symptom, raising the memory
budget as acceptance evidence, forcing `ADAMAS_LLVM_WORKERS=1`, treating
`fused_parallel_requested` cleanup as bootstrap progress, or selecting H7/H8
code solely because their focused guards remain red. Scope: docs/frontier
control only; no compiler behavior changed. Decay trigger: a fresh produced
`s2b` full-prelude compile reaches a different first-bad boundary, a focused
LLVM-entry falsifier supersedes the manual command pair, or a committed
`LLVMEmissionSession` owner slice changes the emission boundary.

[LM-ARCH-0K-BM-TYPEVALUE-OWNER-FACT-CORE|verified 2026-07-01 {F:0.88 G:0.48 R:0.90}]:
Slice 0k-BM implements the H6-core `TypeValue` / `RuntimeTypeIdentity`
contract-owner migration. HIR now owns a `RuntimeTypeIdentity` fact keyed by
`ValueId`, carrying semantic `TypeRef`, display name, origin (`typeof`,
runtime `.class`, explicit type literal, or type-literal query), and runtime
stringification policy. The slice shadows the old authority edges for
`typeof` nil placeholders, runtime `.class` type-literal construction,
`dot_class_literal?` stringification, direct output, interpolation, `<<`,
general call-argument conversion, type-literal query lowering, and local/copy
propagation for the H6-core rows. Multi-argument `typeof` now constructs and
prints the compile-time union, so the owner fact is not limited to
single-argument `typeof`. Fresh baseline evidence on clean HEAD reproduced
H6-core and B3 measured-red and H7 command-call measured-red. Fresh patched
evidence: `regression_tests/type_value_core_runtime_identity_contract.sh
/tmp/adamas_0kbl_typevalue`, `regression_tests/original_vs_stage_semantic_oracle_contract.sh
/tmp/adamas_0kbl_typevalue`, and `regression_tests/p2_type_literal_name_query_no_stub.sh
/tmp/adamas_0kbl_typevalue` all exit 0; the `IO::ByteFormat::LittleEndian`
adversary row `regression_tests/test_byteformat_decode_u32.cr` also exits 0,
proving explicit type literals are not stringified as call arguments; full
`regression_tests/run_all_suites.sh /tmp/adamas_0kbl_typevalue 4` exits 0
with `152/152 + 36/36`. H7 still exits 0 only in measured-red mode with
`ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH=1`. New residual:
`regression_tests/type_value_dynamic_union_class_residual.sh` records H8 as
measured-red with `ADAMAS_EXPECT_DYNAMIC_UNION_CLASS_MISMATCH=1`: dynamic
multi-variant union `.class` still prints static union display
`Int32 | String` where original Crystal prints runtime concrete `Int32`. Scope:
H6-core only; no parser behavior, generic materialization, requested-name
policy, ambient-map policy, backend stub/forwarder behavior, `BlockOwner`, or
broad `NamedTuple`/`Tuple` rendering changed. No green full-H6, `s2b`, or
`s3b` claim is made. Decay trigger: TypeValue consumers are rewritten again,
H7/H8 changes, or generated-stage evidence refutes the owner fact in s2b.

[LM-ARCH-0K-BL-ARCHITECTURE-EXECUTION-LADDER|design-sealed 2026-07-01 {F:0.84 G:0.64 R:0.88}]:
Slice 0k-BL converts the 0k-BK pause into an execution ladder for all future
production slices. A local uncommitted `TypeValue` / `RuntimeTypeIdentity`
owner-fact WIP existed, but it was quarantined in git stash before this
docs-only checkpoint and is not completion evidence. The next production slice
must select exactly one Active Architecture Board row and tranche, name the
legacy authority edge being retired/shadowed/refuted, name the new owner
fact/service and lifetime, enumerate producers and consumers before editing,
run a fresh measured-red baseline, prove the old authority edge is no longer
the sole authority, state generated-stage relevance, and record residual red
boundaries. Immediate consequence for TypeValue: the stashed WIP may be resumed
only as H6-core `contract-owner-migration`, with fresh H6-core/B3 baselines,
multi-argument `typeof` either fixed or explicitly scoped, remaining
`dot_class_literal?` / touched `type_literal?` consumers classified as
compatibility-only or still-authoritative, and the H7 command-call parser guard
kept separate unless a new parser `semantic-service-extraction` slice is
selected first. Rejected repeats remain backend forwarders, target keepalive,
materialization rescue, parser-precedence loops, global ambient-map policy
changes, broad `NamedTuple`/`Tuple` rendering patches, and `BlockOwner`
rollback. Scope: docs/frontier control only; no compiler behavior changed and
no green `s2b`/`s3b` claim is made. Decay trigger: a future production slice
passes this ladder and lands, the Active Architecture Board is superseded, or
fresh generated-stage evidence selects a different owner boundary.

[LM-ARCH-0K-BK-ARCHITECTURE-PAUSE-AFTER-HOSTILE-REVIEW|design-sealed 2026-07-01 {F:0.84 G:0.62 R:0.87}]:
Slice 0k-BK records the explicit architecture pause after hostile review of the
recent repeated pattern: local crash/root probes kept drifting toward backend
forwarders, target keepalive, materialization rescues, ambient-map policy
patches, parser loops, `NamedTuple`/`Tuple` rendering changes, or `BlockOwner`
rollback pressure. The current live guards still show two separate frontiers:
H6-core `TypeValue` / `RuntimeTypeIdentity` remains measured-red, and the
command-call member-access parser guard remains measured-red. The pause does
not revoke the admitted TypeValue lane; it tightens it. The only admitted
behavior movement is still H6-core `contract-owner-migration`, and it must
install a named HIR-owned `TypeValue` / `RuntimeTypeIdentity` fact keyed by
`ValueId` and consumed by the core producer/consumer set. Any future code slice
that needs backend stubs/forwarders, target keepalive, generic materialization,
requested-name or ambient-map policy, parser-precedence loops, broad
`NamedTuple`/`Tuple` behavior, or `BlockOwner` changes must stop before editing
and add a new SDD slice with a named authority edge, falsifier, root-size
budget, and residual boundary. Scope: docs/frontier control only; no compiler
behavior changed and no green `s2b`/`s3b` claim is made. Decay trigger: a
committed TypeValue owner fact lands, the active board is superseded, or fresh
generated-stage evidence proves a different owner boundary is the next
root-sized architecture movement.

[LM-ARCH-0K-BJ-TYPEVALUE-OWNER-FACT-GATE|design-sealed 2026-07-01 {F:0.84 G:0.56 R:0.87}]:
Slice 0k-BJ adds a docs-only implementation gate before the TypeValue
production slice. The next code movement remains `contract-owner-migration`,
but it must install a named HIR-owned `TypeValue` / `RuntimeTypeIdentity` fact
before claiming H6-core progress. The fact must be keyed to HIR `ValueId` and
carry semantic `TypeRef`, canonical display name, origin (`typeof`, runtime
`.class`, explicit type literal, or type-literal query), and runtime
stringification policy. Required producers are `lower_typeof`, runtime
`.class`, `lower_type_literal_from_name`, and type-literal name/string query
lowering. Required consumers are direct output, string interpolation,
call-argument conversion for runtime `.class`, H4 type-literal queries, and
local/copy propagation for the H6-core local nilable rows. Stop rule: a green
H6-core guard is rejected if it still derives source-visible type behavior from
nil placeholders, `dot_class_literal?`, rendered-name shortcuts, backend
stringification, or another local side map instead of the owner fact. Scope:
docs/design only; no compiler behavior changed, no parser behavior changed, no
`BlockOwner`, generic materialization, requested-name, ambient-map, backend
stub/forwarder, or broad `NamedTuple`/`Tuple` behavior changed. Decay trigger:
a committed TypeValue owner fact lands, H6-core changes, or source-shape review
shows the old authority edges no longer match the implementation plan.

[LM-ARCH-0K-BI-H6-SPLIT-TYPEVALUE-CORE-GUARD|measured-red 2026-07-01 {F:0.87 G:0.42 R:0.89}]:
Slice 0k-BI implements the H6 split route admitted by 0k-BH. New guard:
`regression_tests/type_value_core_runtime_identity_contract.sh <compiler>`.
It compares original Crystal and the supplied stage compiler through
`scripts/run_safe.sh` on direct and interpolated `typeof(1)`, direct and
interpolated `1.class`, local nilable `.class`, parenthesized nilable `.class`,
and type-literal `.name` / `.to_s` / `inspect`, while deliberately excluding
the parser-confounded no-parens command-call row
`puts (true ? 1 : nil).class`. Fresh evidence on current `bin/adamas`: strict
mode exits 1; `ADAMAS_EXPECT_TYPEVALUE_CORE_MISMATCH=1` exits 0 after the
stage binary prints blank direct/interpolated `typeof` rows and exits 139 at
`DIRECT_CLASS`. The existing
`regression_tests/command_call_member_access_preservation_contract.sh` remains
the separate measured-red frontend guard and exits 0 under
`ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH=1`. Scope: guard/test plus ledgers
only; no compiler behavior changed. Next admitted route:
`contract-owner-migration` for a HIR-owned `TypeValue` /
`RuntimeTypeIdentity` fact consumed by the core TypeValue rows. Do not claim
the full old H6 surface green until the command-call frontend guard is also
resolved. Decay trigger: the core guard becomes strict-green, the command-call
guard is resolved, or the TypeValue contract rows are redefined.

[LM-ARCH-0K-BH-ARCHITECTURE-PAUSE-GATE|design-sealed 2026-07-01 {F:0.82 G:0.58 R:0.86}]:
Slice 0k-BH adds a docs-only Architecture Pause Gate after the 0k-BG
command-call parser falsifier. A local uncommitted parser WIP widened
`LParen` handling in no-parens command-call parsing and added a tight postfix
hook for command-call arguments, but it was not completed or verified and was
removed before this checkpoint. The lesson is not that the parser boundary is
false; the 0k-BG guard remains measured-red. The lesson is that parser
precedence is broad enough to re-enter tail-chasing unless the production
slice is one bounded exception. Next admitted routes: either one parser-frontier
closure attempt that makes
`regression_tests/command_call_member_access_preservation_contract.sh`
strict-green while preserving targeted parser specs, or an explicit split of
H6 into TypeValue-core plus command-call-frontend guards before resuming the
TypeValue owner-fact migration. Stop rule: if the parser attempt needs a
second implementation loop, regresses adjacent parser specs, or grows into
generic command-call precedence work, revert/quarantine it and return to the
split-H6 / TypeValue-owner route. Scope: docs/frontier control only; no
compiler behavior changed. Forbidden repeats remain TypeValue output
special-cases, `BlockOwner` rollback, generic materialization changes,
requested-name or ambient-map policy changes, backend stubs/forwarders, and
broad `NamedTuple`/`Tuple` rendering. Decay trigger: the command-call guard is
made strict-green with parser-spec evidence, H6 is split, or a committed
TypeValue owner fact supersedes this gate.

[LM-ARCH-0K-BG-COMMAND-CALL-MEMBER-ACCESS-GUARD|measured-red 2026-07-01 {F:0.86 G:0.36 R:0.88}]:
Slice 0k-BG adds executable guard
`regression_tests/command_call_member_access_preservation_contract.sh` for the
frontend command-call expression-preservation boundary found in 0k-BF. The
guard builds a small parser-shape probe and runs it through `scripts/run_safe.sh`.
Strict mode currently exits 1 because `puts (true ? 1 : nil).class` parses as
a root `Adamas::Compiler::Frontend::MemberAccessNode` on the command-call
result, not as a command `CallNode` with a `.class` argument. With
`ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH=1`, the same guard exits 0 and
records the measured-red frontier. Negative controls in the guard assert that
`puts((true ? 1 : nil).class)` and `x = true ? 1 : nil; puts x.class` keep
`.class` as the command argument, while `puts (true ? 1 : nil)` remains a
command call with a ternary argument. Scope: falsifier only, no compiler
behavior change, no TypeValue owner migration, no bootstrap claim. Decay
trigger: parser command-call precedence changes, `CallNode`/`MemberAccessNode`
shape changes, or H6 is split/redefined.

[LM-ARCH-0K-BF-TYPEVALUE-PREFLIGHT-REFUTED-BY-COMMAND-CALL|design-sealed 2026-07-01 {F:0.78 G:0.40 R:0.82}]:
Slice 0k-BF records a docs-only failed-preflight after a reverted local
`contract-owner-migration` TypeValue implementation attempt. The WIP introduced
one HIR-owned type-visible value fact and migrated the H6-reached `typeof`,
`.class`, interpolation, direct-output, `<<`, and call-argument consumers. A
fresh stage1 build of that WIP made B3 and H4 green, but strict H6 still
failed only at direct `puts (true ? 1 : nil).class`: the stage output printed a
blank row where original Crystal prints `Int32`. Controls showed
`puts((true ? 1 : nil).class)`, `x = true ? 1 : nil; puts x.class`, and string
interpolation all printed `Int32`. Debug evidence on the WIP showed the direct
command-call argument was lowered as `Adamas::Compiler::Frontend::TernaryNode`,
not as a `.class` member access. The first new boundary is therefore a
frontend command-call expression-preservation gap, not another TypeValue
consumer. Scope: no production code committed; WIP reverted before this
landmark. Stop rule: do not make H6 green through a source-text direct-puts
workaround, backend stub/forwarder, `BlockOwner` rollback, requested-name
policy, ambient-map policy, or broad `NamedTuple`/`Tuple` rendering. Next
track: classify/falsify the command-call parser/lowering boundary as its own
`semantic-service-extraction` slice, or split H6 into a TypeValue core guard
plus a separate measured-red frontend guard before resuming TypeValue
production code. Decay trigger: command-call parsing/lowering changes, H6 rows
change, or a committed TypeValue implementation produces fresh strict H6
evidence.

[LM-ARCH-0K-BE-ARCHITECTURE-TRANCHE-SELECTOR|design-sealed 2026-07-01 {F:0.84 G:0.62 R:0.88}]:
Slice 0k-BE is a docs-only architecture tranche selector and tail-chasing stop
after the TypeValue implementation receipt. It does not revoke 0k-BD, but it
removes the implicit autopilot from "latest measured-red guard -> next code
fix". Before any production code slice, the slice must declare exactly one
tranche: `contract-owner-migration`, `semantic-service-extraction`,
`cleanup/delete`, or `bootstrap-emergency-with-ledger`. TypeValue remains
admitted only as `contract-owner-migration`: one HIR-owned type-visible fact
must retire or shadow the named H6 authority edges, and success on H6/B3 alone
must not be reported as green `s2b`/`s3b`. If TypeValue needs generic
materialization, `BlockOwner`, requested-name policy, ambient-map policy,
backend stubs/forwarders, or broad `NamedTuple`/`Tuple` rendering, stop and
return to G3 semantic-key migration or a higher-level semantic service
extraction plan. Scope: planning/frontier control only; no compiler behavior
changed and no bootstrap claim. Decay trigger: a production slice lands under
this selector, a fresh generated-stage run refutes the active board, or the SDD
changes tranche vocabulary.

[LM-ARCH-0K-BD-TYPEVALUE-IMPLEMENTATION-RECEIPT|design-sealed 2026-07-01 {F:0.82 G:0.56 R:0.88}]:
Slice 0k-BD is a docs-only implementation receipt for the H6 TypeValue
frontier. It deliberately pauses production changes after the measured-red H6
guard and before adding the HIR-owned `TypeValue` / `RuntimeTypeIdentity` fact.
The admitted production slice must replace a named set of old authority edges:
`typeof(...)`'s nil placeholder, runtime `.class` type-literal construction,
dot-class side maps, direct-output conversion, interpolation conversion, and
type-literal name/string query lowering. The owned fact must carry semantic
`TypeRef`, canonical display name, origin, and runtime-stringification versus
compile-time-only status. Rejected repeats are string-only `lower_typeof`,
interpolation-only or direct-output-only special cases, backend stubs or
forwarders, generic materialization changes, `BlockOwner` changes,
requested-name or ambient-map policy changes, and broad `NamedTuple`/`Tuple`
rendering normalization. If the consumer set widens beyond the H6 guard or
requires those rejected surfaces, the implementation must stop at
classification and return to the G3 semantic-key migration lane. Scope:
planning/frontier control only; no compiler behavior changed and no green
`s2b`/`s3b` claim. Decay trigger: the H6 guard changes, a TypeValue owner fact
lands, B3 strict turns green, or fresh generated-stage evidence selects a
different source-visible type-identity boundary.

[LM-ARCH-0K-BC-TYPEVALUE-RUNTIME-IDENTITY-GUARD|measured-red 2026-07-01 {F:0.86 G:0.42 R:0.89}]:
Slice 0k-BC adds executable guard
`regression_tests/type_value_runtime_identity_contract.sh <compiler>` for the
H6 `TypeValue` / `RuntimeTypeIdentity` contract. It builds and runs the same
source with original Crystal and the supplied stage compiler through
`scripts/run_safe.sh`, then compares direct and interpolated `typeof(1)`,
runtime `1.class`, nilable `(true ? 1 : nil).class`, and type-literal
`.name` / `.to_s` / `inspect` rows. The guard is strict by default; the env
`ADAMAS_EXPECT_TYPEVALUE_MISMATCH=1` is only for asserting the known
measured-red frontier. Fresh measured-red evidence on a stage1 built at this
slice shows blank direct/interpolated `typeof` rows followed by exit 139 at the
direct `.class` row. Scope: missing H6 falsifier closed, HIR-owned TypeValue
fact not implemented, B3 still not fixed, no green `s2b`/`s3b` claim. Decay
trigger: TypeValue guard rows, type-literal lowering, direct/interpolated
output conversion, original Crystal version, or `scripts/run_safe.sh` output
format changes.

[LM-ARCH-0K-BB-TYPEVALUE-RUNTIME-TYPE-IDENTITY|design-sealed 2026-07-01 {F:0.83 G:0.54 R:0.88}]:
Slice 0k-BB is a docs-only hostile self-review checkpoint after the measured-red
B3 oracle. The current type-visible semantic failure is now classified as a
`TypeValue` / `RuntimeTypeIdentity` frontier, not as a standalone
`lower_typeof` bug. The live source has multiple authority edges for the same
semantic family: `typeof(...)` lowers to a nil placeholder, runtime `.class`
creates a nil type-literal pointer, type-literal `.name` / `.to_s` / `inspect`
queries use their own lowering path, and string interpolation has a dot-class
literal special-case. The next admitted production slice must first add or
extend a falsifier covering direct and interpolated `typeof`, runtime `.class`,
nilable `.class`, and type-literal name/string queries, then introduce one
HIR-owned type-visible value fact consumed by those paths. Rejected repeats:
string-only `lower_typeof`, interpolation-only or direct-output-only special
cases, backend stubs/forwarders, generic materialization changes, `BlockOwner`
changes, and green `s2b`/`s3b` claims from B3 alone. Scope: planning/frontier
control only; no compiler behavior changed and no bootstrap claim. Decay
trigger: the TypeValue falsifier lands, HIR type-literal lowering is rewritten,
or fresh original-vs-stage evidence selects a different root boundary.

[LM-ARCH-0K-BA-B3-ORIGINAL-STAGE-SEMANTIC-ORACLE|measured-red 2026-07-01 {F:0.87 G:0.30 R:0.89}]:
Slice 0k-BA adds the B3 original-vs-stage semantic oracle:
`regression_tests/original_vs_stage_semantic_oracle_contract.sh <compiler>`.
It builds the same generated source with original Crystal and the supplied
stage compiler, runs both binaries through `scripts/run_safe.sh`, and compares
explicit source-visible semantic lines: `TYPE=`, `CONST=`, and `UNION=`.
Current stage output is measured-red: it preserves `CONST=7` but prints blank
`TYPE=` and `UNION=` where original Crystal prints `Int32`. The env
`ADAMAS_EXPECT_ORIGINAL_STAGE_MISMATCH=1` is only for asserting that known
frontier; strict mode remains the acceptance gate. Scope: missing-oracle hole
closed, type-visible semantic mismatch not fixed, no green `s2b`/`s3b` claim.
Decay trigger: `typeof` stringification, runtime `.class` stringification,
original Crystal version, `scripts/run_safe.sh` output format, or the B3
contract changes.

[LM-ARCH-0K-AZ-G3-GENERIC-SEMANTIC-KEY-GUARD|verified 2026-07-01 {F:0.86 G:0.38 R:0.90}]:
Slice 0k-AZ closes the missing G3 falsifier without migrating generic
materialization behavior. New guard:
`regression_tests/generic_identity_key_contract.sh`. It runs focused spec
`spec/semantic/generic_identity_key_spec.cr`, proving that
`GenericTemplateKey` equality/hash use owner name, template leaf name, source
`DefIdentity`, and declared type parameter names instead of display/rendered
names. It also proves `GenericInstanceKey` separates instances by template key,
specialization `SemanticTypeId` arguments, receiver identity when present, and
lexical owner, with defensive copies for mutable arrays. Scope: semantic
contract object and falsifier only; generic materialization/registration
call-sites are not yet migrated, and no green `s2b`/`s3b` claim is made.
Decay trigger: generic identity key fields, `DefIdentity`, `SemanticTypeId`, or
the G3 contract in `docs/specs/02-generic-template-registration.md` changes.

[LM-ARCH-0K-AY-H5-FUNCTION-BODY-PRESENCE-GUARD|verified 2026-07-01 {F:0.88 G:0.34 R:0.90}]:
Slice 0k-AY closes the missing H5 falsifier without changing compiler
behavior. New guard:
`regression_tests/hir_function_body_presence_contract.sh`. It runs focused
spec `spec/hir/function_body_presence_contract_spec.cr`, proving that
`HIR::Module#create_function` registers a function but leaves
`has_function_with_body?` false while the entry block still has only its
initial placeholder `Unreachable`; adding an instruction, setting a `Return`,
or explicitly setting an `Unreachable` terminator counts as emitted body
evidence. The same guard proves the downstream HIR->MIR boundary keeps a
bodyless registered HIR function as an empty MIR function with an
`Unreachable` terminator while a real body lowers to `Return`. Scope: contract
falsifier only; no production behavior changed and no green `s2b`/`s3b` claim.
Decay trigger: `has_function_with_body?`, HIR block emission flags, or HIR->MIR
function lowering semantics change.

[LM-ARCH-0K-AX-CONTRACT-FIRST-PIVOT|design-sealed 2026-07-01 {F:0.82 G:0.60 R:0.86}]:
Slice 0k-AX is a docs-only architecture pivot after 0k-AW. The repeated
frontier pattern is now load-bearing evidence: local generated-stage symptoms
have repeatedly led to narrower reports or parity helpers, then revealed a
deeper identity/state/materialization contract gap. The next work must
therefore be selected from contract debt, not from the latest crash stack.
Priority order: (1) function-body presence versus undefined/bodyless stubs
(`docs/specs/05-falsifier-matrix.md` H5), (2) generic template and instance
semantic keys versus rendered names (G3), and (3) original-vs-stage semantic
oracle coverage for future language-behavior changes (B3). A future slice may
still touch production code, but only after it names the contract hole, the old
authority edge, the falsifier/DoD, and why it is not another source-shape or
crash-progress proxy. Scope: planning/frontier control only; no compiler
behavior changed and no bootstrap claim. Decay trigger: a fresh generated-stage
failure is proven to bypass these contract holes and select a different
root-sized owner boundary with stronger evidence.

[LM-ARCH-0K-AW-SHARED-KEEP-REQUESTED-NAME-STATE|verified 2026-07-01 {F:0.86 G:0.40 R:0.88}]:
Slice 0k-AW implements the behavior-neutral shared keep-requested-name state
model admitted by 0k-AV. The paired frontend consumers
`lower_function_if_needed.callsite_args` and
`lower_function_if_needed.suffix_types` now construct a
`KeepRequestedNameDecision` record and read `emitted_result` from that record
instead of recomputing the keep-requested-name expression inline. The record
captures requested symbol, resolved/materialized symbol, selected definition,
predicate input types, collection-policy input types, legacy result, owner
result, emitted result, and a reason. Emitted behavior remains legacy/parity;
this is a state-model checkpoint, not a requested-name policy change and not a
green `s2b`/`s3b` claim. Evidence:
`SOURCE_SHAPE_ONLY=1 REQUIRE_REDESIGNED=1
scripts/semantic_state_scope_admission_report.sh` reports both paired
consumers as `shared_keep_requested_name_model`,
`redesigned_frontend_count=2`, and `state_model_redesign_complete=1`; the
negative no-repeat gate `SOURCE_SHAPE_ONLY=1 REQUIRE_SELECTED=1 ...` still
exits `9`; `regression_tests/block_owner_index_assign_materialization_repro.sh
/tmp/adamas_0kaw_stage1` reports a non-stub
`Hash(UInt64, BlockOwner)#[]=` materialization; split materialization guards
for `String#split(Char)` and coexisting Char/String separators pass on the same
fresh stage1. Scope: shared parity state and guard replacement only. Decay
trigger: emitted keep-requested-name behavior flips, the paired consumers stop
using the record, the owner carrier changes again, or a future generated-stage
run refutes this as the active semantic-state boundary.

[LM-ARCH-0K-AV-STALE-NAMEDTUPLE-HASH-GUARD-RETIRED|verified 2026-07-01 {F:0.86 G:0.32 R:0.90}]:
The executable regression
`regression_tests/hash_named_tuple_index_assign_materialization_repro.sh` was
retired as stale. It searched generated self-IR for the old
`Hash(UInt64, NamedTuple)#[]=` owner-cache materialization/stub shape, while the
current admitted owner carrier is `Hash(UInt64, BlockOwner)`. Running the old
script after the `BlockOwner` migration can produce a false red
`no Hash(UInt64, NamedTuple)#[]= materialization found` even when the current
carrier is not being tested. Future 0k-AV work must add a successor guard for
the current `BlockOwner` carrier before using owner-cache materialization as
DoD. Scope: stale regression retirement only; no compiler behavior changed and
no bootstrap claim. Decay trigger: a successor `BlockOwner` owner-cache
materialization regression lands or the owner carrier changes again.

[LM-ARCH-0K-AV-PLAN-BEFORE-STATE-SCOPE-HELPER|design-sealed 2026-07-01 {F:0.84 G:0.54 R:0.88}]:
Slice 0k-AV is a docs-only hostile self-review checkpoint after 0k-AU. The
0k-AU selector correctly forced a state-model redesign because
`lower_function_if_needed.callsite_args` and `.suffix_types` are a paired
frontend authority problem, not two independent consumers to choose by source
order. A local uncommitted shared keep-requested-name helper WIP showed that the
next failure mode is making `state_model_redesign_complete=1` a new proxy
metric: source shape can become green while semantic identity remains inferred
from legacy ambient predicates. That WIP was reverted before this checkpoint.
The next production slice is admitted only as a behavior-neutral shared
keep-requested-name state model with an explicit owned fact, old authority edge,
legacy parity rule, stale-regression audit, and generated-stage guard. It must
not claim `s2b`/`s3b` progress from source shape alone. The stale
`hash_named_tuple_index_assign_materialization_repro.sh` gate has been retired;
a successor guard must target the current `BlockOwner` carrier before
owner-cache materialization can be used as DoD. Rejected repeats remain backend
forwarder, target
keepalive, requested-name force, `NamedTuple`/`Tuple` rendering change, global
ambient-map policy change, and `BlockOwner` rollback. Scope: plan/SDD
checkpoint only; no compiler behavior changed and no bootstrap claim. Decay
trigger: a future 0k-AV implementation lands with behavior-neutral parity and
fresh generated-stage evidence, or fresh evidence selects a different active
owner boundary.

[LM-ARCH-0K-AU-STATE-SCOPE-NO-REPEAT-SOURCE|verified 2026-07-01 {F:0.86 G:0.48 R:0.88}]:
Slice 0k-AU extends `scripts/semantic_state_scope_admission_report.sh` with
`SOURCE_SHAPE_ONLY=1`, a no-repeat source-shape selector for remaining
`SemanticStateScope` consumers. It scans
`src/compiler/hir/ast_to_hir.cr` without running a compiler and reports
`prefer_callsite_specialization` plus `lower_function_if_needed.override` as
`already_promoted_shadow`, `lower_call.remangle` as `rejected_backend_adjacent`,
and the two remaining frontend direct consumers
`lower_function_if_needed.callsite_args` / `.suffix_types` as
`rejected_multiple_frontend_candidates`. Evidence:
`SOURCE_SHAPE_ONLY=1 scripts/semantic_state_scope_admission_report.sh` prints
`malformed_direct=0`, `frontend_candidate_count=2`, `selected_count=0`,
`already_promoted_count=2`, and `state_model_redesign_required=1`;
`SOURCE_SHAPE_ONLY=1 REQUIRE_SELECTED=1 ...` exits `9`. Consequence: the next
architecture move must be a state-model redesign checkpoint for shared
`lower_function_if_needed` keep-requested-name state, or a stronger falsifier
that collapses the two frontend candidates to exactly one root-sized authority
edge. It is not admitted to pick either consumer by source order or convenience.
Scope: source-shape gate only; no compiler behavior, bootstrap claim,
`BlockOwner` carrier change, backend forwarder, requested-name force, or
`NamedTuple`/`Tuple` rendering change. Decay trigger: the direct caller set
changes, one frontend candidate is eliminated/promoted with evidence, or fresh
generated-stage evidence selects a different state-owner boundary.

[LM-ARCH-0K-AT-SEMANTIC-IDENTITY-PIVOT|design-sealed 2026-07-01 {F:0.82 G:0.50 R:0.86}]:
Slice 0k-AT pauses cleanup/report pursuit for the bootstrap objective and
selects the next root architecture lane: a no-repeat `SemanticStateScope`
selection gate for remaining direct ambient-predicate consumers. The already
promoted `prefer_callsite_specialization` and `lower_function_if_needed.override`
seams must not be selected again. The live source still has direct
`state_scope_consumer_def_has_untyped_regular_param?` callers in
`lower_function_if_needed.callsite_args`,
`lower_function_if_needed.suffix_types`, and `lower_call.remangle`; the selector
must reject promoted and backend-adjacent seams and select at most one
unpromoted root-sized consumer for a future behavior-neutral owner decision. If
no such consumer exists, the next movement is a higher-level state-model
redesign checkpoint, not another report or cleanup classification. Rejected
repeats: backend forwarder, target keepalive, requested-name force,
`NamedTuple`/`Tuple` rendering normalization, global ambient-map policy changes,
additional cleanup classification as bootstrap progress, and `BlockOwner`
rollback. Scope: planning/frontier control only; no compiler behavior and no
bootstrap claim. Decay trigger: the direct ambient-predicate caller set changes,
a future SDD slice explicitly selects cleanup/bloat as the active constraint, or
fresh generated-stage evidence refutes this as the active semantic-identity
boundary.

[LM-ARCH-0K-AS-FUSED-PARALLEL-CLASSIFIED|verified 2026-07-01 {F:0.84 G:0.30 R:0.88}]:
Slice 0k-AS adds a focused `CodePathStatus` cleanup classification for
`fused_parallel_requested`. The cleanup-entry report now supports
`SELECTED_CLEANUP_PATH=fused_parallel_requested` and reports
`cluster=cli.mir`, `status=experimental_live`,
`default_status=not_taken`, `enabled_status=taken`,
`default_rows=1`, `enabled_rows=1`, and `action=keep_experimental_live` on a
fresh stage1 no-prelude run. Negative control remains:
`REQUIRE_DELETE_READY=1` exits 9 with
`inventory_status=no_delete_ready_candidate`. Decision: the fused parallel MIR
path is not delete-ready from current evidence; do not delete it. Scope:
cleanup classification only; no compiler behavior and no bootstrap claim.
Decay trigger: fused parallel semantics are removed by design, the path starts
failing its protecting falsifier, or a future SDD slice intentionally reopens
experimental MIR parallelism.

[LM-ARCH-0K-AR-CLEANUP-INVENTORY|verified 2026-07-01 {F:0.84 G:0.42 R:0.88}]:
Slice 0k-AR extends the `CodePathStatus` cleanup-entry report with a
fail-closed runtime inventory mode. With `LIST_RUNTIME_PATHS=1`, a fresh stage1
no-prelude compile reports `inventory_rows=26`, `inventory_paths=26`,
`inventory_malformed=0`, `inventory_delete_ready_rows=0`, and
`inventory_status=no_delete_ready_candidate`. Negative control:
`LIST_RUNTIME_PATHS=1 REQUIRE_DELETE_READY=1` exits 9 with
`inventory_status=no_delete_ready_candidate`. The inventory marks default-live
paths as `live_default` and default-not-taken paths as `not_taken_unproven`; it
does not promote any row to `delete_ready`. Decision: no cleanup/delete behavior
change is admitted yet. The next cleanup slice must select one
`not_taken_unproven` path and add a protecting falsifier, or define a stricter
`eligible_delete_ready_candidate` class before deleting code. The cleanup
runtime-support report now creates repo-local `tmp/` before `mktemp`. Scope:
cleanup selector coverage only; no compiler behavior and no bootstrap claim.
Decay trigger: a future inventory reports an eligible delete-ready candidate,
runtime path semantics change, or the cleanup lane is paused in favor of a
root-sized correctness edge.

[LM-ARCH-0K-AQ-CLEANUP-PREFLIGHT|verified 2026-07-01 {F:0.82 G:0.34 R:0.88}]:
After Slice 0k-AP, a fresh stage1 ran the existing
`scripts/codepath_status_cleanup_selection_report.sh` cleanup-entry gate for
both supported paths. `SELECTED_CLEANUP_PATH=identity_dry_run` and
`SELECTED_CLEANUP_PATH=phase0_metrics` each reported `default_rc=0`,
`enabled_rc=0`, `default_status=not_taken`, `enabled_status=taken`, and
`status=debug_only`. Decision: neither current CLI metrics path is
`delete_ready`; do not delete `identity_dry_run` or `phase0_metrics` from the
existing cleanup-entry evidence. The next cleanup/delete slice must select a
different named path or first extend the cleanup selector to enumerate a
root-sized candidate with a protecting falsifier. Scope: cleanup preflight only;
no compiler behavior and no bootstrap claim. Decay trigger: cleanup selector
semantics change, a future `CodePathStatus` run reports either path as
`delete_ready`, or the CLI metrics paths are redesigned.

[LM-ARCH-0K-AP-SURFACE-CONSOLIDATION|design-sealed 2026-07-01 {F:0.80 G:0.52 R:0.86}]:
Slice 0k-AP consolidates the architecture report surface after the ambiguous
0k-AO residual. The active SDD now classifies existing report scripts by role:
`generated_stage_transaction_edge_selection_report.sh` is the
`active-stop-gate`; `generated_stage_transaction_spine_classifier.sh` is
supporting only; promoted source-shape reports for
`CallMaterializationTransaction`, `MaterializationSymbolBinding`,
`MethodNameCodec`, `InvocationContext`, and `SemanticStateScope` are guards,
not new selectors; `codepath_status_cleanup_selection_report.sh` is the current
cleanup/delete entry point and creates repo-local `tmp/` before `mktemp`; older
census, ledger, arena, materialization, and layout reports are historical unless
reactivated by a future SDD slice with a decision question, root-size budget,
negative control, and old authority edge.
Decision: the default next executable slice should be `cleanup/delete` through
`CodePathStatus`, or a stronger correctness-selection discriminator that
selects exactly one old authority edge. Scope: control-plane consolidation
only; no compiler behavior, no new bootstrap claim, no `BlockOwner` change.
Decay trigger: a future slice reactivates one historical report with a full SDD
receipt, the active stop gate selects exactly one residual edge, or the board
switches to a different owner boundary.

[LM-ARCH-0K-AO-EXACT-RESIDUAL-AMBIGUOUS|verified 2026-07-01 {F:0.86 G:0.48 R:0.88}]:
Slice 0k-AO extends the existing generated-stage transaction edge selector with
a post-consumer exact-contract missing-body residual classifier. The selector
now creates repo-local `tmp/` before `mktemp`, reports `MAX_RESIDUAL_ROWS`, and
splits `call_materialization.exact_contract.extern_missing_body` by phase,
branch, emitted owner, required contract, symbol relation, and identity status.
Synthetic ledgers covered eligible, ambiguous, too-wide, and no-residual states.
Fresh generated-stage evidence reports `classifier_classification=
reached_tx_and_emit`, `post_consumer_state=
selected_consumed_by_contract_consumer`, `contract_mismatch_rows=0`,
`other_missing_body_rows=14`, `residual_exact_missing_body_rows=14`,
`residual_exact_missing_body_groups=9`,
`residual_exact_missing_body_root_sized_groups=9`, and
`residual_selection_status=rejected_exact_missing_body_ambiguous`. Negative
control: `REQUIRE_RESIDUAL_SELECTED=1` exits 9 on the same log. Decision: the
post-0k-AM exact residual is ambiguous, not a selected behavior-fix edge.
Samples such as `Array#<<`, `Slice#[]`, `IO#read`, `Atomic#get`,
`StaticArray`, `String::Builder`, and `Int32` are routing evidence only. Next
slice must either add a stronger discriminator that names exactly one old
authority edge, or switch to `consolidation` / `cleanup/delete` under the 0k-AN
covenant. Scope: selector/source-shape classification only; no compiler
behavior and no green `s2b`/`s3b` claim. Decay trigger: a fresh generated-stage
run selects exactly one residual group, the residual disappears, or the active
board moves to a different owner boundary.

[LM-ARCH-0K-AN-PACING-COVENANT|design-sealed 2026-07-01 {F:0.78 G:0.54 R:0.86}]:
Slice 0k-AN adds a docs-only architecture pacing covenant after 0k-AM. It
records that the next step must not replace consumer-patch tail-chasing with
selector/report tail-chasing. Future slices must choose exactly one lane before
production edits: `correctness-selection`, `consumer-migration`,
`cleanup/delete`, or `consolidation`. A selector/report slice must state its
decision question, root-size budget, negative control, and the old authority
edge a future consumer would replace or shadow. A broad result such as the
current `other_missing_body_rows=14` stops at classification and does not
authorize behavior changes. A consumer migration requires a root-sized selected
edge plus a DoD proving a legacy consumer reads the owned fact in shadow/parity
mode or that the old edge is refuted. Cleanup requires `CodePathStatus` with a
protecting falsifier. Consolidation must retire, merge, or mark stale an older
report/gate or historical next-step paragraph. No two consecutive report-only
slices are admitted unless the second removes or refutes a previous report
surface. Scope: SDD/TODO/LANDMARKS pacing rule only; no compiler behavior and no
green `s2b`/`s3b` claim. Decay trigger: a future slice proves this covenant is
too restrictive for a root-sized generated-stage edge, or the active board is
replaced by a narrower executable roadmap with equivalent anti-tail-chase
guards.

[LM-ARCH-0K-AM-CONTRACT-CONSUMER|verified 2026-07-01 {F:0.88 G:0.44 R:0.90}]:
Slice 0k-AM implements the behavior-neutral `CallMaterializationTransaction`
contract consumer for the selected 0k-AJ transaction/emission edge. HIR now
stores `MaterializationTransactionContract` facts by transaction id; HIR-to-MIR
attaches `MaterializationContractFacts` to transaction-bound `Call` and
`ExternCall`; backend `[MAT_EMIT]` rows print those contract fields
mechanically; optimizer call replacement preserves both transaction id and
contract metadata. This changes ledger authority only: no emitted call target,
body materialization, backend forwarder, requested-name policy, target keepalive
policy, ambient-map policy, `NamedTuple`/`Tuple` rendering, cleanup behavior, or
`BlockOwner` carrier changed. Fresh generated-stage evidence with a fresh
stage1 reports `classifier_classification=reached_tx_and_emit`,
`mat_tx_rows=735`, `mat_emit_rows=173`, `transaction_bound_emit_rows=68`,
`candidate_selected_rows=0`, `contract_consumer_rows=2`,
`candidate_contract_consumer_rows=2`, `contract_mismatch_rows=0`,
`selection_status=eligible_contract_consumer_state`, and
`post_consumer_state=selected_consumed_by_contract_consumer`. Broader guard:
full suites pass `152/152 + 36/36`. Decision: the 0k-AJ selected edge is now
consumed, not a behavior-fix target. Next admitted slice must select the next
reached transaction/emission edge, likely by splitting the broad exact-contract
missing-body residual (`other_missing_body_rows=14`) into a root-sized class
before any behavior change. Scope: metadata/ledger authority migration only; no
green `s2b`/`s3b` claim. Decay trigger: a fresh generated-stage gate no longer
reports `selected_consumed_by_contract_consumer`, contract mismatches appear,
optimizer copies drop contract metadata, or future generated-stage evidence
refutes `CallMaterializationTransaction` as the active owner boundary.

[LM-ARCH-0K-AL-POST-CONSUMER-STATE-GATE|verified 2026-07-01 {F:0.86 G:0.42 R:0.88}]:
Slice 0k-AL makes the 0k-AK post-consumer selector-state rule executable.
`scripts/generated_stage_transaction_edge_selection_report.sh` now prints
`post_consumer_state` and accepts `REQUIRE_POST_CONSUMER_STATE=<state>`.
The state machine distinguishes `selected_not_consumed`,
`selected_consumed_by_contract_consumer`, and `selected_refuted_or_stale`, so a
future consumer migration does not have to pretend that the old 0k-AJ selector
must stay green after its authority edge is consumed. Synthetic ledger checks
covered all three states. Fresh generated-stage evidence with a fresh stage1:
`classifier_classification=reached_tx_and_emit`, `mat_tx_rows=591`,
`mat_emit_rows=69`, `transaction_bound_emit_rows=29`,
`candidate_selected_rows=4`, `candidate_selected_distinct_txs=3`,
`contract_consumer_rows=0`, `candidate_contract_consumer_rows=0`,
`contract_mismatch_rows=0`, `selection_status=eligible_reached_transaction_emission_edge`,
and `post_consumer_state=selected_not_consumed`. Decision: the next production
slice may implement the behavior-neutral `CallMaterializationTransaction`
contract consumer for the selected edge, but its success criterion is
`selected_consumed_by_contract_consumer` with zero contract mismatches, not a
backend forwarder, target keepalive, requested-name force,
`NamedTuple`/`Tuple` normalization, global ambient-map policy change, direct
segfault patch, or `BlockOwner` rollback. Scope: selector/tool gate only; no
compiler behavior and no `s2b`/`s3b` green claim. Decay trigger:
post-consumer state cannot be reproduced on a fresh generated-stage corridor,
or a future generated-stage run refutes `CallMaterializationTransaction` as the
active owner boundary.

[LM-ARCH-0K-AK-POST-CONSUMER-DECAY-GATE|design-sealed 2026-07-01 {F:0.74 G:0.46 R:0.82}]:
Slice 0k-AK is a docs-only stop checkpoint after the 0k-AJ generated-stage
transaction/emission edge selector. An uncommitted behavior-neutral
shadow-consumer WIP that copied `CallMaterializationTransaction` contract facts
through MIR calls/extern-calls into backend `[MAT_EMIT]` rows was removed before
commit. It was directionally aligned with Phase 2b, but it changed the old
selector's meaning before the SDD defined post-consumer success states. Decision:
the next production slice must first refresh the
`CallMaterializationTransaction` row's DoD and explicitly classify the old
selected edge as `selected_not_consumed`,
`selected_consumed_by_contract_consumer`, or `selected_refuted_or_stale`.
If adding a consumer makes the old 0k-AJ selected edge disappear, that is a
decay event to record, not a reason to redefine rows until
`REQUIRE_SELECTED=1` turns green. Rejected moves remain: backend forwarder or
undefined-extern rescue, requested-name force, target keepalive,
`NamedTuple`/`Tuple` normalization, global ambient-map policy change, direct
segfault patch, and `BlockOwner` rollback. Scope: plan/SDD checkpoint only; no
compiler behavior and no `s2b`/`s3b` green claim. Decay trigger: a future
committed slice defines and verifies the post-consumer selector states or a
fresh generated-stage run refutes `CallMaterializationTransaction` as the
active owner boundary.

[LM-ARCH-GENERATED-STAGE-TX-EMIT-EDGE-SELECTION|verified 2026-07-01 {F:0.86 G:0.36 R:0.88}]:
Slice 0k-AJ adds an executable reached-edge selector:
`scripts/generated_stage_transaction_edge_selection_report.sh`. It parses an
existing classifier log or runs the generated-stage spine classifier, joins
transaction-bound `[MAT_EMIT]` rows to their `[MAT_TX]` metadata, and selects
the next reached `CallMaterializationTransaction` contract class:
`call_materialization.wrapper_or_call_remap.extern_missing_body`
(`required_contract=wrapper_or_call_remap`,
`symbol_relation=body_eq_target_call_eq_requested`,
`identity_status=rejected_mismatch`, backend `kind=extern`, and
`body_present=0`). Fresh current evidence: `classifier_classification=
reached_tx_and_emit`, `mat_tx_rows=604`, `mat_emit_rows=69`,
`transaction_bound_emit_rows=29`, `candidate_selected_rows=4`,
`candidate_selected_distinct_txs=3`, `candidate_selected_owner_kinds=2`,
`candidate_selected_branch_kinds=1`, `source_shape=eligible_reached_edge`, and
`selection_status=eligible_reached_transaction_emission_edge`. Negative control:
with `MAX_SELECTED_ROWS=3`, the same log is rejected as
`selected_edge_too_wide`. Decision: the next production slice may target this
selected transaction/emission edge in shadow/parity mode, but must not jump to a
backend forwarder, target keepalive, requested-name force, `NamedTuple`/`Tuple`
normalization, global ambient-map change, `BlockOwner` rollback, or direct
segfault patch. Decay trigger: the selector reports
`rejected_missing_selected_edge`, `rejected_selected_edge_too_wide`, malformed
ledger rows, or a future generated-stage classifier stops reaching
transaction-bound emits.

[LM-ARCH-GENERATED-STAGE-TX-SPINE-CLASSIFIER|verified 2026-07-01 {F:0.86 G:0.42 R:0.88}]:
Slice 0k-AI adds an executable generated-stage transaction-spine classifier:
`scripts/generated_stage_transaction_spine_classifier.sh`. It builds/uses a
fresh generated s2 through `scripts/run_safe.sh`, compiles a full-prelude
`puts 42` source with `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1`, and
classifies whether the active generated-stage frontier reaches
`CallMaterializationTransaction` rows and transaction-bound emitted-call rows.
Fresh current evidence: `s2_build_rc=0`, `compiler_rc=139`,
`mat_id_rows=615`, `mat_tx_rows=615`, `mat_emit_rows=69`,
`transaction_bound_mat_emit_rows=29`, `stub_rows=0`, and
`classification=reached_tx_and_emit`. Decision: the transaction spine is
reached before the current full-prelude generated-stage segfault, so the next
production slice may stay on `CallMaterializationTransaction`, but only after a
new gate selects one reached transaction/emission edge. Scope: classifier and
plan evidence only; no compiler behavior, backend behavior, requested-name
policy, target keepalive policy, `NamedTuple`/`Tuple` rendering, ambient-map
policy, cleanup behavior, or `BlockOwner` changed. This is not green generated
s2, `s2b`, or `s3b`. Decay trigger: a fresh generated-stage classifier reports
`tx_only_no_emit`, `no_tx_rows`, or build-corridor failure, or a future reached
edge selection refutes transaction/emission correlation as the active frontier.
Current selector: [LM-ARCH-GENERATED-STAGE-TX-EMIT-EDGE-SELECTION].

[LM-ARCH-POST-0K-AH-TAIL-CHASE-CHECKPOINT|superseded 2026-07-01 {F:0.80 G:0.44 R:0.86}]:
After Slice 0k-AH, the architecture track is paused before more production
transaction-consumer migrations. The selected instance-symbol consumers are
already promoted, but the broader transaction source-shape gate still reports
`residual_legacy_edge_count=20`; lowering that number without generated-stage
reachability evidence can become metric chasing rather than bootstrap progress.
The next admitted executable slice must classify a fresh generated s2
full-prelude corridor: does it reach joined `CallMaterializationTransaction`
facts (`[MAT_TX]` / `[MAT_EMIT]`) before the next failure? If yes, the next
transaction slice may select a reached transaction consumer. If no, the
transaction lane pauses and work moves to the reached owner boundary or to a
`CodePathStatus` cleanup slice. Evidence: current `TODO.md` and
`docs/compiler_architecture_sdd.md` record the 0k-AI decision table; current
source-shape gates show `selected_binding_consumer_count=0` for the promoted
consumer group and `residual_legacy_edge_count=20` for the broader transaction
surface. Scope: docs-only pacing checkpoint, not compiler behavior, not green
full-prelude generated s2, not `s2b`, and not `s3b`. Decay trigger: a fresh
generated-stage transaction classifier proves the transaction spine is reached,
or a newer generated-stage run refutes transaction reachability as the active
frontier. Superseded by [LM-ARCH-GENERATED-STAGE-TX-SPINE-CLASSIFIER].

[LM-ARCH-CALL-MATERIALIZATION-INSTANCE-CONSUMER|verified 2026-07-01 {F:0.86 G:0.38 R:0.90}]:
The selected `CallMaterializationTransaction` instance-symbol consumer group is
promoted in behavior-neutral shadow/parity mode. The instance-method override,
keepalive, and diagnostic materialization-symbol consumers in
`lower_function_if_needed_impl` now read `instance_transaction.*` fields rather
than direct `MaterializationSymbolBinding` fields. `CallMaterializationTransaction`
now carries `override_symbol : String?`, preserving the previous optional
override semantics while letting selected consumers read the transaction owner
record. Evidence: `REQUIRE_PROMOTED=1
scripts/call_materialization_transaction_consumer_selection_report.sh` exits 0
with `preferred_source_shape=already_promoted_shadow`,
`transaction_constructor_count=3`, `transaction_field_read_count=6`,
`instance_override_binding_count=0`, `keepalive_binding_count=0`,
`regmat_binding_count=0`, and `selected_binding_consumer_count=0`;
`REQUIRE_PROMOTED=1 scripts/call_materialization_transaction_admission_report.sh`
exits 0 with `symbol_binding_field_read_count=0`,
`transaction_field_read_count=6`, and `residual_legacy_edge_count=20`;
`REQUIRE_PROMOTED=1 scripts/materialization_symbol_binding_admission_report.sh`
exits 0 with `binding_transaction_count=3`; `crystal build src/adamas.cr -o
/private/tmp/adamas_0kah_stage1 --error-trace` exits 0; materialization ledger
and transaction reports pass; full suites pass `152/152 + 36/36`; fresh stage1
builds fresh generated s2 through `scripts/run_safe.sh`; generated s2 compiles
and runs a no-prelude `x = 1; puts x` smoke. Scope: selected consumer
source-shape and broad-regression migration only. It does not flip emitted
symbols, backend behavior, requested-name policy, target keepalive policy,
`NamedTuple`/`Tuple` rendering, global ambient-map policy, cleanup behavior, or
`BlockOwner`, and it is not green full-prelude generated s2, `s2b`, or `s3b`.
Decay trigger: selected consumers start reading `symbol_binding.*` directly
again, transaction construction is rewritten, or a future generated-stage
classifier refutes this transaction edge as relevant.

[LM-ARCH-CALL-MATERIALIZATION-TRANSACTION-CONSUMER-SELECTION|superseded 2026-07-01 {F:0.78 G:0.38 R:0.86}]:
Slice 0k-AG selects the next `CallMaterializationTransaction` consumer edge
without changing compiler behavior. The selected edge is
`lower_function_if_needed.instance_symbol_consumers`: the instance branch
already constructs `CallMaterializationTransaction` records, but the selected
override, keepalive, and diagnostic materialization-symbol consumers still
read `MaterializationSymbolBinding` fields directly. Evidence:
`scripts/call_materialization_transaction_consumer_selection_report.sh` exits 0
with `preferred_source_shape=legacy_instance_symbol_consumers`,
`transaction_constructor_count=3`, `transaction_field_read_count=0`,
`instance_override_binding_count=2`, `keepalive_binding_count=3`,
`regmat_binding_count=1`, and `selected_binding_consumer_count=6`.
`REQUIRE_PROMOTED=1
scripts/call_materialization_transaction_consumer_selection_report.sh` exits 9,
proving the edge is not promoted yet. Scope: source-shape selection and
architecture stop-rule only; no compiler source, emitted symbols, backend
behavior, requested-name policy, target keepalive policy, `NamedTuple`/`Tuple`
rendering, global ambient-map policy, cleanup behavior, or `BlockOwner`
changed, and this is not green full-prelude generated s2, `s2b`, or `s3b`.
Next work: migrate exactly this selected consumer group to read transaction
fields in shadow/parity mode while preserving emitted behavior. Decay trigger:
`lower_function_if_needed_impl` stops constructing instance transactions, the
selected consumers stop reading `symbol_binding.*`, or a future generated-stage
classifier refutes this transaction edge as relevant. Superseded by
[LM-ARCH-CALL-MATERIALIZATION-INSTANCE-CONSUMER] after Slice 0k-AH.

[LM-ARCH-CALL-MATERIALIZATION-TRANSACTION-CONSUMER|verified 2026-07-01 {F:0.84 G:0.40 R:0.88}]:
The first selected `CallMaterializationTransaction` consumer is promoted in
behavior-neutral shadow/parity mode. `src/compiler/hir/ast_to_hir.cr` now has a
`CallMaterializationTransaction` owner record and
`call_materialization_transaction(...)` helper joining request name parts,
requested/target/body/call symbols, selected definition and owner, state scope,
target map, call arg shape, ABI shape, wrapper/forwarder contract, and rejection
reason for the materialization identity/state-scope ledger path. The old
split-argument `log_materialization_identity_ledger(...)` calls are gone;
`log_call_materialization_transaction_ledger(transaction)` reads the record
instead. Evidence: `REQUIRE_PROMOTED=1
scripts/call_materialization_transaction_admission_report.sh` exits 0 with
`preferred_source_shape=already_promoted_shadow`, `transaction_type_count=3`,
`transaction_helper_count=3`, `legacy_ledger_call_count=0`,
`transaction_ledger_call_count=3`, `ledger_transaction_field_read_count=4`, and
`residual_legacy_edge_count=26`; `REQUIRE_PROMOTED=1
scripts/materialization_symbol_binding_admission_report.sh` exits 0 with
`binding_transaction_count=3`; `crystal build src/adamas.cr -o
/private/tmp/adamas_0kaf_stage1 --error-trace` exits 0; and
`scripts/materialization_identity_ledger_smoke.sh
/private/tmp/adamas_0kaf_stage1` exits 0; `scripts/materialization_transaction_report.sh
/private/tmp/adamas_0kaf_stage1` exits 0 with `malformed=0`,
`owner_malformed=0`, and `unjoined_emit_rows=0`; and
`regression_tests/run_all_suites.sh /private/tmp/adamas_0kaf_stage1 4` passes
`152/152 + 36/36`. Scope: selected-consumer source-shape and default-off ledger
migration only. It does not flip emitted symbols, backend behavior,
requested-name policy, target keepalive policy, `NamedTuple`/`Tuple` rendering,
global ambient-map policy, cleanup behavior, or `BlockOwner`, and it is not
green full-prelude generated s2, `s2b`, or `s3b`. Decay trigger:
`lower_function_if_needed_impl` transaction construction is rewritten, ledger
consumers stop reading the transaction record, or a future slice
removes/changes the residual transaction edges.

[LM-ARCH-CALL-MATERIALIZATION-TRANSACTION-GATE|superseded 2026-07-01 {F:0.78 G:0.44 R:0.86}]:
The `CallMaterializationTransaction` spine now has an executable source-shape
admission gate: `scripts/call_materialization_transaction_admission_report.sh`.
It selects `lower_function_if_needed.call_materialization_transaction` and
originally reported `preferred_source_shape=legacy_split_transaction_edge` with
`selection_status=eligible_transaction_spine_owner`. Original measured-red
counts:
`transaction_type_count=0`, `transaction_helper_count=0`,
`split_state_key_count=1`, `split_target_count=1`,
`ambient_state_scope_consumer_count=1`, `legacy_ledger_call_count=3`,
`direct_type_param_scope_count=5`, `direct_body_lowering_count=12`,
`symbol_binding_field_read_count=24`, and `transaction_field_read_count=0`.
`REQUIRE_PROMOTED=1
scripts/call_materialization_transaction_admission_report.sh` exits 9, proving
the selected seam has not been promoted yet. Scope: source-shape gate only; no
compiler behavior, backend behavior, cleanup behavior, generated-stage status,
or `BlockOwner` carrier changed. Next work: Slice 0k-AF must add a
behavior-neutral `CallMaterializationTransaction` record/helper and make one
selected consumer read that record in shadow/parity mode while preserving
emitted behavior. Decay trigger: `lower_function_if_needed_impl` is rewritten,
the selected seam stops being the split transaction authority, or the future
helper turns `REQUIRE_PROMOTED=1` green. Superseded by
[LM-ARCH-CALL-MATERIALIZATION-TRANSACTION-CONSUMER] after Slice 0k-AF.

[LM-ARCH-CALL-MATERIALIZATION-TRANSACTION-SPINE|design-sealed 2026-07-01 {F:0.72 G:0.48 R:0.82}]:
Slice 0k-AD pauses production-code and generated-stage crash-stack pursuit
after the `InvocationContext` shadow/parity seam. The next correctness axis is
now the vertical `CallMaterializationTransaction` spine, not another local seam
chosen from the latest stack. The selected owned fact must join
`request_name_parts`, requested symbol, selected definition, state scope,
target symbol, materialization key, body/materialized symbol, emitted call
symbol, callsite argument types, target type-param map, ABI shape, and
wrapper/forwarder status. Evidence: `docs/compiler_architecture_sdd.md` Active
Architecture Board now names `CallMaterializationTransaction`; Slice 0k-AD
records the old authority edges to reduce and the next executable slice
0k-AE. Scope: docs-only design seal; no compiler source, report script,
backend behavior, cleanup behavior, or `BlockOwner` carrier changed, and no
green full-prelude generated s2, `s2b`, or `s3b` claim is made. Next work:
0k-AE must add a red/green source-shape admission gate for exactly one legacy
consumer that still obtains transaction facts from split locals, rendered
strings, or ambient maps instead of one owner record. Decay trigger: a future
source-shape gate selects a different axis, a generated-stage run refutes
call/materialization transaction identity as relevant, or production code
changes transaction behavior before the 0k-AE gate exists.

[LM-ARCH-INVOCATION-CONTEXT-SHADOW-SEAM|verified 2026-07-01 {F:0.86 G:0.38 R:0.90}]:
The selected `InvocationContext / InlineYieldFrame` seam is now promoted in
behavior-neutral shadow/parity mode. `scripts/invocation_context_admission_report.sh`
selects `lower_super.previous_def.invocation_context` and now classifies the
source as `already_promoted_shadow`; `REQUIRE_PROMOTED=1
scripts/invocation_context_admission_report.sh` exits 0. The selected
consumers no longer directly read `@current_class`, `@current_method`,
`@current_method_is_class`, `@current_super_source_module`, or
`current_method_forward_arg_ids(ctx)`: direct selected-seam counts are
`ambient_owner_method_count=0`, `ambient_kind_count=0`,
`ambient_super_source_count=0`, and `direct_forward_policy_count=0`.
`lower_super` and `lower_previous_def` instead consume an `InvocationContext`
owner fact carrying owner class, method name, class-vs-instance bit,
super-source module, current function name, and legacy forwardable argument ids.
Evidence: fresh stage1 build to `/private/tmp/adamas_invctx_stage1`; the
InvocationContext gate, MaterializationSymbolBinding gate, MethodNameCodec
gate, semantic census, and CodePathStatus census run; full suites pass
`152/152 + 36/36`. Scope: this is a source-shape and broad-regression
authority migration, not a super/previous-def behavior fix and not green
full-prelude generated s2, `s2b`, or `s3b`. Decay trigger: `lower_super` or
`lower_previous_def` starts reading ambient invocation state again, a future
generated-stage owner-boundary run refutes InvocationContext as relevant, or an
InvocationContext behavior flip changes super/previous-def semantics.

[LM-ARCH-INVOCATION-CONTEXT-GATE|guard-only 2026-07-01 {F:0.70 G:0.44 R:0.78}]:
After Slice 0k-Z, the next architecture movement must not be selected directly
from the latest generated-s2 crash stack. A local `SUPER_CTX` /
`ADAMAS_SUPER_CALL_CONTEXT_LEDGER` WIP around `lower_super` and inline-yield
context was classified as non-admitted report-surface growth and removed,
because it added another env-gated ledger before the SDD named a decision
question, source-shape gate, owner fact, or cleanup rule. The reusable
architecture fact is the boundary, not the scratch report: invocation context is
still represented by ambient mutable fields such as `@current_class`,
`@current_method`, `@current_method_is_class`, `@current_super_source_module`,
inline-yield/proc/block stacks, and current `LoweringContext` params. The next
admitted code movement is a red/green `InvocationContext` / `InlineYieldFrame`
source-shape gate selecting one consumer seam, likely `lower_super` /
`lower_previous_def`, followed only later by a behavior-neutral shadow/parity
owner helper. Rejected moves: re-adding a `SUPER_CTX` ledger without the gate,
patching `lower_super` directly, changing implicit `super` forwarding from a
crash stack, resetting inline-yield state as a guard, backend undefined-extern
rescue, or rolling `BlockOwner` back to tuple/namedtuple metadata. Scope: this
is a guard-only planning landmark; it does not claim the generated-s2
full-prelude residual is fixed or that `s2b`/`s3b` is green. Decay trigger: a
fresh generated-stage owner-boundary run refutes invocation context as the
active residual, or a future slice promotes an explicit invocation-frame helper
with source-shape and bootstrap evidence.

[LM-ARCH-SDD-PHASE0B-TRANSITION-GATE|verified 2026-07-01 {F:0.74 G:0.48 R:0.82}]:
The active path to green `s2b`/`s3b` is no longer an unbounded sequence of
local crash/RSS fixes. Live evidence from the latest parse-path identity WIP
showed a real boundary signal: generated s2 loaded 138 raw `Loading:` paths
that canonicalize to 75 files, while stage1 loaded 75 raw / 75 canonical paths.
The WIP reduced generated s2 registration shape to `modules=224`,
`classes=146`, but it did not satisfy the bootstrap DoD: fresh s2 still timed
out after `pass3 after lower_main call` around allocator flush. Therefore the
parse-path canonicalization WIP is evidence for a `NameResolution/file
identity` owner boundary, not a shipped fix. Current next move is the
architecture SDD transition gate: Phase 1 semantic decision census plus Phase
1b dead-code/workaround census, followed by dynamic ledgers for
StateScope/materialization identity or NameResolution/file identity before the
next behavior-changing compiler fix. Evidence: `docs/compiler_architecture_sdd.md`
now records Phase 0b and `scripts/semantic_decision_census.sh` is the first
read-only executable census entry point. Decay trigger: any successful green
`s2b`/`s3b` bootstrap, rewrite of `parse_file_recursive`/require loading, or
replacement of the active architecture SDD execution order.

[LM-ARCH-MATERIALIZATION-IDENTITY-LEDGER|verified 2026-07-01 {F:0.82 G:0.42 R:0.88}]:
The first dynamic SDD owner ledger now exists at the HIR materialization seam.
With `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1`,
`lower_function_if_needed_impl` emits `[MAT_ID]` rows containing phase,
requested symbol, target symbol, materialization state key, body symbol,
call-symbol hint, override reason, lookup branch, ambient `@type_param_map`,
target/merged map, and call arg types. This directly supports the architecture
SDD's `StateScope` and `Materialization` boundaries without changing default
compiler behavior. Evidence: `crystal build src/adamas.cr -o
/private/tmp/adamas_matid_stage1 --error-trace`;
`scripts/materialization_identity_ledger_smoke.sh
/private/tmp/adamas_matid_stage1` passes; `regression_tests/run_all_suites.sh
/private/tmp/adamas_matid_stage1 4` passes 152/152 original + 36/36 combined.
Scope: this is a behavior-neutral diagnostic/ledger, not a fix for any
particular symbol mismatch or a green `s2b`/`s3b` claim. Decay trigger:
rewrites of `lower_function_if_needed_impl`, materialization naming,
`with_isolated_type_param_map`, or HIR call/body symbol creation.

[LM-ARCH-PARSE-PATH-IDENTITY-PROBE|verified 2026-07-01 {F:0.86 G:0.38 R:0.90}]:
The active bootstrap frontier currently reaches `NameResolution/file identity`
before it reaches materialization. Fresh stage1 built fresh s2, but running
s2->s3 with `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1` produced zero `[MAT_ID]`
rows and hit the 4GB safe-wrapper cap during parse/register after
`top-level collection done defs=80 classes=124 modules=271`, with the last
progress row at `module register idx=201/271`. The committed dynamic probe
`scripts/parse_path_identity_probe.sh` uses `ADAMAS_STOP_AFTER_PARSE=1`,
`--no-prelude`, and `--verbose` to compare raw `Loading:` path count with
canonical filesystem identity. Evidence: `bash -n
scripts/parse_path_identity_probe.sh`; `scripts/parse_path_identity_probe.sh
/private/tmp/adamas_sdd_stage1` reports `raw=75 canonical=75` and
`PASS parse_path_identity`; `scripts/parse_path_identity_probe.sh
/private/tmp/adamas_sdd_s2` intentionally exits 3 with
`DUPLICATE_PATH_IDENTITY raw=138 canonical=75`, listing duplicate aliases for
the same files such as `frontend/ast.cr`, `frontend/span.cr`, and
`frontend/string_pool.cr`. Scope: this is a behavior-neutral measured-red gate,
not a path canonicalization fix and not a green `s2b`/`s3b` claim. Decay
trigger: rewrites of `parse_file_recursive`, require path resolution,
`ADAMAS_STOP_AFTER_PARSE`, verbose loading output, or a fresh generated s2 that
passes raw/canonical path parity.

[LM-S2S3-PARSE-PATH-IDENTITY-FIX|verified 2026-07-01 {F:0.88 G:0.36 R:0.90}]:
Generated s2 no longer re-registers the same source files through raw `..`
path aliases while parsing `src/adamas.cr`. Root-shaped boundary:
`parse_file_recursive` used raw absolute path spellings as loaded-file identity,
so generated s2 loaded 138 raw paths that canonicalized to 75 files before
HIR setup. Fix slice: introduce `source_file_identity_key` and route
`parse_file_recursive` loaded-key insertion plus require-fallback
`loaded` checks through that lexical dot-segment identity key. This is a
`NameResolution/file identity` owner fix, not a global path resolver rewrite.
Evidence: `crystal build src/adamas.cr -o /private/tmp/adamas_pathid_stage1
--error-trace`; `scripts/parse_path_identity_probe.sh
/private/tmp/adamas_pathid_stage1` reports `raw=75 canonical=75`; fresh
stage1 builds fresh s2; `scripts/parse_path_identity_probe.sh
/private/tmp/adamas_pathid_s2` reports `raw=75 canonical=75`;
`regression_tests/run_all_suites.sh /private/tmp/adamas_pathid_stage1 4`
passes 152/152 original + 36/36 combined; generated s2 compiles and runs a
no-prelude `x = 1` smoke. Bootstrap movement: generated s2->s3 no longer dies
before materialization solely because of duplicate parse/register shape; with
8GB it reaches 11 `[MAT_ID]` rows, then crashes in
`NodeSlot#node <- AstArena#[] <- AstToHir#lower_call` while draining missing
call targets. Scope: this does not make full-prelude generated s2 or s3 green;
full-prelude `x = 1` still exits 139 after allocator flush / LLVM emission
fallback. Decay trigger: rewrites of source file loading, require fallback,
`source_file_identity_key`, or parse/register bootstrap tracing.

[LM-ARCH-AST-ARENA-OWNERSHIP-GATE|guard-only 2026-07-01 {F:0.72 G:0.44 R:0.84}]:
The residual generated-s2 frontier after the parse-path identity fix is now
classified as an `AstNodeIdentity / ArenaOwnership` boundary before any
`lower_call` behavior patch. Evidence: generated s2->s3 reaches 11 `[MAT_ID]`
rows and then crashes in
`NodeSlot#node <- AstArena#[] <- AstToHir#lower_call` while draining missing
call targets. The architecture claim is deliberately narrower than a fix:
`ExprId.index` alone is not a globally unique AST node identity, and
`expr_id.index < arena.size` is a containment heuristic rather than an owner
proof. The committed static census `scripts/arena_ownership_census.sh` reports
owner helpers, raw `@arena[...]` reads, lower-call raw reads, containment
heuristics, and existing arena debug gates without changing compiler behavior.
The env-gated dynamic ledger `ADAMAS_LOWER_CALL_ARENA_LEDGER=1` emits
`[LC_ARENA]` phase/expr rows from `lower_call`, and
`scripts/lower_call_arena_ledger_smoke.sh` verifies that the channel works on a
no-prelude call without generated compiler artifacts. Next behavior-changing
`lower_call` work must first consume dynamic rows for the failing generated-s2
callsite: current arena, preferred/call arena, resolved owner arena, `ExprId`,
and raw-read site without dereferencing the crashing node slot. If the ledger
proves stale/corrupt `ExprId` or `NodeSlot` producer corruption instead of
arena drift, the patch belongs at that producer, not at the `lower_call`
consumer. Fresh generated-s2 evidence produced `475` `[LC_ARENA]` rows and
`11` `[MAT_ID]` rows before the residual `EXIT 139`. The final observed
lower-call row was `Adamas::Compiler::CLI#run$IO_IO` at
`before.member_object_read`, and current arena, preferred/call arena, and
heuristic owner arena were the same `src/compiler/cli.cr` arena with
`current_has=1`, `preferred_has=1`, and `owner_has=1`. This is not a root-cause
claim, but it makes a simple current-arena-drift consumer fix unlikely for the
last observed edge. Decay trigger: a dynamic lower-call arena ledger refutes
arena ownership as the active boundary, or `AstArena` / `ExprId` identity is
redesigned into an explicit owner-scoped reference.

[LM-ARCH-AST-NODE-REF-SHADOW-FACADE|guard-only 2026-07-01 {F:0.74 G:0.44 R:0.84}]:
The ArenaOwnership slice now has a behavior-neutral `AstNodeRef` facade in
`AstToHir`. `AstNodeRef` is a class, not a struct, so it does not copy an
`ArenaLike` union through generated-stage value semantics. It records
`arena_owner`, `expr_id`, source path, call span, and origin for lower-call raw
AST-read ledger rows. The facade is allocated only when
`ADAMAS_LOWER_CALL_ARENA_LEDGER=1`, and lowering still uses the legacy raw
reads. Scope: this is a shadow identity boundary, not an arena-routing fix and
not a green `s2b`/`s3b` claim. Next step: use `AstNodeRef` to compare current
arena, explicit owner, and heuristic owner at raw-read sites; if these agree at
the crash edge, investigate `NodeSlot`/arena storage producer corruption
instead of adding another `arena_for_expr?` consumer patch. Decay trigger:
`AstNodeRef` starts driving behavior, `ArenaLike` representation changes, or a
future generated-stage ledger refutes the explicit-owner classification.

[LM-ARCH-CODEPATH-STATUS-CENSUS|guard-only 2026-07-01 {F:0.70 G:0.52 R:0.82}]:
Phase 1b now has a read-only static entry point:
`scripts/codepath_status_census.sh`. It groups candidate debug/probe gates,
bootstrap workaround comments, fallback/recovery paths, legacy naming shims,
broad semantic scans, backend semantic leakage, and layout/ABI workaround
surfaces across the compiler hot files. Scope: this census is an owner-map and
cleanup planning input only; it does not classify paths as live, dead, or
`delete_ready`. Deletion still requires runtime branch evidence plus a
protecting falsifier for each candidate. Decay trigger: compiler hot-file
layout changes, debug/workaround gates are renamed, or a real `CodePathStatus`
ledger replaces the static census as the cleanup authority.

[LM-ARCH-LOWER-CALL-ARENA-PARITY-REPORT|guard-only 2026-07-01 {F:0.78 G:0.42 R:0.86}]:
The `AstNodeRef` shadow facade now has an executable parity/classification
report: `scripts/lower_call_arena_parity_report.sh`. It runs a compiler with
`ADAMAS_LOWER_CALL_ARENA_LEDGER=1`, accepts nonzero compiler exit as useful
data when `[LC_ARENA]` rows exist, and buckets lower-call expr rows by
current-arena, explicit `AstNodeRef` owner, and heuristic owner agreement:
`agree_all_have`, `agree_missing_has`,
`ref_current_vs_heuristic_diverge`, `current_vs_ref_owner_diverge`, and
`three_way_diverge`. Baseline no-prelude evidence with a fresh stage1 reports
`phase_rows=5`, `expr_rows=3`, and `agree_all_have=3`. Scope: this is a
diagnostic gate only; it does not route AST reads and does not classify the
generated s2->s3 crash until run on that corridor. Decay trigger:
`[LC_ARENA]` field format changes, lower-call raw-read labels change, or
`AstNodeRef` starts driving behavior.

[LM-S2S3-LOWER-CALL-ARENA-PARITY-REFUTES-OWNER-DRIFT|verified 2026-07-01 {F:0.84 G:0.30 R:0.88}]:
Fresh generated-stage evidence refutes arena-selection/current-arena drift for
the instrumented `AstToHir#lower_call` crash edge. A fresh stage1 built a fresh
s2 under `scripts/run_safe.sh` (`EXIT: 0` after about 178s). Running
`scripts/lower_call_arena_parity_report.sh` with that s2 compiling
`src/adamas.cr` to s3 returned `compiler_rc=139`, `phase_rows=265`,
`expr_rows=210`, `agree_all_have=210`, and zero divergence buckets. The last
expr row before the crash was `Adamas::Compiler::CLI#run$IO_IO`
`before.member_object_read`; current arena, explicit `AstNodeRef` owner, and
heuristic `arena_for_expr?` owner were the same `src/compiler/cli.cr` arena,
with `current_has=1`, `preferred_has=1`, and `owner_has=1`. Scope: this does
not prove the full root and does not make s2->s3 green; it redirects the next
read-only slice away from lower_call arena selection and toward
`NodeSlot`/arena storage producer/read integrity or an uninstrumented raw read.
Decay trigger: lower-call raw-read instrumentation changes, a fresh generated
s2->s3 parity report shows divergence, or the crash stack moves before this
edge.

[LM-ARCH-NODESLOT-INTEGRITY-NEXT-SLICE|guard-only 2026-07-01 {F:0.78 G:0.44 R:0.84}]:
The next admitted architecture implementation slice is
`NodeSlotIntegrity / AstArenaStorage`, not another `lower_call` arena-selection
consumer patch. Rationale: generated-stage lower-call owner parity already
showed current arena, explicit `AstNodeRef` owner, and heuristic owner all
agreeing at the crash edge (`210/210 agree_all_have`, zero divergence buckets),
so owner selection is no longer the highest-value hypothesis for the
instrumented edge. Required next ledger: env-gated/default-off, behavior-neutral
slot producer/read integrity rows with arena owner, `ExprId`, index range, slot
initialization/presence, safe node-kind/span facts when available, producer/read
site, and no broad fallback scan. Forbidden next moves before that ledger:
routing lower-call raw reads through `AstNodeRef`, scanning all arenas to find a
node by index, rewriting parser allocation, or claiming a behavior fix from
crash movement alone. Evidence: `docs/compiler_architecture_sdd.md` now has
Slice 0f and `docs/compiler_refactor_architecture_plan.md` marks the LLVM
writer as postponed for the active bootstrap objective. Decay trigger: a fresh
generated s2->s3 report shows owner divergence, the crash stack moves before
`NodeSlot#node`, or `AstArena` / `NodeSlot` storage representation is rewritten.

[LM-S2S3-NODESLOT-INTEGRITY-REFUTES-MISSING-SLOT|verified 2026-07-01 {F:0.84 G:0.28 R:0.88}]:
Fresh generated-stage evidence refutes missing/uninitialized `NodeSlot` and
out-of-range `ExprId` for the currently instrumented
`AstToHir#lower_call` crash edge. The committed env-gated ledger
`ADAMAS_NODE_SLOT_LEDGER=1` emits `[NODE_SLOT]` rows at existing lower-call
raw-read trace points and reports arena owner, `ExprId`, range, slot presence,
and node pointer presence without routing behavior through the ledger. Evidence:
`crystal build src/adamas.cr -o /private/tmp/adamas_nodeslot_stage1
--error-trace` passes; `scripts/node_slot_integrity_report.sh
/private/tmp/adamas_nodeslot_stage1` reports `rows=9` and
`healthy_present=9`; a default env-off no-prelude compile emits no
`[NODE_SLOT]`; fresh stage1 builds fresh s2 under `scripts/run_safe.sh`
(`EXIT: 0` after about 183s); generated s2->s3 with
`scripts/node_slot_integrity_report.sh /private/tmp/adamas_nodeslot_s2
src/adamas.cr -o /private/tmp/adamas_nodeslot_s3` returns `compiler_rc=139`,
`rows=630`, `healthy_present=630`, and zero `missing_node_payload`,
`missing_slot`, `out_of_range`, `invalid_expr`, or `null_expr` buckets. The
last row is the same `Adamas::Compiler::CLI#run$IO_IO`
`before.member_object_read`, `expr=2828`, with `in_range=1`,
`slot_present=1`, and `node_present=1`. Scope: this does not make s2->s3
green and does not prove the node payload/vtable/deep `node_kind` read is
healthy, because default ledger intentionally avoids dereferencing node payload.
Next read-only slice should target node payload/vtable/deep-read integrity or
the exact uninstrumented consumer after `NodeSlot#node`, not arena owner
selection or slot existence. Decay trigger: fresh generated s2->s3 shows a
non-healthy `[NODE_SLOT]` bucket, the crash stack moves before this edge, or
the arena storage representation changes.

[LM-ARCH-DIAGNOSTIC-LADDER-CHECKPOINT|verified 2026-07-01 {F:0.78 G:0.50 R:0.86}]:
The architecture SDD now treats repeated diagnostic extension as its own
tail-chase risk. After Slice 0f, the live evidence refutes current-arena drift,
out-of-range `ExprId`, and missing/uninitialized `NodeSlot` for the
instrumented `lower_call` edge, but does not name a behavior fix. A local
uncommitted `ADAMAS_NODE_PAYLOAD_LEDGER` WIP was removed rather than carried
forward, because it lacked a named SDD slice, completed generated-stage
evidence, and a cleanup rule. Payload/vtable/deep-read integrity remains an
allowed future falsifier for this corridor, but only as an explicit SDD slice.
The default next track is architecture sealing: make
`SemanticStateScope`/`MaterializationIdentity` carry requested, selected,
target, materialized, and emitted symbol identity as one transaction record,
and add runtime `CodePathStatus` evidence before deleting stale workarounds or
debug gates. Scope: this is a process/architecture checkpoint, not a compiler
behavior fix and not a green `s2b`/`s3b` claim. Decay trigger: owner explicitly
resumes the payload/deep-read frontier as a named SDD slice, a fresh crash
frontier invalidates Slice 0f evidence, or a transaction-record facade lands
and changes the next sealing target.

[LM-ARCH-MATERIALIZATION-PRECALL-TRANSACTION-LEDGER|verified 2026-07-01 {F:0.82 G:0.46 R:0.88}]:
The architecture SDD now has a behavior-neutral pre-call materialization
transaction ledger. With `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1`,
`lower_function_if_needed_impl` emits `[MAT_TX]` rows alongside `[MAT_ID]`
rows. Each transaction records requested symbol, target symbol,
materialization state key, body symbol, call-symbol hint, override reason,
lookup branch, ambient map, target map, call arg types, plus computed
`identity_status`, `symbol_relation`, and `required_contract`. Evidence:
`scripts/materialization_transaction_report.sh` fails closed on compilers that
emit no `[MAT_TX]`; after the slice, a focused stage1 report produced `2513`
rows, `0` malformed rows, `2504` exact rows, and `9`
`body_eq_target_call_eq_requested` rows requiring `wrapper_or_call_remap`.
Full stage1 suites pass (`152/152` original + `36/36` combined). A fresh
generated s2 build exits 0 and the generated s2 emits a no-prelude report with
`1` exact `[MAT_TX]` row and `0` malformed rows. Scope: this is not a behavior
fix and not a green full-prelude `s2b`/`s3b` claim. It records a
`call_symbol_hint`, not a backend-proven final emitted call, so behavior
patches that change materialization or forwarder contracts must either upgrade
this ledger to include final call emission or consume a sibling emitted-call
ledger. Decay trigger: rewrites of `lower_function_if_needed_impl`,
materialization naming, HIR/MIR call lowering, or backend call-target emission.

[LM-ARCH-TAIL-CHASE-PAUSE-AFTER-MAT-TX|verified-boundary 2026-07-01 {F:0.78 G:0.54 R:0.84}]:
The architecture plan has an explicit stop after the pre-call materialization
transaction ledger. A downstream emitted-call ledger is still allowed, but only
as transaction-completeness evidence for Phase 2b: requested, selected, target,
body, emitted call, state-scope authority, and ABI shape must become one owned
fact before a call/materialization behavior patch. It is not allowed as a
backend undefined-extern rescue or as a way to keep chasing the latest stub.
Static census evidence confirms that cleanup and bloat work also needs runtime
ownership evidence before deletion: the semantic census reports broad
`SemanticStateScope`, `Materialization`, `CallResolution`, backend leakage, and
debug/workaround surfaces, while the `CodePathStatus` census reports broad
env/debug, fallback/recovery, legacy/shim, semantic-scan, backend-leakage, and
layout/ABI candidate surfaces. Scope: this is a planning/stop-rule landmark,
not a compiler behavior fix and not a green `s2b`/`s3b` claim. Decay trigger:
a transaction-completeness slice lands, a runtime `CodePathStatus` ledger
replaces the static census as cleanup authority, or fresh generated-stage
evidence invalidates the current owner-ledger path.

[LM-ARCH-RUNTIME-CODEPATH-STATUS-CLI-LEDGER|verified 2026-07-01 {F:0.82 G:0.34 R:0.88}]:
The first runtime `CodePathStatus` ledger exists for coarse
CLI/compiler-driver control flow. With `ADAMAS_CODEPATH_STATUS_LEDGER=1`,
`src/compiler/cli.cr` emits `[CODEPATH_STATUS]` rows for parser mode, parse /
semantic / HIR / MIR driver gates, metrics gates, cache, error/exit gates, and
stop-after gates. `scripts/codepath_status_runtime_report.sh` is the focused
runtime report and fails closed when no rows are emitted. Evidence: fresh
stage1 build passes; the no-prelude runtime report produced `rows=26`,
`malformed=0`, `taken=8`, and `not_taken=18`; the default env-off no-prelude
compile emitted no `[CODEPATH_STATUS]` rows; static semantic and
CodePathStatus censuses still run; full stage1 suites pass (`152/152`
original + `36/36` combined); fresh stage1 builds fresh s2, and the generated
s2 emits the same focused no-prelude report shape (`rows=26`, `malformed=0`).
Scope: this is cleanup/bloat evidence only for coarse CLI branches. It does
not prove any path is `delete_ready`, does not classify `ast_to_hir`,
`hir_to_mir`, or backend semantic branches, and does not make `s2b`/`s3b`
green. Decay trigger: CLI driver control flow changes, the ledger row format
changes, runtime `CodePathStatus` is extended into semantic hot paths, or a
cleanup slice tries to use this evidence as deletion authority without a
protecting falsifier.

[LM-ARCH-TRANSACTION-COMPLETENESS-NEXT-SLICE|guard-only 2026-07-01 {F:0.76 G:0.52 R:0.82}]:
The next correctness-oriented architecture slice is transaction completeness,
not another crash-stack-local behavior patch. Before changing
call/materialization behavior, one report must join requested symbol, selected
definition, target materialization symbol, created body symbol, emitted backend
call symbol, state-scope authority, target map, callsite arg types, and ABI
shape. Each candidate must classify as `exact`, `materialization_keepalive`,
`wrapper_forwarder`, or `rejected_mismatch`. Forbidden next moves: backend
undefined-extern rescue as the first semantic discovery point, forced
materialization to the requested name, global ambient-map ignore, or using
runtime `CodePathStatus` liveness as a substitute for transaction identity.
Evidence: `docs/compiler_architecture_sdd.md` Slice 0k and
`docs/compiler_refactor_architecture_plan.md` now name this as the next
correctness implementation track. Scope: this is a design/guard landmark, not
an implemented transaction-completeness report and not a green `s2b`/`s3b`
claim. Decay trigger: a completed emitted-call transaction report lands, or
fresh generated-stage evidence invalidates the materialization transaction
path.

[LM-ARCH-TRANSACTION-CONTRACT-NOT-BACKEND-LOG|guard-only 2026-07-01 {F:0.78 G:0.58 R:0.84}]:
Hostile self-review of Slice 0k tightened the next-step boundary: final-call
visibility is architecture work only when it is joined to a HIR-owned
materialization transaction identity. A standalone backend emitted-call log, an
`@undefined_externs`-driven forwarder, or a report that discovers the semantic
mismatch only after HIR/MIR has pruned the target body is a tail-chasing
diagnostic, not the next architecture slice. The backend may report mechanical
facts (emitted callee, ABI shape, extern-vs-crystal kind, body presence), but
it must not create or repair the semantic transaction. The first code slice
should be default-off transaction correlation that preserves env-off behavior,
passes transaction identity through HIR/MIR/backend seams, and fails closed on
missing joins or silent requested/target/body/emitted mismatches without an
admitted `exact`, `materialization_keepalive`, `wrapper_forwarder`, or
`rejected_mismatch` contract. Evidence: `docs/compiler_architecture_sdd.md`
Slice 0k now records the hostile self-review, implementation guard, and stop
conditions; current static census still shows broad semantic surfaces, so the
boundary deliberately rejects backend-only rescue. Scope: design/guard only,
not an implemented report and not a green `s2b`/`s3b` claim. Decay trigger: a
transaction-correlation implementation lands, or fresh generated-stage evidence
shows materialization transaction identity is not the active correctness path.

[LM-ARCH-SLICE-0K-A-TRANSACTION-CORRELATION|verified 2026-07-01 {F:0.84 G:0.44 R:0.88}]:
Slice 0k-A now has an implemented, behavior-neutral transaction-correlation
channel. Red gate: after `scripts/materialization_transaction_report.sh` was
upgraded, a Slice 0h-only compiler built at `/private/tmp/adamas_txcorr_red`
failed with `FAIL: no [MAT_EMIT] materialization emitted-call rows emitted`
while still emitting `[MAT_TX]` rows. Implementation shape:
`MaterializationIdentityTransaction` emits a stable `tx=` id, `HIR::Module`
stores a HIR-owned call-symbol to transaction-id map, MIR `Call` /
`ExternCall` carry optional `materialization_tx_id`, HIR-to-MIR direct call
lowering preserves that id for transaction-bound calls, and backend call
emission logs only mechanical `[MAT_EMIT]` facts under
`ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1`. Evidence: focused stage1 report
emits `rows=2513`, `malformed=0`, `emit_rows=16995`, `malformed_emit=0`,
`transaction_bound_emit_rows=5332`, `non_transaction_emit_rows=11663`,
`joined_transactions=1349`, and `unjoined_emit_rows=0`; generated-s2
no-prelude report emits `rows=1`, `emit_rows=2`,
`transaction_bound_emit_rows=1`, `joined_transactions=1`, and
`unjoined_emit_rows=0`; env-off focused compile emits no `[MAT_ID]`,
`[MAT_TX]`, or `[MAT_EMIT]`; full stage1 suites pass `152/152 + 36/36`.
Scope: this proves transaction correlation and backend emitted-call visibility
for a joined HIR-owned subset, not a behavior fix and not a green `s2b`/`s3b`
claim. Broad `[MAT_EMIT] tx=none` rows remain diagnostics only. Decay trigger:
MIR call representation, `lower_function_if_needed_impl`, HIR-to-MIR call
lowering, backend call emission, or the materialization transaction report row
format changes.

[LM-ARCH-SLICE-0K-B-STATESCOPE-AUTHORITY-LEDGER|verified 2026-07-01 {F:0.84 G:0.46 R:0.88}]:
Slice 0k-B now extends the behavior-neutral materialization transaction rows
with selected-definition and state-scope owner fields. Red gate: a Slice 0k-A
compiler built at `/private/tmp/adamas_0kb_red` emitted joined `[MAT_TX]` /
`[MAT_EMIT]` rows but failed the upgraded report with `owner_malformed=2513`.
Implementation shape: `[MAT_TX]` rows now include `selected_def`,
`state_scope`, `map_source`, and `materialization_action`, produced at the HIR
materialization seam; backend `[MAT_EMIT]` rows remain mechanical emitted-call
facts and do not reconstruct source-level semantics. Evidence: focused stage1
report emits `rows=2513`, `malformed=0`, `emit_rows=16995`,
`malformed_emit=0`, `owner_malformed=0`, `joined_transactions=1349`, and
`unjoined_emit_rows=0`; state-scope buckets are `callsite=871` and
`target_materialization=1642`; map-source buckets are
`callsite_arg_types=871`, `target_map=1165`,
`ambient_snapshot_rejected=238`, and `empty_map=239`. Generated-s2 no-prelude
report emits `rows=1`, `emit_rows=2`, `owner_malformed=0`,
`joined_transactions=1`, and `unjoined_emit_rows=0`; full suites pass
`152/152 + 36/36`. Scope: this proves owner fields are available in the
transaction ledger, not that any materialization behavior is fixed and not that
`s2b`/`s3b` are green. Decay trigger: materialization transaction row format
changes, `lower_function_if_needed_impl` state-scope decisions move, or a
completed `SemanticStateScope` / `MaterializationRegistry` facade replaces
these diagnostic fields.

[LM-ARCH-POST-0K-B-FULL-STAGE-STOP|verified-boundary 2026-07-01 {F:0.78 G:0.44 R:0.84}]:
The first full generated-stage transaction report after Slice 0k-B is a stop
signal, not a behavior-fix green light. Fresh stage1 built a fresh generated
s2, but generated s2 compiling full `src/adamas.cr` under
`scripts/materialization_transaction_report.sh` returned `compiler_rc=139` and
failed with `FAIL: no [MAT_EMIT] materialization emitted-call rows emitted`.
The run emitted HIR-side `[MAT_ID]` / `[MAT_TX]` rows through
`Adamas::Compiler::CLI#run$IO_IO`, then crashed before backend emitted-call
correlation. Scope: focused stage1 and generated-s2 no-prelude reports prove
the transaction machinery and owner fields in focused corridors; they do not
prove that full generated s2 reaches the emitted-call seam. Next behavior work
is still blocked. The next admitted architecture move is either a named
full-stage seam-reachability owner slice or a `SemanticStateScope` shadow
facade that turns ambient-map naming authority into an explicit fact before
behavior changes. Forbidden repeats: backend forwarders from
`@undefined_externs`, target keepalive from backend body presence, forced
requested-name materialization, global ambient-map ignore, `@block_owner`
rollback, or NamedTuple/Tuple string normalization as a root fix. Decay
trigger: a fresh generated-s2 full transaction report reaches joined
`[MAT_TX]` / `[MAT_EMIT]` rows for the intended target, or a new owner-scope
facade changes the next behavior-slice gate.

[LM-ARCH-SEMANTIC-STATESCOPE-SHADOW-LEDGER|verified 2026-07-01 {F:0.82 G:0.44 R:0.88}]:
The first behavior-neutral `SemanticStateScope` shadow ledger now exists at
the HIR materialization seam. Red gate: before the slice,
`scripts/semantic_state_scope_report.sh <compiler>` fails with
`FAIL: no [STATE_SCOPE] semantic state-scope rows emitted`. Implementation
shape: `ADAMAS_SEMANTIC_STATE_SCOPE_LEDGER=1` emits `[STATE_SCOPE]` rows with
transaction id, requested/target symbols, selected definition, explicit
authority, map source, allowed/forbidden consumers, lifetime region,
validation status, and ambient/target/callsite maps. The env is independent of
`ADAMAS_MATERIALIZATION_IDENTITY_LEDGER`: enabling only state-scope reporting
does not remember backend transaction ids and does not emit `[MAT_ID]`,
`[MAT_TX]`, or `[MAT_EMIT]`. Focused evidence: fresh stage1 report emits
`rows=2513`, `malformed=0`, `invalid_validation=0`, and
`rejected_without_ambient=0`; authority buckets are `callsite=871` and
`target_materialization=1642`; default env-off focused compile emits no
ledger rows; existing materialization transaction report still passes with
`owner_malformed=0`; full stage1 suites pass `152/152 + 36/36`; fresh stage1
builds fresh generated s2, and generated-s2 no-prelude state-scope report
emits `rows=1` with `malformed=0`. Scope: this is an observability/facade
slice, not a behavior fix, not an `@type_param_map` lifetime change, and not a
green `s2b`/`s3b` claim.
Decay trigger: `lower_function_if_needed_impl` moves, state-scope authority
semantics change, a true `StateScope` facade starts driving behavior, or a
fresh generated-stage report contradicts the focused authority buckets.

[LM-ARCH-MIGRATION-CONTRACT-AFTER-STATESCOPE|design-sealed 2026-07-01 {F:0.78 G:0.56 R:0.84}]:
The active architecture path is now a migration contract, not another
crash-edge fix. Fresh post-StateScope generated-stage evidence shows that a
full generated-s2 run emits `11` valid owned `[STATE_SCOPE]` rows and then
crashes before `[MAT_EMIT]`. lldb pins that crash to
`NodeSlot#node <- AstArena#[] <- AstToHir#lower_call` while draining pending
lower functions. A fresh 8GB `NodeSlotIntegrity` report on the same corridor
emits `rows=639`, `healthy_present=639`, and zero missing/out-of-range/null
buckets. Combined with the earlier owner/parity ledgers, this refutes the
tempting next consumer patches for this instrumented edge: lower-call guard,
arena scan, slot-existence repair, backend forwarder, target keepalive,
forced requested-name materialization, global ambient-map ignore, and
`NamedTuple`/`Tuple` string normalization. The next executable slice must
classify consumers under the owning architecture boundaries:
`StateScope`, `MaterializationRegistry`, `AstNodeRef`, or `CodePathStatus`.
Preferred first follow-up: a `StateScopeConsumerCensus` / shadow report over
the known naming and materialization consumers before any behavior change.
`BlockOwner` remains the admitted owner-metadata boundary and must not be
rolled back to tuple/namedtuple metadata. Scope: docs-only design seal; no
compiler behavior changed and no green `s2b`/`s3b` claim. Decay trigger: a
fresh full generated-stage run reaches joined `[MAT_TX]` / `[MAT_EMIT]` rows,
or one of the migration contracts lands as a behavior-driving facade with
focused and generated-stage evidence.

[LM-ARCH-STATESCOPE-CONSUMER-MIGRATION-GATE|verified 2026-07-01 {F:0.84 G:0.42 R:0.88}]:
Slice 0k-F now has an implemented, behavior-neutral
`StateScopeConsumerCensus` migration gate. The report classifies the known
naming/materialization consumers, including `prefer_callsite_specialization`,
`lower_function_if_needed_impl` `callsite_args` / `suffix_types` / `override`,
`lower_call` remangling, and the direct type-param predicates
`def_has_untyped_regular_param?` /
`raw_annotation_needs_callsite_specialization?`. Each reached consumer emits
an authority and migration decision:
`migrate_to_state_scope`, `migrate_to_materialization_registry`,
`keep_legacy_shim`, `blocked_unknown`, or `rejected_ambient`. Red gate: a
pre-slice compiler from `4d0965e2` fails
`scripts/state_scope_consumer_report.sh` with
`FAIL: no [STATE_SCOPE_CONSUMER] consumer rows emitted` while the focused
compile exits `0`. Fresh stage1 evidence:
`scripts/state_scope_consumer_report.sh /private/tmp/adamas_ssc_stage1`
emits `rows=42224`, `malformed=0`, `invalid_authority=0`,
`invalid_migration=0`, `invalid_validation=0`,
`rejected_without_ambient=0`, and all required consumers are present. The same
report records the blocking migration surface instead of hiding it:
`diagnostic_only=5935`, `keep_legacy_shim=5935`,
`rejected_ambient=2767`, `migrate_to_state_scope=25978`, and
`migrate_to_materialization_registry=7544`. The report classifies every
blocked row (`unclassified_blocked=0`) into
`legacy_shim.concrete_typed_params=4481`,
`legacy_shim.skipped_untyped_params=924`,
`legacy_shim.no_regular_params=530`, and zero
`legacy_shim.regular_untyped_param_review` rows, and prints bounded samples
for each non-empty class. The skipped-untyped bucket contains splat,
double-splat, or block untyped annotations; it does not prove the old
regular-param predicate is wrong. Env-off focused compile emits no
consumer rows and the compiled `basic_sanity` binary exits `0`. Existing
static censuses, `semantic_state_scope_report`, and
`materialization_transaction_report` remain compatible; focused
`String#split` and heap-Proc nilable-union reducers remain green, and
`regression_tests/run_combined.sh /private/tmp/adamas_ssc_stage1` passes
`36/36`. Generated s2 self-build exits `0`, but generated-s2 consumer report fails closed with
`compiler_rc=139`, `rows=17`, and missing `callsite_args` / `suffix_types`
because the generated compiler crashes before those required consumers are
reached. Scope: this is a migration gate, not a behavior fix and not a green
`s2b`/`s3b` claim. Any `diagnostic_only` / `keep_legacy_shim` row blocks
behavior patches on that decision surface until a later
StateScope/MaterializationRegistry migration row and bounded would-change
census exist. The current diagnostic-shim buckets should not drive a global
predicate change; the next behavior candidate must come from already-owned
`migrate_to_state_scope`, `migrate_to_materialization_registry`, or
`rejected_ambient` rows.

Follow-up owner-result preflight refuted the naive shortcut that a migration
class can be used directly as a replacement boolean. The upgraded report exits
`0` and remains malformed-clean, with `owned_candidate_rows=36289`,
`owner_result_unknown=0`, and `owned_would_change=3779`. Candidate classes are
`state_scope=25978`, `materialization_registry=7544`, and
`ambient_rejected=2767`. The proposed owner-result probe is parity-clean for
StateScope (`legacy_result_1=25978`) and ambient rejection
(`legacy_result_0=2767`), but mixed for MaterializationRegistry:
`legacy_result_1=3779` and `legacy_result_0=3765`. This measured-red result
blocks any behavior patch that treats `migrate_to_materialization_registry` as
one boolean rule. The next MaterializationRegistry step must classify by
consumer, decision, selected definition, target map, and callsite arg shape
before a behavior change is admissible.

Follow-up attribution shows why this cannot be a one-consumer fix:
`materialization_registry_rows=7544` split as `legacy_result_1=3779` and
`legacy_result_0=3765`, with every reached consumer mixed:
`def_has_untyped_regular_param` 1775/1355,
`prefer_callsite_specialization` 580/483,
`raw_annotation_needs_callsite_specialization` 229/1055,
`lower_function_if_needed.override` 566/496, and
`lower_call.remangle` 629/376 for result 1/0 respectively. The strongest
observed separator is selected-definition parameter class:
`regular_untyped_params` is mostly result 1 (`3362/3`), while
`concrete_typed_params` is mostly result 0 (`2/2033`) and `no_regular_params`
is mostly result 0 (`4/572`). `short_type_params` (`273/895`) and
`skipped_untyped_params` (`138/262`) remain mixed. All rows have
`target_map_present`, and callsite-arg shape remains mixed. The next
MaterializationRegistry design slice must therefore model selected-definition
parameter classes and exceptions instead of using consumer name, target-map
presence, or call-arg count as a replacement rule. Decay trigger: the required
consumer set moves, the report row format changes, a later `StateScope` facade
starts driving behavior, or fresh generated-stage evidence reaches all
required consumers with different migration buckets.

[LM-ARCH-MATERIALIZATION-DECISION-CONTRACT|design-sealed 2026-07-01 {F:0.80 G:0.54 R:0.86}]:
The next architecture move after Slice 0k-F is not another
`def_has_untyped_regular_param?`, override, remangle, backend-stub, or
`NamedTuple`/`Tuple` patch. The owner-result and attribution ledgers show that
`migrate_to_materialization_registry` is a mixed surface (`3779/3765`) and
that consumer name, target-map presence, callsite-arg shape, and migration
class are insufficient replacement rules. The active SDD now requires a typed
`MaterializationDecision` / `MaterializationRegistry` contract before behavior
changes: the record must include requested symbol, selected definition, target
symbol, `SemanticStateScope`, callsite arg types, target map, and ABI shape,
then classify the row as `exact`, `callsite_specialized`,
`target_materialized`, `wrapper_required`, `legacy_shim`, or
`rejected_mismatch`. `legacy_result` is parity evidence only, not authority.
Accepted next implementation is behavior-neutral shadow/report work with a
red-before-green missing-row gate and bounded would-change buckets. Rejected
next moves: direct consumer predicate patches, forced requested-name
materialization, backend undefined-extern rescue, backend keepalive/forwarder
as first mechanism, `NamedTuple`/`Tuple` display normalization, or rollback of
`BlockOwner` to tuple/namedtuple metadata. Scope: docs-only design seal; no
compiler behavior changed and no green `s2b`/`s3b` claim. Decay trigger: an
implemented `MaterializationDecision` facade starts driving behavior, the
StateScope consumer report row format changes, or fresh generated-stage
evidence produces a materially different MaterializationRegistry split.

[LM-ARCH-MATERIALIZATION-DECISION-LEDGER|verified 2026-07-01 {F:0.84 G:0.46 R:0.88}]:
Slice 0k-G now has a behavior-neutral `MaterializationDecision` shadow
ledger/report. Red gate: after adding
`scripts/materialization_decision_report.sh` but before compiler
instrumentation, fresh `/private/tmp/adamas_matdec_red` failed with
`FAIL: no [MAT_DECISION] materialization decision rows emitted` and
`compiler_rc=0`. Implementation: when
`ADAMAS_MATERIALIZATION_DECISION_LEDGER=1`, the HIR
naming/materialization consumer seam emits `[MAT_DECISION]` rows only for
`migrate_to_materialization_registry` candidates. Focused stage1 evidence:
`scripts/materialization_decision_report.sh /private/tmp/adamas_matdec_stage1`
reports `rows=7544`, `malformed=0`, `invalid_decision=0`,
`invalid_owner=0`, `invalid_reason=0`, `invalid_legacy_result=0`,
`invalid_would_change=0`, `would_change_rows=0`, `legacy_shim_rows=891`,
and `rejected_rows=0`. Decision buckets are `exact=2311`,
`callsite_specialized=2245`, `target_materialized=2097`, and
`legacy_shim=891`; parameter buckets are `regular_untyped_params=3365`,
`concrete_typed_params=2495`, `short_type_params=708`,
`no_regular_params=576`, and `skipped_untyped_params=400`. Existing
StateScope/materialization reports still compose, env-off compile emits no
`[MAT_DECISION]` rows and the tiny binary exits `0`, static censuses run, and
`regression_tests/run_all_suites.sh /private/tmp/adamas_matdec_stage1 4`
passes `152/152 + 36/36`. Generated-stage boundary: fresh generated s2 builds,
but the focused generated-s2 report still fails before the decision seam with
no rows and `compiler_rc=139`; a tiny no-prelude source exits `0` but emits no
rows because it does not reach MaterializationRegistry candidates. Scope: this
is a shadow architecture ledger, not a behavior fix and not a green
`s2b`/`s3b` claim. Decay trigger: the report row format changes, a behavior
consumer starts using `MaterializationDecision`, or fresh generated-stage
evidence reaches the focused decision seam with different buckets.

[LM-ARCH-MATERIALIZATION-PROMOTION-GATE|design-sealed 2026-07-01 {F:0.78 G:0.52 R:0.84}]:
After Slice 0k-G, the active architecture risk is no longer lack of another
diagnostic row; it is ledger proliferation without owner promotion. The SDD now
has Slice 0k-H, a `MaterializationDecision` promotion gate: a new diagnostic
ledger is admitted only if it promotes an existing owner fact into a
legacy-consumer seam in parity/shadow mode, classifies an existing path through
`CodePathStatus`, or refutes the current owner evidence with fresher
generated-stage data. The next admitted implementation is behavior-neutral:
expose a real `MaterializationDecision` owner object/helper to one
naming/materialization consumer while preserving legacy emitted behavior and
printing bounded would-change buckets. Fresh focused generated-s2 recheck
reinforces the stop-rule rather than authorizing a local crash fix: the
`MaterializationDecision` report still emits no rows and exits with
`compiler_rc=139`; the same corridor's `NodeSlotIntegrity` report shows
`rows=105`, `healthy_present=105`, and zero bad buckets, while lower-call arena
parity reports `expr_rows=35`, `agree_all_have=35`, and zero owner divergence.
Rejected next moves remain lower-call/arena/slot consumer patches, backend
undefined-extern rescue, target keepalive/forwarder, forced requested-name
materialization, global ambient-map ignore, `NamedTuple`/`Tuple` display-string
normalization, and rolling `BlockOwner` back to tuple/namedtuple metadata.
Scope: docs-only design seal; no compiler behavior changed and no green
`s2b`/`s3b` claim. Decay trigger: a promoted owner helper lands, a later
generated-stage run reaches `[MAT_DECISION]` with contradictory owner rows, or
the SDD chooses `CodePathStatus` cleanup instead of materialization promotion.

[LM-ARCH-PROMOTION-FIRST-WIP-REFUTED|design-sealed 2026-07-01 {F:0.72 G:0.48 R:0.82}]:
The first attempted 0k-H implementation direction was rejected before commit.
The attempted shape was a dedicated promotion env/report around a preferred
`MaterializationDecision` consumer. That was the wrong first move for the
architecture SDD: it added a new row surface before proving which existing
consumer is eligible for promotion, and it risked turning design law
"promotion before proliferation" into another diagnostic ledger. The WIP was
removed, and `docs/compiler_architecture_sdd.md` now introduces Slice 0k-I:
`Promotion target selection gate`. The next executable step must consume
existing `[STATE_SCOPE_CONSUMER]` / `[MAT_DECISION]` rows and select at most
one `eligible_promote_owner` consumer, or explicitly route to
`CodePathStatus` cleanup. Direct promotion-helper implementation, backend
reconciliation, target keepalive, requested-name materialization, global
ambient-map changes, `NamedTuple`/`Tuple` normalization, lower-call/arena/slot
consumer patches, and `BlockOwner` rollback remain rejected until that
selection gate is green. Scope: docs-only planning correction; no compiler
behavior changed and no green `s2b`/`s3b` claim. Decay trigger: a
promotion-selection report lands and chooses an eligible consumer, or fresh
generated-stage evidence invalidates the current MaterializationDecision owner
rows.

[LM-ARCH-PROMOTION-TARGET-SELECTION-GATE|verified 2026-07-01 {F:0.84 G:0.44 R:0.88}]:
Slice 0k-I now has a behavior-neutral promotion target selection report.
`scripts/materialization_promotion_selection_report.sh` consumes existing
`ADAMAS_MATERIALIZATION_DECISION_LEDGER=1` rows and does not add compiler
instrumentation, a new promotion ledger env, backend hooks, or behavior
changes. Red gate: before the report existed, the command failed with
`FAIL: no materialization promotion selection report exists`. Focused stage1
evidence with `/private/tmp/adamas_0ki_stage1` reports `rows=7544`,
`malformed=0`, `invalid_owner=0`, `invalid_legacy_result=0`,
`invalid_would_change=0`, `eligible_count=1`, and `selected_count=1`. The
single selected consumer is `lower_function_if_needed.override`
(`row_count=1062`, `missing_owner_fields=0`, `invalid_owner_fields=0`,
`would_change_rows=0`, `selection_status=eligible_promote_owner`). Other
candidate consumers are explicitly rejected or unreached:
`prefer_callsite_specialization`, `def_has_untyped_regular_param`, and
`raw_annotation_needs_callsite_specialization` are
`rejected_requires_new_oracle`; `lower_call.remangle` is
`rejected_backend_only`; `lower_function_if_needed.callsite_args` and
`.suffix_types` are `rejected_unreached`. Compatibility gates remain green:
`materialization_decision_report`, `state_scope_consumer_report`,
`semantic_decision_census`, and `codepath_status_census` all exit `0`.
Generated-stage boundary: fresh stage1 builds fresh s2 (`EXIT: 0`), but the
generated compiler still crashes before `[MAT_DECISION]` on the focused
full-prelude report (`compiler_rc=139`). The selection report's residual mode
records this as `generated_stage_status=not_reached_named_residual` with
`no_row_reason=generated_s2_crashes_before_materialization_decision`. Scope:
selection/facade planning only; no compiler behavior changed and no green
`s2b`/`s3b` claim. Decay trigger: the report row format changes, a later
generated-stage run reaches `[MAT_DECISION]` with different candidate buckets,
or the selected `lower_function_if_needed.override` promotion helper lands and
starts driving behavior.

[LM-ARCH-PROMOTION-DEFINITION-GATE|design-sealed 2026-07-01 {F:0.78 G:0.54 R:0.84}]:
Slice 0k-J now defines promotion as a consumption effect, not a new diagnostic
row surface. A local unfinished 0k-J WIP was removed because it added
`[MAT_PROMOTION]` rows and a partial `MaterializationDecisionRecord` refactor
while the selected `lower_function_if_needed.override` seam still called
`state_scope_consumer_def_has_untyped_regular_param?` directly. That shape is
classified as stale/non-admitted. The next code slice may introduce a
behavior-neutral helper only if the override seam obtains parity/shadow input
from the owned `MaterializationDecision` / `MaterializationRegistry` record,
keeps emitted behavior equal to the legacy result, fails closed to legacy when
the owner record is incomplete, and passes a source-shape gate proving the seam
no longer reaches directly for the ambient predicate as its only authority.
Rejected repeats remain direct predicate promotion, `lower_call.remangle`,
backend undefined-extern handling, target keepalive, requested-name
materialization, global ambient-map changes, `NamedTuple`/`Tuple` display
normalization, and rolling `BlockOwner` back to tuple/namedtuple metadata.
Scope: docs-only design seal; no compiler behavior changed and no green
`s2b`/`s3b` claim. Decay trigger: a promoted override helper lands with
source-shape/report evidence, the SDD routes the next slice to `CodePathStatus`
cleanup, or fresh generated-stage evidence invalidates the selected override
consumer.

[LM-ARCH-PIVOT-ANTI-TAIL-CHASE-GATE|design-sealed 2026-07-01 {F:0.78 G:0.56 R:0.84}]:
Slice 0k-K is the current architecture pause/pivot gate before any 0k-J code
helper. It records the anti-tail-chase rule for this frontier: the next code
slice must present an authority-edge replacement receipt before it is admitted.
The receipt must name `old_edge`, `owned_edge`, `legacy_parity`,
`source_shape`, `report_shape`, `generated_stage_boundary`, and
`cleanup_impact`. A helper that only prints `[MAT_PROMOTION]` rows, a crash
probe that does not refute current owner evidence, a backend undefined-extern
rescue, a target keepalive/forwarder, a requested-name materialization patch,
global ambient-map changes, `NamedTuple`/`Tuple` display normalization, or a
`BlockOwner` rollback remains non-admitted. If the receipt cannot be made
concrete, the next track must explicitly switch to `CodePathStatus` cleanup
selection or to a generated-stage reachability owner boundary. Scope:
docs-only design seal; no compiler behavior changed and no green `s2b`/`s3b`
claim. Decay trigger: a 0k-J implementation lands with source-shape/report
evidence, `CodePathStatus` cleanup becomes the selected track, or fresh
generated-stage evidence refutes the current MaterializationDecision owner
route.

[LM-ARCH-OVERRIDE-PROMOTION-RECEIPT|design-sealed 2026-07-01 {F:0.80 G:0.50 R:0.86}]:
Slice 0k-L records the concrete receipt for the next 0k-J code slice. The
`old_edge` is the `lower_function_if_needed.override` seam in
`src/compiler/hir/ast_to_hir.cr`, where `has_untyped_regular_param` currently
comes from a direct call to
`state_scope_consumer_def_has_untyped_regular_param?` and then decides
requested-name vs target-name materialization. The `owned_edge` is an internal
`MaterializationDecisionRecord` built from the same fields already emitted by
`[MAT_DECISION]`: consumer/source decision, requested and target names,
selected definition, param class, state scope, owner, decision, reason, legacy
result, would-change, target map, call arg types, arg ABI, block ABI, and
validation. The admitted helper must use that record for shadow/parity input
but return the legacy boolean for emitted behavior. Required next report:
`scripts/materialization_override_promotion_report.sh`, red on a pre-slice
compiler with no promoted override rows, green only with rows limited to
`lower_function_if_needed.override`, `promotion=shadow_parity`, complete owner
fields, zero malformed rows, and `emitted_result == legacy_result`. Scope:
docs-only implementation receipt; no compiler behavior changed and no green
`s2b`/`s3b` claim. Decay trigger: the helper/report lands, source-shape checks
refute that this edge can be replaced cleanly, or fresh generated-stage evidence
invalidates the selected override seam.

[LM-ARCH-POST-0KL-IMPLEMENTATION-PIVOT|design-sealed 2026-07-01 {F:0.78 G:0.56 R:0.84}]:
Slice 0k-M prevents the next step after the 0k-L helper from becoming another
generated-stage crash chase. The admitted post-0k-L tracks are now explicit:
`MaterializationDecision` owner extraction, `SemanticStateScope` facade,
`NameResolution` / `MethodNameCodec`, `AstNodeRef` / `ArenaOwnership`, or
runtime `CodePathStatus` cleanup. A next slice must replace or shadow a named
authority edge, classify/delete a path through `CodePathStatus`, or refute the
current owner evidence with fresher data. Rejected repeats remain backend stub
rescues, forwarders, remangling, requested-name materialization,
`NamedTuple`/`Tuple` normalization, global ambient-map changes, and rolling
`BlockOwner` back to tuple/namedtuple metadata. Scope: docs-only architecture
pivot; no compiler behavior changed and no green `s2b`/`s3b` claim. Decay
trigger: one admitted lane lands with source-shape/report evidence, or fresh
generated-stage evidence proves that a different owner boundary must replace
the current lane set.

[LM-ARCH-OVERRIDE-PROMOTION-SHADOW-HELPER|verified 2026-07-01 {F:0.84 G:0.42 R:0.88}]:
The 0k-L code slice is implemented as a behavior-neutral authority-edge shadow
checkpoint. `lower_function_if_needed.override` no longer reaches directly for
`state_scope_consumer_def_has_untyped_regular_param?`; it now calls
`materialization_override_shadow_untyped_regular_param?`, which builds an
owned `MaterializationDecisionRecord`, emits `[MAT_PROMOTION]` rows only when
`ADAMAS_MATERIALIZATION_OVERRIDE_PROMOTION_LEDGER=1`, and returns the legacy
boolean. Evidence: red gate
`CHECK_SOURCE_SHAPE=0 scripts/materialization_override_promotion_report.sh
bin/adamas` exits `1` with no promotion rows while compiler exit is `0`;
fresh `/private/tmp/adamas_0km_stage1` green report emits `rows=1062`, only
`lower_function_if_needed.override`, malformed/invalid counts `0`, and
`emitted_mismatch=0`; materialization decision, promotion selection,
state-scope consumer, semantic census, codepath census, and `git diff --check`
gates all exit `0`; `regression_tests/run_combined.sh
/private/tmp/adamas_0km_stage1` passes `36/36`; fresh stage1 builds fresh s2
with `EXIT: 0`; generated s2 emits `rows=3` valid shadow-parity promotion rows
before residual `compiler_rc=139`. Scope: this changes authority plumbing and
debug/report evidence only; it does not change emitted compiler semantics and
does not make `s2b`/`s3b` green. Decay trigger: the override helper starts
returning owner results, `MaterializationDecisionRecord` fields change, or a
later lane replaces this seam with a different owner contract.

[LM-ARCH-PROMOTION-SELECTION-NO-REPEAT|verified 2026-07-01 {F:0.82 G:0.42 R:0.88}]:
Slice 0k-N hardens the promotion-selection report so it cannot select the
already promoted `lower_function_if_needed.override` seam again. The report now
auto-detects the 0k-L source shape and marks the seam
`selection_status=already_promoted_shadow`. Evidence:
`AUTO_DETECT_PROMOTED=0 scripts/materialization_promotion_selection_report.sh
/private/tmp/adamas_0kn_stage1` preserves the old baseline
(`eligible_promote_owner`, `eligible_count=1`, `selected_count=1`,
`preferred_already_promoted=0`), while the default report prints
`promoted_consumers=lower_function_if_needed.override`,
`selection_status=already_promoted_shadow`, `eligible_count=0`,
`selected_count=0`, and `preferred_already_promoted=1`. Scope: report/gate
only; no compiler semantics changed and no green `s2b`/`s3b` claim. The
focused post-0k-L `MaterializationDecision` lane therefore has no second
eligible consumer in the current report surface; the next implementation lane
should move to `SemanticStateScope` facade unless a fresh focused report names
a different unpromoted MaterializationDecision consumer. Decay trigger:
promotion-selection row semantics change, a second unpromoted consumer becomes
eligible with complete owner fields, or the source-shape detector no longer
matches the override seam.

[LM-ARCH-SEMANTIC-STATE-SCOPE-ADMISSION-GATE|design-sealed 2026-07-01 {F:0.80 G:0.52 R:0.86}]:
Slice 0k-O tightens the post-0k-N `SemanticStateScope` lane before any new code.
The previous "add a behavior-neutral scope snapshot" wording was too weak
because it could admit another ledger/helper while every consumer kept reading
ambient state through the legacy helper. The next `SemanticStateScope` code
slice is admitted only if it presents a concrete receipt for exactly one
selected seam: `old_edge`, `owned_edge`, `legacy_parity`, `source_shape`,
`report_shape`, `generated_stage_boundary`, and `cleanup_impact`. The preferred
candidate is currently `prefer_callsite_specialization`, where the source still
directly calls `state_scope_consumer_def_has_untyped_regular_param?`, but that
candidate must be rechecked against the live `StateScopeConsumer` report before
implementation. Rejected repeats remain new rows without edge replacement,
boolean modes on old predicates, global `@type_param_map` changes, broad
multi-consumer migration, backend stub/forwarder/keepalive work, remangling,
requested-name materialization, `NamedTuple`/`Tuple` normalization, and rolling
`BlockOwner` back to tuple/namedtuple metadata. Scope: docs-only admission gate;
no compiler behavior changed and no green `s2b`/`s3b` claim. Decay trigger:
a concrete SemanticStateScope owner-consumption slice lands with source-shape
and report evidence, the live consumer report refutes
`prefer_callsite_specialization` as a root-sized seam, or the owner explicitly
switches the next lane to runtime `CodePathStatus` cleanup.

[LM-ARCH-SEMANTIC-STATE-SCOPE-ADMISSION-SELECTION|verified 2026-07-01 {F:0.84 G:0.42 R:0.88}]:
Slice 0k-P adds the behavior-neutral
`scripts/semantic_state_scope_admission_report.sh` selection gate. It consumes
existing `[STATE_SCOPE_CONSUMER]` rows and emits `[STATE_SCOPE_ADMISSION]`
candidate rows without changing compiler instrumentation or emitted semantics.
Fresh stage1 evidence selects exactly one next state-scope owner-consumption
candidate: `prefer_callsite_specialization`, with
`preferred_source_shape=legacy_direct_edge`, `preferred_rows=3448`,
`migrate_to_state_scope=1256`, `migrate_to_materialization_registry=1063`,
`rejected_ambient=269`, `keep_legacy_shim=860`, `eligible_count=1`, and
`selected_count=1`. Other current consumers are rejected as later
keep-requested-name seams, backend-adjacent remangling, direct predicate helper
rows, or already materialization-promoted override work. The report's
`REQUIRE_PROMOTED=1` red mode currently exits `9` because
`prefer_callsite_specialization` still calls
`state_scope_consumer_def_has_untyped_regular_param?` directly and no promoted
shadow helper is present. Scope: report/selection only; no
`SemanticStateScopeSnapshot` exists yet, no compiler behavior changed, and no
green `s2b`/`s3b` claim is made. Decay trigger: the selected
`prefer_callsite_specialization` helper lands and turns `REQUIRE_PROMOTED=1`
green, live consumer rows change materially, or the owner switches the next lane
to `CodePathStatus` cleanup.

[LM-ARCH-SEMANTIC-STATE-SCOPE-OWNER-CONTRACT|design-sealed 2026-07-01 {F:0.78 G:0.50 R:0.86}]:
Slice 0k-Q pauses code before accepting the first `SemanticStateScope` helper.
A local uncommitted `SemanticStateScopeSnapshot` / `[STATE_SCOPE_PROMOTION]`
WIP was removed as non-admitted because it did not yet prove that
`def_has_untyped_regular_param?` had become parity-only instead of the hidden
authority. The next code slice must implement an owner contract, not another
diagnostic wrapper: exactly `prefer_callsite_specialization`, old direct edge
removed from that selected consumer, owned record with requested/target/
selected-def/maps/lifetime fields, owner result computed separately from
legacy result, `emitted_result == legacy_result`, no other promoted consumer,
and the existing state-scope/materialization/codepath gates still green. If
the future helper only logs rows and returns the legacy predicate without a
separate owner result and mismatch census, it is diagnostic-only and must not
be counted as architecture progress. Scope: docs-only contract, no compiler
behavior changed and no green `s2b`/`s3b` claim. Decay trigger: a concrete
`prefer_callsite_specialization` owner helper lands with source-shape/report
evidence, or the owner explicitly switches to `CodePathStatus` cleanup
selection.

[LM-ARCH-SEMANTIC-STATE-SCOPE-PREFER-CALLSITE-PROMOTED|verified 2026-07-01 {F:0.84 G:0.42 R:0.88}]:
Slice 0k-R promotes the first `SemanticStateScope` consumer seam in
shadow/parity mode. `prefer_callsite_specialization` now calls a named
`SemanticStateScopeDecision` helper instead of directly calling
`state_scope_consumer_def_has_untyped_regular_param?`. The helper evaluates
`def_has_untyped_regular_param?` only as legacy parity, emits
`[STATE_SCOPE_PROMOTION]` rows under
`ADAMAS_SEMANTIC_STATE_SCOPE_PROMOTION_LEDGER=1`, records owner-result classes
(`state_scope`, `materialization_registry`, `rejected_ambient`,
`legacy_shim`), and returns the legacy result as emitted behavior. Evidence:
pre-slice red gate exited `9` with
`preferred_source_shape=legacy_direct_edge`; fresh stage1 build succeeded;
`REQUIRE_PROMOTED=1 scripts/semantic_state_scope_admission_report.sh
/private/tmp/adamas_0kq2_stage1` exits `0` with
`preferred_source_shape=already_promoted_shadow`, `promotion_rows=3448`,
`promotion_non_preferred=0`, `promotion_malformed=0`, `promotion_invalid=0`,
`promotion_emitted_mismatch=0`, and `already_promoted_count=1`;
owner-result buckets are `state_scope=1256`,
`materialization_registry=1063`, `rejected_ambient=269`,
`legacy_shim=860`; existing state-scope, materialization-selection,
semantic-decision, and codepath-status reports still pass; env-off smoke emits
no promotion rows and prints `1`; regression suites pass `152/152 + 36/36`;
fresh generated s2 builds with `EXIT: 0` and compiles/runs a no-prelude
`x = 1` smoke. Residual boundary: generated-s2 full-prelude `x = 1` still exits
`139` after `pass3 after lower_main call`, so this is not a green `s2b`/`s3b`
claim. Decay trigger: the source-shape detector no longer sees the helper, a
future behavior slice consumes `owner_result`, or the state-scope admission
report selects the same seam again instead of treating it as
`already_promoted_shadow`.

[LM-ARCH-CODEPATH-IDENTITY-DRY-RUN-DEBUG-ONLY|verified 2026-07-01 {F:0.80 G:0.34 R:0.86}]:
Slice 0k-S adds the first runtime `CodePathStatus` cleanup selection report
after the promoted `SemanticStateScope` seam. The selected path is
`cli.metrics.identity_dry_run`, classified as `debug_only` and
`classify_only`, not `delete_ready`. Evidence:
`scripts/codepath_status_cleanup_selection_report.sh` runs a default
`ADAMAS_CODEPATH_STATUS_LEDGER=1` no-prelude compile and an enabled
`ADAMAS_CODEPATH_STATUS_LEDGER=1 ADAMAS_IDENTITY_DRY_RUN=1` no-prelude compile;
with fresh `/private/tmp/adamas_0ks_stage1`, both compiler runs exit `0`, each
has exactly one selected row, the default selected status is `not_taken`, the
enabled selected status is `taken`, category is `cli.metrics`, owner is `CLI`,
and the report emits `[CODEPATH_CLEANUP_SELECTION] cluster=cli.metrics
path=identity_dry_run owner=CLI status=debug_only
protecting_falsifier=env_off_not_taken_env_on_taken action=classify_only`.
Existing `codepath_status_runtime_report` still reports `rows=26`,
`malformed=0`, `taken=8`, `not_taken=18`; static codepath and semantic censuses
still run; `bash -n` and `git diff --check` pass. Scope: no deletion, no
compiler behavior change, no green `s2b`/`s3b` claim. Decay trigger: the
runtime path name changes, `ADAMAS_IDENTITY_DRY_RUN` becomes default behavior,
or a future deletion slice promotes this path to `delete_ready` with
HIR/MIR/LLVM and bootstrap guards.

[LM-ARCH-ACTIVE-BOARD-CONTROLS-NEXT-SLICE|design-sealed 2026-07-01 {F:0.78 G:0.58 R:0.84}]:
Slice 0k-T makes the SDD's `Active Architecture Board` the authoritative
current decision surface. The many older "Current next-slice decision after
..." paragraphs are preserved as historical ledger entries, but they no longer
select the next slice by themselves. The board buckets active work into
`SemanticStateScope`, `MaterializationIdentity` / `MaterializationRegistry`,
`NameResolution` / `MethodNameCodec`, `AstNodeRef` / `ArenaOwnership`, and
`CodePathStatus`. A future slice must move exactly one board row by replacing
or shadowing a named authority edge, classifying a named path through runtime
`CodePathStatus`, or refuting the current row with fresher generated-stage
evidence. Default correctness lane after this checkpoint is
`NameResolution` / `MethodNameCodec` plus `MaterializationIdentity` ownership;
cleanup remains admitted only as an explicit `CodePathStatus` slice. Scope:
docs/control-plane only, no compiler behavior changed, no deletion, no
`BlockOwner` rollback, and no green `s2b`/`s3b` claim. Decay trigger: the SDD
board is replaced, a later slice lands without mapping to a board row, or a
green generated-stage bootstrap invalidates the current row priorities.

[LM-ARCH-METHOD-NAME-CODEC-ADMISSION-SELECTION|verified 2026-07-01 {F:0.82 G:0.42 R:0.88}]:
Slice 0k-U adds a behavior-neutral source-shape gate for the
`NameResolution` / `MethodNameCodec` board row:
`scripts/method_name_codec_admission_report.sh`. The selected first seam is
`lower_function_if_needed.exact_lookup_keep_requested_name`, where
`keep_requested_name` still depends on rendered suffix/arity string checks:
`name.includes?('$')`, `!name.includes?("$arity")`, and
`resolved_entry_name.includes?("$arity")`. The future owned edge is a
shadow/parity helper named
`method_name_codec_exact_lookup_keep_requested_name?`. Evidence:
`scripts/method_name_codec_admission_report.sh` exits `0` with
`preferred_source_shape=legacy_string_edge`,
`selection_status=eligible_codec_owner`,
`exact_old_requested_suffix_count=1`, `exact_old_resolved_arity_count=1`, and
`exact_helper_count=0`; `REQUIRE_PROMOTED=1
scripts/method_name_codec_admission_report.sh` exits `9`, proving the future
helper has a red source-shape gate. Scope: source-shape/admission only, no
compiler behavior changed, no materialization naming behavior changed, no
deletion, no `BlockOwner` rollback, and no green `s2b`/`s3b` claim. Decay
trigger: the exact-lookup keep-requested-name branch is rewritten, the helper
lands, or a fresh board update chooses a different MethodNameCodec seam.

[LM-ARCH-METHOD-NAME-CODEC-EXACT-LOOKUP-SHADOW|verified 2026-07-01 {F:0.84 G:0.36 R:0.88}]:
Slice 0k-V promotes the first `MethodNameCodec` consumer in shadow/parity mode.
The exact-lookup `keep_requested_name` branch in
`lower_function_if_needed_impl` no longer directly owns rendered suffix/arity
checks; it calls `method_name_codec_exact_lookup_keep_requested_name?`.
Default emitted behavior still returns the legacy short-circuit result. The
default-off `ADAMAS_METHOD_NAME_CODEC_PROMOTION_LEDGER=1` path computes the
typed owner-result through `MethodNameParts` suffix facts and logs
legacy/owner/emitted parity for this selected seam. Evidence:
`crystal build src/adamas.cr -o /private/tmp/adamas_method_codec_stage1
--error-trace` passes; `scripts/method_name_codec_admission_report.sh` reports
`preferred_source_shape=already_promoted_shadow`,
`selection_status=already_promoted_shadow`,
`exact_old_requested_suffix_count=0`, `exact_old_resolved_arity_count=0`, and
`exact_helper_count=2`; `REQUIRE_PROMOTED=1
scripts/method_name_codec_admission_report.sh` exits `0`; static semantic and
CodePathStatus censuses still run; focused split/materialization/dispatch
guards pass (`string_split_char_delimiter`,
`string_split_separator_materialization_collision`,
`string_split_default_nil_limit`, `string_split_int32_nil_limit_collision`,
`class_arg_overload_dispatch`, and `stage2_method_name_corruption`); fresh
stage1 builds fresh s2 under `scripts/run_safe.sh` (`EXIT: 0` after ~190s),
and that generated s2 compiles and runs a no-prelude `x = 1` smoke. Scope:
behavior-neutral consumer ownership only, no materialization naming behavior
flip, no backend remangling, no `BlockOwner` carrier change, and no green
`s2b`/`s3b` claim. Decay trigger:
the helper starts returning owner-result behavior, sibling keep-requested-name
seams are promoted, `MethodNameParts` suffix semantics change, or generated
stage evidence shows this helper is not self-host safe.

[LM-ARCH-ANTI-LEDGER-PROLIFERATION-PAUSE|design-sealed 2026-07-01 {F:0.76 G:0.58 R:0.84}]:
Slice 0k-W pauses production-code and report-surface work after the
`MethodNameCodec` exact-lookup shadow helper. The immediate risk is no longer
lack of another diagnostic row; it is mistaking another wrapper script for
architecture progress. A local uncommitted
`scripts/method_name_codec_promotion_report.sh` scratch was removed rather than
committed because it only made existing
`ADAMAS_METHOD_NAME_CODEC_PROMOTION_LEDGER=1` rows easier to print. It did not
name a new authority edge, select a new seam, classify a path through
`CodePathStatus`, refute an active-board row, or state the yes/no SDD decision
it would unblock. Next production-code or report-surface work must provide an
implementation receipt: `old_edge`, `owned_fact`, `decision_question`,
`red_gate`, `green_gate`, `generated_stage_boundary`, and `cleanup_rule`.
Rejected repeats remain standalone report proliferation, backend forwarders,
target keepalive, requested-name forcing, global ambient-map changes,
`NamedTuple`/`Tuple` normalization, and rolling `BlockOwner` back to tuple or
namedtuple owner metadata. Scope: docs/control-plane only; no compiler behavior
changed, no deletion, no `BlockOwner` carrier change, and no green `s2b`/`s3b`
claim. Decay trigger: the next slice lands with a concrete authority-edge
receipt, the active board is replaced, or a future generated-stage report
refutes the current MethodNameCodec/MaterializationIdentity priority.

[LM-ARCH-MATERIALIZATION-SYMBOL-BINDING-RECEIPT|design-sealed 2026-07-01 {F:0.78 G:0.54 R:0.84}]:
Slice 0k-X selects the next implementation unit before production edits:
`MaterializationIdentity / lower_function_if_needed.symbol_binding`. The old
authority edge is the split inline symbol-binding logic in
`lower_function_if_needed_impl`: `materialized_name` is chosen from requested
wrapper / shape-specialization / resolved target branches; later `override` is
chosen from requested-wrapper / deferred-lookup / untyped-param / target
branches; keepalive and materialization ledgers consume those separately
computed locals. The selected owned fact for the future code slice is a
`MaterializationSymbolBinding`-style helper/record carrying requested symbol,
resolved target symbol, materialized body symbol, override/call-symbol hint,
selected definition, state-scope/materialization decision, target map, callsite
arg types, ABI class, and keepalive requirement in one HIR-owned object.
Future emitted behavior must stay legacy/parity-only until a separate
would-change slice is admitted. Required next gate: red/green source-shape
evidence proving the selected seam consumes the binding record and the old
inline symbol-binding windows are removed or moved inside the helper as
parity-only logic. Acceptance is stronger than a record-only refactor:
downstream consumers must read body/call/keepalive symbols from the binding
record and must not re-derive them from separate `name` / `target_name` locals
after the helper returns. Scope: docs-only implementation receipt; no compiler
behavior changed, no deletion, no backend remangling, no `BlockOwner` carrier
change, and no green `s2b`/`s3b` claim. Decay trigger: the binding helper lands
with source-shape and stage evidence, a fresh board update selects a different
row, or generated-stage evidence refutes materialization symbol binding as the
next useful authority edge.

[LM-ARCH-MATERIALIZATION-SYMBOL-BINDING-GATE|design-sealed 2026-07-01 {F:0.82 G:0.46 R:0.88}]:
Slice 0k-Y adds the executable source-shape admission gate for the selected
`MaterializationIdentity / lower_function_if_needed.symbol_binding` seam:
`scripts/materialization_symbol_binding_admission_report.sh`. On the current
source it reports `source_shape=legacy_split_edge`,
`selection_status=eligible_symbol_binding_owner`, one old materialized-name
branch, one old override branch, one direct keepalive use, direct ledger symbol
use, and zero binding consumers. With `REQUIRE_PROMOTED=1` it exits 9 today,
which is intentional: the gate is red until a future
`MaterializationSymbolBinding`-style helper/record becomes the consumer-facing
authority for body/call/keepalive symbols. If a future implementation reports
`partial_binding_authority`, it is not architecture progress. Scope:
source-shape gate only; no compiler behavior changed, no backend rescue, no
target keepalive patch, no remangling, no `NamedTuple`/`Tuple` rendering
change, no ambient-map policy change, no `BlockOwner` carrier change, and no
green `s2b`/`s3b` claim. Decay trigger: the gate turns green with a helper
implementation, or the active board selects a different MaterializationIdentity
authority edge.

[LM-ARCH-MATERIALIZATION-SYMBOL-BINDING-SHADOW|verified 2026-07-01 {F:0.86 G:0.50 R:0.88}]:
Slice 0k-Z promotes `lower_function_if_needed.symbol_binding` in
shadow/parity mode. `src/compiler/hir/ast_to_hir.cr` now has a
`MaterializationSymbolBinding` record carrying requested symbol, target
symbol, materialization state key, body symbol, call-symbol hint, override
symbol, and override reason. The old inline materialized-name and override
branches are gone from `lower_function_if_needed_impl`; instance keepalive and
instance/class/def materialization-ledger consumers read binding fields instead
of recomputing split locals. `scripts/materialization_symbol_binding_admission_report.sh`
and `REQUIRE_PROMOTED=1` now report `source_shape=already_promoted_shadow`,
with `old_materialized_branch_count=0`, `old_override_branch_count=0`,
`direct_keepalive_count=0`, `direct_ledger_materialized_count=0`, and
`direct_ledger_override_count=0`. Verification: fresh stage1 builds; full
regression suites pass `152/152 + 36/36`; materialization transaction and
promotion-selection reports have malformed/invalid counts at zero; fresh stage1
builds fresh s2; generated s2 no-prelude smoke compiles and runs `x = 1` with
output `1`. Residual boundary: generated s2 full-prelude smoke still exits 139
after `pass3 after lower_main call`, so this is not a green `s2b`/`s3b` claim
and does not authorize backend forwarders, target keepalive behavior patches,
requested-name forcing, remangling, `NamedTuple`/`Tuple` rendering changes,
ambient-map policy changes, or `BlockOwner` rollback. Decay trigger: emitted
symbol behavior starts reading owner-result instead of legacy parity, generated
stage evidence refutes the binding as self-host safe, or the active board
selects a different MaterializationIdentity consumer.

[LM-S2S3-FUNCTION-TYPE-PARAM-MAP-DIG-OPTIONAL-LOOKUP|verified 2026-06-30 {F:0.84 G:0.24 R:0.88}]:
Fresh generated s2 no longer stops in
`__adamas_string_eq <- __crystal_proc_1627 <-
AstToHir#lower_generic_type_ref` while compiling `src/adamas.cr` to s3. lldb
and HIR probes tied `__crystal_proc_1627` to the local
`normalize_typeof_name : String -> String` lambda in `lower_generic_type_ref`.
The Proc receiver was a heap Proc with declared `String -> String` parameters;
the bad argument was already a `Bool | String` local before the call. The first
bad local binding came from `arg_name = br` in the
`@function_type_param_maps.dig?(..., "__block_return__")` fallback. Standalone
falsifiers for `Hash(String, Hash(String, String))` showed direct
`has_key? + []` lookup returns `String`, while nested `dig?` returns nil and
inner `[]?` produces an invalid-looking String value under V2. Root-shaped
boundary for this bootstrap slice: self-host compiler metadata lookup relied on
nested Hash optional/dig semantics that are not safe in V2. Fix slice: add
`function_type_param_map_value?` and route every `@function_type_param_maps`
`__block_return__` lookup through `has_key? + []` instead of `dig?`. Evidence:
`crystal build src/adamas.cr -o /private/tmp/adamas_lgtr_stage1 --error-trace`;
`regression_tests/function_type_param_map_safe_lookup_repro.sh
/private/tmp/adamas_lgtr_stage1` passes;
`regression_tests/run_all_suites.sh /private/tmp/adamas_lgtr_stage1 4` passes
152/152 original + 36/36 combined; fresh fixed stage1 builds fresh s2; fixed
s2->s3 no longer stops in `lower_generic_type_ref` and instead reaches a later
RSS frontier after `pass3 after lower_main call` (safe-wrapper kills at both
4GB and 8GB). Scope: compiler metadata lookup hardening only; standalone
`Hash#dig?`/inner `Hash#[]?` remains a residual bug family and this is not a
green s2->s3/s3b claim. Decay trigger: rewrites of
`@function_type_param_maps`, block-return metadata propagation, Hash optional
lookup lowering, or `lower_generic_type_ref` `typeof(yield)` recovery.

[LM-S2S3-HASH-ENTRY-PRIMITIVE-TUPLE-FIELDGET-ABI|verified 2026-06-30 {F:0.87 G:0.34 R:0.89}]:
Fresh generated s2 no longer stops in
`Hash(Tuple(UInt32, UInt32), Nil)#entry_matches? <- Set#add <-
AstToHir#lower_break` while compiling `src/adamas.cr` to s3. lldb on the
crashing baseline s2 showed the incoming lookup key was a valid tuple pointer,
but the existing `Hash::Entry` stored the primitive tuple key inline in the
entry body. The generated `entry_matches?` consumer loaded the first entry word
as a pointer (`ldr x9, [entry]`) and then dereferenced it, misreading inline
tuple fields as an address. Producer-side disassembly of `Hash::Entry#initialize`
and `Hash#set_entry` showed the write path already copied the tuple payload
inline. Root-shaped boundary: `FieldGet @key` for a primitive Tuple/NamedTuple
field inside an inline-container struct receiver (`Hash::Entry`) used the
pointer-carrier read path instead of borrowing the field address. Fix slice:
when `lower_field_get` sees an inline primitive tuple field on an
inline-container struct receiver, return the field GEP and mark it as an inline
aggregate pointer. Evidence: `crystal build src/adamas.cr -o
/private/tmp/adamas_deadset_stage1_fix --error-trace`; focused
`Set(Tuple(UInt32, UInt32))` reducer prints `true/true/2`; patched s2
disassembly for the same `entry_matches?` directly reads `[entry]` and
`[entry+4]` without dereferencing `[entry]`; `regression_tests/run_all_suites.sh
/private/tmp/adamas_deadset_stage1_fix 4` passes 152/152 original + 36/36
combined; fresh fixed stage1 builds fresh s2; fixed s2->s3 now stops in the
later frontier
`__adamas_string_eq <- __crystal_proc_1627 <-
AstToHir#lower_generic_type_ref`, not in `Hash(Tuple(UInt32, UInt32),
Nil)#entry_matches?`. Scope: this is an inline-container field-read ABI repair
for primitive tuple payloads, not a global Hash rewrite and not a green
s2->s3/s3b claim. Decay trigger: any rewrite of `Hash::Entry` container layout,
primitive tuple carrier rules, or `lower_field_get` aggregate read semantics.

[LM-S2S3-HEAP-PROC-INDIRECT-UNION-ARG-ABI|verified 2026-06-30 {F:0.86 G:0.30 R:0.89}]:
Fresh generated s2 no longer stops in
`__adamas_string_eq <- __crystal_proc_653 <-
LLVMIRGenerator#emit_extern_call` while compiling `src/adamas.cr` to s3. IR
and lldb disassembly tied `__crystal_proc_653` to the heap Proc body for
`cast_fixed_arg`: the generated function expected declared Proc parameters,
including full `Nil | TypeRef` union arguments, but `emit_indirect_call`
unconditionally unwrapped every union argument as if the indirect call were raw
yield dispatch. That shifted the Proc ABI and left `expected_type` stale before
the first `expected_type == "void"` comparison. A standalone reducer
`(String, Wrap?, String, String, Wrap?)` returned `REF` before the fix and
`VALUE` after the fix, proving the second nilable argument was preserved only
when heap Proc calls pass full unions. Fix slice: add
`MIR::IndirectCall#unwrap_union_args` with the existing unwrap behavior as the
default, preserve that default for raw yield callbacks, and set
`unwrap_union_args: false` only in heap Proc dispatch. Evidence:
`crystal build src/adamas.cr -o /private/tmp/adamas_procabi_stage1
--error-trace`; `regression_tests/proc_nilable_union_arg_indirect_call_repro.sh
/private/tmp/adamas_procabi_stage1` passes; `regression_tests/run_all_suites.sh
/private/tmp/adamas_procabi_stage1 4` passes 152/152 original + 36/36
combined; fresh fixed stage1 builds fresh s2; fixed s2->s3 now stops in the
later frontier
`Hash(Tuple(UInt32, UInt32), Nil)#entry_matches? <- Set#add <-
AstToHir#lower_break`, not in `__crystal_proc_653` or
`LLVMIRGenerator#emit_extern_call`. Scope: this is a bounded heap Proc
indirect-call union-argument ABI repair, not a global Proc/yield ABI redesign
and not a green s2->s3/s3b claim.

[LM-S2S3-INTERPOLATION-I32-ARG-TYPEREF-HELPER-ABI|verified 2026-06-30 {F:0.86 G:0.26 R:0.89}]:
Fresh generated s2 no longer stops in
`MIR::TypeRef#hash <- Hash(MIR::TypeRef, String)#[]? <-
LLVMTypeMapper#llvm_type <- LLVMIRGenerator#emit_string_interpolation` while
compiling `src/adamas.cr` to s3. Boundary probes inside
`emit_string_interpolation` and `interpolation_i32_arg` showed the
interpolation metadata was valid before the helper call: caller-side
`part_type.id` read succeeded, and callee-side `hint.id` could also be read
when probed before `@type_mapper.llvm_type(hint)`. The crash then occurred in
`Hash(TypeRef, String)#key_hash -> TypeRef#hash`, and a scalar id-cache attempt
was refuted because it simply moved the crash to the first `type_ref.id` read
inside `LLVMTypeMapper#llvm_type`. Root-shaped boundary: the nilable wrapper
argument `hint_type : TypeRef?` is unsafe across the interpolation helper call
under self-hosting; the caller can translate the local `TypeRef` to scalar LLVM
metadata before crossing that boundary. Fix slice: change
`interpolation_i32_arg` to accept `hint_llvm_type : String?` plus a scalar
`signed : Bool`, preserving emitted-value and cross-block-slot precedence while
removing the `TypeRef?` helper argument. Evidence: `crystal build
src/adamas.cr -o /private/tmp/adamas_interp_scalar_stage1 --error-trace`;
fresh fixed stage1 builds fresh s2; `regression_tests/run_all_suites.sh
/private/tmp/adamas_interp_scalar_stage1 4` passes 152/152 original + 36/36
combined; lldb on fresh fixed s2->s3 now stops in the later frontier
`__adamas_string_eq <- __crystal_proc_653 <-
LLVMIRGenerator#emit_extern_call`, not in `MIR::TypeRef#hash` or
`LLVMTypeMapper#llvm_type`. Scope: this is a bounded interpolation-helper ABI
repair, not a global `TypeRef` hash/value-round-trip fix and not a green
s2->s3/s3b claim.

[LM-S2S3-MISSING-REQUIRED-PARAM-EACH-PARAM-CALLBACK|verified 2026-06-30 {F:0.84 G:0.28 R:0.88}]:
Fresh generated s2 no longer stops with `EXC_BREAKPOINT` in
`AstToHir#missing_required_runtime_param_types? <- AstToHir#lower_method` while
compiling `src/adamas.cr` to s3. Fresh base stage1 built fresh s2; base s2->s3
reproduced `EXIT 133`, and lldb stopped in `missing_required_runtime_param_types?`.
A marker immediately before the `return true` branch did not print in generated
s2, refuting that return as the immediate edge. A wider primitive marker probe
showed the final generated-s2 marker was the callback `loop` marker, with no
`after skip`, pinning the trap to the yielded `each_param` callback skip line
(`next if named_only_separator?(param) || param.is_block ||
param.is_double_splat`). Root-shaped boundary: this predicate used
yielded-block control-flow in a self-hosted hot path, not corrupt `call_types`
or corrupt parameter metadata. Fix slice: rewrite only
`missing_required_runtime_param_types?` as an indexed `while` scan over
`param_at_or_nil`, preserving null-param skip, named/block/double-splat skip,
and required-`VOID` detection without yielded-block `next`, `break`, or `return`.
Evidence: `crystal build src/adamas.cr -o
/private/tmp/adamas_missing_param_fix_stage1 --error-trace`; fresh fixed stage1
builds fresh s2; fixed s2 compiling `src/adamas.cr` no longer crashes in
`missing_required_runtime_param_types?`; `regression_tests/run_all_suites.sh
/private/tmp/adamas_missing_param_fix_stage1 4` passes 152/152 original +
36/36 combined. Residual frontier: fixed s2->s3 now exits 139 in
`MIR::TypeRef#hash <- Hash(MIR::TypeRef, String)#[]? <-
LLVMTypeMapper#llvm_type <- LLVMIRGenerator#emit_string_interpolation` during
LLVM emission after allocator flush. Scope: this is a bounded parameter-scan
callback-control fix, not a global `each_param` or block-callback ABI repair and
not a green s2->s3/s3b claim.

[LM-S2S3-STATIC-TRUTHY-LITERAL-CACHED-BOOL|verified 2026-06-30 {F:0.85 G:0.32 R:0.89}]:
Fresh generated s2 no longer stops in
`AstToHir#static_truthy_value <- AstToHir#lower_short_circuit_condition <-
AstToHir#lower_while` while compiling `src/adamas.cr` to s3. Primitive probes
inside `static_truthy_value` showed `ctx.value_for(value_id)` succeeded and
the last failing path was a Bool `Literal`: `value.type.id=1`
(`TypeRef::BOOL`), `is_literal=1`, and the probe printed after `value.value`
returned before the crash. Root-shaped boundary was therefore the
polymorphic `case bool_lit = value.value` over `LiteralValue`, not
`ctx.value_for`, `value.type`, or the payload load. This matches the existing
`Literal` representation contract in `hir.cr`: primitive payloads are mirrored
to `@int_value` / `@uint_value` / `@float_value` because V2 can corrupt the
`@value` union tag, and `Literal#to_s` already uses `@int_value` for Bool.
Fix slice: make `static_truthy_value` evaluate Bool literals through
`value.int_value != 0` instead of reading and case-dispatching on
`value.value`. Evidence: `crystal build src/adamas.cr -o
/private/tmp/adamas_static_truthy_fix_stage1 --error-trace`; fresh fixed
stage1 builds fresh s2; fixed s2 compiling `src/adamas.cr` no longer crashes
in `static_truthy_value`; with a 20GB `run_safe` cap lldb now stops in the
later frontier `AstToHir#missing_required_runtime_param_types? <-
AstToHir#lower_method`; `regression_tests/run_all_suites.sh
/private/tmp/adamas_static_truthy_fix_stage1 4` passes 152/152 original +
36/36 combined. Scope: this is a bounded Bool-literal static-truthiness fix,
not a global `LiteralValue` union ABI repair and not a green s2->s3 claim.

[LM-S2S3-STRINGIFY-TYPE-EXPR-ARENA-BOUNDARY|verified 2026-06-30 {F:0.85 G:0.34 R:0.89}]:
Fresh generated s2 no longer stops in
`NodeSlot#node <- AstArena#[] <- AstToHir#stringify_type_expr <-
AstToHir#lower_call` while compiling `src/adamas.cr` to s3. Boundary probes
showed this was not a corrupt or unowned `ExprId`: the failing value was
`ExprId 774`, the current arena had size `109`, `@main_arenas` had `398`
entries, and the existing `arena_for_expr?` path resolved the same id to a
known arena of size `775`. Root-shaped boundary was `stringify_type_expr`
using raw `@arena[expr_id]`, unlike nearby helpers such as `node_for_expr`
that already route through arena resolution. Fix slice: make
`stringify_type_expr` a resolver wrapper that rejects null/invalid ids,
looks up the owning arena with `arena_for_expr?`, and executes the former body
as `stringify_type_expr_in_current_arena` under `with_arena(arena)`. This
preserves recursive type-AST stringification while reading child ids from the
owning arena; it does not drop valid foreign type expressions as nil.
Evidence: `crystal build src/adamas.cr -o
/private/tmp/adamas_stringify_fix_stage1 --error-trace`; fresh fixed stage1
builds fresh s2; fixed s2 compiling `src/adamas.cr` no longer crashes in
`stringify_type_expr`; with a 20GB `run_safe` cap lldb now stops in the later
frontier `AstToHir#static_truthy_value <-
AstToHir#lower_short_circuit_condition <- AstToHir#lower_while`;
`regression_tests/run_all_suites.sh /private/tmp/adamas_stringify_fix_stage1
4` passes 152/152 original + 36/36 combined. Scope: this is a bounded
type-expression arena-boundary fix, not a global arena identity redesign and
not a green s2->s3 claim. Caveat: the same s2->s3 run may hit the 16GB
`run_safe` memory cap before exposing the later `static_truthy_value` stack.

[LM-S2S3-ENUM-PREDICATE-FIND-BLOCK|verified 2026-06-30 {F:0.84 G:0.28 R:0.89}]:
Fresh generated s2 no longer stops in
`AstToHir#lower_enum_predicate <- AstToHir#lower_member_access <-
AstToHir#lower_if` while compiling `src/adamas.cr` to s3. Boundary probes
first showed the non-enum `Nil | String` predicate path completed through
`after_lazy enum=nil`, then pinned the crash to the enum predicate
`Path.to_kind$Path::Kind_Bool`: enum metadata was valid
(`enum_key=Path::Kind`, `enum=Path::Kind`, `count=2`), `base=posix` and
`target=posix` were valid, and the crash happened before the match step
completed. Root-shaped producer was the hot-path yielded block
`members.keys.find { |m| underscore_lower(m) == target }`, not enum metadata
resolution or member-name normalization. Fix slice: replace that block `find`
with an indexed scan over `members.keys`, preserving the same comparison while
avoiding a self-host-brittle block callback and captured `target` in this
compiler chokepoint. Evidence: `crystal build src/adamas.cr -o
/private/tmp/adamas_enum_fix_stage1 --error-trace`; fresh fixed stage1 builds
fresh s2; fixed s2 compiling `src/adamas.cr` no longer crashes in
`lower_enum_predicate` and instead reaches the next frontier,
`NodeSlot#node <- AstArena#[] <- AstToHir#stringify_type_expr <-
AstToHir#lower_call`; `regression_tests/run_all_suites.sh
/private/tmp/adamas_enum_fix_stage1 4` passes 152/152 original + 36/36
combined. Scope: this is a bounded enum-predicate matching repair, not a
global fix for every `Enumerable#find` / block-capture shape and not a green
s2->s3 claim.

[LM-S2S3-BLOCK-ARENA-LOWERING|verified 2026-06-30 {F:0.85 G:0.34 R:0.89}]:
Fresh generated s2 no longer stops in
`NodeSlot#node <- AstArena#[] <- AstToHir#collect_assigned_vars_in_expr <-
AstToHir#lower_block_to_block_id` while compiling `src/adamas.cr` to s3.
Baseline lldb stopped in `NodeSlot#node` with an ASCII-looking fault address,
but env-gated boundary probes showed the first bad transition was earlier:
`lower_block_to_block_id` entered for `Exception#inspect_with_backtrace$IO`
with a cached block arena `size=138` and `body_max=76`, while the current
caller arena was `size=41`. The method then unconditionally wrote
`@block_node_arenas[node.object_id] = @arena`, clobbering the correct cached
arena before `collect_assigned_vars` read body expr `76` from arena `41`.
Fix slice: resolve the block arena at `lower_block_to_block_id` entry from
the existing cache / `resolve_arena_for_block` / caller fallback, store it via
`store_block_arena`, lower the block with `@arena` set to that block arena,
and restore the caller arena in `ensure`. Evidence:
`crystal build src/adamas.cr -o /private/tmp/adamas_arena_fix_stage1
--error-trace`; fresh fixed stage1 builds fresh s2; fixed s2 compiling
`src/adamas.cr` no longer crashes in `collect_assigned_vars_in_expr` and
instead reaches the next frontier,
`AstToHir#lower_enum_predicate <- AstToHir#lower_member_access <-
AstToHir#lower_if`; `regression_tests/run_all_suites.sh
/private/tmp/adamas_arena_fix_stage1 4` passes 152/152 original + 36/36
combined. Scope: this is a bounded block-arena lifetime repair, not a global
AstArena/NodeSlot storage fix and not a green s2->s3 claim.

[LM-S2S3-MEMBER-ACCESS-SUFFIX-STRIP|verified 2026-06-30 {F:0.84 G:0.30 R:0.89}]:
Fresh generated s2 no longer stops in
`String#bytesize <- AstToHir#parse_method_name <- AstToHir#apply_default_args`
while compiling `src/adamas.cr` to s3. lldb showed `parse_method_name` was
called with `x0=0x10`, so the argument was a tiny String pointer, not merely a
bad String payload. Targeted raw-pointer probes showed `apply_default_args`
was a consumer: `method_name` was valid, `full_method_name`/`func_name` were
`0x10`, and the caller already had corrupt `base_method_name`. A second
caller-side probe pinned the producer:
`resolve_method_call` returned a valid String (`pre_raw` high), `dollar=16`,
and the local suffix-strip expression `base_method_name[0, dollar]` produced
`post_raw=16`, exactly the integer count reinterpreted as a pointer. Fix
slice: replace that hot-path substring operation with the existing
`strip_type_suffix(resolve_method_call(...))` helper, which uses
`byte_slice(0, dollar)` rather than `String#[](Int32, Int32)`. Evidence:
`crystal build src/adamas.cr -o /private/tmp/adamas_parse_fix_stage1
--error-trace`; fresh fixed stage1 builds fresh s2; fixed s2 compiling
`src/adamas.cr` no longer crashes in `parse_method_name`; with a 16GB
`run_safe` cap it reaches the next frontier,
`NodeSlot#node <- AstArena#[] <- AstToHir#collect_assigned_vars_in_expr <-
AstToHir#lower_block_to_block_id`; `regression_tests/run_all_suites.sh
/private/tmp/adamas_parse_fix_stage1 4` passes 152/152 original + 36/36
combined. Scope: this is a bounded member-access suffix-strip repair, not a
global fix for every `String#[](start, count)` use.

[LM-S2S3-EACH-PARAM-BLOCK-BREAK|verified 2026-06-30 {F:0.84 G:0.28 R:0.90}]:
Fresh generated s2 no longer stops with `EXC_BREAKPOINT` in
`__crystal_block_proc_744 <- AstToHir#each_param <- lower_method` while
compiling `src/adamas.cr` to s3. The earlier lldb stack pointed at a
`lower_method` block callback; replacing the later parameter collector did not
move the stack, which refuted that consumer. The root-shaped producer was the
untyped-param default inference branch in `lower_method`, where
`each_param(params) do |param| ... break` used non-local block control-flow to
stop scanning when a parameter had neither annotation nor default. Fix slice:
add `param_at_or_nil` and rewrite only that scan as an indexed `while` loop
whose condition carries `all_defaulted`, preserving early-stop semantics
without a yielded-block `break`. Evidence: `crystal build src/adamas.cr -o
/private/tmp/adamas_eachparam_break_stage1 --error-trace`;
`regression_tests/run_all_suites.sh /private/tmp/adamas_eachparam_break_stage1
4` passes 152/152 original + 36/36 combined; fresh fixed stage1 builds fresh
s2; fixed s2 compiling `src/adamas.cr` no longer hits the `each_param`
breakpoint and instead reaches the next frontier, a SIGSEGV in
`String#bytesize <- AstToHir#parse_method_name <- AstToHir#apply_default_args`
after `[STAGE2_DEBUG] pass3 after lower_main call`. Scope: this is a bounded
`lower_method` untyped-default scan fix, not a global `each_param` or block
callback rewrite.

[LM-S2S3-LOWER-UNLESS-TUPLE-DESTRUCTURING|verified 2026-06-30 {F:0.84 G:0.30 R:0.90}]:
Fresh generated s2 no longer stops with SIGSEGV in `AstToHir#lower_unless`
while compiling `src/adamas.cr` to s3. Root was the branch-result coercion
producer inside `lower_unless`, not `UnionWrap` or union variant lookup.
A gated probe immediately before `UnionWrap.new` showed the direct branch
values were valid (`then=62`, `else=63` in the crashing case), but the tuple
destructured block parameters from `incoming.map do |(blk, val)|` printed as
corrupted `blk={}` / blank `val` before the wrap call. Nearby `lower_if`
already carried the local invariant "Use indexed tuple access to avoid V2 tuple
destructuring issues" and used indexed arrays for the same merge/coercion
shape. Fix slice: rewrite the two-branch `lower_unless` value merge to build
indexed `incoming_blocks` / `incoming_values` arrays and add phi incomings in a
plain `while` loop, avoiding both `map` tuple destructuring and the later
`coerced_incoming.each` tuple destructuring. Evidence: `crystal build
src/adamas.cr -o /private/tmp/adamas_unless_fix_stage1 --error-trace`;
`regression_tests/run_all_suites.sh /private/tmp/adamas_unless_fix_stage1 4`
passes 152/152 original + 36/36 combined; fresh fixed stage1 builds fresh s2;
fixed s2 compiling `src/adamas.cr` no longer segfaults in `lower_unless` and
instead reaches the next frontier, `EXC_BREAKPOINT` in
`__crystal_block_proc_744 <- AstToHir#each_param <- lower_method`. Scope: this
is a bounded `lower_unless` merge repair, not a global tuple-destructuring fix
for generated s2.

[LM-S2S3-ARENA-FALLBACK-CAPTURED-LOCAL|verified 2026-06-30 {F:0.86 G:0.30 R:0.90}]:
Fresh generated s2 no longer stops with
`error: ExprId out of bounds: 260 (arena=:67, current=:67, main_arenas=398,
inline_arenas=0)` while compiling `src/adamas.cr` to s3. Root was not packed
main expressions and not an empty arena registry. A targeted probe in
`arena_for_expr?` showed `@main_arenas` contained 177 arenas whose size covered
ExprId 260 and the original `@main_arenas.each` loop visited matching
candidates, but the captured locals `best` / `best_size` were still `nil` /
`Int32::MAX` after the block returned in generated s2. Fix slice: replace the
`@inline_arenas.each` and `@main_arenas.each` fallback scans in
`AstToHir#arena_for_expr?` with explicit `while` loops so the selected arena is
written in the current frame. Evidence: `crystal build src/adamas.cr -o
/private/tmp/adamas_exprfix_stage1 --error-trace`; `regression_tests/run_all_suites.sh
/private/tmp/adamas_exprfix_stage1 4` passes 152/152 original + 36/36
combined; fresh fixed stage1 builds fresh s2; fixed s2 compiling
`src/adamas.cr` no longer raises the ExprId 260 OOB and instead reaches the
next frontier, a SIGSEGV in `AstToHir#lower_unless` after
`[STAGE2_DEBUG] pass3 after lower_main call`. Scope: this is a bounded
arena-fallback repair for a directly observed captured-local writeback failure;
it does not fix the broader block-capture family and does not make s2->s3
green.

[LM-S2S3-HIR-CALL-CTOR-FACTORY-MIGRATION|verified 2026-06-30 {F:0.86 G:0.44 R:0.90}]:
Fresh generated s2 no longer stops in
`String#size <- AstToHir#scan_hir_function_for_live_types` while compiling
`src/adamas.cr` to s3. Root was not the scanner/live-type consumer. Temporary
probes first showed `options.optimize = 3` in `src/compiler/cli.cr:1003`
emitted a malformed HIR `Call` with raw low `method_name` pointer `97`, no
receiver, and no args; after assignment call construction was migrated to
factories, the next malformed call came from `Path.new(*parts).to_s` in
`src/stdlib/file.cr:681` with raw low `method_name` pointer `0`. The shared
producer class is self-hosted misselection of overloaded `HIR::Call.new`
constructor shapes, where receiver `ValueId`s can be consumed as method-name
values. Fix slice: add explicit no-receiver block/virtual factories and migrate
production HIR call construction in `AstToHir` to intent-named factories
(`with_receiver*` / `without_receiver*`). Only the two intentional
placeholder `Call.new(..., "")` sites remain. Evidence: `crystal build
src/adamas.cr -o /private/tmp/adamas_call_factory_stage1 --error-trace`;
`regression_tests/run_all_suites.sh /private/tmp/adamas_call_factory_stage1 4`
passes 152/152 original + 36/36 combined; fresh stage1 builds fresh s2;
fixed s2 compiling `src/adamas.cr` no longer segfaults in scanner and instead
exits with `error: ExprId out of bounds: 260`. Static grep plus independent
Spark scout audit found no remaining production `Call.new` sites in
`ast_to_hir.cr`. Scope: this removes the overloaded HIR `Call.new` construction
hazard in `AstToHir`; it does not make s2->s3 green. Residual frontier is the
new ExprId arena-boundary diagnostic after `pass3 after lower_main call`.

[LM-S2S3-IS-A-NARROWING-TARGET-CARRIER|verified 2026-06-30 {F:0.88 G:0.36 R:0.90}]:
Fresh generated s2 no longer stops in
`AstToHir#apply_is_a_narrowing -> TypeRef#==` while compiling `src/adamas.cr`
to s3. Root was the metadata carrier, not `type_ref_for_name` and not the
narrowing consumer loop. Env-gated probes showed
`is_a_narrowing_targets` produced a valid `("parser", OptionParser TypeRef)`
entry and the local array still read back correctly inside the producer, but
the caller of the recursive helper saw the returned `Array(Tuple(String,
TypeRef))` entry corrupted before `apply_is_a_narrowing` consumed it.
Standalone reducers confirmed the representation class: recursive returns of
tuple arrays carrying `String + small value` corrupt after return, while
`Array` of a reference carrier with the same `String` and `TypeRef` fields
preserves `RESULT parser 2566`. Fix slice: replace the internal is-a narrowing
target carrier with private reference class `IsANarrowingTarget` and route the
case-branch narrowing call sites through the same carrier. Evidence:
`crystal build src/adamas.cr -o /private/tmp/adamas_isa_class_stage1
--error-trace`; `regression_tests/hir_is_a_narrowing_target_carrier_guard.sh
/private/tmp/adamas_isa_class_stage1`; full suites pass 152/152 original +
36/36 combined; fresh stage1 builds fresh s2; fixed s2->s3 no longer stops in
`TypeRef#==` and now reaches `String#size <- scan_hir_function_for_live_types`.
Scope: this is a bounded compiler-internal carrier fix, not a general V2 tuple
array storage fix. Residual frontier is the new `String#size` crash.

[LM-S3B-BOOTSTRAPENV-GET-OWNERLOSS-REFUTATIONS|in-progress 2026-06-29 {F:0.82 G:0.30 R:0.86}]:
Generated s3's `STUB CALLED: get$Q$$String` frontier is not a backend-stub
root. Static IR from an s2-built compiler shows startup lowering emits
`call i1 @get$Q$$String(ptr @.str.17)`, where `@.str.17` is
`"STAGE2_BOOTSTRAP_TRACE"` from
`Adamas::Compiler::BootstrapEnv.get?("STAGE2_BOOTSTRAP_TRACE")`. A focused
s2->s3 trace showed the class-method resolver selects
`Adamas::Compiler::BootstrapEnv.get?$String`, but final emit collapses to bare
`get?$String`. Correction from a later focused trace: the earlier "blank after
splat packing" wording is stale because direct `full_method_name || ""` debug
strings are not reliable in this self-hosted nilable corridor. The later trace
showed source/path recognition, static lookup, and M3F path refine all preserve
the owner-qualified `Adamas::Compiler::BootstrapEnv.get?$String`; the owner is
lost only by the lower-call identity channel before/at final resolver
consumption. Refuted fixes: restoring a pre-pack snapshot did not change the
final emit; restoring directly from `splat_pack_full_method_name` made s2->s3
segfault during registration; broad source-`Path.method` recovery fixed the
outer emit but over-fired to `Frontend::ArrayLiteralNode.named...` stubs;
typed-entry-plus-lib fallback still fixed the outer emit but exposed a malformed
inner call while lowering `BootstrapEnv.get?`:
`lookup=Adamas::Compiler::BootstrapEnv.` with one `Pointer(UInt8)` argument.
Three newer local repair attempts are also refuted and reverted: pre-base
static-owner reconstruction caused repeated s2->s3 segfaults in
`register_function -> annotation_type_ref -> monomorphize_generic_class`; an
M3E lookup-only static-owner correction let patched s2 build but made repeated
s2->s3 runs segfault before/after lower_main; and a
`static_resolved_call_name` carrier, which preserved the selected static/path
resolver identity for `lookup_name`, fixed a cheap no-prelude
`BootstrapEnv.get?("X")` IR reducer but failed the real self-host falsifier.
The carrier-built s2 segfaulted while compiling `src/adamas.cr`, with lldb
stopping in `Array(TypeRef)#size -> Array(TypeRef)#equals? -> Module#intern_type
-> AstToHir#type_ref_for_name_inner -> register_concrete_class`. A follow-up
checkpoint probe pinned the owner collapse to the third method-name null guard:
generated s2 wrote `full_method_name=Adamas::Compiler::BootstrapEnv.get?$String`
at the PathNode refine entry and preserved it through the top-level checks, then
`method_name = "" unless v2_string_readable?(method_name)` corrupted the
neighboring local so `BASE_METHOD` read `full_method_name=get?`. Later hostile
rechecks showed that `v2_string_readable?` is not a sound produced-code
invariant: a standalone reducer compiled by stage1 emits valid `ptrtoint` /
`pointerof` loads and exits with valid pointer buckets, while generated s2 emits
`ret i64 0` for both raw String pointer extraction paths and lowers the large
high-address bound to `0`. Global `v2_string_readable? = true` is still refuted,
because the `BootstrapEnv.get?("X")` reducer then segfaults in
`String#single_byte_optimizable? -> String#index(Char, Int32) ->
strip_type_suffix_uncached`; other guard sites are protecting real invalid
strings. Unconditional third-guard removal fixed the cheap IR reducer but
exposed a later s2->s3 crash in
`String#bytesize -> String#ends_with?(Char) -> ensure_accessor_method`. Narrower
skip attempts using `static_class_name && full_method_name`, a carried
`path_static_refined` Bool, and a recomputed `PathNode` AST-shape Bool all
failed under generated s2: the cheap reducer still emitted the bare
`get$Q$$String` stub. A narrower lexical-short-name variant, which derived
MemberAccess short names from source and bypassed the third guard for static
calls by assigning `method_name = lexical_method_name`, also failed under
generated s2. Marking `v2_string_readable?` as `@[NoInline]` was refuted too.
An external callsite map carrier, keyed by `node.object_id`, fixed the
`BootstrapEnv.get?("X")` reducer under generated s2 but regressed the real
s2->s3 bootstrap gate: patched s2 segfaulted after `lower_main` in
`AstToHir#pack_splat_args_for_call -> lower_call`. These are
consumer/local-carrier/guard-shaped fixes and should not be repeated.
Evidence: `/tmp/adamas_static_snapshot_s2s3.log` retains bare
`CALL_EMIT ... emit=get?$String`; `/tmp/adamas_static_sourcepath_s2s3.log`
shows `CALL_EMIT ... emit=Adamas::Compiler::BootstrapEnv.get?$String` followed
by the malformed inner lookup and exit 139; `/tmp/adamas_static_pathbase_s2s3.log`
shows the broad fallback over-fire to the `ArrayLiteralNode.named` stub. Current
next root step: do not ship another consumer restore, broad `Path.method`
fallback, static-owner guard, local Bool/string carrier, or backend stub
forwarding for this frontier. Later explicit-return raw-pointer reducers
refuted the broad "produced-code raw pointer/int literal lowering is the next
root" wording: with explicit returns, stage1-built and generated-s2 binaries
both return valid non-null pointer buckets, and `v2_string_readable?` itself
uses explicit returns. The earlier raw-pointer reducer was not a faithful
next-root oracle. The active direction is the SDD
method-resolution/materialization identity ledger. A focused
`Exception::CallStack.skip("x")` no-prelude guard now pins the first bad layer
to HIR under generated s2: stage1 emits `call
Exception::CallStack.skip$String` plus a matching function body; generated s2
emits `Class Exception::`, a dummy `Type(36)` literal, `call skip$String`, and
no `Exception::CallStack.skip$String` body. The next discriminating probe is
class/nested-method registration and selected-call identity for that static
call, not raw-pointer lowering. Follow-up probes pinned the first bad
registration path: stage1 takes `register_class_with_name` through
`before_current` with current `AstArena` fit=1 and registers
`Exception::CallStack.skip$String`; generated s2 sees current `VirtualArena`
fit=0, the nested body member reads as generic `Node`, source repair returns
`repaired=0`, and fallback registers the same method as `Exception::.skip$String`.
An instrumented generated-s2 repair run showed the snippet itself is good:
source present, slice header `class CallStack`, leading name `CallStack`,
parse roots=1, reparsed arena present. The bad transition inside repair is
root fetch: `program.roots[0]` has `expr=1`, `null=0`, `invalid=0`,
`arena_size=2`, but `reparsed_arena.[]?(expr_id)` returns nil. A narrow
replacement of that one lookup with strict `reparsed_arena[expr_id]` was
refuted: patched stage1 passed the static-call guard and built fresh s2, but
patched generated s2 still emitted bare `skip$String` and no
`Exception::CallStack.skip$String` body. Next probe must name the producer below
that failed repair: reparsed `AstArena` root/slot storage, `TypedNode?`
materialization, or the outer `VirtualArena` body-node storage.
Two behavior attempts after this pin were refuted and reverted. Replacing
`resolve_class_name_for_definition`'s open-ended range split with explicit
`byte_slice` lengths partially moved generated-s2 HIR from `Class Exception::`
to `Class Exception::CallStack`, but did not fix the focused guard: the emitted
call stayed bare `skip$String` and no owner-qualified body was emitted. Adding
an exact typed PathNode target check before M3F path-refine fallback also left
generated-s2 HIR unchanged. These refute standalone class-name byte-slice and
late exact-target rebinding as sufficient fixes. The selected-name-to-BASE
identity channel is now fixed by a root producer-lifetime change, not by another
resolver carrier. A primitive generated-s2 trace showed
`full_method_name=Exception::CallStack.skip` survived through defaults and
prepack maps, then was corrupted exactly by
`_post_fmn_ok = full_method_name.nil? || full_method_name == method_name`: the
ordinary value-expression `||` narrowed `full_method_name` while lowering its
RHS equality and leaked that branch-local binding into later reads. Standalone
reducer `regression_tests/short_circuit_value_narrowing_leak.cr` reproduced the
same shape and crashed in `String#bytesize`; its LLVM showed the later
`full_method_name || "nil"` using the RHS-only narrowed slot. Fix:
`lower_short_circuit` now scopes RHS truthy/falsy narrowing with
`with_scoped_condition_narrowing`, matching the earlier condition-context fix.
Evidence: focused value reducer prints
`VALUE=Exception::CallStack.skip`, older
`short_circuit_condition_narrowing_leak.cr` still prints `RESULT=7`, fresh
generated s2 preserves `Exception::CallStack.skip$String` through BASE and HIR
emits `call Exception::CallStack.skip$String`, and
`regression_tests/run_all_suites.sh /tmp/adamas_value_narrow_fix_stage1 4`
passes 152/152 original + 36/36 combined. Residual frontier: generated-s2 HIR
still lacks the `func Exception::CallStack.skip$String` body, and the compiled
no-prelude binary aborts with
`STUB CALLED: Exception$CCCallStack$Dskip$$String`. Next probe:
nested static method body registration/materialization for the now-correct call
symbol. Do not return to owner-loss guards, `v2_string_readable?` tweaks,
raw-pointer lowering, exact-target rebinding, or local resolver carriers for
this slice.

[LM-S3B-SHORT-CIRCUIT-VALUE-NARROWING-LEAK|verified 2026-06-29 {F:0.88 G:0.52 R:0.91}]:
Value-expression short-circuit lowering had the same dominance-lifetime class
as the earlier condition-context leak, but outside
`lower_short_circuit_condition`. In `ok = full.nil? || full == method`, lowering
the RHS equality narrowed `full` to a non-nil binding that only dominates the
RHS branch. `lower_short_circuit` registered that narrowed binding in the
surrounding local environment, so a later `full || "nil"` read it on paths where
it was undefined; backend phi filtering then replaced the non-dominating
incoming with null. The focused compiler trace hit this in
`lower_call`'s post-print predicate for `Exception::CallStack.skip`, and the
standalone reducer crashed before the fix. Fix: wrap value short-circuit RHS
lowering in `with_scoped_condition_narrowing` for static and dynamic
`&&`/`||` paths, preserving genuine RHS reassignments via the existing
restore-if-current-id rule. Evidence: `crystal build src/adamas.cr -o
/tmp/adamas_value_narrow_fix_stage1 --error-trace`; value reducer exit 0 with
`VALUE=Exception::CallStack.skip`; existing condition reducer exit 0 with
`RESULT=7`; fresh fixed s2 preserves the owner-qualified static call through
BASE; full suites pass 152/152 + 36/36. Scope: this fixes narrowed-local leakage
from value short-circuit RHS lowering, not nested static body materialization.

[LM-S3B-LOWER-SUPER-IMPLICIT-ARGS-NO-SELF|verified 2026-06-29 {F:0.88 G:0.38 R:0.90}]:
Fresh `s2 -> s3` moved past `error: Index out of bounds` after
`pass3 after lower_main call`. The first bad boundary was HIR pending-demand
lowering, not MIR/LLVM. Existing `ADAMAS_TRACE_FLUSH_ENTER` showed
`flush_pending_functions -> lower_missing_call_targets` scanning
`Exception#backtrace?`; lldb then stopped on `__adamas_raise` with stack
`Array(HIR::Parameter)#[](Range(Int32, Nil)) -> AstToHir#lower_super ->
lower_method -> lower_function_if_needed_impl -> process_pending_lower_functions
-> lower_missing_call_targets -> flush_pending_functions`. Root: implicit
no-arg `super` / `previous_def` forwarding used `ctx.function.params[1..]`,
which assumes param 0 is always synthetic `self`. Class/static/top-level
wrapper functions may have no `self` and even no params, so slicing from index
1 raises `IndexError`. Fix slice: `current_method_forward_arg_ids` forwards all
current params but skips the first only when its HIR parameter name is exactly
`self`; both `lower_super` and `lower_previous_def` use it. Evidence:
`crystal build src/adamas.cr -o /tmp/adamas_super_forward_stage1 --error-trace`;
`regression_tests/class_method_noarg_super_forward_repro.sh
/tmp/adamas_try_noblock_stage1` is red with `Index out of bounds`;
`regression_tests/class_method_noarg_super_forward_repro.sh
/tmp/adamas_super_forward_stage1` and the same guard on
`/tmp/adamas_super_forward_s2` return `status=0`; fixed s2 builds
`/tmp/adamas_super_forward_s3` from `src/adamas.cr` with exit 0. Adjacent guard
`regression_tests/array_bool_join_module_super_repro.sh
/tmp/adamas_super_forward_stage1` remains green. Adversary caveat: this is a
compile-frontier fix, not a broad class-method-super runtime semantics fix;
fixed s2 compiles the small class-method-super reducer to a binary that prints
`0`, and generated s3 compiling `puts "hi"` aborts with
`STUB CALLED: get$Q$$String`. Residual frontier is therefore generated-s3
materialization of `get?`, not green s3/s3b.

[LM-S3B-INLINE-TRY-SCALAR-BLOCK-CALLBACK|verified 2026-06-29 {F:0.88 G:0.34 R:0.90}]:
The fresh `s2 -> s3` crash no longer stops in
`AstToHir#inline_try_with_block`. The first bad boundary was not `TypeRef`
parameter passing. Baseline `/tmp/adamas_537e13fc_s2` compiling the focused
`Exception#backtrace?` reducer crashed while lowering
`@callstack.try &.printable_backtrace`: lldb stopped in
`inline_try_with_block + 588` at `ldr x1, [x8]` with `x8 = 0`, because the
generated `inline_try_core` block callback path read closure cells that were
allocated only on the non-union `inline_try_without_nil` branch. Removing that
dead non-union callback moved the crash into `__crystal_block_proc_1871`, where
the callback treated scalar `ValueId` argument `4` as a pointer (`ldr w3, [x8]`,
address `0x4`). Fix slice: nilable `try` no longer sends the scalar
`ValueId` through a generated Crystal block callback; block and proc paths
inline the small nil/value/merge CFG separately and call
`inline_try_block_body` / `inline_try_proc_body` directly. Evidence:
`crystal build src/adamas.cr -o /tmp/adamas_try_noblock_stage1 --error-trace`;
`scripts/run_safe.sh /tmp/adamas_try_noblock_stage1 900 12288 src/adamas.cr -o
/tmp/adamas_try_noblock_s2`; focused guard
`regression_tests/stage2_inline_try_block_scalar_callback_repro.sh
/tmp/adamas_try_noblock_s2` returns `status=0`; the same guard is red on
baseline `/tmp/adamas_537e13fc_s2`; old full-prelude guard
`regression_tests/stage2_lower_field_get_full_prelude_frontier_repro.sh
/tmp/adamas_try_noblock_s2` remains green. Residual frontier: fixed
`/tmp/adamas_try_noblock_s2` compiling `src/adamas.cr` to s3 exits 1 with
`error: Index out of bounds` after `pass3 after lower_main call`, so s3 is not
green. Scope: this is a source-level avoidance of the generated block-callback
ABI for this scalar `ValueId` try-inline path, not a general closure-lowering
or `TypeRef` ABI fix.

[LM-S2S3-RANDOM-MACRO-FOR-KEYWORD-MEMBER|verified 2026-06-29 {F:0.88 G:0.44 R:0.90}]:
Fresh compiler `/tmp/adamas_random_rootfix` moves past the
`Random#rand_int(Int32)` undefined-extern frontier. Root was a parser
macro-body nesting bug plus include-order replay gap, not a backend stub or
Random-specific stdlib issue. In macro text, `range.begin` and `range.end`
tokenize as keyword tokens after dot; `parse_macro_body` previously treated
`begin` as a block opener and `end` as a block closer regardless of dot context.
For `src/stdlib/random.cr` this left `block_depth=1`, consumed the outer
`{% end %}`, reached EOF, and dropped the `MacroForNode` plus later module
members from the registered `Random` body. `Random::PCG32` had already included
early `Random` reopenings from `random/secure.cr` and `random/pcg32.cr`, so the
later main `Random` reopening also needed module macro-for include replay for
existing includers. Fix slice: ignore keyword block effects after dot while
scanning macro text, register included module `MacroForNode` expansions for
concrete classes, and replay module macro-for generated members to existing
includers when later module reopenings are registered. Evidence:
`crystal build src/adamas.cr -o /tmp/adamas_random_rootfix --error-trace`;
`regression_tests/macro_body_keyword_member_after_dot_repro.sh
/tmp/adamas_random_rootfix`;
`regression_tests/module_macro_for_include_private_helper_repro.sh
/tmp/adamas_random_rootfix`;
direct `Random.rand(10)` no longer emits `STUB CALLED: Random#rand_int`;
`regression_tests/stage2_lower_field_get_full_prelude_frontier_repro.sh
/tmp/adamas_random_rootfix` returns `status=0`; full suites pass 151/151
originals + 36/36 combined. Caveat: this verifies the materialization frontier
moved/cleared, not statistical correctness of Random output.

[LM-S2S3-NILABLE-FORWARD-NESTED-IVAR-CANONICALIZATION|verified 2026-06-29 {F:0.88 G:0.42 R:0.90}]:
Fresh s2 now moves past the old `Time::Format#initialize(String, Location?)`
nilable field-store crash. Root was a producer identity/order bug, not backend
ABI: `Time::Format` was registered before nested `Time::Location` was known, so
the ivar metadata for `@location : Location?` used stale `Nil | Location` while
the initializer parameter/value type was `Nil | Time::Location`. MIR then saw a
non-all-ref ghost union and lowered the field store as `memcpy(ptr %location)`,
crashing on the nil default. Fix slice: during final ivar layout,
`canonical_ivar_storage_type_ref` canonicalizes owner-scoped simple union
variants after all nested class names are known, turning stale `Nil | Inner`
into `Nil | Outer::Inner` for field storage. Evidence:
`regression_tests/nilable_forward_nested_class_ivar_repro.sh /tmp/adamas_tfmt_fix`
passes and static LLVM IR shows `store ptr %inner`; `Time.utc.to_s("%F")`
compiled by `/tmp/adamas_tfmt_fix` exits 0 and
`Time::Format#initialize` stores `ptr %location`; `/tmp/adamas_tfmt_fix` builds
fresh `/tmp/adamas_tfmt_s2`; `regression_tests/stage2_lower_field_get_full_prelude_frontier_repro.sh /tmp/adamas_tfmt_s2`
passes with moved frontier `random_rand_int_int32_stub`; full suites pass
151/151 originals + 36/36 combined. Superseded residual frontier:
`STUB CALLED: Random$Hrand_int$$Int32` under produced s2; see
`LM-S2S3-RANDOM-MACRO-FOR-KEYWORD-MEMBER`.

[LM-S2S3-LOWER-FIELD-GET-CONSUMER-SIDETABLE|verified 2026-06-28 {F:0.86 G:0.34 R:0.88}]:
The active full-prelude `puts "x"` s2 crash moved past
`HIRToMIRLowering#lower_field_get`. Fresh clean probes localized the first
crashing value to `String#bytesize` reading `@bytesize` (`FieldGet id=1`,
offset 4). The HIR producer path was correct in both stage1 and s2:
`lower_instance_var` constructed the `FieldGet` with `TypeRef::INT32` (`id=4`),
the constructor, `ctx.emit`, and `ctx.register_type` preserved `id=4`, and the
MIR side table `@hir_value_types[field.id]` still held `id=4` immediately before
the old crash. The bad boundary was the MIR consumer reading the inherited
`field.type` directly under s2. Fix slice: `lower_field_get` derives
`field_hir_type = @hir_value_types[field.id]? || field.type` and uses that value
for storage/layout/load decisions. A second adjacent s2-only crash in the same
consumer path came from using `Array#find` while matching MIR field descriptors;
that single compiler-critical lookup now uses an explicit indexed loop. This is
not a claim that language-level `Array#find` is fixed. Evidence:
`/tmp/adamas_fgclean_stage1` builds `/tmp/adamas_fgclean_s2` successfully;
fresh s2 compiling full-prelude `puts "x"` exits 134 at
`STUB CALLED: Time$CCLocation$Dlocal`, not 139 in `lower_field_get`;
`ptr_value_field_heap_struct_repro`, `struct_pointer_word_boundary_repro`,
`tuple_small_struct_element_inline_repro`, `p2_generated_stage2_no_prelude_puts_guard`,
and suites 151/151 + 36/36 pass. Guard:
`regression_tests/stage2_lower_field_get_full_prelude_frontier_repro.sh`.
Superseded residual frontier: materialization of `Time::Location.local`; the
later `Random#rand_int(Int32)` residual is now superseded by
`LM-S2S3-RANDOM-MACRO-FOR-KEYWORD-MEMBER`.

[LM-S2S3-ARCH-STOPRULE-CURRENT-BATCH|verified-boundary 2026-06-27 {F:0.84 G:0.62 R:0.88}]:
SUPERSEDED for the active crash by later landmarks, currently
`LM-S3B-INLINE-TRY-SCALAR-BLOCK-CALLBACK`; retained as the branch-level
architecture stop-rule and cleanup boundary.
Current `work/s3-range-slice-frontier` is not merge-ready. The previous broad
dirty batch was reduced before continuing: stale `ADAMAS_*_LEDGER` probes, an
unbacked `lower_field_get` Void guard, stale backend bootstrap rewrites, and a
misclassified `stage2_try_inline...` repro were removed instead of being carried
forward. The `BlockOwner` owner-metadata boundary remains load-bearing and must
not be reverted to `NamedTuple` or positional `Tuple`. Fresh stage1
`/tmp/adamas_cleaned_batch` builds, originals 151/151 + combined 36/36 pass,
and fresh s2 `/tmp/adamas_cleaned_batch_s2` builds. The bootstrap gate is still
red: generated s2 compiling minimal full-prelude `puts "x"` exits 139 after
`pass3 after lower_main call`; fresh lldb stops in
`Adamas::MIR::HIRToMIRLowering#lower_field_get(HIR::FieldGet) + 3448`
(`ldr w8, [x8]`, address `0x300000000`). The current frontier is therefore not
"parser fixed means s2 clean" and not "merge to main"; the next slice must
localize the HIR `FieldGet` producer/consumer boundary before any behavior
patch. Backend repair paths must be classified with `CodePathStatus` before
expansion or deletion. Spark scout should use GPT Codex Spark xHigh if/when
available; do not use Claude as scout on this project for now.

[LM-HIR-CASE-STRUCT-CONSTANT-VALUE-SEMANTICS|verified 2026-06-27 {F:0.86 G:0.46 R:0.88}]:
`case x; when StructConstant` now follows Crystal's `condition === subject`
semantics for non-primitive conditions instead of raw storage/pointer equality.
Baseline `d623f52f` compiles and runs the focused reducer but prints
`eq=true` / `case=miss`; fixed compiler prints `eq=true` / `case=hit`. Guard:
`regression_tests/struct_constant_case_equality_repro.sh`. Implementation keeps
raw `Eq` for primitive scalar same-type cases and routes non-primitive fallback
through `emit_binary_call(ctx, condition, "===", subject)`. Evidence:
`crystal build src/adamas.cr -o /tmp/adamas_cleaned_batch --error-trace`;
focused reducer passes; `regression_tests/run_all_suites.sh
/tmp/adamas_cleaned_batch 4` passes originals 151/151 + combined 36/36. Scope:
HIR case lowering only; it does not move the current `lower_field_get` s2
frontier.

[LM-S2S3-ESCAPED-INTERP-STRING-PARSER|verified 2026-06-27 {F:0.88 G:0.36 R:0.90}]:
Fresh s2 no longer truncates a class body when a string literal contains an
escaped interpolation opener such as `io << "\\\#{"`. Root was frontend
`lex_string`: the previous two-pass pre-scan/fast path missed the escape in
self-hosted execution, then treated the escaped `#{` as real interpolation and
scanned to EOF, swallowing following methods. Fix slice: `lex_string` now uses
one processed scanner for all string literals, sets interpolation only in that
scanner, and retains processed slices through `StringPool`; the parsed-class
debug oracle now avoids stage2-unsafe varargs and only walks members when
explicitly requested. Evidence: `crystal build src/adamas.cr -o
/tmp/adamas_frontend_slice --error-trace` succeeds;
`regression_tests/stage2_escaped_interpolation_string_parser_repro.sh
/tmp/adamas_frontend_slice` passes; fresh s2 built with `scripts/run_safe.sh
/tmp/adamas_frontend_slice 900 12288 src/adamas.cr -o
/tmp/adamas_frontend_slice_s2` exits 0; the same regression passes under
`/tmp/adamas_frontend_slice_s2`. Scope: parser/frontend self-application only;
it does not clear the current `lower_field_get` bootstrap frontier.

[LM-S2S3-LOWER-FIELD-GET-PUTS-X-FRONTIER|verified-boundary 2026-06-27 {F:0.80 G:0.30 R:0.86}]:
SUPERSEDED by `LM-S2S3-LOWER-FIELD-GET-CONSUMER-SIDETABLE`; retained as the
red baseline for the moved frontier.
After the escaped-interpolation frontend fix, generated s2 still cannot compile
minimal full-prelude `puts "x"`. `scripts/run_safe.sh
/tmp/adamas_frontend_slice_s2 120 2048 /tmp/adamas_puts_x.cr -o
/tmp/adamas_puts_x_frontend_slice` exits 139 after `pass3 after lower_main
call`. Fresh lldb on the same compiler/input stops at
`Adamas::MIR::HIRToMIRLowering#lower_field_get(HIR::FieldGet) + 3480`
(`ldr w8, [x8]`, address `0x300000000`), called from `lower_value`,
`lower_block`, `lower_function_body`, and `lower_all_bodies`. This was the
then-current red boundary. Do not continue from the older `IO#<<` runtime
recursion row without re-observing it; if a FieldGet crash returns, first
localize the exact HIR FieldGet producer, field metadata, and stage1-vs-s2
divergence.

[LM-S2S3-STATE-SCOPE-LEDGER-IO-SHIFT|stale-boundary 2026-06-27 {F:0.84 G:0.30 R:0.55}]:
STALE after `LM-S2S3-ESCAPED-INTERP-STRING-PARSER`; reverify before using as
the active frontier.
Default-off `ADAMAS_STATE_SCOPE_LEDGER` was added as the Slice-0
StateScope/materialization identity ledger. Fresh stage1 and fresh s2 builds
both succeed with the ledger compiled in but disabled by default. With the
ledger enabled for `IO#<<,String#to_s,Reference#to_s` on minimal full-prelude
`puts "x"`, stage1 emits the expected body edge:
`IO#<<$String -> String#to_s$IO`, and materializes `String#to_s$IO`.
Fresh s2 materializes `IO#<<$String` itself under the correct requested/target
symbol with `call_arg_types=String`, but the body edge diverges:
`IO#<<$String -> Reference#to_s$IO`, with `selected_target=-` /
`selected_def=-`. Existing `DEBUG_PARAM_TYPES` narrows the producer boundary:
stage1 lowers `IO#<<$String param=obj` as `String(id=15)`, while fresh s2 lowers
the same parameter as `Unknown(id=15)`. The produced binary still exits 138
(Bus error). This reclassifies the active `puts "x"` frontier away from a
materialized-symbol-vs-call-symbol body mismatch and toward TypeRef descriptor
loss during method-parameter registration/lowering in s2. Do not patch `IO#<<`
locally or add a backend rescue; this row should not drive the next slice unless
the same runtime recursion is re-observed on the current tree.

[LM-S2S3-TYPEREF-NEW-CASE-IDENTITY|stale-boundary 2026-06-27 {F:0.88 G:0.25 R:0.55}]:
STALE after `LM-S2S3-ESCAPED-INTERP-STRING-PARSER`; reverify before using as
the active frontier.
Default-off `ADAMAS_TYPEREF_ID_LEDGER` refined the active `puts "x"` frontier
below descriptor lookup. In stage1, `IO#<<$String param=obj` has
`id=15`, `string_id=15`, `eq_string=1`, `case_string=1`, and
`clone_case_string=1` both before and after parameter registration. In fresh
s2, the incoming callsite type is still case-matchable
(`call id=15`, `case_string=1`, `name=String`), but reconstructing the same id
with `TypeRef.new(15)` yields `clone_case_string=0`. The untyped-parameter
path uses `type_ref_array_fetch_or_void`, which reconstructs call types through
`TypeRef.new(type_ref_array_id_or_void(...))`; the selected parameter is
therefore `== TypeRef::STRING` and `id == TypeRef::STRING.id`, but
`case selected when TypeRef::STRING` fails and `get_type_name_from_ref` returns
`Unknown`. The s2-produced `puts "x"` binary still exits 138. This refutes the
descriptor-loss framing for this boundary and points at primitive `TypeRef`
case/`===` identity for constructed values under self-hosting. Do not patch
`IO#<<`, do not add backend rescue, and do not change descriptor registry for
this symptom without a lower falsifier if it reappears.

[LM-S3B-BLOCK-SHORTHAND-ARRAY-INDEX-DISPATCH|verified 2026-06-27 {F:0.88 G:0.50 R:0.88}]:
Generated s2 no longer crashes in `Range#begin` while compiling
`AstToHir#try_unify_tuple_variant_names`. Root was CallNode overload dispatch:
the parser expands block shorthand `&.[idx]` into `__arg0.[](idx)`, so
`parsed.map(&.[i])` bypassed IndexNode lowering. Trace showed the argument type
was already `Int32`, but the CallNode resolver selected
`Array(String)#[](Range)` and passed the integer index as a Range pointer. Fix:
for `Array`/`StaticArray` receivers in `lower_call`, `[]`, one argument, and an
argument that is not Range by AST or TypeRef, emit the same `IndexGet` element
access used by IndexNode lowering. Evidence:
`regression_tests/block_shorthand_array_index_repro.sh
/tmp/adamas_array_shorthand_fix` passes; Range materialization and prior
UnionWrap ARC guards pass; originals 151/151 + combined 36/36 pass; fixed
stage1 builds `/tmp/adamas_array_shorthand_s2`.

[LM-S3B-SORT-CMP-PROC-CARRIER|verified 2026-06-27 {F:0.88 G:0.42 R:0.88}]:
After `LM-S3B-BLOCK-SHORTHAND-ARRAY-INDEX-DISPATCH`, fresh s2 no longer fails
the s3 build in `Slice(UInt8).cmp(Tuple(String, Int32), Tuple(String, Int32),
Proc)` called from `Slice(Tuple(String, Int32)).merge_sort!` /
`Array(Tuple(String, Int32))#sort!`. Root had two parts. First, block-suffix
calls double-wrapped block carriers: `Array#sort!(&block)` materialized a Proc
object and passed it to `Slice#sort!(&block)`, which wrapped it again; the final
comparator loaded a Proc object pointer as if it were a function pointer. Fix:
forward raw callbacks to callee block parameters and reserve Proc
materialization for ordinary `Proc` / `Proc?` parameters. Second, the
comparator's bare `Proc` parameter erased its return shape, so
`block.call(v1, v2)` lowered as `void` and `cmp` returned zero for every pair.
This slice recovers the stdlib `Slice(UInt8).cmp` comparator return contract as
`Int32`; it is not a global erased-Proc return inference fix. Evidence:
`regression_tests/sort_by_tuple_key_runtime_repro.sh
/tmp/adamas_block_proc_cmp_fix` passes with output `1,2,3`; block-shorthand
Array index, stage2 Range materialization, and ARC UnionWrap guards pass;
originals 151/151 + combined 36/36 pass; static LLVM IR shows raw `%block`
forwarding to `Slice#sort!$block`, exactly one Proc materialization before
`merge_sort!`, and `Slice(UInt8).cmp(..., Proc)` calling and returning `i32`.

[LM-S3B-INLINE-TRY-BLOCK-FRONTIER|verified-boundary 2026-06-27 {F:0.72 G:0.30 R:0.78}]:
After `LM-S3B-SORT-CMP-PROC-CARRIER`, fixed stage1 builds
`/tmp/adamas_block_proc_s2`, and that s2 gets past the previous sort/comparator
crash. The next s2->s3 frontier is separate: `scripts/run_safe.sh
/tmp/adamas_block_proc_s2 900 12288 src/adamas.cr -o /tmp/adamas_block_proc_s3`
exits 139 after `pass3 after lower_main call`; lldb stops in
`Adamas::HIR::AstToHir#inline_try_with_block` from `lower_call` during
`process_pending_lower_functions`. A falsifier run with
`ADAMAS_DISABLE_TRY_INLINE=1` changes the failure to `STUB CALLED:
Adamas::HIR::AstToHir::class_name:String#empty?`, so `inline_try_with_block` is
a verified boundary but not yet a verified root. Do not fold this frontier back
into sort/Proc carrier or Array Range slicing.

[LM-S2B-ENUM-MEMBER-GENERIC-INFERENCE|verified 2026-06-27 {F:0.89 G:0.55 R:0.88}]:
Generated s2b no longer crashes the no-prelude smoke in
`Adamas::HIR::EscapeAnalyzer#build_summary` after `lower_main`. Root was
producer-side generic type inference: `Array.new(param_count,
LifetimeTag::StackLocal)` inferred `Array(LifetimeTag::StackLocal)`, a singleton
enum-member owner, instead of `Array(LifetimeTag)`. The generated
`Array(LifetimeTag::StackLocal).new(Int32, LifetimeTag)` constructor called an
initializer body that accepted only `self`, zeroed size/capacity, and left
`@buffer = null`; `build_summary` then wrote into that null buffer. Fix:
`infer_type_name_from_node(PathNode)` canonicalizes registered enum member paths
to the declaring enum before generic constructor inference. Evidence:
`regression_tests/enum_member_array_new_repro.sh bin/adamas` passes; originals
151/151 + combined 36/36 pass; ASAN bootstrap
`/tmp/adamas_bootstrap_enum_owner_fix` builds s2 and both s2 smokes pass; static
IR shows `EscapeSummary#initialize` now calls `Array(LifetimeTag).new(Int32,
LifetimeTag)`.

[LM-S3B-EXPRID-INVALID-STRUCT-ABI-FRONTIER|verified-boundary 2026-06-27 {F:0.78 G:0.42 R:0.82}]:
After the enum-member inference fix, ASAN `--stages 3` bootstrap advances past
s2: stage1 and stage2 builds succeed and both s2 smokes pass. The first s3
frontier is a build crash during module registration (`idx=151/268`) in
`Adamas::Compiler::Frontend::ExprId#invalid?`. `ExprId` is a 4-byte struct
(`{Int32}`), but generated s2 emits `invalid?` as `define i1 ... (ptr %self)`;
the crashing receiver is `0x000c00001102`, a non-null scalar-looking value.
This is a next-slice by-value struct-call/receiver representation frontier, not
an `EscapeSummary`/filled-array regression. Do not widen the `invalid?` null
guard; localize the call producer or struct ABI boundary first.

[LM-S2B-FILLED-ARRAY-FASTPATH-OVERREACH|verified 2026-06-26 {F:0.88 G:0.45 R:0.86}]:
Produced s2b no longer hits the ASAN heap-buffer-overflow in
`Array(Adamas::HIR::TypeRef)#dup` caused by `Array.new(size, value)` routing
pointer-valued arrays through `__adamas_array_new_filled_i32`. The i32 helper
hardcodes 4-byte stride and `Array(Int32)` runtime id; a pointer-valued
`Array(String).new(2, "x")` standalone reducer allocated only 8 bytes for two
elements and `dup` copied 16 bytes. Fix: the HIR fast-path now uses filled-array
helpers only for their exact supported element types (`Bool`, `Int32`) and lets
all other element types lower through the normal `Array(T).new` path. Evidence:
ASAN reducer `regression_tests/array_filled_pointer_value_dup_repro.sh
bin/adamas` passes; focused Bool/Int32/String filled-array smoke passes;
originals 151/151 + combined 36/36 pass; ASAN bootstrap builds s2 and advances
past the old `Array(TypeRef)#dup` heap overflow. Next frontier is separate:
stage2 smoke now null-derefs in
`Hash(Adamas::Compiler::Semantic::DefIdentity, Int32).new(Int32, Nil)`.

[LM-S2B-HASH-DEFAULT-PROVIDER-FRONTIER|verified-boundary 2026-06-26 {F:0.82 G:0.55 R:0.78}]:
Current post-filled-array stage2 smoke frontier is in the Hash default provider
path, not in source reads or `Array#dup`. The s2 no-prelude smoke crashes in
`Hash(Adamas::Compiler::Semantic::DefIdentity, Int32).new(Int32, Nil)` while
constructing `AstToHir`. A standalone stage1-compiled reducer shows the family:
`Hash(String, Int32).new(0)` and `Hash(String, Int32).new { 0 }` abort on a
missing-key lookup, but `Hash(String, Int32).new(initial_capacity: 0)` works.
IR boundary: `Hash(String, Int32).new$Proc_Nil` calls
`Hash#initialize$Proc_Nil` with no args, so `@block` remains nil. A rejected
named-only allocator lookup probe made the initializer receive and store the
block, but `Hash#[]` then jumped through a raw `__crystal_block_proc_N` pointer
because `@block : Proc?` expects a heap Proc object. Do not patch the
`@phase0_body_infer_counts` field or `Hash#[]`; next fix must address
initializer/default-arg forwarding together with block-to-Proc materialization.

[LM-S2B-FULL-PRELUDE-DIRNAME|verified 2026-06-25 {F:0.82 G:0.45 R:0.85}]:
Produced s2b's full-prelude `puts 42` corridor no longer dies in the
`indexable.cr` wildcard require path. Probe showed `safe_dirname(abs_path)` for
`src/stdlib/indexable.cr` returned `.../src/stdlib/indexable.` because
self-hosted `String#rindex('/')` returned the final `.cr` byte position, not the
last slash. The malformed base dir made `resolve_wildcard_require("./indexable/*")`
look in `indexable./indexable`, return nil, and fall into the stage2-broken
`Dir.glob` source fallback (`error: Unreachable`). Fix: CLI path helpers use a
manual byte reverse separator scan. Evidence: old s2b fails
`regression_tests/stage2_full_prelude_wildcard_require_repro.sh` on
`Unreachable`; fixed s2b resolves `./indexable/*` to
`src/stdlib/indexable/mutable.cr`. Next frontier is separate:
`STUB CALLED: Adamas::HIR::AstToHir#yield_return_function_for_block_call?...`
during `lower_main`.

[LM-S2B-YIELD-BLOCK-CALL-MATERIALIZATION|verified 2026-06-26 {F:0.82 G:0.40 R:0.82}]:
Produced s2b's full-prelude `puts 42` corridor no longer aborts on the
`AstToHir#yield_return_function_for_block_call?` undefined-extern stub. Source
registration had the concrete `mangled_name : String` overload, but self-hosted
materialization demanded the `mangled_name : String?` wrapper form and could not
find a DefNode. Fix: add an explicit nilable overload that returns false for nil
and delegates to the concrete overload otherwise. Evidence: the old post-dirname
s2b fails `stage2_yield_return_block_call_materialization_repro.sh` on the exact
stub; the fixed s2b passes that guard and moves to the separate
`AstToHir#lower_block_to_proc(...)` stub frontier.

[LM-S2B-LOWER-BLOCK-TO-PROC-MATERIALIZATION|verified 2026-06-26 {F:0.83 G:0.42 R:0.84}]:
Produced s2b's full-prelude `puts 42` corridor no longer aborts on the
`AstToHir#lower_block_to_proc` undefined-extern stub. The registered helper def
was visible in the overload index, but resolver rejected it because self-hosted
callsite inference widened `block_arena_for_proc` from the declared
`Frontend::ArenaLike` contract to `Nil | ArenaLike | String` / pointer-erased
forms. Fix: explicitly type the three local `block_arena_for_proc` bindings as
`Adamas::Compiler::Frontend::ArenaLike`, preserving the existing arena-selection
expression while restoring the helper's materialization signature. Evidence:
old post-yield s2b fails
`regression_tests/stage2_lower_block_to_proc_materialization_repro.sh` on the
exact stub; fixed s2b passes it, contains no `STUB CALLED` string for
`lower_block_to_proc`, keeps the yield-return guard green, and compiles/runs
no-prelude `x = 1`; stage1 suites pass 149/149 + 36/36. Next frontier is later
MIR lowering, not block/proc materialization: full-prelude `puts 42` crashes in
`HIRToMIRLowering#set_block_map` via `mir_block_for` ->
`resolve_pending_phis` -> `lower_function_body`.

[LM-S3B-ARRAY-SORT-RUNTIME-TYPE-ID|verified 2026-06-26 {F:0.86 G:0.50 R:0.86}]:
Produced s3b's nested macro wildcard require path no longer loses the resolved
`Array(String)` in the source fallback. Root was not macro scanning, wildcard
resolution, or `case when Array` selection by itself. `files.sort` lowered
through `__adamas_sort_string_array_dup` with the raw HIR `Array(String)`
TypeRef id as the new object's header (`161` in the repro), while other Array
allocation paths and all-ref union type checks used the MIR/runtime id (`181`).
The sorted array therefore failed `String | Array(String) | Nil` dispatch and
the fallback dropped the required file. Fix: when HIR bakes the runtime header
literal for the sort dup helper, translate via `MIR::TypeRef.from_hir(arr_type)`.
Evidence: `array_sort_runtime_type_id_repro.sh` red->green (`181 -> 181`,
`CASE=Array`); small LLVM oracle emits
`@__adamas_sort_string_array_dup(..., i32 181)`; produced compiler parses
`/tmp/adamas_parser_tail_probe/macro_nested_event_tail.cr` and loads
`macro_reqs/loaded.cr` (`Files: 262`); suites pass 149/149 + 36/36. Residual
risk: other HIR code paths that bake runtime object headers from raw
`TypeRef.id` remain candidates and should be audited before generalizing.

[LM-M4i0|verified]: Fresh RELEASE stage1 SIGSEGV'd in the recursive-descent parser
(`parse_block_body_with_optional_rescue`) while building s2b. Root: `crystal build`
links with the bundled `ld64.lld`, which IGNORES `-Wl,-stack_size` ("not yet
implemented" warning), so stage1 got the default 8MB macOS main-thread stack (LC_MAIN
stacksize 0) and overflowed parsing the large self-hosted source; release frames are
bigger than debug, so only release crashed, and the older stable `bin/adamas` predated
the source growth. Proof: bare `clang -Wl,-stack_size,0x10000000` via the SYSTEM
`/usr/bin/ld` sets LC_MAIN stacksize, but `crystal build --link-flags=-Wl,-stack_size`
-> ld64.lld -> stacksize 0; adding `-fuse-ld=/usr/bin/ld` -> 64MB. Fix (build contract,
`scripts/build_stage1_original_cached.sh`, Darwin): force
`--link-flags="-fuse-ld=/usr/bin/ld -Wl,-stack_size,0x4000000"`. Binaries this compiler
later produces already use `clang -> system ld` via cli.cr, so s2b/s3b inherit the 64MB
stack; only the `crystal build` step needed the override. Verified: recipe s1b
`otool -l | grep LC_MAIN` stacksize=64MB; release s1b builds s2b (S2B_EXIT=0); combined
31/31. (M4h2 release s2b then advanced past the union_all_reference_types? crash to a new
`lower_main`/`set_synthetic_main_definition_location` blocker — M4i1.)

[LM-M4i1b|verified]: The compiler-internal nested namespace invariant — `MIR::X` / `HIR::X`
inside the Adamas compiler must resolve to ONE identity, the FQ `Adamas::MIR::X` /
`Adamas::HIR::X`. The type-name resolver's anchored short-circuit minted a distinct SHORT
"ghost" identity whose methods are never materialized; this is the root of the whole M4h/M4i
family (M4h0 union value confusion; M4i1 `STUB CALLED: HIR::Function#definition_location=`).
Fix (`2b95eae2`): `registered_compiler_nested_type_alias` canonicalizes any MIR/HIR head whose
`Adamas::<name>` is already registered (`type_name_exists?` guard — never invents a name, never
rewrites Crystal:: or a user program's own top-level MIR/HIR). Earlier narrowing was reverted:
its justification ("broad destabilizes release") was the pre-existing parser stack overflow
fixed by LM-M4i0, not canonicalization. Verified: 474 canon / 60 unique / HIR::Function 32x /
adversary 0 non-MIR-HIR; combined 31/31; release s2b on `puts 1` stops aborting on the ghost
setter and advances into lowering the actual call. NEW frontier M4i2: NULL-pointer deref in
`lower_call` (`ldr x8,[x8]`, x8=0x0) lowering `puts 1` — a null struct-field/ExprId in the
program-lowering path, classified separately.

[LM-S2B-TWOHEAP-FIX-D|verified 2026-06-18 {F:0.85 G:0.7 R:0.85}]: The #1 s2b startup crash is
FIXED by D (scoped family-consistent allocator redirect), branch `s2b-twoheap-gc-fix-D`, 7 edits
all in `src/compiler/mir/llvm_backend.cr` (NO stdlib). Atomic byte-buffer family moved off Boehm:
`GC.malloc_atomic`→`__adamas_malloc64` (libc calloc), `GC.realloc`→`__adamas_gc_aware_realloc`
(GC_base-aware: Boehm blocks via GC_realloc, libc via libc realloc); scanned `GC.malloc` (GMP,
EventLoop arena) left on Boehm. The wrapper is emitted at the module epilogue ONLY when a reachable
`ExternCall "GC_realloc"` exists (`gc_aware_realloc_needed?`) — same condition that links libgc, so
its `@GC_base`/`@GC_realloc` resolve (fixes a self-introduced `Undefined symbols: _GC_base,_GC_realloc`
link bug on GC-free programs). EVIDENCE: baseline `/tmp/s2b_clean` SIGSEGVs on `x=1`; `/tmp/s2b_gated`
compiles `x=1` exit 0 ~1s, output links (88752 B, no undefined GC syms) + runs clean; suite 160/160 +
31/31; repro `regression_tests/gc_aware_realloc_gating_repro.sh` rc=0. SUPERSEDES the in_progress
owner-paradox / repr-flip framings below (those localized WHERE byte_at read freed memory; the
watchpoint-proven WHO was Boehm collecting a live libc-anchored String). NEXT: E = ARC-owned String.

[LM-S2B-STARTUP-OWNER|superseded 2026-06-17→resolved-by-D 2026-06-18]: The #1 s2b startup crash (byte_at SIGSEGV
when the stage2 binary compiles even `x=1`) is a DETERMINISTIC MISCOMPILE in s2b's own
generated code, NOT runtime memory corruption. Decisive observable (deterministic
`/tmp/s2b_dbg2`, baked env probes, zero crash-rate dependence): for the entry call
`Crystal.main(argc,argv){...}` inside fn `main$Int32_Pointer(Pointer(UInt8))`, s2b emits
owner `Int32#main$...` (instance, sep `#`) where the reference emits `Crystal.main$...`
(static, sep `.`). The bogus `Int32` owner == arg_types[0] (argc:Int32) i.e. the call
degrades to an instance call whose owner is the receiver's type. Cascade: corrupt owner →
bogus `Int32#new$Array(String)_IO::FileDescriptor` queued → lowering reads garbage
`type_annotation` → `String#byte_at` SIGSEGV (corridor:
byte_at←strip_ascii_edge_whitespace←type_ref_for_name←prefer_callsite_specialization
(param.type_annotation)←lower_missing_call_targets).
REFUTED this session:
  (a) `UInt32?#nil?`/`ValueId?` "zombie-nil" UNIVERSAL miscompile — `/tmp/nilable_uint32_nil_repro.cr`
      compiled by stage1 is CLEAN for all 4 cases (nil→nil?=true; 0_u32→nil?=false). So `.nil?` on
      `UInt32?` is not broken in general; the earlier "receiver_id=0 vs recv_type=nil" divergence
      conflated two different program points (BASE_METHOD@~74135 vs CALL_EMIT@~78480), not one slot.
  (b) String↔Slice repr-flip on the receiver name — s2b reads `name=Crystal` CLEAN (probe
      `[CRYSTAL_RECV]`), not garbage. The owner "Int32" is a clean valid type, not source bytes.
CONFIRMED divergence (probe `[CRYSTAL_RECV]` at ast_to_hir.cr lower_call, method=="main",
gated DEBUG_CRYSTAL_RECV=1): reference `obj_kind=Identifier name=Crystal cns=Crystal
mod_like=true is_mod_m=true module_defs=true` vs s2b `obj_kind=(empty) name=Crystal
cns=Crystal mod_like=true is_mod_m=FALSE module_defs=true`. Two s2b anomalies: (1)
`obj_kind.to_s` renders EMPTY but the enum VALUE is still Identifier (since `cns=Crystal`
got set via the Identifier branch) → a cosmetic Enum#to_s miscompile, not causal. (2)
`is_module_method?("Crystal","main")` = `@function_types.has_key?("Crystal.main")||has_function_base?`
returns FALSE in s2b, TRUE in reference — a String-keyed registry-lookup divergence.
OPEN PARADOX (owner side, NOW DEMOTED — see lldb session below): s2b has `class_name_str="Crystal"`
at the probe (line ~71646), and the intervening fallbacks (71671-71825) only SET class_name_str when
nil — so the `if class_name_str` block at ~72038 SHOULD run
`full_method_name = resolve_class_method_with_inheritance("Crystal","main") || "Crystal.main"`. Yet
BASE_METHOD@~74135 showed bare `full_method_name=main`. Staged trace probes A/B/C/D (CR_A_blockend@72105,
CR_B_pre_m3f@~73963, CR_C_pre_instref@~74010, CR_D_post_instref@~74043, gated DEBUG_CRYSTAL_RECV &&
method=="main") to localize the reset — NOT YET REBUILT/RUN.

=== 2026-06-17 lldb session on /tmp/s2b_dbg2 (DETERMINISTIC, 100% crash even under lldb) ===
The byte_at SIGSEGV crash is RECLASSIFIED as a `type_annotation` String↔Slice REPR-FLIP that is
*independent of* the Crystal.main owner paradox (HYP-B favored over HYP-A). Evidence:
  * Deterministic backtrace: byte_at ← strip_ascii_edge_whitespace ← type_ref_for_name(_inner)
    ← prefer_callsite_specialization(param_type) ← lower_function_if_needed_impl
    ← process_pending_lower_functions ← lower_missing_call_targets ← flush_pending_functions ← CLI#compile.
  * The corrupt `param_type` at the crash decodes to ORDINARY STDLIB SOURCE text, not the bogus
    Int32#main target: heads = "reverse : Array(", "map_with_index!(", "compact! : self",
    "address.to_u64!", "atomicrmw(:mi", "days[month", "...value), ordering)". So the def whose params
    are corrupt is a legit stdlib method, NOT the owner-misresolved Int32#new$Array(String)_IO::FileDescriptor.
  * PRODUCER/CONSUMER SPLIT (the key new fact): all three DefParamInfo construction sites are probed
    (build_param_infos_from_params.type+.readback @36036/36046; build_param_infos.type+.readback
    @36069/36079; nested_producer.ta_source+.readback @24908/24918) and fired ZERO BADSTR. The
    CONSUMERS fired 39 (build_param_stats_from_infos.type @36164) + the crash one
    (prefer_callsite_specialization.param_type @36614). So `type_annotation` is a VALID independent
    heap String at construction and CORRUPT when the SAME cached array is re-read later.
    `safe_slice_to_string` ends in `String.new(slice)` (ast_to_hir.cr:12227) = a real byte COPY, so
    production cannot be a zero-copy view — confirms post-production corruption.
  * FIELDCORR probe (@36161, within build_param_stats_from_infos): within the corrupt struct, field0
    `name` is VALID (nm_bs=5/6), field2 `type_annotation` is the source pointer, `external_name` nil;
    `same=true` (block-var == params[idx], i.e. STORED corruption not an iteration-copy flip). Affects
    even SIZE-1 arrays (idx=0/1) → RULES OUT append-realloc/struct-copy-on-grow as the cause. So an
    external write stomps field2 (offset 16) of stored DefParamInfo structs with a Slice-into-source
    value, between production and consumption; field0 untouched.
  * Heap addresses are NON-deterministic run-to-run (arr≈39e9 run1 vs ≈51e9 run3) although the
    miscompile/bt is deterministic → pre-set lldb watchpoints from a prior run's address are INFEASIBLE;
    the baked probes + deterministic bt are the working trace channel. `frame variable` yields nothing
    (binary lacks local-var DWARF), so base_method_name must come from an in-code probe, not lldb.
NEXT: (1) add a probe in prefer_callsite_specialization printing base_method_name/resolved_name on bad
param_type to NAIL HYP-B (legit stdlib def). (2) Localize the WRITER: a phase-boundary validation sweep
re-checking cached @function_param_infos_by_def_id type_annotations to find the first window where a
valid field flips to a source pointer (watchpoints infeasible). (3) Owner paradox is a SEPARATE,
likely non-crashing issue — keep A/B/C/D for it but do not let it block the repr-flip fix.
=== 2026-06-17 confirmation run (s2b_dbg3, full re-instrumented) — HYP-S CONFIRMED ===
Re-ran the producer probes (RESCAN added to build_param_infos + build_param_infos_from_params) and
consumer probes: 39× `build_param_stats_from_infos.type` BADSTR + 1 crash, ZERO producer/readback/RESCAN
BADSTR. All 39 fire DURING `lower_main` (between "lower_main: exprs=12" and "pass3 after lower_main").
Crucially the SAME `build_param_stats_from_infos` runs at pass2 prime-time (`prime_param_caches_for_registered_def`)
with 0 BADSTR ⇒ the field2 stomp happens strictly BETWEEN pass2 register and pass3 lower_main consumption.
HYP-S (post-construction stomp of stored field2) is now the active root, superseding any "producer
repr-flip" framing. Bisection in flight: `scan_param_caches_for_corruption(label)` CACHESCAN added to
cli.cr at after_register_functions / before+after fixup_inherited_ivars / before_lower_main; built into
/tmp/s2b_dbg4. Window suspects: fixup_inherited_ivars internals + lower_main deferred classvar/const init.
CAUTION-tier fix (do not commit until mechanism pinned; remove all probes first). Reducers:
/tmp/nilable_uint32_nil_repro.cr (refuter). Memory: [[s2b-startup-crash-rc-overfree-refuted]].

=== 2026-06-17 ROOT CAUSE FOUND (lldb hardware watchpoint + code audit) — TWO-HEAP GC HAZARD ===
The "post-construction field2 stomp" (HYP-S) is RECLASSIFIED: the writer is the Boehm GC recycling a
live String. This is mechanism-level proof and SUPERSEDES the rate-based "GC-UAF refuted 3×" /
"GC_DONT_GC=clean is layout-masking" notes (those refuted GC *aggressiveness*; the real defect is a
GC-reachability gap, which they never tested).
EVIDENCE:
  * lldb scripted hardware WRITE watchpoint (/tmp/wp_trace.py) on the live normalized "Int" String
    (held by @normalize_decl_cache : Hash(String,String)) fired in `GC_build_fl` (libgc free-list
    builder) ← GC_generic_malloc_many ← GC_malloc_kind ← GC_realloc ← GC$Drealloc ←
    String$CCBuilder$Hresize_to_capacity (during register_class → mangle_type_param_suffix). I.e. the
    GC threads the STILL-REFERENCED String's exact block onto a free list, then a later
    String::Builder realloc recycles it and overwrites it with source text → the cached String becomes
    a header-less pointer-into-source → byte_at SIGSEGV at the later cache HIT.
  * GC_DONT_GC=1: watchpoint does NOT fire, program exits cleanly (status 1, no crash). Collection is
    necessary AND sufficient for the bug (mechanism, not crash-rate).
WHY THE GC MISSES THE REFERENCE (code audit, llvm_backend.cr):
  * `Pointer(T).malloc` → MIR `lower_pointer_malloc` (hir_to_mir.cr:7622) → `__adamas_malloc64`
    (llvm_backend.cr:6540) → loads `@__adamas_calloc_fn` which is `global ptr @calloc` (libc), NEVER
    repatched to GC anywhere (grep: only def+use sites). So Array/Hash entry buffers live in the LIBC
    heap.
  * stdlib `String`/`String::Builder` allocate via `GC.malloc`/`GC.realloc` (no compiler override) →
    REAL Boehm `GC_malloc`/`GC_realloc` (backtrace-confirmed). So Strings live in the BOEHM GC heap.
  * Boehm traces roots + its own heap only; it does NOT scan interior pointers of a libc-malloc'd
    region (GC_base()==NULL there). A chain GC-object → libc Hash @entries buffer → GC String breaks at
    the libc buffer ⇒ the String value is unreachable to the GC ⇒ collected while still logically live.
  This is a TWO-HEAP cross-reference hazard, not a GC-model deficiency: a non-GC (libc) container buffer
  holds the only reference to a GC-allocated String.
WHY NON-DETERMINISTIC / layout-sensitive: depends on whether a collection runs between the value's last
GC-visible reference dying (producing stack frame returns) and the cache HIT, plus whether other
GC-scanned locations transiently hold the same String. Fully reconciles ASLR sensitivity + "crash rate
is an invalid metric" + the field0-valid/field2-flipped pattern (field2 String value collected; field0
name still referenced elsewhere).
FIX is genuinely owner's call — every viable fix touches the GC/allocator boundary the owner gated
("never expand GC use / change the GC model"): (A) original-Crystal-faithful: `Pointer(T).malloc`
chooses GC_malloc when T has inner pointers (scanning) vs libc/atomic when pointer-free — correct &
general but needs the matching realloc routed to GC_realloc for those buffers (broader); (B) enforce
leak-to-exit by disabling Boehm collection at startup (GC_disable/GC_set_dont_gc) — minimal, matches the
documented "GC=leak-to-exit" intent, raises peak memory (compiler is short-lived); (C) register the
libc container heap as GC roots — fragile. CONSULTING OWNER before implementing (high-stakes, conflicts
with prior conclusions + a hard constraint). Probes still in tree (uncommitted): CACHESCAN in
ast_to_hir.cr + 4 calls in cli.cr; A/B/C/D, RESCAN, PCS_BADDEF, FIELDCORR, NDC — REMOVE before any fix.
Watchpoint script: /tmp/wp_trace.py. Deterministic repro: /tmp/s2b_dbg4 /tmp/bis.cr.

[LM-M4i2c|verified]: The "floating" non-deterministic s2b crash (which surfaced at lower_call /
collect_return_types / CLI#compile depending on build layout) is ONE root: a
`heap-buffer-overflow READ of size 8` in `Array(Adamas::HIR::TypeRef)#dup`, caught by ASAN
(build s2b with `ADAMAS_EXTRA_LINK_FLAGS="-fsanitize=address"` via cli.cr; toolchain works, no GC
conflict). The calloc'd element buffer is 4 bytes (HIR::TypeRef is a 4-byte struct, `id : Int32`)
but dup's memcpy uses an 8-byte element stride, over-reading one element of adjacent heap; that
garbage then propagates and crashes elsewhere (hence "floating"). Allocated in lower_call
(+0x179d8). => an Array-of-struct element-size/stride codegen bug, NOT arena lifetime / null
ExprId. A source-level milestone file-probe was the WRONG tool (it perturbed the crash site); ASAN
catching the corruption at its source was decisive. Fix (M4i2d, pending): align the
Array(HIR::TypeRef) allocation stride with the dup/copy stride. Repro: /tmp/s2b_asan under
ASAN_OPTIONS; report /tmp/m4i2c_asan_report.txt.

[LM-M4i3|verified]: Tuple container storage policy — Slice layout + inline primitive tuple sort.
Root A (Slice layout): `IndexSet`/`ArrayGet`/`ArraySet` on `Slice(T)` used Crystal `Array` field
offsets (size @4, buffer @16); Slice struct has size @0, data ptr @8. `Slice(Tuple(...))#sort!` →
`merge_sort!` → `insert_head!` getelementptr'd slice @16 → null buffer → SIGSEGV. Fix: detect
`Slice(...)` in `container_mir_is_slice?`; use size @0 and data ptr @8 for Slice.
Root B (storage policy): ref-carrying `Array(Tuple)` uses pointer-slot ABI; inline primitive tuples
(`inline_primitive_tuple_type?`) use byte-stride inline storage. `emit_array_literal` memcpy
primitive tuples inline. `emit_array_get`/`emit_array_set` combined `inline_container_struct_type?
|| inline_primitive_tuple_type?` for byte-stride GEP. `emit_store` removed wrong `store ptr` branch
for non-slot destinations (always falls through to memcpy). `emit_gep_dynamic` marks inline
primitive tuple GEPs as `@inline_tuple_gep_aliases` (not pointer-slots).
Root C (value semantics): `Slice(T)#unsafe_fetch` for inline primitive tuple returned a direct GEP
alias into the buffer; insertion sort `v = unsafe_fetch(j)` aliased buffer[j] and was corrupted
when `unsafe_put(j, unsafe_fetch(j-1))` shifted elements. Fix: `emit_builtin_override` intercepts
`Slice$L...$R$Hunsafe_fetch$$Int32` and emits malloc+memcpy (heap copy), restoring value semantics.
Evidence: `regression_tests/array_tuple_sort_runtime_repro.sh` prints 1/2/3 (was 1/1/1 then
1/1/2); p2 guards green; combined 31/31. Full-prelude s2b not re-gated (separate frontier).
Trust {F/G/R: 0.90/0.65/0.90} [verified].

[LM-M4i2d|verified]: M4i2c root FIXED. Precise root (refines M4i2c): the 4-byte source buffer that
`Array(Adamas::HIR::TypeRef)#dup` over-read was produced by `lower_array_map_dynamic` /
`lower_array_map_with_index_dynamic` (ast_to_hir.cr). The dynamic inline `Array#map` lowering emits
the result `ArrayNew` with the SOURCE element type's container stride, then stores the BLOCK-RESULT
values. In the s2b crash that was `arg_value_ids.map { |id| ctx.type_of(id) }`: source
`Array(ValueId)` = 4-byte inline (UInt32), result `Array(TypeRef)` = 8-byte heap pointers (V2
struct-as-pointer). Buffer malloc'd `count*4`, elements stored at stride 8 -> heap overflow on store
and on the later `dup` copy. The generic `Array(TypeRef)` corridor (initialize/push/index/dup/
resize) was already uniformly 8-byte; the container-storage helpers were correct (TypeRef->8,
ValueId->4). So this is NOT a dup change, NOT an ExprId/tuple/union storage change, and NOT the
global inline-struct ABI — it is the map lowering feeding the wrong element type to ArrayNew. Fix:
made `HIR::ArrayNew#element_type` settable and, once the block-result store type is known, patch
`new_array.element_type = set_type` in both dynamic-map lowerings so alloc stride == IndexSet store
stride == read/dup stride. MIR/LLVM lowering runs in a later pass, so the post-loop mutation is safe.
Evidence: s2b IR `lower_call` ArrayNew buffer strides went 11x4/23x8 -> 2x4/29x8/3x1 (9 under-sized
map buffers corrected; the residual 4/1 are genuine inline-result maps). ASAN s2b on `puts 1`: the
`heap-buffer-overflow READ in Array(...TypeRef)#dup` is GONE. No regression: HEAD and fixed s2b both
crash at the SAME pre-existing deterministic non-ASAN frontier — a wild/null element deref iterating
an `Array(Tuple(String, Int32))` after `sort!` in `lower_call` (HEAD lower_call+126880 addr
0x1675cb59a; fix +126736 addr 0x1675fb59a) — the dup over-read previously returned garbage that let
non-ASAN limp to the same spot. combined 31/31; p2_array_heap_struct_dup_stride / _tuple_storage /
_value_union_storage / _pointer_void_byte_stride all green (ExprId stays 8). NEXT frontier
(separate, pre-existing): the Array(Tuple(String,Int32)) sort!+deref null/wild element in lower_call
while lowering the `puts 1` call. Trust {F/G/R: 0.88/0.55/0.9}.
Adversary-scan (post-fix, clean): all 6 `ArrayNew` sites + dynamic transforms reviewed —
`select`/`reject` are source->source (element_type both sides, correct), `zip` allocates
`tuple_type`, hash keys/values use the stored key/value type; the source->result element-stride
class is closed for `map`/`map_with_index` only, no other latent crash of this class.

[LM-M4i6a|verified]: Constructor return-type pinning no longer depends on bootstrap-hot
`Array#sort_by!` / `Array#find` block helpers. The s2b ASAN `puts 1` frontier after M4i5
was a null deref at `AstToHir#lower_call+0x690f8`; disassembly showed the path inside
`method_name == "new"` owner-candidate handling, immediately around
`Array(Tuple(String, Int32))#sort!$block`, `Array(String)#size`, and
`Hash(String, ClassInfo)#has_key?`. This was not trusted as a general tuple-sort fix:
the accepted change preserves the existing candidate semantics (fully-qualified owners
first, duplicate removal, prefer `@class_info`, then `type_ref_for_name`) but uses explicit
while-loop scans instead of `uniq!`, `sort_by!`, and `find`. Evidence: host build
`/tmp/adamas_m4i6_owner_candidates_s1` passed; combined 31/31; p2 tuple/stride guards green;
`array_tuple_sort_runtime_repro.sh` compile/run prints 1/2/3; ordinary `puts 1` compile/run
prints 1; ASAN s2b no longer reports the old `lower_call+0x690f8` SEGV and advances to a
new `__adamas_ptr_copy` heap-buffer-overflow after `lower_main`. NEXT frontier (M4i6b):
localize the bad `Pointer#copy_from/copy_to` helper call; ASAN reports source allocation
8 bytes and `__adamas_ptr_copy+0x14` over-reading via `memcpy`, with no caller frame.
Trust {F/G/R: 0.86/0.50/0.86}.

[LM-M4i6b|verified]: TypeRef tail slices no longer route through the generic
`Array(TypeRef)#[]?(Range)` storage corridor in bootstrap-hot HIR paths. The M4i6a ASAN
frontier (`__adamas_ptr_copy` heap-buffer-overflow after `lower_main`, source allocation
8 bytes) was localized with a temporary return-address probe: bad caller
`0x1008cc9c0` mapped to `Array(Adamas::HIR::TypeRef)#[]?(Int32, Int32)`, and the only
real Range callsites were inlined into `AstToHir#lower_module_method` and `AstToHir#lower_def`.
Source correlation: TypeRef `[1..]` tails in tuple/block/proc lowering. Fix:
`type_ref_array_tail` manually copies tail elements via `type_ref_array_fetch_or_void`, and
the TypeRef-tail sites (`expand_flat_block_param_types`, unbound instance wrappers,
inline-yield tuple expansion, proc tuple destructuring) use it instead of `[1..]`. This is a
bounded bridge toward PLAN_INLINE_STRUCTS: it removes a fragile generic Array/Range storage
dependency without changing the global struct ABI. Evidence: host build
`/tmp/adamas_m4i6b_type_ref_tail_s1`; combined 31/31; p2 tuple/stride guards green;
`array_tuple_sort_runtime_repro.sh` compile/run prints 1/2/3; ordinary `puts 1` compile/run
prints 1; ASAN s2b `puts 1` no longer reports the old `Array(TypeRef)#[]?` over-read and
advances past `lower_main` to a new null `String#bytesize` frontier (M4i6c). Trust
{F/G/R: 0.86/0.55/0.86}.

[LM-M4i6c|verified]: Advisory enum tracking now guards against null generated
`String` type names before calling `String#empty?`. The M4i6b ASAN frontier after
`lower_main` was `String#bytesize -> String#empty? -> AstToHir#track_enum_value ->
lower_method -> lower_function_if_needed_impl`, with `x0=0`/null receiver. Fix:
`track_enum_value` returns immediately when `type_name.unsafe_as(UInt64) == 0_u64`;
non-null names still follow the existing `empty?` and enum-candidate logic. This is
advisory metadata only: a null type name cannot identify a real enum, so the guard
prevents a crash without claiming to repair the upstream metadata/storage corridor.
Evidence: host build `/tmp/adamas_m4i6c_track_enum_s1`; combined 31/31; p2 tuple/
stride guards green; `array_tuple_sort_runtime_repro.sh` compile/run prints 1/2/3;
ordinary `puts 1` compile/run prints 1; ASAN s2b `puts 1` no longer reports the old
`String#bytesize`/`track_enum_value` SEGV and advances to a new null deref in
`Set(Adamas::HIR::ValueId).new` after `lower_main`. NEXT frontier (M4i6d): localize
the `Set(ValueId).new` null deref; likely another compiler-internal collection/
storage corridor related to the broader PLAN_INLINE_STRUCTS migration. Trust
{F/G/R: 0.84/0.42/0.86}.

[LM-M4i6d|verified]: Backend compiler-UInt32-alias delegates now recognize
`Adamas::HIR::*` / `Adamas::MIR::*` names produced by the M4i1b broad
canonicalization, not only short and `Crystal::HIR/MIR::*` names. Root: the
ASAN M4i6c frontier was `$CCSet$LAdamas$CCHIR$CCValueId$R.new(ptr null)`; because
`compiler_u32_alias_set_owner?` did not match the Adamas-qualified owner, the
raw generated body treated the nil default-capacity pointer as an `Int32` and
called `Set(UInt32)#initialize$arity1`. Fix: extend alias token/prefix/suffix
sets for Set.new, Set TypeRef delegation, Hash key-hash, and root Set aliases to
the Adamas-qualified HIR/MIR compiler ids. Evidence: host build
`/tmp/adamas_m4i6d_set_alias_s1`; combined 31/31; p2 tuple/stride guards green;
`array_tuple_sort_runtime_repro.sh` compile/run prints 1/2/3; ordinary `puts 1`
compile/run prints 1; ASAN s2b `puts 1` no longer reports the old Set(ValueId)
null deref, and the generated IR emits
`$CCSet$LAdamas$CCHIR$CCValueId$R$Dnew` as a delegate to
`Set$LUInt32$R$Dnew(ptr null)`. NEXT frontier (M4i6e): ASAN heap-buffer-overflow
in `Array(Tuple(String, Adamas::HIR::TypeRef, Nil|Int64, Nil|String,
Nil|Adamas::HIR::SourceLocation))#push`, reading 64 bytes at the end of a
64-byte buffer. Trust {F/G/R: 0.86/0.58/0.88}.

[LM-M4i6e|partial]: HIR parameter-type tuple coercion was necessary but not
sufficient for the nested tuple layout mismatch feeding wide
`Array(Tuple(...))#push` containers. Host gates passed, but hostile lldb/IR
review of `/tmp/adamas_m4i6e_hir_tuple_coerce_asan_s2compiler` still found a
remaining path where a narrow tuple body was passed to a wide `Array#<<`.
Trace showed why: the receiver was `Array(Tuple(...wide...))`, but the selected
method suffix was still derived from the narrow argument, so parameter-only
coercion saw matching source/target types. Trust {F/G/R: 0.86/0.62/0.88}.

[LM-M4i6f|verified]: Container writes must coerce the stored value to the
receiver container element type before emitting `Array/Slice#<<`. Root:
container storage layout is owned by the receiver element type, not by the
selected method suffix when lazy resolution still carries a narrow argument
shape. Fix: `lower_binary` and receiver-call `<<` paths route the value through
`coerce_arg_to_container_element_type`, which uses existing tuple/union coercion
to rebuild narrow tuples into the declared container element layout. Evidence:
host build `/tmp/adamas_m4i6f_container_write_coerce_s1`; ordinary `puts 1`
compile/run prints 1; ASAN stage2 build succeeds; IR for `__crystal_block_proc_92`
now allocates a 72-byte wide tuple and passes it to
`Array(Tuple(...SourceLocation))#<<`; ASAN s2b `puts 1` no longer reports the old
`Array(Tuple(...SourceLocation))#push` heap-buffer-overflow; p2 tuple/stride
guards green; `array_tuple_sort_runtime_repro.sh` compile/run prints 1/2/3;
combined 31/31. NEXT frontier (M4i6g): ASAN SEGV/null read in
`Slice(UInt8)#cmp(Tuple(String, Int32), Tuple(String, Int32), Proc)` while
compiling s2 `puts 1`. Trust {F/G/R: 0.90/0.62/0.90}.

[LM-M4i6g|verified]: Block-pass forwarding must use the resolver/mangler's block
suffix semantics and the runtime Proc carrier ABI. Root: the old forwarding
guard checked only `ends_with?("_block")`, so methods mangled as `$block` (for
example `Array(Tuple(String, Int32))#sort!$block`) did not forward `&block` and
called `Slice#sort!$block` with null. A raw-forwarding experiment proved the
second invariant: `Slice(UInt8)#cmp(..., Proc)` loads a heap Proc object
`{fn, env}`; passing the raw block function pointer made it read machine-code
bytes as the Proc header and produced a high-PC BUS. Fix: accept block suffixes
via `method_suffix` + `suffix_has_block_flag?`, wrap the forwarded block value in
`HIR::MakeProc(fn, nil_env)`, and pass that Proc object as the callee's block
argument. Evidence: final host build `/tmp/adamas_m4i6g_block_pass_forward_v2_s1_final`
passed; ordinary `puts 1` compile/run prints 1; IR for
`Array(Tuple(String, Int32))#sort!$block` allocates a Proc object, stores
`%block` at offset 0 and null env at offset 8, then calls `Slice#sort!$block`
with that object; `regression_tests/array_tuple_sort_runtime_repro.sh` compile/run
prints 1/2/3; p2 tuple/stride guards green; combined 31/31. ASAN s2 `puts 1`
advances past the old null/raw block frontier and past `lower_main`. NEXT
frontier (M4i6h): invalid/wild type descriptor state during tuple registration
(`MIR::Type#add_element_type`, sample `self=0x559`; separate ASAN sample:
packed/wild `HIR::TypeRef` in `HIR::Module#get_type_descriptor`). Trust
{F/G/R: 0.88/0.58/0.88}.

[LM-557|verified]: Generated stage2 semantic no-codegen checks now survive
ordinary method definitions, typed/untyped parameters, return annotations,
splat params, and the primitive `Proc#call(*args : *T) : R` signature. Root
pattern: semantic scope traversal used `Set(SymbolTable)`, which hashes object
identity through `Reference#hash -> Crystal::Hasher#reference`; produced `s2`
crashed there while checking a tiny `struct Foo; def call; end; end` reducer.
After that was removed, the next produced-only reducer crash was
`SymbolCollector#handle_def -> String.new(Slice(UInt8))` on raw def
param/return slices, including the `Proc#call` signature. The fix replaces
semantic `SymbolTable` visited sets with identity arrays, passes source
providers into single-file `run_check`, and lets `SymbolCollector#handle_def`
recover method names, param names/types, and return annotations from source
spans before falling back to guarded raw slices. Refuted variant: reading
`arena.extra_sources` inside the collector regressed even bare defs because
that array path is itself fragile in produced `s2`; source must come through
the file/provider boundary. Evidence: `CRYSTAL_CACHE_DIR=/private/tmp/cv2_cache_symbol_final
crystal build src/adamas.cr -o /private/tmp/cv2_symbol_final --error-trace`;
host guards `p2_generated_stage2_no_codegen_def_semantic_frontier.sh`,
`p2_qualified_module_namespace_no_prelude.sh`,
`p2_full_prelude_generic_template_namespace_no_pollution.sh`, and
`p2_self_nested_module_registration_frontier.sh` on `/private/tmp/cv2_symbol_final`;
`scripts/run_safe.sh /private/tmp/cv2_symbol_final 300 4096 src/adamas.cr
-o /private/tmp/cv2_symbol_final_s2/cv2_s2`; produced guards
`p2_generated_stage2_no_codegen_def_semantic_frontier.sh`,
`p2_generated_stage2_char_macro_for_frontier.sh`,
`p2_qualified_module_namespace_no_prelude.sh`, and
`p2_full_prelude_generic_template_namespace_no_pollution.sh` on
`/private/tmp/cv2_symbol_final_s2/cv2_s2`. Boundary: produced full-prelude
`puts 42` still exits 139, but now reaches `concrete_after_new Proc`, then
`Char::Reader`, logs `[INFER_INDEX] method=byte_at self=Char::Reader obj=nil`,
reaches `concrete_after_new Char::Reader`, and segfaults at the next frontier.
{F/G/R: 0.86/0.55/0.86} [verified]

[LM-556|verified]: Generated stage2 full-prelude `puts 42` now moves past the
Char macro-for registration/body-scan trap and reaches the next `Proc`
class-body frontier. Root pattern: class constant recording was using the full
class macro-for registrar for method-only expansion text, and the produced
stage2 macro iterable key path could also lose `op.id`, yielding malformed text
such as `def (other : Char) : Bool`. The fix separates class record-time
macro-for scanning from method registration, only reparses class macro
expansions that can define record-time declarations, and registers the exact
stdlib `Char` `op,desc` six-entry comparison primitive macro directly as six
binary primitive signatures. Evidence: `CRYSTAL_CACHE_DIR=/private/tmp/cv2_cache_char_clean
crystal build src/adamas.cr -o /private/tmp/cv2_char_clean --error-trace`;
`regression_tests/p2_qualified_module_namespace_no_prelude.sh
/private/tmp/cv2_char_clean`;
`regression_tests/p2_self_nested_module_registration_frontier.sh
/private/tmp/cv2_char_clean`;
`regression_tests/p2_full_prelude_generic_template_namespace_no_pollution.sh
/private/tmp/cv2_char_clean`; `scripts/run_safe.sh /private/tmp/cv2_char_clean
300 4096 src/adamas.cr -o /private/tmp/cv2_char_clean_s2/cv2_s2`; and
`regression_tests/p2_generated_stage2_char_macro_for_frontier.sh
/private/tmp/cv2_char_clean_s2/cv2_s2`. Boundary: produced `s2` still exits
139 on full-prelude `puts 42`, but the trace now shows
`concrete_after_body_scan Char`, `concrete_after_new Char`, then
`class_with_name_enter Proc` and `concrete_before_body_loop Proc`; the next root
is `Proc` class body registration, not Char. Refuted variants: broad
constant-only macro-for skipping regressed module registration around
`Crystal::Hasher`; parser-first/textual primitive parsing failed in produced
`s2` because the Char expansion already lost the operator name. {F/G/R:
0.84/0.48/0.84} [verified]

[LM-554|verified]: Generated stage2 CLI pre-scan no longer performs full
constant registration for complex class/module body constants. Root pattern:
the pre-scan pass exists to make outer constants visible across reopened and
nested types, but full `register_constant` also performs literal probing, type
inference, and deferred runtime-init enqueueing at a phase where tuple/proc
constants such as `Number::SI_PREFIXES` / `Number::SI_PREFIXES_PADDED` can
crash produced stage2. The fix splits pre-scan visibility from real constant
registration: scalar Number/Bool/Char constants still use full registration so
early ivar defaults such as `IO::DEFAULT_BUFFER_SIZE` keep type/literal
metadata, while complex RHS forms are recorded in a separate pre-scan constant
index used only by constant-name lookup. Refuted variants: making all pre-scan
constants name-only, or storing `TypeRef::VOID` in `@constant_types`, both let
self-build reach invalid LLVM (`store ptr 32768`) because scalar metadata was
lost. Evidence: `CRYSTAL_CACHE_DIR=/private/tmp/cv2_cache_prescan_final crystal
build src/adamas.cr -o /private/tmp/cv2_prescan_final --error-trace`;
`regression_tests/p2_macro_compare_versions_control_no_raw_sanitize.sh
/private/tmp/cv2_prescan_final`; `regression_tests/p2_qualified_module_namespace_no_prelude.sh
/private/tmp/cv2_prescan_final`;
`regression_tests/p2_prescan_complex_constants_frontier.sh
/private/tmp/cv2_prescan_final`; `scripts/run_safe.sh
/private/tmp/cv2_prescan_final 300 4096 src/adamas.cr -o
/private/tmp/cv2_prescan_final_s2/cv2_s2`; and the same three guards on
`/private/tmp/cv2_prescan_final_s2/cv2_s2`. Boundary: produced full-prelude
`puts 42` now passes `pre-scan constants done`, then exits 133 later during
module/generic registration around `Float::FastFloat`; this is a moved
frontier, not a clean full-prelude smoke. {F/G/R: 0.88/0.56/0.90}
[verified]

[LM-553|verified]: Generated stage2 macro-control registration now folds
`compare_versions(Crystal::VERSION, ...)` without falling back to raw macro
sanitization of inactive branches. Root pattern: produced compiler code cannot
rely on fragile runtime/class-constant version reads or nilable tuple/index
helper boundaries while registering macro-expanded text. The fix uses
macro-expanded version literal methods, source-backed `ConstantNode` definition
names for reparsed arenas, direct builtin-version operand scanning, and
in-place branch selection instead of returning `Tuple(Bool, String?)` for
selected macro-control text. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_compare_cleanup --error-trace`;
`regression_tests/p2_macro_compare_versions_control_no_raw_sanitize.sh
/tmp/cv2_compare_cleanup`; `regression_tests/p2_qualified_module_namespace_no_prelude.sh
/tmp/cv2_compare_cleanup`; `scripts/run_safe.sh /tmp/cv2_compare_cleanup 300
4096 src/adamas.cr -o /tmp/cv2_compare_cleanup_s2/cv2_s2`; and the same
two guards on `/tmp/cv2_compare_cleanup_s2/cv2_s2`. Boundary: generated
`cv2_s2` full-prelude `puts 42` no longer emits the old 51KB
`Float::FastFloat::Powers` raw-sanitize trace under `DEBUG_MACRO_STRIP_HOT=8192`,
but it still exits 133 at the next frontier during CLI pre-scan immediately
after `pre-scan class/module loops start`. {F/G/R: 0.88/0.58/0.90}
[verified]

[LM-532|in_progress]: The next confirmed root pattern is registration-time
semantic work reading AST slices too early, rather than true demand-driven
lowering. Source-first extraction for `DefNode` names, `def self` receivers,
explicit return annotations, and parameter type annotations moves generated
stage2 full-prelude compilation past `Errno` enum registration and past nested
`Crystal::Once` module registration. Disabling eager body-return inference only
for nested module method registration also preserves demanded no-prelude
lowering: `M::N.value` still emits `func @M::N.value() -> Int32`. Evidence:
host-built `/tmp/cv2_param_source_candidate` passes
`p2_enum_class_setter_return_infer_no_prelude.sh`,
`p2_nested_module_registration_no_prelude.sh`,
`p2_bootstrap_semantic_emit_oracle.sh`, and
`p2_visibility_private_accessor_no_prelude.sh`; direct self-host build
`scripts/run_safe.sh /tmp/cv2_param_source_candidate 300 4096
src/adamas.cr -o /tmp/cv2_direct_param_source/cv2_s2` exits 0 after ~143s.
Boundary: the produced `cv2_s2` still cannot compile a full-prelude smoke; it
now fails later at `Exception::CallStack#initialize` while class registration
handles an index expression/parameter annotation corridor. This is progress to
a later `s2` smoke frontier, not `s2 -> s3` readiness. {F/G/R:
0.86/0.52/0.88} [in_progress]

[LM-531|in_progress]: `safe_slice_to_string` is now the concrete
generated-stage2 crash corridor, but the first raw-readable guard attempt is
too broad. Evidence: lldb with ASLR enabled on generated `cv2_s2` stopped at
`Slice(UInt8)#to_unsafe -> AstToHir#safe_slice_to_string`, first from
`infer_concrete_return_type_from_body(Errno.value=)` and then, after moving
method-name lookup to source fallback, from `register_type_method_from_def`.
This refines LM-530: the immediate fault is not proven to be arena object
identity; it is an unsafe parser-slice representation boundary where generated
self-host code can treat a `Slice(UInt8)` argument as a heap-backed/invalid
slot and crash before the code validates the underlying address. Adversary:
applying a raw `readable_address?` check to every `pointerof(slice)` slot is
not correct; a host no-prelude enum-setter reducer then fails in `lower_main`
with `Index out of bounds`, and `ADAMAS_TRUST_SLICE_ADDR=1` restores exit
0 but emits wrong method names (`ErrnoTest.()` / `ErrnoTest.=`). Next root
step: implement a dual-representation slice decoder or source-first extraction
at the vulnerable call sites, and keep `safe_slice_to_string` from calling
`slice.to_unsafe` until the active representation is proven safe. {F/G/R:
0.84/0.50/0.86} [in_progress]

[LM-530|in_progress]: Generated `cv2_s2` full-prelude smoke currently fails
before `s3` starts. Canonical `scripts/run_safe.sh` output stops during
`Errno` registration at `register_type_method_from_def(Errno.value=)`, after
`after_query_yield` and before `after_return_type`; no-prelude smoke remains
green. lldb perturbs the failure: the same generated compiler can pass enum
registration and then crash later in
`capture_initialize_params -> infer_type_from_expr_inner` while registering
`Exception::CallStack`/`Path[dir]`. Refuted local branches: source-backed
class-method receiver detection moves the trace past `Errno.value` but not the
canonical smoke; tail-parameter return inference plus source-backed parameter
annotation recovery passes host no-prelude guards but still does not move the
canonical `run_safe` crash. Current strongest root hypothesis is not
`Errno`-specific: registration-time inference is still separating `ExprId`,
`DefNode`, source spans, and value-union `ArenaLike` identity, so cache/source
lookups can choose a wrong or unstable arena under generated `s2`; Grok ACP
independently proposed replacing `ArenaLike.object_id`-style keys with stable
arena ids and registering all reparse/macro arenas before using them. Boundary:
this is a hypothesis with live traces, not a verified fix. Later local source
review refuted one Grok sub-premise: `AstArena`, `VirtualArena`, and `PageArena`
are classes in current source, not copied struct arenas, so the stable-arena-id
idea may still be useful for source/cache keys but does not explain the
confirmed `safe_slice_to_string` crash by itself. Any stable-arena-id change is
CAUTION-tier and must start with a tiny no-prelude arena identity oracle before
touching the full bootstrap. {F/G/R: 0.76/0.50/0.80}
[in_progress]

[LM-529|in_progress]: The current `codegen` bootstrap frontier is past the
focused stage2 no-prelude semantic corpus, but not yet proven through
`s2 -> s3`. The latest local checkpoint builds a host-built compiler, uses it
to build generated `cv2_s2`, and that generated compiler compiles and runs
`regression_tests/bootstrap_semantic_corpus.cr --no-prelude`. Current root-cause
patterns are: generated-stage2 nilable/small-struct slot drift; arena
identity/lifetime drift when `ExprId` is separated from its arena; V2
over-lowering through safety nets/RTA/missing-target scans instead of original
Crystal-style exact demand; compiler hot paths re-entering fragile stdlib
generic/block helpers (`map`, `each`, `find`, splats) while self-hosted; and
MIR/LLVM backend type-state drift around pointer/int/union coercions. Visibility
modifier findings from the hostile review are largely addressed in current
source: parser accessor macros now preserve visibility metadata, CLI/HIR
validate `VisibilityModifierNode` before unwrapping, and function/accessor
visibility is propagated into HIR lookup. Boundary: this is a source-verified
and no-prelude-S2 checkpoint, not a fresh `s2 -> s3` proof; the next robust
move is to add no-prelude oracles for visibility/accessors plus the recent
inline-yield, proc-literal, phi/switch, and pointer-return corridors, then run
the smallest `s2 -> s3` bootstrap attempt under `scripts/run_safe.sh`.
Project-memory note: `/Users/sergey/bin/cfmem` was unavailable on 2026-05-01
because `libggml.0.dylib` was missing, so this landmark is the durable
checkpoint until cfmem is repaired. {F/G/R: 0.78/0.55/0.86} [in_progress]

[LM-528|in_progress]: The stage2 `private DIGITS_DOWNCASE` failure split into
two roots. First, generated `cv2_s2` was not promoting uppercase identifier
assignment to `ConstantNode`; concrete `IdentifierNode` constant detection plus
ASCII byte checks makes the no-prelude `private VALUE = 1; VALUE` reducer pass
on generated `cv2_s2`. Second, making more constants visible exposed fragile
arena identity and exact-signature boundaries: deferred constants now carry a
typed `ExprId`+arena record, and several arena/reparse helpers normalize
`ArenaLike?` with explicit casts and avoid `map/find` block helpers. Evidence:
host build `/private/tmp/cv2_cast_candidate` passes
`p2_visibility_modifier_semantics_no_prelude.sh`,
`p2_visibility_private_accessor_no_prelude.sh`, and
`p2_splat_default_args_no_prelude.sh`; the focused
`p2_visibility_private_const_module_no_prelude.sh` passes on both the host-built
candidate and generated `/private/tmp/cv2_bs_s2_cast/cv2_s2`; `s1 -> s2` builds
that generated compiler in ~213s with no-prelude smoke green. Boundary:
`private class Hidden; def value; 1; end; end;
Hidden.new.value` now gets past registration stubs but still segfaults in
`lower_main` via `lookup_function_def_for_call -> String#includes?`, and
full-prelude stage2 smoke still segfaults at top-level collection. {F/G/R:
0.84/0.48/0.86} [in_progress]

[LM-527|verified]: Visibility modifier wrappers must be validated before
top-level collection or HIR member passes discard them. The first HIR-only
patch validated `unwrap_visibility_member*` and expression lowering, but the
new no-prelude guard refuted completeness: `protected class Hidden` still
compiled because `CLI#collect_top_level_nodes` recursively stripped
`VisibilityModifierNode` before class registration. The fix adds matching
validation in the top-level collector and in all HIR visibility unwrap helpers.
Covered semantics match original Crystal for non-call forms: private
type/constant/macro wrappers are accepted, protected type/constant/macro
wrappers raise `can only use 'private' for ...`, and invalid non-call targets
raise `can't apply visibility modifier`. Evidence: `crystal build
src/adamas.cr -o /private/tmp/cv2_visibility_modifier_semantics
--error-trace`; `p2_visibility_modifier_semantics_no_prelude.sh`,
`p2_visibility_private_accessor_no_prelude.sh`,
`p2_visibility_protected_namespace_no_prelude.sh`,
`p2_bootstrap_semantic_emit_oracle.sh`, and
`p2_named_tuple_annotation_keys_no_prelude.sh` pass with that compiler; parser
visibility spec remains green. Boundary: wrapped `CallNode` is intentionally
still allowed as the macro-call escape hatch for `private record`-style forms
until v2 has a reliable expanded/unexpanded macro-call marker. {F/G/R:
0.91/0.68/0.91} [verified]

[LM-526|verified]: Owner-context annotation resolution, structural union alias
resolution, and Crystal-compatible protected namespace access are one
bootstrap corridor. The first symptom was a stage2 stub for
`CLI#debug_cli_root_block_state(String, AstArena, Array(ExprId))`: the method
was declared against `Frontend::ArenaLike`, but registration resolved
annotations without the method owner's namespace and then let union descriptors
collapse through scalar alias resolution/type-cache hits. The follow-up symptom
was `protected method 'entries_size' called for Hash(...)`; trace showed
`current=Hash::KeyIterator(...)`, `owner=Hash(...)`, so the missing invariant
was Crystal's `has_protected_access_to?` same-namespace rule, not an
`entries_size` special case. The fix resolves def annotations with the method
owner, preserves union descriptor names during mangling, resolves union aliases
per variant, rejects non-union cache hits for union keys, and implements
protected access through hierarchy/generic-base/same-top-namespace checks.
Evidence: `crystal build src/adamas.cr -o /private/tmp/cv2_protected_namespace
--error-trace`; `p2_visibility_protected_namespace_no_prelude.sh` and
`p2_visibility_private_accessor_no_prelude.sh` pass with that compiler;
`ADAMAS_STOP_AFTER_HIR=1 ADAMAS_PHASE_STATS=1 scripts/run_safe.sh
/private/tmp/cv2_protected_namespace 180 4096 src/adamas.cr -o
/private/tmp/cv2_protected_namespace_s2` exits 0 after ~145s. Boundary:
`lower_missing` still fanouts from `615 -> 35882` in ~159s; that is the next
demand-driven root, not part of this visibility/union fix. {F/G/R:
0.91/0.62/0.91} [verified]

[LM-525|verified]: LLVM value lookup in the generated-stage2 backend must avoid
block iterator helpers in the materialization predicate. After LM-524 removed
the debug-cache tuple-key crash, generated `cv2_s2` crashed in
`LLVMIRGenerator#value_ref(UInt32)` from `emit_extern_call`. LLDB disassembly
localized the first stop to
`@current_func_params.any? { |p| p.index == id }`; replacing only that iterator
with a direct loop moved the crash into
`find_def_inst` at `block.instructions.find { |inst| inst.id == id }`. The root
pattern is not a missing default value: this hot backend lookup corridor was
using closure/Enumerable helpers while generated stage2 still has fragile block
helper ABI paths. The fix replaces both predicates with direct while loops,
preserving the same lookup semantics without invoking block iterators.
Evidence: `crystal build src/adamas.cr -o /tmp/cv2_value_ref_def_loop
--error-trace`; `p2_bootstrap_semantic_emit_oracle.sh`,
`p2_pending_budget_no_prelude.sh`, `p2_universal_helper_fanout_no_prelude.sh`,
and `p1_ir_shape_check.sh` pass with `/tmp/cv2_value_ref_def_loop`; canonical
`s1 -> s2` builds `cv2_s2` in about 229s. ASLR-enabled LLDB now stops later in
`File.new_internal -> File.open -> CLI#file_sha256`, not in
`LLVMIRGenerator#value_ref` or `find_def_inst`. Boundary: this is a backend
self-host hot-path hardening, not a general block ABI fix; block/proc carrier
work remains tracked separately. {F/G/R: 0.90/0.56/0.91} [verified]

[LM-524|verified]: MIR debug line-scope caching must avoid tuple keys under
self-hosted stage2. After the class-method nested-yield fix, generated `cv2_s2`
still built, but the no-prelude smoke segfaulted after `lower_main: exprs=5`.
LLDB stopped in `__adamas_string_eq` through
`Tuple(String, Int32)#== -> Hash(Tuple(String, Int32), UInt32)#fetch ->
HIRToMIRLowering#hir_innermost_scope_for_source_line ->
propagate_debug_local_bindings -> lower_function_body`; registers showed
invalid String pointers (`-1` / small integer) reaching the equality helper.
Reinitializing the cache instead of `.clear` was insufficient, refuting plain
Hash reuse as the full cause. The root was the compiler-internal
`@hir_line_scope_cache` using `{loc.path, loc.line}` tuple keys in generated
stage2. The fix rewrites it to `Hash(String, Hash(Int32, UInt32))` and
reinitializes both scope caches per function, preserving the existing
stage2-sensitive lowering-map invariant while removing the tuple-key Hash
surface from this hot debug path. Evidence: `crystal build
src/adamas.cr -o /tmp/cv2_scope_cache_nested --error-trace`;
`p2_class_method_nested_yield_block_param_no_prelude.sh`,
`p2_loop_block_proc_capture_no_prelude.sh`,
`p2_bootstrap_semantic_emit_oracle.sh`, and `p2_pending_budget_no_prelude.sh`
pass with `/tmp/cv2_scope_cache_nested`; canonical `s1 -> s2` builds `cv2_s2`
in about 227s, and fresh LLDB now stops later in
`Crystal::MIR::LLVMIRGenerator#value_ref(UInt32)` from `emit_extern_call`,
not in `__adamas_string_eq`. Boundary: general tuple-key Hash safety is
still tracked separately; this fixes the compiler debug-cache root, not every
possible tuple-key user program. {F/G/R: 0.91/0.58/0.92} [verified]

[LM-523|verified]: Class-method block-yield inference must bind `self` to the
callee owner, not the caller context. After the loop-capture fix, the generated
stage2 smoke reached `CLI#file_sha256` but lowered
`File.open { |file| file.read(buffer) }` to `Pointer#read(Slice(UInt8))`.
Focused HIR evidence showed the lowered `File.open$arity6_block` body already
created a concrete `File` and yielded it; the loss happened earlier in
AST-level `block_param_types_for_call -> infer_yield_param_types_from_body`.
For class methods with no instance receiver, that inference used
`@current_class` as `self_type_name`, so nested delegation through
`open_internal { |file| yield file }` ran under the caller owner instead of
`File`. The fix prefers the callee owner recovered from the function name
(`owner_override`) before falling back to `@current_class`. Evidence: the
focused `File.open` HIR reducer now types both the inline block param and
`__crystal_block_proc_0` param as `File` and dispatches to
`File#read(Slice(UInt8))`; the no-prelude
`p2_class_method_nested_yield_block_param_no_prelude.sh` reducer guards the
same class-method nested-yield shape with `FileLike.open -> open_internal`;
`crystal build src/adamas.cr -o /tmp/cv2_yield_owner_fix --error-trace`
passes; canonical `s1 -> s2` builds `cv2_s2` in about 230s, and generated
`cv2_s2.ll` now contains `__crystal_block_proc_720 -> File#read(Slice(UInt8))`
instead of the old `Pointer#read` frontier. Boundary: generated `cv2_s2`
no-prelude smoke now segfaults after `lower_main: exprs=5`; LLDB stops in
`__adamas_string_eq` through
`Tuple(String, Int32)#== -> Hash(Tuple(String, Int32), UInt32)#fetch ->
HIRToMIRLowering#hir_innermost_scope_for_source_line ->
propagate_debug_local_bindings -> lower_function_body`. {F/G/R:
0.94/0.66/0.94} [verified]

[LM-522|verified]: Standalone block-proc lowering must use the same capture
walk and untyped-param defaulting invariants as inline block lowering.
`CLI#file_sha256` exposed both gaps: the block body is a `LoopNode`, but
`collect_proc_body_ident_walk` and `detect_written_captures_walk` did not
traverse `LoopNode` and several related AST containers, so `buffer` and
written `hash` were missed; then `lower_block_to_proc` kept an untyped block
parameter as `VOID` while `lower_block_to_block_id` defaulted the same param to
`POINTER`. The fix expands those walkers and coerces untyped standalone block
params from `VOID` to `POINTER`, preserving parity with the inline block view.
Evidence: `p2_loop_block_proc_capture_no_prelude.sh` requires loop-body
captures and `Reader#read(Buffer)` in the standalone proc HIR; the focused
`File.open` reducer now captures `buffer,hash` and emits
`Pointer#read(Slice(UInt8))` instead of dropping the call or selecting
`Hash(...MIR::Function...)#read`; `p2_abstract_getter_vdispatch_no_prelude.sh`
and `p2_bootstrap_semantic_emit_oracle.sh` pass; canonical `s1 -> s2` builds
`cv2_s2` in about 215s and moves the smoke frontier from
`Hash(String, Array(Tuple(String, Crystal::MIR::Function)))#read(Slice(UInt8))`
to `Pointer#read(Slice(UInt8))` in `CLI#file_sha256`. Boundary: the remaining
frontier is block-param precision for File.open (pointer-shaped param still
needs dispatch to concrete File/IO read), not missing loop captures. {F/G/R:
0.93/0.66/0.93} [verified]

[LM-521|verified]: Generated concrete accessors must materialize before
inherited abstract lookup for virtual dispatch targets. A concrete getter such
as `Frontend::LiteralNode#span` is registered in `@function_types` but has no
`DefNode`; `lower_function_if_needed_impl` previously ran
`lookup_function_def_for_call` first, so a concrete `LiteralNode#span` request
could resolve to inherited abstract `Node#span`, leaving the generated
accessor unmaterialized and linking generated stage2 smoke paths to a backend
stub. The fix preempts inherited lookup only for registered generated-accessor
requests with no `DefNode`, then lets `maybe_generate_accessor_for_name` emit
the concrete body. Evidence: `p2_abstract_getter_vdispatch_no_prelude.sh`
rejects `Node#span` stubs and requires both `LiteralNode#span` and
`__vdispatch__Node#span`; a full-prelude optional-getter reducer prints `7`
through `scripts/run_safe.sh`; `abstract_class_method_dispatch_synth.sh`,
`test_vdispatch_struct_return`, `p2_bootstrap_semantic_emit_oracle.sh`,
`p2_pending_budget_no_prelude.sh`, and
`p2_universal_helper_fanout_no_prelude.sh` pass; canonical `s1 -> s2` now
builds `cv2_s2` and moves past the previous `Frontend::Node#span` smoke abort.
New frontier: generated `cv2_s2` no-prelude smoke aborts later at
`Hash(String, Array(Tuple(String, Crystal::MIR::Function)))#read(Slice(UInt8))`
from `Adamas::Compiler::CLI#file_sha256`. {F/G/R: 0.94/0.64/0.94}
[verified]

[LM-520|verified]: Return-type force-lowering must be demand-gated by whether
the call's current return type still needs exact resolution. The old
`lower_call` / `lower_member_access` path called
`force_pending_call_targets_for_return_type` for every pending target after
ordinary lazy lowering, even if the call already had a concrete non-union
return type. `timeout_sample_lldb.sh` on the canonical `s1 -> s2` gate showed
the live stack in `lower_missing_call_targets -> process_pending_lower_functions
-> lower_call -> force_pending_call_targets_for_return_type ->
force_lower_function_for_return_type`, with large samples in method lookup and
generic class monomorphization. The fix skips that force-refresh for concrete
non-union return types while preserving it for `VOID`, union returns, and
unresolved generic placeholders. A stricter first attempt that skipped unions
was refuted by a stage1 full-prelude `puts 42` smoke failure in
`Crystal::System::Dir.current`, where `File.info?` required a widened union PHI.
Evidence: focused p1/p2 guards passed; full-source `STOP_AFTER_HIR` improved
from about 234s / `process_pending +14225` / ~50.9k HIR functions to about
137s / `process_pending +272` / ~35.6k HIR functions; canonical `s1 -> s2`
now passes stage1 smokes and reaches `llc` after about 166s instead of timing
out. Boundary: the current frontier is a backend LLVM type mismatch
(`ptrtoint ptr %r685` with `%r685 : double`) in generated `cv2_s2.ll`, not a
HIR pending-queue timeout. {F/G/R: 0.94/0.62/0.94} [verified]

[LM-519|verified]: Generic receiver stripping must preserve namespace path
segments. The old overload/method-index helpers normalized
`Indexable(T)::ItemIterator(Array(String), String)#each` to `Indexable#each`,
so `ItemIterator#each` could select the `Indexable(T)#each` body and emit a
bogus nested constructor demand
`Indexable(T)::ItemIterator(Indexable(T)::ItemIterator(Array(String), String), String).new`.
The fix strips generic arguments per namespace segment for method-index keys
and stripped overload lookup, producing `Indexable::ItemIterator#each`, and
adds generic-template resolution for classes declared under generic
namespaces. Evidence: `regression_tests/p2_nested_generic_new_inference.sh
/tmp/cv2_method_index_path3` requires the specialized iterator constructors
and rejects the bogus nested `ItemIterator(...).new`; build and p1/p2 focused
guards passed; full-source `STOP_AFTER_HIR` exits 0 after about 234s. Boundary:
full-source `lower_missing` still grows `17423 -> 50628 (+33205)`, so the next
bootstrap root is broad concrete-call demand volume, not this namespace
lookup bug. {F/G/R: 0.92/0.66/0.93} [verified]

[LM-481|verified]: Backend-owned runtime intrinsics must not be demand-driven
as source-level HIR functions. HIR currently emits `__adamas_string_eq`,
`__adamas_hash_get_entry_ptr`, `__adamas_hash_entry_deleted`, and
`__adamas_select_ptr` as plain `Call` instructions, but MIR lowering turns
unresolved calls into `extern_call`, and the LLVM backend either defines those
runtime helpers or intercepts them specially (`select_ptr`). A focused patch
skips that exact allowlist in `lower_missing_call_targets`,
`remember_callsite_arg_types`, and `lower_function_if_needed_impl`. Evidence:
`regression_tests/p2_backend_intrinsic_boundary_no_prelude.sh
/tmp/cv2_intrinsic_boundary_check` keeps `string_eq` / `select_ptr` visible in
HIR while rejecting their appearance in missing-source logs; fresh generated
`s1` full-source `STOP_AFTER_HIR` exits 0 after about 220s, and
`rg '__adamas_(string_eq|hash_get_entry_ptr|hash_entry_deleted|select_ptr)'
/tmp/cv2_missing_intrinsic/run.log` returns no matches. Boundary: this removes
one wrong demand source but does not by itself shrink the remaining
`lower_missing` total (`+25690` in the measured run). {F/G/R:
0.91/0.62/0.92} [verified]

[LM-482|verified]: Class vdispatch wrappers can share a case body when many
runtime type IDs resolve to the exact same inherited implementation. The MIR
vdispatch generator now keeps all switch labels but interns only class-dispatch
case bodies by callee `FunctionId`; union-dispatch cases and
`dispatch_class`-specialized cases remain unique because they carry
case-specific unwrap/specialization semantics. Evidence: local hostile review
of `generate_vdispatch_body` confirmed legal multi-label switch targets and
PHI predecessor shape; the focused self-host artifact reduced broad
`Object#hash` wrapper size from roughly 50k lines to roughly 10k lines, and the
current canonical `s1 -> s2` partial `cv2_s2.ll` is about 3.7MB instead of the
previous 170MB+ over-materialized artifacts. Boundary: this is an IR-size/root
compaction, not the final bootstrap fix; full `s1 -> s2` still times out after
allocator flush. {F/G/R: 0.86/0.64/0.84} [verified]

[LM-483|verified]: Generated stage2 can still miss inline-default ivar
initialization for closure by-reference state in `AstToHir`; keep those fields
explicitly initialized in the constructor until the broader inline-default
root is fixed. Evidence: the vdispatch-compacted generated `cv2_s2` no-prelude
smoke crashed in `Set(String)#includes?` from
`AstToHir#lower_identifier` because `@closure_ref_prefer_cell` was nil despite
the inline ivar default. Explicit constructor initialization restored the
focused no-prelude guards. Boundary: this is a contained workaround for a known
generated-stage2 initialization bug, not a replacement for the later general
inline-default fix. {F/G/R: 0.86/0.45/0.88} [verified]

[LM-484|verified]: Current full `s1 -> s2` frontier has moved past HIR
STOP_AFTER_HIR but still fails the canonical 300s bootstrap gate in the
post-HIR tail. Command:
`BOOTSTRAP_STAGE_OUT=/tmp/cv2_bs_s2_intrinsic BOOTSTRAP_CHAIN_STAGES=2
BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
scripts/build_bootstrap_stages.sh --stages 2 --out /tmp/cv2_bs_s2_intrinsic`.
Stage1 builds and both smokes pass; stage2 is killed at about 302s after
`[ALLOC_FLUSH] Generated 98 deferred allocators`, with partial
`/tmp/cv2_bs_s2_intrinsic/cv2_s2.ll` around 3.7MB. Boundary: next work should
sample the allocator/MIR/LLVM tail, not re-open the backend intrinsic boundary
unless new evidence appears. {F/G/R: 0.93/0.54/0.94} [verified]

[LM-485|verified]: The canonical `s1 -> s2` timeout is visible after allocator
flush, but the measured primary supplier is the initial missing-target sweep,
not allocator generation or repair fixed points. A phase-split
`ADAMAS_STOP_AFTER_HIR=1 ADAMAS_PHASE_STATS=1` run using
`/tmp/cv2_phase_split_check` reports:
`process_pending: 3159 -> 17572 (+14413)`, `emit_tracked_sigs: 17572 -> 17836
(+264)`, `lower_missing.initial: 17836 -> 43126 (+25290) in 144271.9ms`,
`repair_stale_calls: +26`, `repair_receiver_calls: +217`,
`deferred_allocators: +5`, and `final_missing.fixed_point: +110`. The same
run exits `STOP_AFTER_HIR` in about 220s. A separate
`ADAMAS_STOP_AFTER_MIR=1` run still times out at 300s during
`Pass 2: Lowering 35221 function bodies... Body 20001/35221`, so MIR is
processing the large reachable set created upstream. Refuted branches:
pre-sizing MIR `@cross_block_values` did not move the full bootstrap frontier,
and a delta-only `lower_missing_call_targets` scan changed fixed-point timing
and grew the HIR set to 47120 functions. Next work should reduce concrete-call
demand admitted by `lower_missing.initial`, not optimize allocator flush first.
{F/G/R: 0.93/0.58/0.93} [verified]

[LM-518|verified]: Env-gated macro-body diagnostics were a real but partial
source-demand leak because `MacroExpander` imported `json` solely for
diagnostic output and used `Hash#to_json` inside runtime-disabled branches. HIR
still lowers whole method bodies, so those branches pulled generic
`Array/Hash/Set#to_json` and `JSON::Builder` into the compiler bootstrap graph.
The root fix replaced the two diagnostic `.to_json` calls with a local
scalar-only `MacroDiagJson` writer and removed `require "json"` from
`src/compiler/semantic/macro_expander.cr`. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_macro_json_free --error-trace`;
`regression_tests/p2_pending_budget_no_prelude.sh /tmp/cv2_macro_json_free`
printed `process_delta=2 emit_delta=4 lower_missing_delta=0 total=40
max_queue=29`; the p2 semantic emit, backend-intrinsic, and each-index
no-prelude guards passed; full-source `STOP_AFTER_HIR` exited in about 201s
with `42859` functions and no `JSON::Builder`/generic `to_json` top supplier in
the fresh missing summary. Boundary: the remaining `lower_missing.initial`
volume is still about `+25104`, now dominated by virtual/abstract calls
(`IO#<<`, `Proc#call`) and hash/object-id helper corridors, so this is not the
final bootstrap fix. {F/G/R: 0.94/0.58/0.94} [verified]

[LM-462|verified]: Bootstrap semantic-equivalence scaffolding exists as a thin
scripts-only layer over the current bootstrap ladder. `scripts/build_bootstrap_stages.sh`
wraps `scripts/bootstrap_chain.sh` and exposes stable names
`s1_bootstrap`..`s5b`; `scripts/emit_bootstrap_ir.sh` emits HIR/MIR/LLVM for a
compiler/corpus pair under `scripts/run_safe.sh`; `scripts/normalize_bootstrap_ir.sh`
strips known non-semantic ids, tmp paths, temp suffixes, and stub-name hashes;
`scripts/compare_bootstrap_stages.sh` diffs normalized S1..S5 dumps against
`regression_tests/bootstrap_semantic_corpus.cr`. Evidence: `bash -n` is green,
one emit smoke with `bin/adamas` produced all three artifacts, and a
synthetic five-stage directory where all stage names point at the same compiler
prints `SEMANTIC_EQ: S1..S5 ok`. Boundary: this is only the gate scaffold; it
does not prove the real `original -> stage1 -> s2b -> s3b -> s4b -> s5b` chain
is green. {F/G/R: 0.90/0.58/0.92} [verified]

[LM-463|verified]: The first real use of the bootstrap semantic gate stops at
`s1 -> s2b`, before any HIR/MIR/LLVM comparison is possible. Command:
`BOOTSTRAP_STAGE_OUT=/tmp/cv2_bs_s2 BOOTSTRAP_CHAIN_STAGES=2
BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096 scripts/build_bootstrap_stages.sh
--stages 2 --out /tmp/cv2_bs_s2`. Stage1 built with host Crystal and both
plain/no-prelude smokes passed. Stage2 self-host build was killed by
`scripts/run_safe.sh`: `[KILL] Timeout after 300s (FDs: 12, RSS:
2281984KB)`, no `/tmp/cv2_bs_s2/cv2_s2` was produced, and the last initial
trace reached `lower_main: exprs=30`. Boundary: do not advance to `s3b+` until
this stage2 stall is explained. {F/G/R: 0.93/0.50/0.95} [verified]

[LM-464|verified]: The stage2 `lower_main: exprs=30` timeout has been refined
to a HIR pending-lowering queue explosion, not a stuck top-level expression.
`DEBUG_MAIN=1 DEBUG_MAIN_PROGRESS_EVERY=1` showed all 30 main expressions start
and return; expr 29 took about `9.3s`, expr 30 took about `80.9s`, and stage2
still timed out. A focused rerun with `ADAMAS_STOP_AFTER_HIR=1
ADAMAS_PHASE_STATS=1 ADAMAS_LOWER_PROGRESS=1` timed out before the
STOP_AFTER_HIR gate but entered `process_pending_lower_functions`: the queue
reached about `78k` entries (`idx=9877/78012`, `idx=12022/76438`) and visible
entries were broad compiler-container `#inspect`, `#to_s`, and `#object_id`
instantiations. Boundary: stop chasing `lower_main` expr 30; localize pending
queue producers. {F/G/R: 0.94/0.55/0.96} [verified]

[LM-465|verified]: `ADAMAS_PENDING_EXPLOSION_TRACE=1` identifies the first
observed deep Array `#inspect` enqueue during the stage2 pending explosion.
Evidence: a build of `/tmp/cv2_pending_trace_ctx` succeeded, and the focused
run emitted `[PENDING_EXPLOSION] first deep Array inspect enqueued source=defer
current=Object#inspect depth=1 queue=12325
name=Array(Array(Array(Tuple(UInt32, Array(Hash(String, UInt32))))))#inspect$IO`
before `[MAIN] expr 30/30`. Boundary: the first observed trigger is
`Object#inspect` fallback lowering on a deep compiler-container Array shape,
not the later `RelatedSpan` symptom. {F/G/R: 0.92/0.52/0.94} [verified]

[LM-466|verified]: Virtual-target diagnostics confirm that the first deep
Array `#inspect` enqueue is caused by eager virtual-target replay from broad
`Object` targets. The decisive sequence in `/tmp/cv2_s2_vtarget_diag.log` is:
`record parent=Object method=to_s args=[405]`, replay of the deep Array child,
`record parent=Object method=inspect args=[405]`, replay of the same child, and
then `[PENDING_EXPLOSION] ... current=Object#inspect ...`. The same log also
shows broad early `Reference#object_id` replay over many compiler-internal
Array/Hash shapes. Boundary: virtual replay is a contributor, but any replay
gate must preserve vdispatch-table completeness. {F/G/R: 0.94/0.62/0.95}
[verified]

## Refuted Bootstrap Fix Branches

[LM-467|refuted]: Broad virtual-target replay gating alone is not a sufficient
fix for the stage2 `STOP_AFTER_HIR` timeout. Guard A skipped immediate
`Object`/`Reference` replay in `record_virtual_target` while
`@lazy_rta_active == false`; it lowered the first deep `#inspect` queue from
`12325` to `9866`, but `[PENDING_EXPLOSION]` still appeared and the 120s
diagnostic still timed out. Extended guard A2 also skipped broad ancestors in
`replay_virtual_targets_for_registered_class` and local call/member replay
loops before lazy RTA; it removed the first `[PENDING_EXPLOSION]` line, but the
300s `STOP_AFTER_HIR` run still timed out: `process_pending` took `248224.0ms`,
lowered `61454` functions, grew HIR functions `3088 -> 64182`, then began
another pending/safety-net pass from about `2300` queued functions. Boundary:
do not land broad replay gating by itself. {F/G/R: 0.95/0.60/0.95} [verified]

[LM-468|refuted]: Emit-only pruning, and the replay+emit combination, are not
the next sufficient fix either. A bounded `emit_all_tracked_signatures` guard
for universal `inspect/to_s/object_id/to_json` on deep generic container owners
still timed out at the original frontier; the first `[PENDING_EXPLOSION]`
remained under `Object#inspect` and the run did not advance into
`emit_tracked_sigs`. The combined patch (broad replay gating + emit pruning)
also timed out: `/tmp/cv2_s2_combo_emit_replay.log` still showed
`process_pending` lowering `61454` functions, HIR functions growing
`3088 -> 64185`, and `[PHASE_STATS] process_pending: ... in 260147.0ms`.
Boundary: do not retry replay/emit heuristics alone; the live blocker is still
growth inside `process_pending_lower_functions` and its active producers.
{F/G/R: 0.94/0.58/0.95} [verified]

[LM-469|refuted]: A defer/enqueue guard for universal helper families on deep
generic/compiler-internal owners did not move the active frontier. The local
experiment added a narrow guard inside `lower_function_if_needed_impl` before
the `inside_lowering?` pending append, targeting
`hash/to_json/to_i/inspect/to_s/object_id` on deep `Array/Hash/Tuple` and
compiler-internal owners unless demanded by RTA/AST reachability. The focused
300s diagnostic still showed the old frontier: first `[PENDING_EXPLOSION]`
under `Object#inspect` at queue `12325`, `[LOWER] p0 #9600 idx=9877/78012`,
and broad helper-family entries around the same queue positions. The patch was
reverted. Boundary: do not retry name-family enqueue guards without better
provenance accounting. {F/G/R: 0.88/0.48/0.90} [verified]

## Active Working Hypothesis

[LM-475|verified]: The generated-stage2 no-prelude `Tuple$Heach$$block`
frontier was a receiverless-call resolution bug, not a print-runtime bug.
IR for the fresh self-host artifact (`/tmp/cv2_puts_stringfix_s2_ir.ll`) showed
the crashing `Tuple$Heach$$block` call came from `lower_call`'s
`explicit_call_target_known` helper over `{primary_mangled_name,
mangled_method_name}`, not from the runtime print fallback. The enabling source
bug was the final bare-call `Object` fallback in `AstToHir#lower_call`: unlike
the earlier self-resolution branches, it did not exempt `puts/print/p/pp`, so
generated `s2b` could incorrectly bind bare no-prelude `puts` to receiver-call
resolution and die before the direct runtime print corridor. Adding the missing
builtin exemption removes the old frontier. Evidence:
`regression_tests/stage2_no_prelude_puts_runtime_repro.sh /tmp/cv2_puts_receiverfix`
=> `not reproduced`;
`regression_tests/p2_generated_stage2_no_prelude_interp.sh /tmp/cv2_puts_receiverfix`
=> `p2_generated_stage2_no_prelude_interp_ok`;
`regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh /tmp/cv2_owned_return_fix3`
=> `p2_generated_stage2_no_prelude_puts_guard_ok frontier=io_filedescriptor_tell`.
Boundary: this does not make generated no-prelude codegen fully green; the next
blocker is `STUB CALLED: IO::FileDescriptor#tell`. The synthetic-main MIR
blockers (`Missing hash key: __crystal_main`, then `MIR function stub not found
for: __crystal_main`) are removed by the function-name fallback fix in MIR
owned-return/stub lookup. {F/G/R: 0.92/0.70/0.93}
[verified]

[LM-480|verified]: The generated-stage2 `IO::FileDescriptor#tell` abort was a
HIR inherited-wrapper materialization bug, not a missing runtime helper. The
front-end resolved `IO::FileDescriptor#tell` to ancestor `IO#tell`, but
`lower_function_if_needed_impl` treated the ancestor body as sufficient and
skipped materializing the requested child symbol. The bounded fix switches the
"already lowered" gate and lowering state bookkeeping to the actual
materialized symbol, and lowers inherited instance wrappers under the requested
owner when the callsite needs a concrete child method body. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_tell_fix --error-trace` succeeded;
plain `File.open { |f| f.tell }` HIR emitted by `/tmp/cv2_tell_fix` contains
only `IO#tell` (`rg -n "func @IO::FileDescriptor#tell|func @IO#tell"
/tmp/io_tell_probe_plain_fix.hir` => only `func @IO#tell`);
`scripts/run_safe.sh /tmp/cv2_tell_fix 420 4096 src/adamas.cr -o
/tmp/cv2_tell_fix_s2` succeeded; `lldb --batch -o 'disassemble -n
IO$CCFileDescriptor$Htell' /tmp/cv2_tell_fix_s2` shows a real delegate body
calling `IO$CCFileDescriptor$Hpos`, not an abort stub; and
`regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
/tmp/cv2_puts_fix2` now also disassembles `IO$CCFileDescriptor$Hputs` and
verifies the nilary wrapper delegates to `print(Char)` instead of reusing the
string-overload body. Full self-host MIR emitted by `/tmp/cv2_puts_fix2`
contains `func @IO::FileDescriptor#puts(%0: Type#204) -> Nil` and a separate
`func @IO::FileDescriptor#puts$String(%0: Type#204, %1: String) -> Nil`; the
old generated-stage2 newline crash in `String$Hbytesize` is gone. Boundary:
generated no-prelude stage2 still is not green; the next blocker moved earlier
to a fresh crash right after `lower_main: exprs=1`. {F/G/R: 0.94/0.75/0.93}
[verified]

[LM-471|verified]: `Array(String)#each_index` fallback block-param inference
must yield `Int32`, not the element type. The generated-stage2 crash after
`lower_main: exprs=1` was reproduced as a segfault in
`__crystal_block_proc_291` because `Array(String)#each$block` passed an Int32
index to a callback materialized as `String ->`; host HIR/MIR showed
`func @__crystal_block_proc_291(%0: String)`. The root was
`fallback_block_param_types`, which only handled `*_with_index` as index-aware
and treated bare `each_index` like element-yielding `each`. After the fix,
fresh self-host HIR has `func @__crystal_block_proc_291(%2: 4)` and
`Array(String)#unsafe_fetch$Int32`; `regression_tests/p2_selfhost_stage2_shape_guard.sh
/tmp/cv2_emitblock_fix` passes and
`regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
/tmp/cv2_emitblock_fix` moves the frontier to
`hash_each_entry_with_index_null_block`. {F/G/R: 0.93/0.70/0.92}
[verified]

[LM-470|hypothesis]: The current bootstrap blocker is not one universal-method
family but missing demand provenance. Multiple producers can turn potential
targets into pending work: virtual replay, `lower_virtual_target_owner`,
`remember_callsite_arg_types`, direct body lowering, RTA call records, and
late safety nets. The next useful step is not another name-based guard; it is
fast `--no-prelude` oracle coverage plus enqueue-provenance accounting by
`source -> family -> owner-base -> current function`. {F/G/R: 0.65/0.55/0.70}
[hypothesis]

[LM-471|verified]: Fast p2 no-prelude sentinels now protect the bootstrap
debug loop from using full `s1 -> s2b` as the first falsifier. Evidence:
`regression_tests/p2_pending_budget_no_prelude.sh /tmp/cv2_pending_sources`
prints `p2_pending_budget_no_prelude_ok process_delta=25 emit_delta=7
lower_missing_delta=30 total=103 max_queue=57`;
`regression_tests/p2_universal_helper_fanout_no_prelude.sh
/tmp/cv2_pending_sources` prints
`p2_universal_helper_fanout_no_prelude_ok deep_helpers=0`;
`regression_tests/p2_bootstrap_semantic_emit_oracle.sh /tmp/cv2_pending_sources`
prints `p2_bootstrap_semantic_emit_oracle_ok`. Boundary: these are fast
sentinels, not bootstrap proof. {F/G/R: 0.92/0.45/0.94} [verified]

[LM-472|verified]: Periodic pending-source diagnostics now expose the dominant
producer families before the 120s timeout. With
`DEBUG_PENDING_SOURCES=1 DEBUG_PENDING_SOURCES_SAMPLES=1
DEBUG_PENDING_SOURCES_EVERY=5000 DEBUG_PENDING_SOURCES_TOP=15
ADAMAS_PENDING_EXPLOSION_TRACE=1 ADAMAS_STOP_AFTER_HIR=1
ADAMAS_PHASE_STATS=1 ADAMAS_LOWER_PROGRESS=1`, the focused run timed
out as expected but printed `[PENDING_SOURCES]` snapshots at queue
`5000..35000`. At queue `35000`, the dominant families were `Array#to_s: 5479`,
`Array#inspect: 5476`, `Array#exec_recursive: 5448`, `Array#object_id: 2741`,
`Hash::Entry#to_s: 1221`, `Hash::Entry#inspect: 814`, `Hash#to_s: 812`,
`Hash#inspect: 810`, and `Hash#exec_recursive: 798`. Boundary: next work should
target the source of recursive formatting demand, not another isolated
`Object#inspect` guard. {F/G/R: 0.93/0.55/0.94} [verified]

[LM-508|verified]: The opt-in AST demand reachability filter reduces the early
all-defs supply phase but does not yet fix the canonical bootstrap graph size.
Patch state: default `compute_ast_reachable_functions` remains conservative
unless `ADAMAS_AST_FILTER_DEMAND=1`; the opt-in path scans packed
`main_exprs`, walks reachable method names, gates candidate owners by
constructed/always-reachable types, and feeds the existing AST filter. Evidence:
`regression_tests/p2_ast_filter_demand_no_prelude.sh /tmp/cv2_ast_demand2`
prints `p2_ast_filter_demand_no_prelude_ok process_delta=2
lower_missing_delta=45 total=92`; full `STOP_AFTER_HIR` with
`ADAMAS_AST_FILTER=1 ADAMAS_AST_FILTER_DEMAND=1` exits 0 and shifts
phase stats from baseline `process_pending +14371, lower_missing +25702,
43471 total` to `process_pending +4148, lower_missing +35210, 43091 total`.
`DEBUG_MISSING_SUMMARY=1` identifies the compensating concrete-call demand as
`IO#<<`, `__adamas_string_eq`, `Array#root_buffer`, Hash internals,
`JSON::Builder`, and `Hash::Entry#inspect/to_s`. Boundary: do not enable this
by default or filter `lower_missing` blindly; the next root target is why
serialization/formatting/hash bodies enter HIR before the concrete missing-call
sweep. {F/G/R: 0.91/0.58/0.93} [verified]

[LM-509|verified]: LLVM backend reachability pruning is now exposed behind
`ADAMAS_LLVM_REACHABILITY=1` but remains default-off. Evidence:
`regression_tests/p2_llvm_reachability_no_prelude.sh /tmp/cv2_llvm_reach`
prints `p2_llvm_reachability_no_prelude_ok ... emitting 5 functions`;
full compiler progress run with the env enabled reaches backend RTA and emits
`27833 functions (37792 total, 9959 pruned)` with a `146MB` `.ll` artifact,
versus the previous `37711` emit-all / `189MB` canonical timeout shape. Boundary:
this does not complete the 300s `s1 -> s2b` gate; the run still times out after
function emission while emitting LLVM tail declarations/finalization, so the
next root target is remaining huge-IR tail cost and missing backend reachability
edges, not flipping this env on by default. {F/G/R: 0.92/0.60/0.93} [verified]

[LM-473|verified]: Context-enhanced pending-source samples identify the current
dominant source contexts. With sample context enabled, the 80s run timed out as
expected but showed `Array#to_s` samples enqueued from `Object#to_s`,
`Array#inspect` from `Object#inspect`, `Array#object_id` from
`Reference#same?`, `Hash#to_s` from `Object#to_s`, `Hash#inspect` from
`Object#inspect`, and `Hash#each` from `Dir::Globber#glob`. Boundary: the next
bounded fix/reducer should target broad universal fallback adapter replay, not
deep-container name guards. {F/G/R: 0.94/0.58/0.94} [verified]

[LM-474|verified]: Virtual-target context logging confirms the earliest
broad-parent replay callsites. In the 45s diagnostic,
`record parent=Reference method=object_id args=[] ... current=Reference#same?`
immediately replayed `Array(Float64)` under `Reference`, and
`record parent=Object method=to_s args=[405] ... current=Object#to_s`
immediately replayed `Array(Float64)` under `Object`. Boundary: the next
candidate fix should consider self-calls inside root fallback methods as
current-owner static/demand-local operations, not global subclass replay.
{F/G/R: 0.94/0.60/0.94} [verified]

[LM-475|refuted]: Suppressing exact RTA-called marking during speculative
virtual-target replay is not sufficient. The uncommitted experiment added a
replay-depth guard around `lower_virtual_target_owner` and made
`record_pending_callee_for_rta` ignore functions enqueued inside that depth.
Fast p2 guards stayed green, but the 120s full diagnostic still timed out with
the same first `[PENDING_EXPLOSION]` at queue `12325` and `[PENDING_SOURCES]`
snapshots through queue `35000`. The patch was reverted. Boundary: the active
fanout is not explained by exact `@rta_called_methods` marking alone.
{F/G/R: 0.90/0.50/0.92} [verified]

[LM-476|obj]: `regression_tests/p2_root_self_replay_no_prelude.sh` is the
small synthetic oracle for the broad-root replay corridor. It defines
`Object#to_s`, `Object#inspect`, `Reference#same?`, and nested `Box(T)` /
`Pair(A, B)` owners under `--no-prelude`; current baseline:
`process_delta=20`, `total=47`, `object_replays=28`,
`reference_replays=21`, `deep_owner_replays=12`. This proves the corridor is
exercised without full-prelude bootstrap and gives future fixes a fast movement
signal before `s1 -> s2b`.
{F/G/R: 0.93/0.55/0.94} [verified]

[LM-477|refuted]: Filtering `rta_method_part_matches_owner?` so broad
`Object` / `Reference` receivers do not ancestor-match universal helper method
parts is not sufficient. The uncommitted experiment built successfully and kept
fast p2 guards green, but `p2_root_self_replay_no_prelude.sh` was unchanged:
`process_delta=20`, `total=47`, `object_replays=28`,
`reference_replays=21`. The patch was reverted. Boundary: exact queued method
names / replay-generated wrappers are enough to keep the synthetic corridor
alive even without broad ancestor matching.
{F/G/R: 0.92/0.45/0.94} [verified]

[LM-478|refuted]: Combining broad-root immediate replay gating with the
broad-root helper RTA filter is still not enough. Synthetic root oracle replay
counts moved (`Object 28->16`, `Reference 21->16`) but `process_delta=20` and
`total=47` did not move. A 120s full `STOP_AFTER_HIR` diagnostic still timed
out; queue reached `40k`, first deep explosion moved to the deep
`Array#inspect` owner itself, and top producers remained universal helper
families (`Array#to_json`, `Array#inspect`, `Array#to_s`,
`Array#exec_recursive`, `Array#hash`, `Hash#...`). The source patch was
reverted. Boundary: partial replay reduction is still symptomatic.
{F/G/R: 0.91/0.55/0.93} [verified]

[LM-479|verified]: RTA keep-reason diagnostics identify the active admission
mechanism. Env-gated `DEBUG_RTA_KEEP_REASONS=1` reports top keep/defer buckets
inside `process_pending_lower_functions`. In a 120s STOP_AFTER_HIR diagnostic,
the first snapshot at `idx=5000 queue=34512` was dominated by
`keep:exact_called`: `Array#to_s: 1469`, `Array#object_id: 738`,
`Hash#to_s: 650`, `Hash#object_id: 341`, `Hash::Entry#to_s: 314`.
Boundary: the next fix must explain why these concrete wrapper names are marked
exact-called; owner/method-part fallback is not the primary keeper at this
frontier. {F/G/R: 0.94/0.62/0.94} [verified]

[LM-480|verified]: `scripts/timeout_sample_lldb.sh` is useful on this
compiler. A 90s sampled STOP_AFTER_HIR run showed hotspots in string hashing,
`type_ref_for_name_inner`, `type_name_cache_depends_on_context?`, and
`lower_node/lower_expr`; LLDB backtrace caught nested
`force_lower_function_for_return_type -> lower_call -> lower_method` activity.
Boundary: current cost is HIR/type/name work from excessive admitted wrappers,
not LLVM or a single runtime tight loop. {F/G/R: 0.86/0.55/0.88} [verified]

[LM-481|verified]: Concrete receiver block-target lookup fixes the
`Indexable(T)#reverse_each$$block` abort-stub corridor. The root cause was that
explicit receiver block lookup skipped receiver descriptors whose names
contained generic arguments, so calls on concrete `Array(...)` receivers could
fall back to the generic module block owner. The fix keeps
`yield_receiver_base_name(ctx.type_of(receiver_id))` for block-target lookup,
canonicalization, and block emit lookup. Evidence:
`DEBUG_CALL_TRACE=reverse_each DEBUG_HOOK_FILTER=reverse_each
ADAMAS_STOP_AFTER_HIR=1 scripts/run_safe.sh /tmp/cv2_commit_candidate 300
4096 src/adamas.cr -o /tmp/cv2_commit_candidate_reverse_stop` exited 0,
and grep found no `Indexable(T)#reverse_each$block` trace while concrete
`Array(...)#reverse_each$block` targets were lowered. {F/G/R:
0.93/0.62/0.94} [verified]

[LM-482|verified]: Default argument expansion must search included modules
before final call-target canonicalization. The root cause was that
`apply_default_args` looked up the pre-canonical concrete owner only, then
parent classes, and missed defaulted module methods such as
`Enumerable#each_with_index(offset = 0, &)`. The fix walks the receiver owner's
included-module chain with `find_module_def_recursive_with_owner` and preserves
the found arena for parameter/default reads. Evidence:
`DEBUG_CALL_TRACE=each_with_index DEBUG_HOOK_FILTER=each_with_index
ADAMAS_STOP_AFTER_HIR=1 scripts/run_safe.sh /tmp/cv2_commit_candidate 300
4096 src/adamas.cr -o /tmp/cv2_commit_candidate_each_stop` exited 0 and
showed repeated `after_args ... args=0` followed by `after_defaults ... args=1`
for concrete Array/Slice calls. {F/G/R: 0.93/0.62/0.94} [verified]

[LM-483|verified]: Direct LLVM small-Hash linear-scan overrides are unsound for
self-hosted `Hash(String, Nil)` / `Hash(String, T)` paths. The root cause was
duplicating `Hash::Entry` field layout in the backend while V2's entry payloads
and offsets are owned by the type registry and normal lowering. The fix disables
`emit_hash_string_linear_scan_override` and lets HIR/MIR lowering emit the real
method body. Evidence: full self-compile with
`ADAMAS_PHASE_STATS=1 scripts/run_safe.sh /tmp/cv2_commit_candidate 300
4096 src/adamas.cr -o /tmp/cv2_s2_commit_candidate` exited 0, the generated
LL had no `direct small Hash linear scan` marker and no
`Hash$LString$C$_Nil$R$Hupdate_linear_scan`, and
`regression_tests/p2_selfhost_hir_emit_no_prelude.sh /tmp/cv2_s2_commit_candidate`
printed `p2_selfhost_hir_emit_no_prelude_ok`. Boundary: stage2 still has a
separate `Enumerable(T)#any?$$block` blocker for richer no-prelude/function
smokes. {F/G/R: 0.92/0.55/0.93} [verified]

[LM-484|verified]: Four stage2 shape roots were isolated and guarded in
`regression_tests/p2_selfhost_stage2_shape_guard.sh`. First, cache-only return
repair must not overwrite already concrete call-site types: the bad
`Slice(UInt8)#[] -> Slice(UInt8)` repair caused `Parser#is_constant_name?` to
load a `Char` from a `UInt8` value; the fixed MIR keeps `UInt8` and emits
`zext ... : Char`. Second, bare `return` in nilable functions must emit a nil
union value; `String#byte_index(Int32, Int32)` no longer contains a bare `ret`.
Third, deferred runtime constants must update `@constant_types` after lowering;
`CRYSTAL_SRC_PATH` now reads as `String` instead of `VOID`, avoiding
`Path | String` variant-0 miswrap and the previous `String#bytesize` crash.
Fourth, splat parameters must be rebound as tuple locals inside method bodies;
`Dir.glob$..._block_splat` now allocates a tuple for `patterns` and no longer
self-recurses. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_splat_tuple_guard --error-trace` exited 0;
`ADAMAS_STOP_AFTER_MIR=1 scripts/run_safe.sh /tmp/cv2_splat_tuple_guard
300 4096 src/adamas.cr --emit mir --no-link -o
/tmp/cv2_splat_tuple_guard_mir` exited 0; and
`regression_tests/p2_selfhost_stage2_shape_guard.sh /tmp/cv2_splat_tuple_guard`
printed `p2_selfhost_stage2_shape_guard_ok`. Boundary: this proves shape
invariants, not a green generated-stage2 compiler. {F/G/R: 0.94/0.62/0.94}
[verified]

[LM-485|verified]: The current generated stage2 compiler still times out even
after LM-484. Full-prelude `puts 42` compilation moves past the old
`CRYSTAL_SRC_PATH`/`Dir.glob` crashes but times out under `run_safe.sh`.
The smallest no-prelude smoke also times out:
`scripts/run_safe.sh /tmp/cv2_s2_splat_tuple_guard 30 2048
/tmp/cv2_no_prelude_expr_splat_tuple_guard.cr --no-prelude --no-codegen`.
Samples identify the next root area rather than the fixed roots:
`__adamas_string_eq` in one timeout and
`Indexable.range_to_index_and_count -> Range(Int32, Int32)#begin` in another.
Boundary: do not run `s3b+`; next work is a minimal no-prelude oracle for this
string/range primitive hang. {F/G/R: 0.88/0.42/0.90} [verified]

[LM-486|verified]: Three additional generated-stage2 no-prelude blockers were
moved forward. First, nilable query calls on concrete containers must preserve
receiver-owned specializations even when the implementation lives in an
included module; `Array(Nil | Array(ExprId))#[]?$Int32` now materializes through
`Indexable#[]?` instead of falling back to `#[]?$Range`. Second, semantic cache
key hashes must avoid `.hash` on immediate primitive fields while self-hosting;
`MethodLookupKey` and related keys now combine object ids and booleans with
integer arithmetic, removing the generated-stage2 `Object#hash` vdispatch
blocker. Third, `TypeInferenceEngine#primitive_metaclass?` must not rely on
flow narrowing across `type.is_a?(PrimitiveType) && type.name...`; explicit
`PrimitiveType` casting makes HIR emit `PrimitiveType#name -> String` followed
by `String#ends_with?`, not stale `Hash(...HIR::Value)#ends_with?`. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_primitive_metaclass_narrow
--error-trace` exited 0; `ADAMAS_STOP_AFTER_HIR=1 ... --emit hir --no-link`
showed the explicit cast and `String#ends_with?$String`;
`ADAMAS_STOP_AFTER_MIR=1 ... --emit mir --no-link` exited 0 and showed
`PrimitiveType#name` plus `call @... : Bool`; full stage2 build produced
`/tmp/cv2_s2_primitive_metaclass_narrow`; and
`regression_tests/p2_selfhost_stage2_shape_guard.sh
/tmp/cv2_primitive_metaclass_narrow` printed
`p2_selfhost_stage2_shape_guard_ok`. Boundary: generated stage2 still times out
after parse on minimal no-prelude; latest sample is hot in
`__adamas_string_eq`, which is the next root target. {F/G/R:
0.92/0.55/0.93} [verified]

[LM-487|verified]: The full `s1 -> s2b` wrapper gate now produces the stage2
compiler but fails at the generated-compiler smoke. Command:
`BOOTSTRAP_STAGE_OUT=/tmp/cv2_bs_s2 BOOTSTRAP_CHAIN_STAGES=2
BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
scripts/build_bootstrap_stages.sh --stages 2 --out /tmp/cv2_bs_s2`. Stage1
build and both stage1 smokes passed; stage2 self-host build passed in
`293.23s` with peak RSS about `3437.70MB`, producing
`/tmp/cv2_bs_s2/cv2_s2`; stage2 plain `puts 42` smoke timed out after `60s`.
A `run_safe.sh` safety-harness defect was found at the same boundary: wedged
child processes can block `lsof` / `wait`, so the wrapper parent may not return
even after writing the timeout marker. Boundary: next compiler work should
debug the generated `s2b` smoke/no-prelude timeout, not the stage2 self-host
build. {F/G/R: 0.93/0.55/0.94} [verified]

[LM-488|verified]: Nested inline-yield fallback must not emit a call back to
the currently lowered splat/block wrapper. The root cause was
`inline_yield_fallback_call` preserving an `inline_key` that already contained
`$..._block_splat`; because the old correction ran only for bare names, a depth
or repeat guard inside `Dir.glob(*patterns, &block)` emitted a self-call that
repacked the splat tuple indefinitely in generated stage2. The fix resolves
bare, `_splat`, and current-function fallback targets through the block overload
table, prefers a typed non-splat block target when available, and does not
eagerly force the corrected callee body during fallback. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_dirglob_rootfix3 --error-trace`
exited 0; mini `Dir.glob` HIR emit under `scripts/run_safe.sh` no longer
contains `Dir.glob$Path | String_File::MatchOptions_Bool_block_splat`; full
`ADAMAS_STOP_AFTER_HIR=1 ... src/adamas.cr --emit hir --no-link`
exited 0 after about `189s`; `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/tmp/cv2_dirglob_rootfix3` and
`regression_tests/p2_selfhost_stage2_shape_guard.sh /tmp/cv2_dirglob_rootfix3`
both passed. Boundary: `s1 -> s2b` now builds `cv2_s2`, but generated-stage2
smokes still fail: plain prelude smoke hits `STUB CALLED: String$Heach$$block`,
and no-prelude smoke times out after `puts$String`. {F/G/R: 0.94/0.58/0.94}
[verified]

[LM-489|verified]: The inline-yield fallback correction must not de-splat
scalar splat-wrapper calls. The regression from LM-488 was that a scalar
`Dir.glob("pattern", &block)` fallback could be over-corrected from the
`Path | String ... _block_splat` wrapper to the `Enumerable` overload, making
the generated stage2 compiler dispatch `String#each$block` inside
`Dir.glob$Enumerable...`. The fix only prefers a typed non-splat block target
when the first call argument is already a tuple/collection; scalar calls keep
the `_block_splat` wrapper so the wrapper performs tuple packing before
forwarding. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_dirglob_scalar_guard --error-trace` exited 0; a mini scalar
`Dir.glob` HIR emit showed the wrapper calling `Dir.glob$Enumerable...` with a
tuple local and no `String#each$block`; full
`ADAMAS_STOP_AFTER_HIR=1 ... src/adamas.cr --emit hir --no-link`
exited 0 after about `187s`; `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/tmp/cv2_dirglob_scalar_guard` and
`regression_tests/p2_selfhost_stage2_shape_guard.sh /tmp/cv2_dirglob_scalar_guard`
both passed. The full `s1 -> s2b` wrapper built stage2 in `295.29s` with peak
RSS about `3315.53MB`; generated-stage2 smokes still fail later, now as
timeouts in prelude loading and after `puts$String`, not as
`String#each$block`. Boundary: do not treat this as a green generated-stage2
compiler; the next root is the generated compiler timeout frontier.
{F/G/R: 0.94/0.58/0.94} [verified]

[LM-490|verified]: Generated-stage2 semantic helper stubs can come from
source-level helper calls whose HIR call targets are emitted but whose bodies
are not materialized by the current demand pipeline. Two adjacent roots were
moved. First, `SymbolCollector#@table_stack` inferred as
`Array(SymbolTable) | Array(String)`, so `current_table` called generic
`Array#last() -> T` and the generated compiler hit `T#lookup_macro$String`.
Adding `@table_stack : Array(SymbolTable)` makes `current_table` return
`SymbolTable` and removes `T#lookup_macro` from HIR/MIR. Second, trivial
`NameResolver` zero-arg helpers (`current_owner_symbol`, `in_method_body?`,
`current_method_is_class_method?`, `top_level_scope?`,
`type_expression_context?`) were present as calls but not materialized as
bodies; inlining their simple stack/depth checks at source call sites removes
that abort-stub cluster. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_semantic_helper_commit --error-trace` exited 0;
`regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/tmp/cv2_semantic_helper_commit` and
`regression_tests/p2_selfhost_stage2_shape_guard.sh
/tmp/cv2_semantic_helper_commit` both passed; the full `s1 -> s2b` wrapper
built stage2 at `/tmp/cv2_bs_s2_semantic_helpers/cv2_s2`, and generated
no-codegen no-prelude smoke moved past `T#lookup_macro` and
`NameResolver#current_owner_symbol` to
`TypeInferenceEngine#guard_watchdog!`. Refuted: direct replacement of
`guard_watchdog!` with `Frontend::Watchdog.check!` removes the stub but
duplicates watchdog lowering and fails the stage2 build envelope; changing
`guard_watchdog!` visibility to public still leaves calls without a body in HIR.
Boundary: next root is the demand/materialization issue for
`TypeInferenceEngine#guard_watchdog!`, not the already-moved helper cluster.
{F/G/R: 0.91/0.52/0.92} [verified]

[LM-491|verified]: `TypeInferenceEngine#guard_watchdog!` was a stale deferred
leaf-helper target, not a missing def registration. The def was registered
early, but calls emitted during `TypeInferenceEngine` lowering deferred the
zero-arg helper into the work queue; later lazy-RTA/safety-net passes could
leave a concrete call target without a materialized body, so LLVM generated
`STUB CALLED: Adamas::Compiler::Semantic::TypeInferenceEngine#guard_watchdog!`.
The safe fix is not a broad stale-Pending requeue: that was tested and rejected
because it reopens the deep generic formatting/iterator fan-out and times out.
Instead, this specific leaf guard bypasses nested deferral and is lowered
immediately. Evidence: `crystal build src/adamas.cr -o /tmp/cv2_guardleaf
--error-trace` exited 0; `ADAMAS_STOP_AFTER_HIR=1 scripts/run_safe.sh
/tmp/cv2_guardleaf 300 4096 src/adamas.cr -o /tmp/cv2_guardleaf_stop`
exited 0 after about `197s`; `--emit hir --no-link` produced a HIR body
`func @Adamas::Compiler::Semantic::TypeInferenceEngine#guard_watchdog!`
that calls `Frontend::Watchdog.check!`; `regression_tests/p2_selfhost_stage2_shape_guard.sh
/tmp/cv2_guardleaf` and `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/tmp/cv2_guardleaf` both passed. Boundary: a direct full `s1` codegen attempt
still timed out at 300s in later lowering, so the next frontier must be
re-measured from a fresh generated `s2b` rather than assumed green.
{F/G/R: 0.92/0.48/0.91} [verified]

[LM-492|verified]: The generated-stage2 `Class$Dcrystal_type_id` abort was a
type-literal primitive lowering hole duplicated across `lower_call` and
`lower_member_access`. `Hasher#class(value)` was emitted as
`copy %value; call Class.crystal_type_id()` because member-access on a
type-literal receiver fell through to static `Class.*` resolution before
primitive lowering could emit the original compiler's metaclass/type-id
semantics. The fix keeps `crystal_type_id` and `crystal_instance_type_id` on
the primitive path for type-literal receivers and emits an `Int32` type-id
literal in both call and no-parens member-access paths. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_typeid3 --error-trace` exited 0;
`regression_tests/p2_selfhost_stage2_shape_guard.sh /tmp/cv2_typeid3` passed
and now rejects `Class.crystal_type_id` / `Class#crystal_type_id`;
`regression_tests/p2_bootstrap_semantic_emit_oracle.sh /tmp/cv2_typeid3`
passed; fresh `scripts/run_safe.sh /tmp/cv2_typeid3 420 4096
src/adamas.cr -o /tmp/cv2_typeid3_s2_full` exited 0 after about `248s`;
generated `s2b` no-prelude no-codegen smoke moved past
`Class$Dcrystal_type_id` to `STUB CALLED: Char$Hascii_control$Q`. Boundary:
this is a root fix for type-id primitive dispatch, not a green generated-stage2
compiler; the next frontier is `Char#ascii_control?` materialization.
{F/G/R: 0.93/0.55/0.93} [verified]

[LM-493|verified]: The generated-stage2 `Char$Hascii_control$Q` abort was a
leaf primitive materialization hole, not a demand-queue root cause.
`Char#control?` calls `ascii_control?` after `ascii?`, but generated `s2b`
still emitted an abort stub for the raw `Char` predicate. The fix lowers
implicit self, explicit call, and no-parens member-access forms of
`Char#ascii_control?` inline as `self < 0x20 || self == 0x7f`, matching
`src/stdlib/char.cr` without touching stdlib/runtime. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_charctl_final --error-trace`
exited 0; `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/tmp/cv2_charctl_final` and `regression_tests/p2_selfhost_stage2_shape_guard.sh
/tmp/cv2_charctl_final` passed; fresh `scripts/run_safe.sh
/tmp/cv2_charctl_final 420 4096 src/adamas.cr -o
/tmp/cv2_charctl_final_s2_full` exited 0 after about `252s`; generated `s2b`
no-prelude no-codegen smoke moved past `Char$Hascii_control$Q` to
`STUB CALLED: Printer$Dshortest$$Float32_IO`. Boundary: this is a root fix for
one missing primitive predicate, but the generated-stage2 compiler is still
not green.
{F/G/R: 0.92/0.45/0.92} [verified]

[LM-494|verified]: The generated-stage2 `Printer$Dshortest$$Float32_IO` abort
was caused by eager debug string interpolation inside
`Semantic::TypeInferenceEngine`, not by missing float-print helpers in user
code. `infer_identifier` eagerly built debug strings such as
`receiver=#{@receiver_type_context.try(&.to_s)}` before checking
`@debug_enabled`, and `debug_hook` is a compile-time no-op in normal builds.
That forced `Object#to_s(io)` on compiler-internal objects during semantic
inference, which reached `Float32#to_s(io)` and the unlowered
`Printer.shortest(self, io)` corridor. The fix replaces eager `debug` and
`debug_type_trace` methods with runtime-gated macros in
`type_inference_engine.cr`, so interpolated strings are only built when
debugging is actually enabled. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_printerfix --error-trace` exited
0; `regression_tests/p2_bootstrap_semantic_emit_oracle.sh /tmp/cv2_printerfix`
and `regression_tests/p2_selfhost_stage2_shape_guard.sh /tmp/cv2_printerfix`
passed; fresh `scripts/run_safe.sh /tmp/cv2_printerfix 420 4096
src/adamas.cr -o /tmp/cv2_printerfix_s2_full` exited 0 after about `242s`;
generated `s2b` no-prelude no-codegen smoke moved past
`Printer$Dshortest$$Float32_IO` and now reaches semantic checking with
`error[E3001]: Function 'puts' not found`. Boundary: this fixes the eager debug
formatting root cause in semantic inference, but no-prelude top-level `puts`
resolution is still missing.
{F/G/R: 0.93/0.58/0.93} [verified]

[LM-495|verified]: The generated-stage2 no-prelude top-level `puts` failure was
a semantic/HIR parity gap, not a new runtime problem. After LM-494, generated
`s2b` no longer aborted in `Printer.shortest`, but
`test_no_prelude_interpolation.cr --no-prelude --no-codegen` still stopped in
semantic analysis with `error[E3001]: Function 'puts' not found`. The HIR
lowerer already has receiverless `puts`/`print` corridors; type inference did
not. The fix adds a tiny receiverless builtin semantic path for top-level
`puts`/`print`, returning `Nil` and letting HIR handle the actual lowering.
Evidence: `crystal build src/adamas.cr -o /tmp/cv2_puts --error-trace`
exited 0; `regression_tests/p2_bootstrap_semantic_emit_oracle.sh /tmp/cv2_puts`
and `regression_tests/p2_selfhost_stage2_shape_guard.sh /tmp/cv2_puts` passed;
fresh `scripts/run_safe.sh /tmp/cv2_puts 420 4096 src/adamas.cr -o
/tmp/cv2_puts_s2_full` exited 0 after about `241s`;
`regression_tests/p2_generated_stage2_no_prelude_interp.sh /tmp/cv2_puts`
passed. The next measured blocker is
`STUB CALLED: Tuple$Heach$$block` from
`regression_tests/stage2_no_prelude_puts_runtime_repro.sh /tmp/cv2_puts_s2_full`.
Boundary: top-level `puts` semantic parity is fixed, but runtime no-prelude
`puts` still falls into a tuple/block lowering corridor in generated stage2.
{F/G/R: 0.94/0.60/0.94} [verified]

[LM-496|verified]: The generated-stage2 `Tuple$Heach$$block` abort for
no-prelude `puts 7` was a compile-mode tracking bug in HIR print fallback
selection, not a real tuple root cause. `s1` already compiled the tiny
`puts 7 --no-prelude` repro to a direct `call void @__adamas_print_int32_ln`
shape, but generated `s2b` still disabled `emit_runtime_print_fallback`
because `prelude_io_print_available?` inferred availability from ambient
`IO` method tables instead of the actual `--no-prelude` option. That let the
generated compiler drift back into the ordinary variadic `puts(*objects)` path,
which iterates the implicit tuple and hit `Tuple#each(&block)` in self-host
mode. The fix threads `options.no_prelude` into `HIR::AstToHir` and makes
`prelude_io_print_available?` return false under `--no-prelude`, so supported
primitive/string/bool print calls always take the runtime fallback corridor in
that mode. Evidence: `CRYSTAL_CACHE_DIR=/tmp/crystal_cache_v2_noprel_printfix
crystal build src/adamas.cr -o /tmp/cv2_noprel_printfix --error-trace`
exited 0; `regression_tests/stage2_no_prelude_puts_runtime_repro.sh
/tmp/cv2_noprel_printfix` returned `not reproduced`; and
`regression_tests/p2_generated_stage2_no_prelude_interp.sh
/tmp/cv2_noprel_printfix` remained green. Boundary: this proves the
no-prelude print-mode decision must depend on compile options, but the next
generated-stage2 frontier still needs fresh measurement after this fix.
{F/G/R: 0.95/0.66/0.95} [verified]

[LM-497|verified]: The generated-stage2 no-prelude `puts 7` frontier moved
past the late backend Hash iterator / block-param-shape corridor. Root chain:
`Crystal::MIR::LLVMIRGenerator#emit_missing_crystal_function_stubs` built a
temporary missing-function `Hash` and then re-walked it via `Hash#each` or
`each_key`; both lower through `Hash#each_entry_with_index`, which exposed the
open nested raw callback ABI and crashed in a null block callback. Returning a
flat `Array({name, return_type, arg_count, arg_types})` snapshot from
`collect_missing_crystal_functions` removes that artificial Hash iterator from
the late emission pass. The first Array snapshot attempt used a nested tuple
payload and exposed a separate generated-stage2 aggregate-layout bug, so the
snapshot is intentionally flat; nested tuple/aggregate block params remain a
real follow-up oracle, not a general flattening policy. A second root in the
same path was block-param inference for compiler collection aliases:
`Crystal::MIR::Array(T)` was not normalized before element inference, so
`Array(T)#each` block procs could be emitted as `Void ->`. Reusing
`normalize_compiler_collection_owner_name` in element/hash block-param
inference changes the self-host HIR for the late-emission Array loop from a
`Void` block param to a real tuple param. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_flat_missing --error-trace`
passed; `scripts/run_safe.sh /tmp/cv2_flat_missing 420 4096 src/adamas.cr
-o /tmp/cv2_flat_missing_s2` exited 0; `scripts/run_safe.sh
/tmp/cv2_flat_missing_s2 120 1024 /tmp/repro_puts7.cr --no-prelude -o
/tmp/repro_puts7_bin` moved to `STUB CALLED:
IO$CCFileDescriptor$Hsystem_pos` instead of the old null callback / tuple
segfault frontiers. {F/G/R: 0.94/0.67/0.93} [verified]

[LM-498|verified]: The generated-stage2 no-prelude `puts 7` frontier moved
past `IO::FileDescriptor#system_pos`, `Crystal::System::Kqueue.set`, and the
`File#file_descriptor_close` recursion crash. The first two were exact-demand
and overload-resolution gaps: same-owner system/class helper calls needed to
mark concrete targets as RTA demand, and raw `Pointer` arguments needed to
match typed `Pointer(T)` parameters so the real Kqueue overload was selected
instead of an abort stub. The bus-error frontier was a separate inherited
wrapper root: requested `File#file_descriptor_close` was materialized by
lowering the ancestor `IO::FileDescriptor` body under `@current_class = File`,
so implicit calls inside the ancestor body resolved back to the child wrapper
and self-recursed. The fix preserves requested wrapper owner only for
value/primitive/generic owner-specialization cases; normal reference-class
inherited wrappers lower the resolved ancestor body while still materializing
the requested dispatch symbol. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_inherited_owner --error-trace` passed; HIR emitted with
`DEBUG_CALL_LOOKUP=file_descriptor_close DEBUG_BLOCK_CALL_ABI=1` shows
`File#file_descriptor_close` calling
`IO::FileDescriptor#file_descriptor_close$block`, not itself; and
`regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
/tmp/cv2_inherited_owner` reports
`p2_generated_stage2_no_prelude_puts_guard_ok frontier=string_null_byte`.
`regression_tests/p2_selfhost_stage2_shape_guard.sh /tmp/cv2_inherited_owner`
also passes after updating its `Dir.glob(...block_splat)` oracle from the stale
tuple-allocation shape to the actual invariant: the forwarding block proc is
`String`-shaped and the old `_block_splat` / `String#each$block` regressions
are absent.
Boundary: `IO#pos` is now an accepted runtime dispatch-helper shape for
`IO::FileDescriptor#tell`; the next root is generated-stage2
`String#byte_index(0)` / null-byte false positive, not another
`check_no_null_byte` callsite workaround. {F/G/R: 0.94/0.68/0.93} [verified]

[LM-499|verified]: The generated-stage2 `String contains null byte` frontier was
a div/rem signedness bug in `llvm_backend`, not a `String#byte_index(0)` search
bug. Root chain: `CLI` builds `pipeline_hash_str = pipeline_hash.to_s(16)` from
a `UInt64` FNV hash whose seed is `0xcbf29ce484222325` (high bit set);
`Int#to_s(base)` calls `num.remainder(base).abs` where `num : UInt64` and
`base : Int32`; MIR emits `BinaryOp::Mod` with `receiver_type = UInt64` as
result but keeps the `Int32` right operand untouched; the backend then
promoted both operands via `sext Int32 -> i64` (fine) but selected `srem`
because `is_signed = left_is_signed || right_is_signed` was true whenever any
operand was signed. `srem i64 0xcbf29ce484222325, 16` returns a negative
remainder (srem follows dividend sign in 2's complement), which `.abs` on a
`UInt64` treats as a huge index into the `digits` buffer, corrupting bytes and
inserting `0x00`. `File.exists?("#{pipeline_hash_str}.ll")` then raises
`String contains null byte` through `check_no_null_byte`. The fix mirrors
original Crystal `primitives.cr:149`: `t1.signed? ? srem : urem`. In
`llvm_backend.cr`, div/rem now derives signedness from dividend only
(`left_is_signed`) instead of OR-ing both operands. Evidence:
`regression_tests/p2_u64_to_s_base16_no_null.sh bin/adamas` baseline
without fix printed corrupted bytes with embedded nul (`byte_index(0)==0`);
with fix prints `cbf29ce484222325`, `16`, `true`. Full regression suite delta
vs baseline: zero changed. The generated-stage2 no-prelude `puts 7` frontier
moves past `string_null_byte` to a new corridor: `--no-codegen` now hits
`STUB CALLED: Array(Nil | Array(Crystal::Compiler::Frontend::ExprId))#check_index_out_of_bounds$Int32_block`;
full codegen times out in `Crystal::RWLock#write_lock` reached from
`Process.fork`. Boundary: this is a codegen root fix, not a demand-pipeline
fix; the next frontier is the new `check_index_out_of_bounds` stub on a
deep nilable-Array container. {F/G/R: 0.94/0.70/0.94} [verified]

[LM-500|verified]: The generated-stage2 `check_index_out_of_bounds` ABORT-stub
frontier was a lazy-RTA allowlist gap, not a virtual-dispatch or receiver-set
bug. Root chain: `Indexable#fetch(index : Int, &)` calls the private helper
`check_index_out_of_bounds(index) { return yield }`. The private helper is
visible only through the fetch body (not through any virtual dispatch site), so
under lazy RTA its method-part is tracked in `@rta_called_method_parts` but its
virtual-receiver set never includes concrete container types. In
`process_pending_lower_functions`, `should_keep` walks
`@rta_called_methods` (exact) → `rta_live_owner?` (owner liveness) →
`rta_method_part_matches_owner?` (virtual-dispatch receiver match). All three
miss for private Indexable helpers on live container types, so the function is
deferred and later emitted as an ABORT stub by `llvm_backend.cr`. The existing
mechanism for this class of helper is
`internal_container_helper_exact_demand?` /
`internal_container_helper_name_exact_demand?` in `ast_to_hir.cr`, which
allowlists private helpers so `record_pending_callee_for_rta` adds them to
`@rta_called_methods` exactly. The allowlist already contained `unsafe_fetch`,
`fetch`, `increase_capacity`, etc., but `check_index_out_of_bounds` was missing
for Array, Slice, and Deque. The fix adds `check_index_out_of_bounds` to the
Array, Slice, and Deque arms of both allowlists. Evidence: targeted
`[CIOOB_TRACE]` instrumentation at the defer decision showed
`reason=defer:method_part owner_live=true mpart_matches=false` for 6 affected
types before the fix; after the fix `generated_s2.ll` contains 78 real
`check_index_out_of_bounds` function definitions and 0 `abort_stub` lines; the
`--no-codegen` probe now exits 0 with no `STUB CALLED`, advancing the
`p2_generated_stage2_no_prelude_puts_guard.sh` recorded frontier from
`array_check_index_oob_stub` to `nocodegen_clean_full_codegen_hang`; full
regression suite delta vs baseline on the same branch is zero (original 147:
133-134/13-14 with `bootstrap_semantic_corpus` flaking equally on both; combined
31: 23/8 identical). Boundary: the next frontier for the full-codegen
`puts 7 --no-prelude` corridor is the 60s hang after `lower_main: exprs=1`,
likely still the `Crystal::RWLock#write_lock` / `Process.fork` corridor noted
in LM-499. {F/G/R: 0.92/0.72/0.94} [verified]

[LM-501|verified]: The generated-stage2 `Crystal::RWLock#write_lock` prologue
emitted `mov w9, #0x4 ; str w9, [x10]`, writing LLVM
`AtomicOrdering::Acquire = 4` into the `@writer` atomic slot instead of the
intended `LOCKED = 1`. Root cause: the inline lowering of `Atomic(T)#set` and
`Atomic(T)#swap` in `src/compiler/mir/hir_to_mir.cr` lines 2978-2992 read
`args[2]` as the stored value whenever the HIR call carried three arguments.
Crystal's `Atomic#swap(value, ordering)` puts the value at arg index 1 and the
ordering enum at index 2, so the inliner was storing the ordering enum (Acquire
= 4) into the slot and reading the prior contents back as an 8-byte `ptr`
(aliasing the full pointer-sized word of the heap-allocated `Atomic(Int32)`
struct). Fix: both branches now read `new_val = args.size > 1 ? args[1] :
const_int(0, INT32)`; the old `args[2]` fallback is removed. Evidence: before
the fix, the generated-stage2 binary's `Crystal$CCRWLock$Hwrite_lock`
disassembly contained `mov w9, #0x4 ; str w9, [x10]`; after the fix the
prologue instead does `adrp x8, Crystal$CCRWLock__classvar__LOCKED ; ldr w9,
[x8] ; str w9, [x10]` (loads the `LOCKED` classvar and stores that i32 into
the atomic slot). Grok (xAI grok-build via `~/.grok/bin/grok_acp_delegate.py`)
located the suspicious inline lowering and the pre-existing proper-atomic path
(`emit_atomic_rmw` in `src/compiler/mir/llvm_backend.cr` near line 23719) with
28 read-only tool calls on a timeboxed task file; verification happened here.
Regression guard is extended in
`regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh` to assert the
positive shape (no raw `#0x4` store, presence of the LOCKED classvar symbol
reference) in the write_lock disassembly. Boundary: the write_lock body is
still a non-atomic load+store inline — `emit_atomic_rmw` / `atomicrmw xchg`
infrastructure exists in the backend but is not reached because hir_to_mir
short-circuits `Atomic#swap` before any MIR `AtomicRMW` is produced; for
single-threaded stage2 the non-atomic behaviour is not the active blocker.
The full-codegen `puts 7 --no-prelude` corridor now fails one level deeper:
`Crystal::System::Process.@@rwlock` classvar stays `null` because
`Crystal::RWLock.new` is never lowered (RTA never records the constructor for
a struct-classvar init), and `write_lock(NULL)` faults on entry with
`EXC_BAD_ACCESS address=0x0` at offset +24 (first load through self). That is
the next frontier. Regression suite delta vs baseline on the same branch is
zero (original and combined counts unchanged; the first combined 21/10 run
was a flake reproduced back to 23/8 on isolated rerun). {F/G/R: 0.92/0.55/0.92}
[verified]

[LM-502|verified]: The `Crystal::System::Process.@@rwlock` classvar staying
`null` after LM-501 (so `Process.fork`'s `lock_write { LibC.fork }` faulted
on entry to `write_lock(NULL)` at offset +24) was a deferred-init recording
gap, not an RTA / lowering issue. `Crystal::System::Process` reopens with
`@@rwlock = Crystal::RWLock.new` under a `{% else %}` Darwin branch, so the
`AssignNode` target reaches HIR through a macro-branch expansion. The four
class-body / macro-expansion iteration loops in `ast_to_hir.cr` (sites
~20448, ~20519, ~20590, ~20656) all matched `when AssignNode` but only
forwarded to `record_constant_definition` when `target.is_a?(ConstantNode)`;
`ClassVarNode` targets were silently dropped, so `@deferred_classvar_inits`
never received the rwlock entry and no `__classvar_init__Crystal$$CCSystem$$CCProcess__rwlock`
function was emitted. Fix: extracted helper `register_class_assign_from_expansion`
that preserves the existing `ConstantNode` recording and additionally pushes
`{expr_id, @arena, class_name}` onto `@deferred_classvar_inits` for
`ClassVarNode` targets; the four existing AssignNode call sites now route
through this helper. The deepest macro-literal inner loop (no prior
ConstantNode/AssignNode arm) was deliberately left untouched: an exploratory
addition there flipped `String::Formatter::HAS_RYU_PRINTF` macro branches
during constant rediscovery and stubbed
`String::Formatter(Tuple(Float64))#current_char`, so the fix is intentionally
narrow. Evidence: `lower_main: lazy classvar recording` count rises from 20
to 21 on full-prelude `puts 7`; the fork test IR contains
`define void @__classvar_init__Crystal$$CCSystem$$CCProcess__rwlock()` whose
body executes `%r3 = call ptr @Crystal$CCRWLock$Dnew()` and
`store ptr %r3, ptr @Crystal$CCSystem$CCProcess__classvar__rwlock`, with
matching call sites at every `@@rwlock` read; `--no-codegen` probe still
exits 0; `p2_generated_stage2_no_prelude_puts_guard.sh` reports
`frontier=nocodegen_clean_full_codegen_hang` (LM-500 boundary preserved);
sprintf_float_fixed_prefix_repro still fails with
`STUB CALLED: String$CCFormatter$LTuple$LFloat64$R$R$Hcurrent_char` on both
fix and freshly-rebuilt baseline (deterministic isolated repro 3/3 each),
confirming it is a pre-existing failure that was masked as `PASS` by a
parallel-run flake in the baseline regression log. Boundary: with the
classvar populated, `Process.fork`'s parent path no longer NULL-derefs, but
the post-fork child now hangs in `Crystal::System::Signal.after_fork`'s
`@@pipe.each` block (offset +68 in the disassembly) — that is the next
frontier. {F/G/R: 0.85/0.55/0.85} [verified]

[LM-503|investigation][parked]: Re-running the LM-502 fork verification
script (`/tmp/lm502/fork_test.cr`) now exposes two distinct V2 bugs that
sit *behind* `Process.fork` but are off the bootstrap critical path. They
are recorded so future work doesn't rediscover them.

(A) **Method overload conflation** — `Crystal::System::Process.fork` has
two overloads: `def self.fork(*, will_exec = false)` (keyword) and
`def self.fork(&)` (block). RTA lowered only ONE function symbol
`Crystal$CCSystem$CCProcess$Dfork$block(ptr %will_exec)`: the body
belongs to the keyword overload, but the signature carries the block
overload's `$block` mangling and accepts the block proc as a single ptr
parameter. At the call site the block proc address is passed as
`will_exec`, the if-test becomes `icmp ne ptr null` (always true), and
control flows down the will_exec=true branch. Cannot reduce to an
isolated repro — 9+ minimal tests with surface-similar shapes
(`fork_overload.cr`, `fork_ov2.cr`, `fork_ov3.cr`,
`fork_close_overload.cr`, `inner_lib.cr` … `inner_lib5.cr`) all emit
both `$arity1` and `$block` overloads correctly. The bug needs more
context — likely macro guards on the keyword overload's body (the
`{% if SOCK_CLOEXEC %}{% else %}` block at process.cr:146-173) plus the
specific suffix-flag combinatorics in `strip_mangled_suffix_flags`
(`ast_to_hir.cr` ~84768) interact with `resolve_method_call`
(~30393+) in a way that the synthetic tests don't trigger.

(B) **`Crystal::EventLoop#after_fork_before_exec` never lowered** —
abstract base at `event_loop.cr:1` (no method); subclasses define it
(`libevent.cr:15`, `kqueue.cr:31-43`, `polling.cr:112-114`,
`epoll.cr` similarly). `fork_run.ll` contains an ABORT-stub for
`Crystal$CCEventLoop$Hafter_fork_before_exec` (lines 222701-222703) and
no subclass overrides — but the *sibling* method `after_fork` is fully
emitted (definition at line 138629, vdispatch at 147572). The
counter-intuitive part: `after_fork` lives inside
`{% unless flag?(:preview_mt) %} … {% end %}` macro guards in every
subclass, while `after_fork_before_exec` does NOT. So this is the
opposite of LM-502's macro-guard skipping pattern. Likely an RTA
discovery gap specific to the sites that *call*
`after_fork_before_exec` (only `Crystal::System::Process.fork`'s
keyword overload at process.cr:196), which never gets exercised
because of bug (A).

Strategic decision: park. `Process.fork` is legacy/deprecated and not
on the bootstrap critical path; TODO.md frontiers are
`guard_watchdog!`, prelude load timeout, `Enumerable(T)#any?$block`,
`lower_missing` growth — all independent. {F/G/R: 0.55/0.40/0.65}
[parked]

[LM-504|verified]: The generated-stage2 `puts 7 --no-prelude` full-codegen
hang (guard script recorded frontier `nocodegen_clean_full_codegen_hang`)
had a different root cause than the LM-501/LM-502 RWLock corridor: HIR
`lower_unary` always lowered `node.operand` *first*, and then matched
the operator text. For `->Module.method` (parsed as
`UnaryNode("->", Call(...))`), that evaluated the target method
eagerly at the literal site. In stage2's prelude, the line

    class_property after_fork_child_callbacks = [
      ->Crystal::System::Signal.after_fork,
      ->Crystal::System::SignalChildHandler.after_fork,
      -> { Random::DEFAULT.new_seed },
    ]

was compiled as three direct method calls at `__crystal_main` time,
before signal pipes / channels were initialised. `Signal.after_fork`
iterated a nil `@@pipe` and spun. The fix adds a prefix check on
`op_str == "->"` in `ast_to_hir.cr:52877` that dispatches to a new
`lower_method_pointer` helper. The helper synthesises a
`__crystal_method_ptr_N` thunk function, lowers the operand inside the
thunk's own `LoweringContext` (saving/restoring outer inline-yield and
loop stacks), terminates the thunk with `Return(call_value)`, and emits
`emit_make_proc_value` with a null environment for the outer context.
The proc type is `Proc(ReturnType)` with no parameters (sufficient for
the 0-arity `after_fork_child_callbacks` shape).

Evidence:

- Probe `/tmp/lm504/probe3.cr` (`->Foo.bar.call`) now prints `42` and
  HIR contains `func_pointer @__crystal_method_ptr_0 + make_proc`
  instead of `call Foo.bar()` at the literal site.
- Stage2 LLVM IR contains thunks numbered 1889, 1890, 1891 matching
  the three `->...` call sites in `Process.after_fork_child_callbacks`.
- Regression suite: 22 → 23 passing out of 31 combined (pre-fix
  baseline `/tmp/cv2_lm502_built` vs fixed `bin/adamas`); no new
  failures. Remaining 8 failures are pre-existing RTA STUB gaps
  (`Permissions$Hvalue`, `UInt8$Hremainder`, etc.) unrelated to
  proc-pointer paths.
- Generated-stage2 `puts 7 --no-prelude` no longer hangs — it now
  exits in ~0s with `STUB CALLED: Crystal$CCEventLoop$Hafter_fork`
  followed by `llc failed` (ABORT stub emitted for the abstract
  `EventLoop#after_fork` because RTA never discovered the virtual
  dispatch reached via `Proc.call` in the child iteration).

The new frontier — RTA discovery gap for `Crystal::EventLoop#after_fork`
called through the `Process.after_fork_child_callbacks` proc chain —
is recorded for follow-up as a sibling to LM-503(B) (which is the
same pattern for `after_fork_before_exec`). The existing guard script
`p2_generated_stage2_no_prelude_puts_guard.sh` does not yet recognise
this shape; it still falls through to the historical
`nocodegen_clean_full_codegen_hang` label because no earlier shape
check matches `STUB CALLED: Crystal$CCEventLoop$Hafter_fork`.

Regression: `regression_tests/proc_pointer_module_method.cr`
(EXPECT: ok). {F/G/R: 0.9/0.6/0.9} [verified]

[LM-505|verified]: Dead `exception = nil` branches were still creating
concrete `Nil#inspect_with_backtrace$IO` demand after the packed-splat
alignment fix. Minimal no-prelude repro:

    def buffered(message : String, *args, exception = nil)
      if exception
        exception.inspect_with_backtrace(IO.new)
      end
    end

called through a wrapper as `buffered(message, *args, exception: exception)`
with the wrapper defaulting `exception` to nil. HIR before the fix already had
`branch false`, but both branches had been lowered first, so the dead then-body
still contained `%5.Nil#inspect_with_backtrace$IO`. Root cause: `lower_if`
asked `static_nil_condition_value` before lowering the condition, but that
static evaluator understood `nil?`/`null?` checks and literal forms, not a bare
IdentifierNode whose current HIR local type was exactly `Nil`. The fix adds only
that narrow source-semantics case (`local : Nil => if local` is statically
false), avoiding broader "non-nil type => true" pruning because current runtime
null-check safeguards for reference/pointer-like values are separate.

Evidence:

- `regression_tests/dead_nil_branch_after_splat_repro.sh /tmp/cv2_nil_branch_fix`
  -> `dead_nil_branch_after_splat_ok`
- `regression_tests/named_arg_after_splat_type_alignment.sh /tmp/cv2_nil_branch_fix`
  -> `named_arg_after_splat_type_alignment_ok`
- `ADAMAS_STOP_AFTER_HIR=1 ADAMAS_PHASE_STATS=1
  DEBUG_PENDING_SOURCES=1 ... scripts/run_safe.sh /tmp/cv2_nil_branch_fix 300
  4096 src/adamas.cr -o /tmp/cv2_nil_branch_stop_hir` -> `[EXIT: 0]`;
  `lower_missing` remains large (`17775 -> 46442`, `+28667`), proving this
  closes a real dead-demand bug but does not solve the broader formatting
  helper explosion. {F/G/R: 0.9/0.55/0.9} [verified]

[LM-506|verified]: RTA method-part replay was over-permissive for root-typed
virtual calls. A call such as `exception : Object;
exception.inspect_with_backtrace(io)` records a broad receiver, then
`rta_method_part_matches_owner?` could keep any live owner whose hierarchy
matched the broad receiver, even if that owner did not declare or inherit the
called instance method. This produced thousands of queued/lowered names like
`Array(UInt64)#inspect_with_backtrace$IO::Memory` from
`Crystal#buffered_message`; `lower_function_if_needed_impl` later reported a
lookup miss for that exact name. A broad method-family suppression was refuted:
it removed the concrete `MyError#inspect_with_backtrace` override for an
`Object`-typed receiver. The accepted fix instead adds a method-existence gate
inside RTA method-part matching: the candidate owner must declare or inherit the
short method name directly, via ancestors, or via included modules before the
method part can keep/replay it.

Evidence:

- `regression_tests/rta_root_virtual_method_replay_guard.sh
  /tmp/cv2_rta_declared_method` -> `rta_root_virtual_method_replay_ok`
  (preserves `MyError#inspect_with_backtrace$IO`, rejects unrelated owner).
- `regression_tests/p2_pending_budget_no_prelude.sh
  /tmp/cv2_rta_declared_method` ->
  `p2_pending_budget_no_prelude_ok process_delta=3 emit_delta=4
  lower_missing_delta=44 total=92 max_queue=57`.
- `ADAMAS_STOP_AFTER_HIR=1 ADAMAS_PHASE_STATS=1
  DEBUG_PENDING_SOURCES=1 ... scripts/run_safe.sh /tmp/cv2_rta_declared_method
  300 4096 src/adamas.cr -o /tmp/cv2_rta_decl_stop_hir` -> `[EXIT: 0]`;
  `lower_missing` improved from `+28667` to `+25702`, and `Array` function
  prefix count dropped from `11817` to `8930`. `Array#inspect_with_backtrace`
  remains visible in enqueue-source accounting, so the next root remains the
  broader `lower_missing`/container-helper materialization corridor.
  {F/G/R: 0.9/0.65/0.9} [verified]

[LM-507|verified]: The canonical bootstrap-stage wrapper had an infrastructure
bug independent of compiler codegen. On macOS Bash 3.2 with `set -u`, invoking
`scripts/build_bootstrap_stages.sh --stages 2 --out ...` with no extra
bootstrap-chain arguments failed immediately at `"${CHAIN_ARGS[@]}"` with
`CHAIN_ARGS[@]: unbound variable`. The fix branches on
`${#CHAIN_ARGS[@]}` and calls `bootstrap_chain.sh` without expanding the empty
array when no passthrough arguments exist.

Evidence:

- `bash -n scripts/build_bootstrap_stages.sh` -> exit 0.
- `scripts/build_bootstrap_stages.sh --help` -> prints usage.
- Re-running `BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
  scripts/build_bootstrap_stages.sh --stages 2 --out /tmp/cv2_bs_current_s2`
  no longer fails in the wrapper; it builds stage1, passes both stage1 smokes,
  then reaches the real stage2 compiler build.

Boundary: the real canonical `s1 -> s2b` gate still fails at stage2 timeout
after emitting `/tmp/cv2_bs_current_s2/cv2_s2.ll` (189MB, 3,930,328 lines,
39,112 LLVM `define`s, 338 stub markers) and after
`[ALLOC_FLUSH] Generated 98 deferred allocators`. This points back to the
over-materialized helper graph / large-IR corridor, not to the wrapper.
{F/G/R: 0.96/0.8/0.95} [verified]

[LM-508|verified]: The late LLVM backend timeout hypothesis was narrowed by
opt-in tail-generation timing. `ADAMAS_LLVM_TAIL_STATS=1` is intentionally
paired with `ADAMAS_TRACE_STDERR=1` because the probes use
`bootstrap_trace_puts`; without the trace env the diagnostic remains silent.
On the full compiler stage2 attempt with LLVM reachability enabled, backend
generation reported `RTA kept: 27806 (pruned 9921)` from `37727` MIR functions,
then completed `generate(io)` and reached `[LLVM_TAIL_GEN] phase=finalize_enter
out=180584919` before `run_safe` killed the overall compile at 300s. The
tail helpers themselves were fast: string constants about `50ms`, undefined
extern declarations about `98ms`, missing Crystal stubs about `21ms`, and
`emit_type_name_table` about `166ms` while adding the largest tail payload
(`~27.8MB` for `21694` type names).

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_tail_stats --error-trace`
  -> exit 0.
- `regression_tests/p2_llvm_tail_stats_no_prelude.sh /tmp/cv2_tail_stats`
  -> `p2_llvm_tail_stats_no_prelude_ok phase=type_name_table ...`.
- `ADAMAS_TRACE_STDERR=1 ADAMAS_LLVM_REACHABILITY=1
  ADAMAS_LLVM_TAIL_STATS=1 scripts/run_safe.sh /tmp/cv2_tail_stats 300
  4096 src/adamas.cr -o /tmp/cv2_tail_stats_trace_s2` -> expected
  timeout, but the log contains `[STAGE2_TRACE] step5: generate done` before
  `[KILL] Timeout`.

Boundary: this is diagnostic only. It refutes "one slow backend tail helper" as
the current root and moves the frontier to total generated-IR volume / pre-llc
budget. It does not make `s1 -> s2b` green and does not justify increasing
timeouts. {F/G/R: 0.9/0.65/0.9} [verified]

[LM-509|verified]: Generated stage2 no-prelude `puts 7` exposed that
bootstrap-hot debug helpers must not depend on variadic tuple splats. Before
the fix, the generated compiler aborted during pass3 setup with:

    STUB CALLED: Crystal$CCHIR$CCAstToHir$Hdebug_env_filter_match$Q$$String_Tuple$LString$R_splat

The root was not `puts` lowering. `debug_env_filter_match?(env_key, *texts)`,
`debug_hook_filter_match?(*texts)`, and `debug_class_repair_enabled_for?(*texts)`
generated tuple-splat helper calls throughout the compiler, but generated
stage2 had ABORT stubs for those helper bodies. The fix changes those helpers
to fixed optional text slots (current callsites use at most four texts) and
keeps the matching logic local, preserving debug-env behavior without requiring
Tuple splat lowering in the bootstrap-hot path.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_debug_filter_fix --error-trace`
  -> exit 0.
- `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
  /tmp/cv2_debug_filter_fix` -> `p2_generated_stage2_no_prelude_puts_guard_ok
  frontier=nocodegen_clean_full_codegen_hang`.
- The fresh full-codegen compile log no longer mentions
  `debug_env_filter_match`; it now stops at
  `Tuple$LString$C$_Crystal$CCMIR$CCType$R$Hjoin$$IO_String_block`, while the
  secondary `--no-codegen` probe exits 0.

Boundary: this is a root fix for debug helper splat usage, not a general tuple
block lowering fix. The next generated-stage2 root is the tuple `join` block
stub family. {F/G/R: 0.9/0.65/0.9} [verified]

[LM-510|verified]: The tuple `join` generated-stage2 frontier was localized to
backend extern-call argument formatting, not user `puts` semantics. An lldb
abort backtrace for generated `puts 7 --no-prelude` showed:

    Tuple(String, Crystal::MIR::Type)#join(IO, String, &block)
    Tuple#to_s(IO)
    Tuple#to_s
    Crystal::MIR::LLVMIRGenerator#emit_extern_call

The triggering source was `args = arg_entries.map { |(t, v, _)| "#{t} #{v}" }
.join(", ")` in `emit_extern_call`. In generated stage2, that block
destructuring / interpolation path could format the tuple itself and reach the
unlowered tuple `join` block stub. The accepted fix keeps the formatting inline
and indexed (`entry[0]`, `entry[1]`) so no new helper method must be discovered
by RTA and no tuple `to_s`/block-join body is needed in this bootstrap-hot path.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_extern_join_inline
  --error-trace` -> exit 0.
- `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
  /tmp/cv2_extern_join_inline` -> `p2_bootstrap_semantic_emit_oracle_ok`.
- `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
  /tmp/cv2_extern_join_inline` -> `p2_generated_stage2_no_prelude_puts_guard_ok
  frontier=eventloop_close_fd_rta_gap`.

Boundary: this is a root fix for the current backend formatter dependency on
tuple block formatting, not a general tuple block/destructuring implementation.
The next generated-stage2 root is `Crystal::EventLoop#close(IO::FileDescriptor)`
RTA/lowering discovery. {F/G/R: 0.9/0.62/0.9} [verified]

[LM-511|verified]: The generated-stage2
`Crystal::EventLoop#close(IO::FileDescriptor)` frontier was a two-stage demand
tracking mismatch, not an EventLoop-specific backend bug.

Findings:

- HIR lowering did emit the call as virtual and materialized the inherited
  implementation as `Crystal::EventLoop::Polling#close$Crystal::System::FileDescriptor`.
- Final HIR RTA then pruned that materialized virtual target because it rebuilt
  reachability from calls and type descriptors without honoring the target set
  already demanded by HIR virtual-dispatch lowering.
- After retaining those HIR-demanded targets, MIR still needed one compatibility
  rule: a virtual call with a typed suffix may resolve to a unique same-method,
  same-arity inherited implementation when the exact typed name is absent. This
  is constrained to a single candidate so ambiguous overload families such as
  `<<$Char` vs `<<$String` stay rejected.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_vtarget_mir --error-trace`
  -> exit 0.
- `ADAMAS_STOP_AFTER_HIR=1 scripts/run_safe.sh /tmp/cv2_vtarget_fix 300
  4096 src/adamas.cr --emit hir --no-link -o /tmp/cv2_vtarget_fix_hir`
  -> exit 0; final HIR retained
  `Crystal::EventLoop::Polling#close$Crystal::System::FileDescriptor`.
- `ADAMAS_TRACE_STDERR=1 scripts/run_safe.sh /tmp/cv2_vtarget_mir 360
  4096 src/adamas.cr --emit llvm-ir --no-link -o /tmp/cv2_vtarget_mir_ir`
  -> exit 0; `IO::FileDescriptor#system_close` calls
  `__vdispatch__Crystal$CCEventLoop$Hclose$$IO$CCFileDescriptor$$T329`, the
  vdispatch body calls `Crystal$CCEventLoop$CCPolling$Hclose$$Crystal$CCSystem$CCFileDescriptor`,
  and the old `STUB CALLED: Crystal$CCEventLoop$Hclose$$IO$CCFileDescriptor`
  string is absent.
- `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
  /tmp/cv2_vtarget_mir` -> `p2_generated_stage2_no_prelude_puts_guard_ok
  frontier=nocodegen_clean_full_codegen_hang`.
- `regression_tests/p2_bootstrap_semantic_emit_oracle.sh /tmp/cv2_vtarget_mir`,
  `regression_tests/p2_llvm_tail_stats_no_prelude.sh /tmp/cv2_vtarget_mir`,
  and `regression_tests/p2_pending_budget_no_prelude.sh /tmp/cv2_vtarget_mir`
  -> all ok.

Boundary: this preserves HIR-demanded virtual targets and allows only unique
same-arity MIR typed-suffix fallback. It is not a broad arity-only overload
fallback and does not implement unresolved block/tuple lowering families.
Current generated-stage2 guard frontier is the full-codegen-only
`nocodegen_clean_full_codegen_hang` state. {F/G/R: 0.92/0.68/0.92} [verified]

[LM-512|verified]: The generated-stage2 `String#call` / duplicate-HIR-id
frontier was two independent HIR registration/lowering bugs, not a Nil
call-argument ABI bug.

Findings:

- `of -> Nil` was stringified without preserving the nilary proc shape, so
  registration-time inference for `Process.after_fork_child_callbacks` seeded
  `Array(String)`. That later lowered callback elements as `String#call`.
- Generic container names that used `get_type_name_from_ref` collapsed
  `Proc(...)` to the display name `Proc`, losing callable type parameters for
  Array/Hash/NamedTuple specialization and element access.
- Struct/HIR getter inlining treated any zero-arg method sharing an ivar name as
  a field getter. In generated stage2 this inlined
  `HIR::Function#next_value_id` as a raw `@next_value_id` field load, skipping
  the increment and causing duplicate HIR ids such as repeated `%2`.
- A failed alternate branch showed `SystemError#included` expands to a
  `BeginNode` containing `extend ::SystemError::ClassMethods`, but naive
  recursive processing currently reintroduces a stage2 `lower_main` timeout.
  Keep that as a separate CAUTION root task; it is not part of this verified
  slice.

Fix:

- `stringify_type_expr` handles unary `->` as `Proc(Return)`, mapping
  nilary `-> Nil` to `Proc(Void)` to match emitted callback bodies.
- Generic container canonicalization now preserves full Proc parameter shape via
  `generic_param_type_name_from_ref`.
- Array element typing checks the value's own Array descriptor before trusting a
  stale lowering-context type map.
- Getter field inlining is proof-based: only a DefNode whose body is the
  trivial `@ivar` getter can inline; out-of-arena getter body ExprIds return
  "not proven getter" instead of raising.
- `p2_generated_stage2_no_prelude_puts_guard.sh` now fails closed on any
  unrecorded `STUB CALLED` before accepting the current no-codegen-clean/full
  codegen frontier.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_safe_commit --error-trace` ->
  exit 0, only the known `Random::DEFAULT` warning.
- `regression_tests/p2_bootstrap_semantic_emit_oracle.sh /tmp/cv2_safe_commit`
  -> `p2_bootstrap_semantic_emit_oracle_ok`.
- `regression_tests/p2_pending_budget_no_prelude.sh /tmp/cv2_safe_commit` ->
  `p2_pending_budget_no_prelude_ok process_delta=3 emit_delta=4
  lower_missing_delta=44 total=92 max_queue=57`.
- `bash -n regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh` and
  `git diff --check` -> exit 0.
- `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
  /tmp/cv2_safe_commit` -> `p2_generated_stage2_no_prelude_puts_guard_ok
  frontier=nocodegen_clean_full_codegen_hang`.

Boundary: this is a root fix for proc-shaped type registration and proven
getter field inlining. It does not implement general `SystemError#included`
BeginNode expansion, full codegen hang diagnosis, or general nested tuple/block
payload lowering. {F/G/R: 0.92/0.70/0.92} [verified]

[LM-513|verified]: The generated-stage2 no-prelude `puts 7` malformed LLVM
frontier was an LLVM backend slot-map consumption bug, not stale Hash storage.

Findings:

- Generated stage2 emitted invalid IR:
  `store ptr null, ptr %` inside `__crystal_main`.
- A temporary clear-check showed `@cross_block_slots.size == 0`,
  `has_key?(3_u32) == false`, and `@cross_block_slots[3_u32]? == nil` at
  function entry in generated stage2, so the map was not retaining stale keys.
- A falsifier that routed real `Hash#clear` functions through the existing V2
  layout-safe clear body did materialize those bodies in `generated_s2.ll`, but
  the empty `%` stores still reproduced. That refuted the stale-Hash-clear
  hypothesis for this frontier.
- The surviving source pattern was the backend's use of
  `@cross_block_slots[inst.id]?` directly in assignment-in-condition. In the
  generated compiler this could enter the slot-store branch for a missing key
  and bind an empty local string. The backend invariant is stricter: cross-block
  slot stores are legal only when the slot map contains the key.

Fix:

- `emit_instruction` now gates cross-block slot consumption with
  `@cross_block_slots.has_key?(inst.id)` and indexes only after that guard.
- The generated-stage2 guard now treats the old `store ptr null, ptr %` shape
  as a hard regression and records the next frontier precisely as
  `extern_puts_arg_type_codegen_gap`.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_slot_haskey_only --error-trace`
  -> exit 0, only the known `Random::DEFAULT` warning.
- `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
  /tmp/cv2_slot_haskey_only` ->
  `p2_generated_stage2_no_prelude_puts_guard_ok
  frontier=extern_puts_arg_type_codegen_gap`; saved IR no longer contains
  `store ptr null, ptr %`.
- `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
  /tmp/cv2_slot_haskey_only` -> `p2_bootstrap_semantic_emit_oracle_ok`.
- `regression_tests/p2_pending_budget_no_prelude.sh
  /tmp/cv2_slot_haskey_only` ->
  `p2_pending_budget_no_prelude_ok process_delta=3 emit_delta=4
  lower_missing_delta=44 total=92 max_queue=57`.
- `bash -n regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh` and
  `git diff --check` -> exit 0.

Boundary: this fixes the empty cross-block slot malformed-LLVM class. It does
not fix the next generated-stage2 semantic codegen bug: `puts 7` currently
lowers to duplicate `__adamas_print_int32_ln(ptr null)` calls instead of a
single `i32 7` extern call. {F/G/R: 0.92/0.62/0.91} [verified]

[LM-514|verified]: The generated-stage2 no-prelude `puts 7` extern-call ABI
frontier was two backend key-presence failures, not a HIR runtime-print fallback
bug.

Findings:

- Generated HIR for the repro already contained one extern call:
  `extern_call @__adamas_print_int32_ln(%2)`, with `%2` as `Int32`.
- Generated MIR lowering first duplicated that one HIR block:
  `[MIR_LOWER] function=__crystal_main blocks=1`, followed by
  `ordered blocks count=2` and two emitted extern calls. The source was
  `order_blocks_for` using `Set(HIR::BlockId)`, which is backed by
  `Hash(BlockId, Nil)`; generated stage2 mis-deduped the single-entry function.
- After block ordering was made deterministic with a linear visited list, the
  backend still emitted `call void @__adamas_print_int32_ln(ptr 7)`.
  That refuted the earlier "ptr null only" formulation and exposed the second
  root: extern-call arg typing used `@value_types[arg_id]? || TypeRef::POINTER`
  even though the Int32 type entry was present.
- The same generated-stage2 hazard had already appeared in slot lookup: nilable
  `hash[key]?` in critical codegen maps can conflate missing keys with present
  values or enter the wrong branch. The backend invariant is key-presence first,
  then indexing.

Fix:

- `HIRToMIR#order_blocks_for` uses a small linear `Array(HIR::BlockId)` visited
  list instead of `Set(HIR::BlockId)` for this tiny traversal.
- `LLVMIRGenerator#emit_extern_call` gates `@value_types` argument lookups and
  called-function signature tracking with `has_key?` before indexing.
- `LLVMIRGenerator#value_ref` applies the same key-presence invariant for
  constants, cross-block slots, and value names.
- `p2_generated_stage2_no_prelude_puts_guard.sh` now classifies any
  `__adamas_print_int32_ln(ptr ...)` call as the extern arg type frontier,
  so `ptr 7` cannot be hidden as a generic full-codegen frontier again.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_extern_arg_type_fix
  --error-trace` -> exit 0, only the known `Random::DEFAULT` warning.
- `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
  /tmp/cv2_extern_arg_type_fix` ->
  `p2_generated_stage2_no_prelude_puts_guard_ok
  frontier=nocodegen_clean_full_codegen_hang`.
- Raw kept IR from that guard shows exactly:
  `call void @__adamas_print_int32_ln(i32 7)`.
- `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
  /tmp/cv2_extern_arg_type_fix` -> `p2_bootstrap_semantic_emit_oracle_ok`.
- `regression_tests/p2_pending_budget_no_prelude.sh
  /tmp/cv2_extern_arg_type_fix` ->
  `p2_pending_budget_no_prelude_ok process_delta=3 emit_delta=4
  lower_missing_delta=44 total=92 max_queue=57`.
- `bash -n regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh` and
  `git diff --check` -> exit 0.

Boundary: no-prelude extern-call ABI for this reducer is fixed, but generated
stage2 still does not produce a runnable binary in the full-codegen path. The
recorded next frontier remains `nocodegen_clean_full_codegen_hang`: the same
generated compiler exits cleanly under `--no-codegen`, and the full path emits
a valid-looking `.ll`/object but leaves no executable. {F/G/R: 0.93/0.65/0.92}
[verified]

[LM-515|verified]: The full-prelude Kqueue `after_fork` HIR branch leak was a
macro-literal registration ordering bug, not a stdlib/runtime problem.

Findings:

- `Crystal::EventLoop::Kqueue#after_fork` was first registered through the
  module macro-literal path, before the later class macro-literal consistency
  path could replace the poisoned base symbol.
- `process_macro_literal_in_module` evaluated `strip_macro_lines` before
  `expand_flag_macro_text`, destroying `{% if LibC.has_constant?(:EVFILT_USER)
  %}` / `{% else %}` markers before the platform branch selector could run.
  The parser then saw both branch bodies as plain Crystal and registered the
  EVFILT_USER path together with the fallback `@pipe` / `system_pipe` path.
- Semantic macro expansion also needed a platform `LibC.has_constant?`
  fallback for constants whose declarations are hidden behind platform
  requires. HIR and semantic fallback lists must stay synchronized; this
  checkpoint aligns the modeled kqueue/epoll/io_uring/POSIX signal constants.

Fix:

- Expand flag/member-query macro controls before stripping macro lines in the
  raw-text and per-text `process_macro_literal_in_module` paths.
- Parse expanded class macro-literal bodies with
  `parse_macro_literal_class_body` and feed children through
  `register_class_members_from_expansion`, avoiding a second hand-written
  registration case tree.
- Teach `evaluate_flag_condition_state` to evaluate simple
  `LibC.has_constant?(:X)` / `Type.has_method?(:x)` text conditions when
  `expand_flag_macro_text` sees source text instead of AST `MacroIfNode`s.
- Add a Darwin/BSD regression guard that extracts
  `Crystal::EventLoop::Kqueue#after_fork` HIR and requires `LibC.@@EVFILT_USER`
  while rejecting `Crystal::System::FileDescriptor.system_pipe`,
  `LibC.@@EVFILT_READ`, and `Crystal::EventLoop::Polling#pipe` in that body.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_macro_control_check
  --error-trace` -> exit 0, only the known `Random::DEFAULT` warning.
- `regression_tests/p2_macro_control_module_literal_guard.sh
  /tmp/cv2_macro_control_check` -> `p2_macro_control_module_literal_guard_ok`.
- `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
  /tmp/cv2_macro_control_check` -> `p2_bootstrap_semantic_emit_oracle_ok`.
- `regression_tests/p2_pending_budget_no_prelude.sh
  /tmp/cv2_macro_control_check` ->
  `p2_pending_budget_no_prelude_ok process_delta=3 emit_delta=4
  lower_missing_delta=44 total=92 max_queue=57`.
- `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
  /tmp/cv2_macro_control_check` ->
  `p2_generated_stage2_no_prelude_puts_guard_ok
  frontier=nocodegen_clean_full_codegen_hang`.
- `bash -n regression_tests/p2_macro_control_module_literal_guard.sh` and
  `git diff --check` -> exit 0.

Boundary: this proves the Kqueue `after_fork` branch leak is removed on the
local Darwin target. It does not prove cross-target macro semantics. A later
test-oracle maintenance pass restored `p2_selfhost_stage2_shape_guard.sh` by
making stale demand-tied callback sentinels demand-aware; see LM-516.
{F/G/R: 0.91/0.58/0.90} [verified]

[LM-516|verified]: `p2_selfhost_stage2_shape_guard.sh` needed demand-aware
callback sentinels after recent demand/RTA and macro-control fixes removed two
incidental old materialization paths.

Findings:

- The LM-471 `Array(String)#each_index` bug was real, but the self-host MIR
  gate was requiring a historical side effect: `Array(String)#each$block`
  happened to contain a nested `each_index` callback under an older generated
  stage2 frontier. Current self-host MIR may not materialize that wrapper at
  all, so absence of the nested proc is not a shape regression.
- The `Dir.glob(..._block_splat)` callback-shape check had the same issue:
  earlier fixes deliberately moved or removed the old wrapper demand while
  preserving the invariant that, if the forwarding proc is emitted, it must be
  `String`-shaped and must not self-recurse.
- A one-pass AWK check was order-fragile because MIR function definitions can
  be printed before the function that references their `func_pointer`. The
  guard now scans the MIR twice: first to collect nested callback proc names
  from the wrapper body, then to validate the referenced proc definitions.

Fix:

- Make the `Array(String)#each_index` and `Dir.glob(..._block_splat)` shape
  sentinels demand-aware: if the nested proc is present, its signature is
  enforced; if the wrapper/proc is absent, the self-host MIR gate does not fail.
- Add `regression_tests/p2_each_index_block_param_no_prelude.sh`, a direct fast
  no-prelude HIR oracle for the actual LM-471 invariant. It compiles
  `["x"].each_index { |i| i }`, requires the `Array(String)#each_index$block`
  call, and rejects a `String`-shaped block proc.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_shape_guard_check
  --error-trace` -> exit 0, only the known `Random::DEFAULT` warning.
- `regression_tests/p2_each_index_block_param_no_prelude.sh
  /tmp/cv2_shape_guard_check` -> `p2_each_index_block_param_no_prelude_ok`.
- `regression_tests/p2_selfhost_stage2_shape_guard.sh
  /tmp/cv2_shape_guard_check` -> `p2_selfhost_stage2_shape_guard_ok`.
- `bash -n regression_tests/p2_each_index_block_param_no_prelude.sh
  regression_tests/p2_selfhost_stage2_shape_guard.sh` and `git diff --check`
  -> exit 0.

Boundary: this is test-oracle maintenance, not a compiler behavior change. It
keeps the old shape checks active when the old wrappers are emitted and moves
the `each_index` root invariant to a direct no-prelude guard. It does not add a
direct `Dir.glob` focused oracle; that remains covered indirectly by the
existing self-host gate when the wrapper is materialized. {F/G/R:
0.93/0.62/0.92} [verified]

[LM-517|verified]: The generated-stage2 no-prelude `puts 7` full-codegen/link
frontier is cleared by fixing the bootstrap CLI command tail, not by changing
HIR/MIR/LLVM code generation for the program body.

Findings:

- Preserved artifacts showed the generated compiler emitted `repro_bin.ll` and
  a valid Mach-O object, but left only `repro_bin.o.cmdtmp` and exited without a
  final executable. The first root was in `CLI#run_command_capture_output`:
  generated stage2 mis-lowered `Crystal::System::Process.fork`'s nilable
  parent/child contract as a plain `Int32`, so the parent compiler process also
  entered the child `execvp(llc)` path and skipped the rename/link tail.
- After switching that path to raw `LibC.fork`, the next root was
  `LibC.waitpid(pid, out status, 0)`: generated stage2 mis-lowered the `out`
  storage and decoded pointer garbage as the wait status. Explicit
  `pointerof(status)` observes the real tool status.
- The next no-prelude link tail pulled an unlowered `Time#<=>` through the
  runtime-stub freshness check, and the LLVM cache path could treat stale or
  empty artifacts as hits. The tail now avoids Time ordering for the stub, gates
  LLVM cache hits with `command_output_ready?`, and copies cache artifacts via a
  small LibC read/write helper instead of bootstrap-hot `FileUtils.cp`.
- The `p2_generated_stage2_no_prelude_puts_guard.sh` RWLock sentinel is now
  demand-aware: if `Crystal::RWLock#write_lock` is emitted, it must still load
  `LOCKED`; if the demand-driven generated compiler does not materialize it,
  the guard no longer fails on absence alone.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_runner_rawcopy_check
  --error-trace` -> exit 0, only the known `ld64.lld` stack-size warning.
- `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
  /tmp/cv2_runner_rawcopy_check` ->
  `p2_generated_stage2_no_prelude_puts_guard_ok`.
- `regression_tests/p2_pending_budget_no_prelude.sh
  /tmp/cv2_runner_rawcopy_check` ->
  `p2_pending_budget_no_prelude_ok process_delta=3 emit_delta=4
  lower_missing_delta=44 total=92 max_queue=57`.
- `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
  /tmp/cv2_runner_rawcopy_check` -> `p2_bootstrap_semantic_emit_oracle_ok`.
- `regression_tests/p2_each_index_block_param_no_prelude.sh
  /tmp/cv2_runner_rawcopy_check` -> `p2_each_index_block_param_no_prelude_ok`.
- `bash -n regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh`
  and `git diff --check` -> exit 0.

Boundary: this is a root fix for the bootstrap-critical CLI command/link tail.
It is not a general fix for all nilable-return lowering, all `out` arg
lowering, `Time#<=>`, or `FileUtils.cp` in arbitrary code. Those remain
separate compiler/runtime follow-ups if they appear outside this tail.
{F/G/R: 0.94/0.62/0.94} [verified]

[LM-518|verified]: Lowered constant truthiness must prune dead branch bodies,
not just emit a constant branch terminator.

Findings:

- `responds_to?` can become a Bool literal only after expression lowering.
  The previous `lower_if` static path only handled AST-literal conditions, and
  `lower_condition_branch` always emitted a `Branch` even when the lowered
  condition was a constant Bool.
- The first fix converted constant lowered conditions to direct `Jump`, but a
  hostile no-prelude oracle still failed for `dynamic && x.responds_to?(:object_id)`:
  `lower_if` had already created `then_block` and unconditionally lowered the
  then body, leaving an unreachable `Int32#object_id` call in HIR.
- The root fix is to preserve condition side effects, compute CFG reachability
  after condition lowering, and for no-`elsif` `if` expressions lower only the
  reachable body when exactly one body block is reachable. This keeps dead
  `responds_to?` branches from becoming source demand.
- A refuted adjacent experiment: treating exact `Proc#call` as backend-owned
  removed that name from the top missing summary but changed full-source
  `lower_missing.initial` by only one function (`+25104` -> `+25103`) and was
  reverted. It is not the current lower-missing root.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_static_truthy_if
  --error-trace` -> exit 0.
- `regression_tests/p2_static_truthy_dead_branch_no_prelude.sh
  /tmp/cv2_static_truthy_if` ->
  `p2_static_truthy_dead_branch_no_prelude_ok lower_missing_delta=0`.
- The focused HIR for `dynamic && x.responds_to?(:object_id)` has no
  `Int32#object_id` call; it emits a dynamic branch to the RHS block, the RHS
  lowers `responds_to?` to `false`, and jumps to the else block.
- `regression_tests/p2_pending_budget_no_prelude.sh
  /tmp/cv2_static_truthy_if`,
  `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
  /tmp/cv2_static_truthy_if`,
  `regression_tests/p2_backend_intrinsic_boundary_no_prelude.sh
  /tmp/cv2_static_truthy_if`,
  `regression_tests/p2_each_index_block_param_no_prelude.sh
  /tmp/cv2_static_truthy_if`, and
  `regression_tests/p1_ir_shape_check.sh /tmp/cv2_static_truthy_if` all
  passed.
- Full-source `STOP_AFTER_HIR` exited 0 with
  `process_pending: 3146 -> 17177 (+14031)`,
  `emit_tracked_sigs: 17177 -> 17404 (+227)`,
  `lower_missing.initial: 17404 -> 42402 (+24998)`, and
  `lower_missing: 17404 -> 42732 (+25328)`.

Boundary: this is a verified root fix for lowered-constant dead-branch demand,
but not the final Hash/object-id corridor. Full-source logs still show
`Hash#entry_matches?` / union call-shape demand producing value-type
`object_id` missing targets; that is the next separate root to localize.
{F/G/R: 0.91/0.56/0.90} [verified]

[LM-519|verified]: `responds_to?(:object_id)` must be answered from the
Reference/value type hierarchy, not from the mutable function registry.

Findings:

- Full-source HIR after LM-518 still showed value-type `object_id` demand.
  Inspecting the dump found functions where `UInt32.responds_to?(:object_id)`
  had lowered to `literal true`, for example in `Hash(UInt32, Int32)#key_hash`.
- Focused minimal Hash programs were clean, which ruled out the source
  `Hash#key_hash` logic itself as the only root. The full compiler run had
  polluted the function registry with synthetic value-type `object_id`
  specializations; later `type_responds_to_method?` calls used
  `has_function_base?` and treated those synthetic entries as real method
  availability.
- `object_id` is a Reference primitive in Crystal. Value types such as
  `UInt32`, `Int32`, and `Tuple` must answer false regardless of whether a
  previous lowering pass has created a synthetic `Type#object_id` function.

Fix:

- `type_responds_to_method?` now handles instance `object_id` through the class
  parent chain: `Reference` and descendants answer true; `Object`/value
  hierarchies answer false. Other methods keep the existing lookup path.
- Added `p2_object_id_responds_to_semantics.sh`, which checks that
  `UInt32.responds_to?(:object_id)` lowers to false and emits no
  `UInt32#object_id`, while `String.responds_to?(:object_id)` still preserves
  the `Reference#object_id` path.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_object_id_semantics
  --error-trace` -> exit 0.
- `regression_tests/p2_object_id_responds_to_semantics.sh
  /tmp/cv2_object_id_semantics` -> `p2_object_id_responds_to_semantics_ok`.
- `regression_tests/p2_static_truthy_dead_branch_no_prelude.sh`,
  `p2_pending_budget_no_prelude.sh`, `p2_bootstrap_semantic_emit_oracle.sh`,
  `p2_backend_intrinsic_boundary_no_prelude.sh`,
  `p2_each_index_block_param_no_prelude.sh`, and `p1_ir_shape_check.sh` all
  passed with `/tmp/cv2_object_id_semantics`.
- Full-source `STOP_AFTER_HIR` exited 0; value-type `object_id` dropped out of
  the top missing summary. Phase stats were essentially unchanged:
  `lower_missing.initial: 17404 -> 42403 (+24999)` and
  `lower_missing: 17404 -> 42733 (+25329)`.

Boundary: this is a correctness/root fix for `responds_to?(:object_id)`
semantic pollution, not a bootstrap-volume fix. The next volume roots are now
visible as `Indexable#new`, `Proc#call`, HIR/MIR value initializers, and debug
helper demand in the initial missing-target sweep.
{F/G/R: 0.92/0.58/0.90} [verified]

## Active Strategy

- Main fast loop: `--no-prelude` oracles and focused STOP_AFTER_HIR budget
  checks.
- Integration gate: canonical `s1 -> s2b` must pass before any `s2 -> s3`
  attempt. The generated-stage2 no-prelude `puts 7` full-codegen/link guard is
  now green; next gate is broader no-prelude corpus emission/comparison.
- Rare full gate: `s1 -> s5b` plus normalized HIR/MIR/LL equality.
- Do not run `s3b+` until generated `s2b` passes the fixed no-prelude corpus and
  normalized `s1_bootstrap` vs `s2b` semantic comparison.

[LM-521|verified]: known emitted LLVM SSA type must dominate stale MIR/def type
hints when adapting call arguments.

Findings:

- After LM-520, canonical `s1 -> s2` no longer timed out but `llc` rejected
  the generated stage2 LLVM IR: `%eq_ptr_to_fp.158.bits64 = ptrtoint ptr %r685
  to i64` while `%r685` was defined as `double`.
- The failing instruction came from the call-argument formatter's
  `eq_ptr_to_fp` path, not from the generic `BinaryOp` comparison lowering.
  In the `expected_llvm_type == actual_llvm_type` branch, `value_ref(a)` can
  return an SSA value whose actual emitted LLVM type is already recorded in
  `@emitted_value_types`.
- The bug was an evidence ordering problem: an older `find_def_inst(a).type`
  hint still said `ptr`, and the formatter used that stale fact to force a
  packed-scalar `ptrtoint` decode even when the newer emitted-type fact said
  the actual SSA value was already `double`.

Fix:

- Split `known_emitted_actual` from the fallback `emitted_actual`.
- Decode packed pointer scalar bits for float/double arguments only when the
  known emitted SSA type is `ptr`, or when no emitted-type fact exists and the
  stale def-type hint is the only available evidence.
- This preserves the existing packed scalar ABI path while preventing
  `ptrtoint ptr` from being emitted against known `float`/`double` SSA values.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_arg_fp_known_type
  --error-trace` -> exit 0.
- `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
  /tmp/cv2_arg_fp_known_type`,
  `regression_tests/p2_nested_generic_new_inference.sh
  /tmp/cv2_arg_fp_known_type`,
  `regression_tests/p2_backend_intrinsic_boundary_no_prelude.sh
  /tmp/cv2_arg_fp_known_type`,
  `regression_tests/p2_pending_budget_no_prelude.sh
  /tmp/cv2_arg_fp_known_type`,
  `regression_tests/p2_universal_helper_fanout_no_prelude.sh
  /tmp/cv2_arg_fp_known_type`,
  `regression_tests/p2_object_id_responds_to_semantics.sh
  /tmp/cv2_arg_fp_known_type`,
  `regression_tests/p1_ir_shape_check.sh /tmp/cv2_arg_fp_known_type`, and
  `regression_tests/abstract_class_method_dispatch_synth.sh` all passed.
- Canonical `s1 -> s2`:
  `BOOTSTRAP_STAGE_OUT=/tmp/cv2_bs_s2_arg_fp_known
  BOOTSTRAP_CHAIN_STAGES=2 BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
  scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_arg_fp_known` built stage2 successfully:
  `STAGE 2 BUILD: ok wall=215.71s peak_rss≈2342.52MB`.

Boundary: generated `s2` now builds, but both smoke tests abort immediately
during parser setup with
`STUB CALLED: Adamas$CCCompiler$CCFrontend$CCNode$Hspan`. That is the next
runtime/vdispatch frontier; no `s2 -> s3` attempt yet.
{F/G/R: 0.92/0.62/0.91} [verified]

[LM-522|verified]: qualified alias-chain fallback must resolve compound alias
suffixes before tuple elements choose scalar vs pointer lowering.

Findings:

- The generated `s2` `File.new_internal` smoke crash was caused by tuple
  element zero from `Crystal::System::File.open` being observed as
  `File::FileDescriptor::Handle` instead of `Int32`.
- Alias registration only indexed the final leaf suffix (`Handle`), and
  contextual alias lookup rejected names containing `::`. As a result,
  `resolve_type_alias_chain("File::FileDescriptor::Handle")` returned the
  unresolved qualified name even though the canonical registered alias was
  `Crystal::System::FileDescriptor::Handle => Int32`.
- LLVM then treated the tuple element as pointer-shaped and emitted `load ptr`
  from the tuple slot followed by `load i32` from the fd value. The actual tuple
  producer stored `{i32 fd, i1 close_on_finalize}`, so the generated compiler
  dereferenced small fd integers as pointers.

Fix:

- `register_type_alias` now indexes every proper trailing suffix, including
  compound keys such as `FileDescriptor::Handle`.
- Qualified alias-chain fallback now checks compound suffix aliases only. It
  deliberately avoids leaf-only fallback for qualified names so `Foo::Handle`
  cannot bind to an unrelated unique platform handle alias.
- Added `p2_file_open_tuple_handle_alias_shape.sh`, a full-prelude compile-only
  LLVM shape guard for `File.new_internal`.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_alias_suffix --error-trace`
  passed.
- `regression_tests/p2_file_open_tuple_handle_alias_shape.sh
  /tmp/cv2_alias_suffix` passed and showed scalar `load i32` in
  `File.new_internal`.
- `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
  /tmp/cv2_alias_suffix`, `regression_tests/p2_pending_budget_no_prelude.sh
  /tmp/cv2_alias_suffix`, `regression_tests/p2_universal_helper_fanout_no_prelude.sh
  /tmp/cv2_alias_suffix`, and `regression_tests/p1_ir_shape_check.sh
  /tmp/cv2_alias_suffix` passed.
- Canonical `s1 -> s2`:
  `BOOTSTRAP_STAGE_OUT=/tmp/cv2_bs_s2_alias_suffix
  BOOTSTRAP_CHAIN_STAGES=2 BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
  scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_alias_suffix` built stage2 successfully:
  `STAGE 2 BUILD: ok wall=225.41s peak_rss≈2385.45MB`.

Boundary: generated `s2` smoke tests still abort immediately, but the frontier
moved. Full-prelude smoke now hits
`NamedTuple(Span, ExprId, ExprId)#[](Symbol)`; no-prelude smoke hits
`CLI#debug_cli_root_block_state(String, AstArena, Array(ExprId))`. No `s3+`
attempt yet.
{F/G/R: 0.93/0.66/0.92} [verified]

[LM-523|verified]: NamedTuple generic annotation keys must be preserved before
generic type-parameter resolution.

Findings:

- Generated `s2` full-prelude smoke aborted in an unlowered
  `NamedTuple(Span, ExprId, ExprId)#[](Symbol)` stub while compiling parser
  macro-if branch handling.
- The source shape is keyed:
  `Array(NamedTuple(span: Span, condition: ExprId, body: ExprId))`, followed by
  `branch[:condition]`.
- `type_ref_for_name_inner` split `NamedTuple(span: Span, condition: ExprId,
  body: ExprId)` into raw generic parameters, then resolved the whole
  `key: Type` entry as a type name before the NamedTuple-specific parser ran.
  For namespaced value types this erased the keys and materialized positional
  `NamedTuple(Span, ExprId, ExprId)`.

Fix:

- Added a shared generic-parameter resolver for ordinary type arguments.
- For `NamedTuple`, parse each `key: Type` entry first, resolve only the value
  type, then rebuild `key: resolved_type` before descriptor materialization.
- Added `p2_named_tuple_annotation_keys_no_prelude.sh`, a no-prelude reducer
  with namespaced `Span`/`ExprId` that rejects keyless
  `NamedTuple(...Span, ...ExprId...)#[](Symbol)` HIR and requires `index_get`.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_namedtuple_keys
  --error-trace` passed.
- `regression_tests/p2_named_tuple_annotation_keys_no_prelude.sh
  /private/tmp/cv2_namedtuple_keys` passed.
- Negative control against `/tmp/cv2_alias_suffix` failed as expected with the
  old keyless `NamedTuple(...Span, ...ExprId...)#[](Symbol)` call.
- `regression_tests/p2_file_open_tuple_handle_alias_shape.sh
  /private/tmp/cv2_namedtuple_keys`,
  `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
  /private/tmp/cv2_namedtuple_keys`,
  `regression_tests/p2_pending_budget_no_prelude.sh
  /private/tmp/cv2_namedtuple_keys`,
  `regression_tests/p2_universal_helper_fanout_no_prelude.sh
  /private/tmp/cv2_namedtuple_keys`, and
  `regression_tests/p1_ir_shape_check.sh /private/tmp/cv2_namedtuple_keys`
  passed.
- Canonical `s1 -> s2`:
  `CRYSTAL_CACHE_DIR=/private/tmp/crystal_cache_v2_nt_boot
  BOOTSTRAP_STAGE_OUT=/private/tmp/cv2_bs_s2_namedtuple_keys
  BOOTSTRAP_CHAIN_STAGES=2 BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
  scripts/build_bootstrap_stages.sh --stages 2 --out
  /private/tmp/cv2_bs_s2_namedtuple_keys` built stage2 successfully:
  `STAGE 2 BUILD: ok wall=214.41s peak_rss≈2380.64MB`.
- The generated `/private/tmp/cv2_bs_s2_namedtuple_keys/cv2_s2.ll` no longer
  contains the keyless parser-branch NamedTuple `#[](Symbol)` stub.

Boundary: generated `s2` smoke tests still abort immediately, but both
full-prelude and no-prelude now hit
`CLI#debug_cli_root_block_state(String, AstArena, Array(ExprId))`. No `s3+`
attempt yet.
{F/G/R: 0.94/0.66/0.93} [verified]

[LM-524|verified]: `Proc#call` is backend-owned demand boundary, not a source
HIR materialization target.

Findings:

- HIR lowers proc receiver calls to explicit `Call(..., "Proc#call", ...)` so
  MIR can select heap Proc dispatch with `call_heap_proc`.
- Before the fix, a tiny no-prelude reducer left `Proc#call` in HIR and also
  reported `Proc#call` in the missing-source demand summary. That is the wrong
  boundary: the call is intentionally visible for backend lowering, not a
  request to materialize a source-level stdlib body.
- The backend-owned runtime-call filter now includes `Proc#call`,
  `Proc#call$...`, and `Proc#call(...)`, while deliberately not matching
  arbitrary `#call` methods.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_proc_call_boundary
  --error-trace` passed.
- `regression_tests/p2_proc_call_backend_boundary_no_prelude.sh
  /private/tmp/cv2_proc_call_boundary` passed and verifies both sides of the
  invariant: `Proc#call` remains in HIR and does not appear in the missing
  source-demand log.
- `regression_tests/p2_backend_intrinsic_boundary_no_prelude.sh
  /private/tmp/cv2_proc_call_boundary`,
  `regression_tests/p2_pending_budget_no_prelude.sh
  /private/tmp/cv2_proc_call_boundary`, and
  `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
  /private/tmp/cv2_proc_call_boundary` passed.
- Full-source `STOP_AFTER_HIR` measurement with missing summaries still exits
  0 but reports `lower_missing: 615 -> 35892 (+35277) in 166338.1ms`.

Boundary: this fix removes a real false demand edge, but it is not the
remaining bootstrap fanout root. The next root-cause corridor is still the
supply-driven `Hash` / `Array` / `Hash::Entry` materialization family.
{F/G/R: 0.92/0.58/0.91} [verified]

[LM-525|verified]: generated `s2b` no-prelude smoke now passes after fixing
backend alloca/name/string-constant state boundaries.

Findings:

- Generated stage2 first emitted invalid LLVM for the fixed no-prelude
  interpolation oracle: duplicate `%r3` / `%r5` allocas in `__crystal_main`.
  Root: `emit_hoisted_allocas` emitted MIR stack `Alloc` slots at `fn_entry`,
  then the buffered block-IR alloca splitter hoisted the same alloca lines
  again when generated stage2 missed the `@emitted_allocas` guard.
- After de-duplicating names already emitted by the entry prepass, the frontier
  moved to `%0.conv1`, an invalid derived local name. Root: interpolation temp
  names derived suffixes from `name.lstrip('%')`, which is unsafe for numeric
  LLVM locals. The string interpolation path now uses a helper that strips one
  leading percent and prefixes digit-leading bases.
- After that, the frontier moved to undefined `@.str.0`. Root: generated s2
  discovered string constants during function emission, but the final tail
  emission read a Hash-backed table that had lost those entries. String
  constants now keep parallel arrays as the authoritative ordered table and
  retain the Hash only as a cache.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_string_table_arrays
  --error-trace` passed.
- `regression_tests/p2_no_prelude_unique_alloca_names.sh
  /private/tmp/cv2_string_table_arrays`,
  `regression_tests/p2_bootstrap_semantic_emit_oracle.sh
  /private/tmp/cv2_string_table_arrays`, and
  `regression_tests/p2_pending_budget_no_prelude.sh
  /private/tmp/cv2_string_table_arrays` passed.
- Canonical `s1 -> s2`:
  `BOOTSTRAP_STAGE_OUT=/private/tmp/cv2_bs_s2_string_table_arrays
  BOOTSTRAP_CHAIN_STAGES=2 BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
  scripts/build_bootstrap_stages.sh --stages 2 --out
  /private/tmp/cv2_bs_s2_string_table_arrays` built stage2 successfully:
  `STAGE 2 BUILD: ok wall=234.69s peak_rss≈2421.55MB`, with
  `smoke no-prelude: ok`.
- The new guard also passes when run directly against generated
  `/private/tmp/cv2_bs_s2_string_table_arrays/cv2_s2`.

Boundary: generated `s2b` full-prelude smoke still fails with SIGBUS
immediately after `prelude exists`; no `s2 -> s3` attempt yet.
{F/G/R: 0.94/0.68/0.93} [verified]

[LM-526|verified]: splat/default overload selection must reuse the
pre-default concrete entry for packing.

Findings:

- `apply_default_args` forced `call_has_named_args=true`, which let positional
  calls match overloads with required named-only parameters and also discarded
  the concrete overload chosen before default expansion.
- Splat packing then re-resolved from the generic base after defaults were
  appended, while the first scalar argument had not yet been packed into the
  tuple splat slot. In self-host MIR this produced wrong scalar wrappers such
  as `Dir.glob$String` / `Dir.glob$String_File::MatchOptions_Bool`.
- The fix preserves the real named-argument signal and returns the selected
  overload name from `apply_default_args`; `pack_splat_args_for_call` receives
  that name and packs against the same entry.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_commit_candidate
  --error-trace` passed.
- `regression_tests/p2_splat_default_args_no_prelude.sh
  /private/tmp/cv2_commit_candidate` passed.
- The negative control with an older compiler emitted `func @collect$Int32`;
  the fixed compiler emits `func @collect$Tuple(Int32)_Int32`.
- `regression_tests/p2_selfhost_stage2_shape_guard.sh
  /private/tmp/cv2_commit_candidate` passed and rejects the old bad
  `Dir.glob$String` wrappers.

Boundary: this removes the self-host `Dir.glob` shape bug but does not solve
the remaining full-prelude private-constant parser/deferred-constant frontier.
{F/G/R: 0.91/0.62/0.90} [verified]

[LM-527|verified]: raw C callback Proc values need carrier provenance through
class variables.

Findings:

- `LibGC.get_push_other_roots : ->` returns a raw function pointer callback,
  but after storing it in `@@prev_push_other_roots`, MIR lost the carrier
  provenance and lowered `@@prev_push_other_roots.call` as heap Proc dispatch.
- The generated LLVM loaded a function pointer from offset 0 of the raw code
  pointer and crashed in the GC push-root callback path with SIGBUS.
- MIR now builds a Proc carrier index across HIR functions, propagates raw
  carriers through extern calls, copies/casts/union wraps, and records carrier
  state for classvar set/get. `Proc#call` uses raw `call_indirect` for
  `RawFnptrCallback` and keeps heap dispatch for `HeapProcObject`.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_commit_candidate
  --error-trace` passed.
- `regression_tests/p1_mixed_proc_block_yield_carrier.sh
  /private/tmp/cv2_commit_candidate` passed.
- Canonical `s1 -> s2` with the Proc-carrier fix built stage2 and the
  full-prelude smoke moved past the previous `GC_set_push_other_roots` SIGBUS
  to a visibility/private-constant validation failure.

Boundary: the carrier propagation is still pragmatic side-map provenance, not
the full explicit block-carrier contract; alias/dataflow gaps remain tracked in
the closure carrier plan.
{F/G/R: 0.88/0.55/0.88} [verified]

[LM-528|verified]: generated `s2` visibility failure is actually an uppercase
constant parser/deferred-constant frontier.

Findings:

- The full-prelude smoke after the Proc-carrier fix fails on
  `src/stdlib/int.cr:673`: `private DIGITS_DOWNCASE = ...`.
- A fast no-prelude generated-`s2` oracle with `private VALUE = 1` reproduces
  the same `can't apply visibility modifier` failure.
- Hostile diagnostics showed the visibility wrapper inner expression is an
  assignment whose target is treated as an identifier in generated `s2`, not a
  constant. Attempts to force uppercase recognition moved the self-host build
  into deferred-constant/lower_main failures, so a broad visibility allowlist
  would be a symptom patch.

Evidence:

- Failing generated-`s2` oracle:
  `scripts/run_safe.sh /private/tmp/cv2_bs_s2_commit_candidate/cv2_s2
  10 1024 /private/tmp/cv2_private_const_commit_candidate/private_const.cr --no-prelude
  --emit hir --no-link ...` reports `can't apply visibility modifier` for
  `private VALUE = 1`.
- Detail run identified the full-prelude source:
  `path=src/stdlib/int.cr span=673:3-673:45 snippet=private DIGITS_DOWNCASE`.
- Parser constant-name experiments are intentionally not part of the green
  commit because they expose the next root instead of fixing it.

Boundary: next work should fix parser constant classification and deferred
constant initializer ownership together, with a generated-`s2` no-prelude
oracle for `private VALUE = 1`.
{F/G/R: 0.86/0.50/0.86} [verified]

[LM-529|verified]: Crystal String payload search helpers must be bounded, not
`strstr`-based.

Findings:

- Crystal String payloads are length-delimited and not NUL-terminated, but the
  V2 LLVM backend emitted `String#includes?(String)` and
  `String#index(String, offset)` helpers that called libc `strstr` on
  `self + 12` / `search + 12`.
- Generated `cv2_s2` exposed this during compiler self-host lookup filters
  searching for `"$$block"`: no-prelude private-class lowering crashed in
  `lookup_function_def_for_call -> String#includes?` before reaching the
  actual method/Hash-demand frontier.
- The backend now emits bytesize-bounded `memcmp` loops for both helpers and
  returns false/-1 for null operands. Two `lower_call` hot guards also bind
  `full_method_name` to an explicit local before calling `includes?('#')`,
  because generated stage2 can still pass a null String receiver through
  chained nilable guards.

Evidence:

- `crystal build src/adamas.cr -o
  /private/tmp/cv2_string_nullsafe_candidate --error-trace` passed.
- `regression_tests/p2_string_bounded_search_runtime_repro.sh
  /private/tmp/cv2_string_nullsafe_candidate` passed.
- `regression_tests/p2_visibility_modifier_semantics_no_prelude.sh
  /private/tmp/cv2_string_nullsafe_candidate` passed.
- `scripts/run_safe.sh /private/tmp/cv2_string_nullsafe_candidate 300 4096
  src/adamas.cr -o /private/tmp/cv2_s2_string_nullsafe` built generated
  stage2.

Boundary: this fixes the unsafe String-search helper root and hardens two
compiler hot guards, but does not claim the broader nilable short-circuit
codegen issue is solved. Generated `cv2_s2` now moves the simple
`String#includes?("$$block")` and `private class Hidden` no-prelude reducers
past String segfaults and stops at existing Hash stubs (`Hash#each` /
`Hash(String, Array(Tuple(String, Crystal::MIR::Function)))#<<$String`).
{F/G/R: 0.89/0.56/0.89} [verified]

[LM-530|verified]: generated-stage2 overload lookup and lazy enum no-prelude
frontiers are distinct root causes, not Hash/Set method gaps.

Findings:

- Generated `s2` lowered some hot `lookup_function_def_for_call` fallback
  calls to the no-arg `@function_def_overloads` ivar getter instead of the
  two-arg helper, then treated the returned Hash as an `Array(String)` local.
  This produced `Hash#each` / `Hash(String, Array(...))#<<` abort stubs.
- Renaming those hot fallback calls through `function_def_overload_keys`
  removes the helper/getter basename collision from that generated path.
- The next private-class reducer crash was a nil `@lazy_enum_searched` ivar:
  the lazy enum trackers were declared with inline defaults but were not part
  of the explicit AstToHir constructor/reset recovery path that generated
  stage2 needs for the large AstToHir object.
- After explicit initialization, the reducer advanced to `Dir.glob` via lazy
  enum source discovery. That scan is invalid under `--no-prelude`; ordinary
  classes should not trigger source-sibling enum recovery when no prelude graph
  is loaded.

Evidence:

- `crystal build src/adamas.cr -o
  /private/tmp/cv2_lazy_enum_noprelude_candidate --error-trace` passed.
- `scripts/run_safe.sh /private/tmp/cv2_lazy_enum_noprelude_candidate 300 4096
  src/adamas.cr -o /private/tmp/cv2_s2_lazy_enum_noprelude` built
  generated stage2.
- Generated stage2 compiled both no-prelude reducers:
  `"Hidden.new".includes?("$$block")` and `private class Hidden; def value :
  Int32; 1; end; end; Hidden.new.value`.

Boundary: this does not claim the global AstToHir inline-default ivar problem
is solved. It fixes the lazy enum state that was missing from the existing
explicit constructor/reset corridor and records the broader pattern in
`WEIRD_CODE_NOTES.md`.
{F/G/R: 0.90/0.56/0.90} [verified]

[LM-531|verified]: Qualified extern-call type suffixes are argument
specializations, not return-type evidence.

Findings:

- The reducer `Array(Box)#unsafe_fetch$Int32` had HIR/MIR return `Box`/`ptr`,
  but LLVM `emit_extern_call` treated `$Int32` as a return hint, emitted
  `call i32`, and the missing-body pass synthesized an abort stub for
  `Array$LBox$R$Hunsafe_fetch$$Int32`.
- The fix restricts suffix-return hints to bare primitive extern helpers
  (`unsafe_shl`, `unsafe_shr`, `unsafe_div`, `unsafe_mod`), where the suffix
  denotes operation/result width instead of a qualified method argument.
- The missing-body pass now has a generic top-level
  `Array(T)#unsafe_fetch(Int32)` late primitive body. It derives the element ABI
  from the `Array(T)` owner and loads `@buffer[@offset_to_buffer + index]`.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_array_fetch_candidate
  --error-trace` passed.
- `regression_tests/p2_array_class_ref_unsafe_fetch_no_prelude.sh
  /tmp/cv2_array_fetch_candidate` passed.
- `regression_tests/p2_array_struct_unsafe_fetch_return_no_prelude.sh
  /tmp/cv2_array_fetch_candidate` passed.
- Generated LLVM for the reducer contains
  `call ptr @Array$LBox$R$Hunsafe_fetch$$Int32` and
  `define ptr @Array$LBox$R$Hunsafe_fetch$$Int32`, with no abort stub.
- `regression_tests/p2_generated_stage2_lookup_lazy_enum_no_prelude.sh
  /tmp/cv2_array_fetch_candidate` passed.

Boundary: this fixes the backend extern/stub ABI root for direct
`Array(T)#unsafe_fetch(Int32)`, not all collection method materialization gaps.
{F/G/R: 0.94/0.68/0.94} [verified]

[LM-532|verified]: `elsif` conditions need the same short-circuit condition
lowering as the main `if` condition.

Findings:

- Generated `s2` crashed in full-prelude smoke before pass1 registration by
  calling `String#empty?` on a null `name` inside
  `MacroExpander#resolve_scoped_macro_value`.
- The generated LLVM for
  `MacroExpander#evaluate_to_macro_value` showed the source condition
  `elsif name && constant_like_name?(name)` was lowered as a value-level `&&`;
  `constant_like_name?` was called and its result was discarded, then
  `resolve_scoped_macro_value(name, context)` was reached even on the
  `name == nil` path.
- The root was an asymmetry in `lower_if`: the main `if` condition routed
  `&&`/`||` through `lower_short_circuit_condition`, but each `elsif`
  condition used `lower_expr` plus a later truthiness check.
- The fix creates the `elsif` body/next blocks before lowering the condition
  and routes `&&`/`||` through `lower_short_circuit_condition`.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_elsif_sc_candidate
  --error-trace` passed.
- `regression_tests/p2_elsif_short_circuit_condition_no_prelude.sh
  /tmp/cv2_elsif_sc_candidate` passed.
- `scripts/build_bootstrap_stages.sh --stages 2 --out /tmp/cv2_bs_s2_elsif`
  built `s2` in 238s and passed no-prelude smoke. The previous
  `String#empty?` null crash disappeared; plain smoke now advances to the next
  independent frontier:
  `AstToHir#extract_alias_name_value_from_source(AliasNode, ArenaLike)` stub
  during `LibC` registration.
- New `s2` LLVM for `evaluate_to_macro_value` branches on
  `constant_like_name?` before calling `resolve_scoped_macro_value`, and the
  nil path no longer reaches that call.

Boundary: this fixes condition-context lowering for short-circuiting `elsif`
conditions. It does not claim all value-level nilable `&&`/`||` semantics are
fully audited; keep adding focused no-prelude oracles when those forms appear
as runtime values rather than branch conditions.
{F/G/R: 0.93/0.72/0.93} [verified]

[LM-533|verified]: Source-backed extern registration must not expose
stage2 helper calls through redundant `ArenaLike` or mixed nilable lib-name
specializations.

Findings:

- After the `elsif` fix, generated `s2` full-prelude smoke advanced to
  `LibC` registration and aborted on
  `AstToHir#extract_alias_name_value_from_source(AliasNode, ArenaLike)`.
  Adding that helper to the exact-demand corridor moved the frontier to
  `register_extern_fun_from_source`.
- `register_extern_fun_from_source` had a redundant `arena : ArenaLike`
  parameter even though its only caller passed the current `@arena`. Removing
  that ABI dimension moved the frontier to
  `resolve_extern_fun_signature_from_source`.
- The signature resolver mixed lib and top-level extern contexts via
  `lib_name : String?`. Generated stage2 emitted a concrete `$String...` call
  for the lib path, while overload lookup resolved the body to the broader
  `$Nil | String...` target. Lowering materialized the broader target, leaving
  the concrete `$String...` symbol as an abort stub.
- The fix splits lib and top-level source signature resolution: lib externs
  use a `String`-typed resolver, top-level `fun` declarations use a separate
  resolver with no `lib_name` parameter, and the source helper family reads
  `@arena` internally instead of threading `ArenaLike` through generated-stage2
  helper signatures.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_source_extern_split_candidate
  --error-trace` passed.
- `regression_tests/p2_source_extern_signature_no_prelude.sh
  /tmp/cv2_source_extern_split_candidate` passed.
- `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_source_extern_split` built `s2` in 240s and passed
  no-prelude smoke. The previous alias/external-source abort stubs disappeared;
  full-prelude smoke now advances to the next independent frontier:
  `Hash(String, Hash(UInt32, Crystal::HIR::Value))#to_unsafe` during
  `LibC` registration.

Boundary: this fixes the source-backed lib extern registration helper ABI and
the concrete-vs-nilable lib-name specialization mismatch. It does not solve
the broader rule that a concrete call symbol resolved to a broader typed
overload may still need an explicit requested-symbol wrapper.
{F/G/R: 0.91/0.66/0.91} [verified]

[LM-534|verified]: Stage2 lib registration advanced past invalid
parser-slice/visibility receiver calls by restoring explicit typed boundaries.

Findings:

- Generated `s2` previously aborted during full-prelude plain smoke with
  `Hash(String, Hash(UInt32, Crystal::HIR::Value))#to_unsafe` while registering
  `LibC`. HIR tracing showed the bad call was frozen during stage2 HIR
  lowering, not only in LLVM.
- The source site was `safe_str_guard(member.name, ...)` in broad AST
  registration paths. The macro inlined pointer validation and called
  `.to_unsafe` at the broad callsite, where generated stage2 had lost
  branch-local Slice narrowing.
- Moving validation into `safe_slice_guard?(slice : Slice(UInt8))` preserves a
  typed helper boundary while leaving the macro responsible only for control
  flow (`next`/`return`).
- The next generated `s2` full-prelude smoke exposed
  `Hash(... )#null_ptr?` in `unwrap_visibility_member_in_arena`. LL showed
  `current.expression` lowered as virtual `Node#expression` despite the
  surrounding `is_a?(VisibilityModifierNode)` check. Explicit
  `current.unsafe_as(VisibilityModifierNode)` after the check forces the
  concrete accessor and removes the invalid receiver.
- The following crash in `parse_macro_literal_lib_body` came from
  `program.roots.map { |id| parsed_arena[id] }.find(&.is_a?(LibNode))`.
  Reparsed macro helpers now validate root ids, use `arena.[]?`, and select
  Lib/Class/Def roots with explicit `node_kind` loops instead of block-heavy
  `map/find` chains.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_final_boundary_candidate
  --error-trace` passed.
- `ADAMAS_STOP_AFTER_HIR=1 DEBUG_CALL_TRACE='to_unsafe,null_ptr'
  scripts/run_safe.sh /tmp/cv2_final_boundary_candidate 300 4096
  src/adamas.cr -o /tmp/cv2_final_boundary_s2_hir` exited 0; grep found
  no `Hash(String, Hash(UInt32, Crystal::HIR::Value))#to_unsafe` or
  `Hash(String, Hash(UInt32, Crystal::HIR::Value))#null_ptr?`.
- `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_reparsed_roots` built `s2` and passed no-prelude smoke. Plain
  smoke advanced to a new frontier:
  `MacroNumberValue.numeric_suffix` during `LibC` macro condition evaluation.

Boundary: this is a compiler-boundary hardening commit, not a general closure
or block-carrier fix. A speculative `numeric_suffix` rewrite from
`Array#find` to `while + unsafe_fetch` was refuted because it regressed s2
build to an earlier corrupted `ExprId` failure.
{F/G/R: 0.92/0.62/0.92} [verified]

[LM-535|verified]: MacroNumberValue numeric suffix lookup must avoid
Array/block machinery during generated-stage2 macro condition evaluation.

Findings:

- After LM-534, generated `s2` full-prelude plain smoke reached
  `MacroNumberValue.numeric_suffix` while evaluating a `LibC` macro condition.
  LLDB showed a null dereference inside `numeric_suffix` before returning to
  `MacroNumberValue.from_literal`.
- The generated LL for the original `["_i8", ...].find { |candidate|
  literal.ends_with?(candidate) }` had already been expanded into an
  Array(String) loop, but its loop cursor alloca was never initialized before
  the first load. The crash happened before the first semantic
  `String#ends_with?` check.
- A first local rewrite to `while idx < suffixes.size; suffixes.unsafe_fetch`
  was refuted: it still used an Array and regressed s2 build to an earlier
  corrupted `ExprId` lower_main failure.
- The accepted change keeps the same fixed suffix table and precedence, but
  spells it as direct `return suffix if literal.ends_with?(suffix)` checks.
  This removes Array allocation, block lowering, and iterator state from this
  bootstrap macro-evaluator path.

Evidence:

- `crystal build src/adamas.cr -o
  /tmp/cv2_numeric_suffix_chain_candidate --error-trace` passed.
- `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_numeric_suffix_chain` built `s2` in 235s and passed
  no-prelude smoke. The previous `MacroNumberValue.numeric_suffix` crash
  disappeared; plain smoke advanced to
  `resolve_lib_global_decl_from_source(Span, ArenaLike)` abort stub during
  `LibC` registration.

Boundary: this is a targeted fixed-table bootstrap hardening, not proof that
general `Array#find` or block lowering is fixed. Add a focused oracle before
claiming the broader iterator/block path.
{F/G/R: 0.90/0.55/0.90} [verified]

[LM-536|verified]: One-use lib global source recovery should not expose an
`ArenaLike` helper ABI boundary.

Findings:

- After LM-535, generated `s2` full-prelude plain smoke failed during `LibC`
  registration on an abort stub for
  `AstToHir#resolve_lib_global_decl_from_source(Span, ArenaLike)`.
- Adding the helper to the AstToHir exact-demand allowlist was refuted: `s2`
  still built successfully, but plain smoke hit the same stub. This ruled out a
  simple omitted-method-name explanation.
- The helper was only called from `resolve_lib_global_decl` and only passed the
  current `@arena`. Inlining source lookup/parsing into
  `resolve_lib_global_decl` removed the concrete-vs-broad helper symbol and
  kept the recovery logic on the already demanded caller.

Evidence:

- `crystal build src/adamas.cr -o
  /tmp/cv2_lib_global_inline_candidate --error-trace` passed.
- `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_lib_global_inline` built `s2` in 250s and passed no-prelude
  smoke. Full-prelude plain smoke advanced past complete `LibC` registration
  and now fails later during `Errno` enum registration on
  `detect_method_yield(DefNode, ArenaLike, Bool)`.

Boundary: this fixes a one-use source-recovery ABI boundary. It does not prove
that all remaining `ArenaLike` helpers should be inlined; each should be
checked against call count, exact-demand behavior, and whether it can read
`@arena` internally without changing semantics.
{F/G/R: 0.90/0.58/0.90} [verified]

[LM-537|verified]: The method-yield wrapper boundary, not yield scanning
itself, blocked generated-stage2 enum registration.

Findings:

- After LM-536, generated `s2` full-prelude plain smoke passed `LibC`
  registration and failed during `Errno` enum registration on an abort stub for
  `AstToHir#detect_method_yield(DefNode, ArenaLike, Bool)`.
- The wrapper only selected `def_contains_yield_from_source?` when source scan
  was preferred, then fell back to `def_contains_yield?`. The generated `s2.ll`
  already contained bodies for both underlying scanners, so the missing body
  was the wrapper boundary itself.
- Adding `detect_method_yield` to the AstToHir exact-demand allowlist was
  refuted: s2 still built, but plain smoke hit the same stub.
- Inlining the wrapper's source-scan/fallback selection at the three
  method-registration call sites removed the emitted wrapper symbol while
  preserving the existing scanner behavior.

Evidence:

- `crystal build src/adamas.cr -o
  /tmp/cv2_detect_yield_inline_candidate --error-trace` passed.
- `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_detect_yield_inline` built `s2` in 239s and passed
  no-prelude smoke. Full-prelude plain smoke advanced from
  `detect_method_yield(DefNode, ArenaLike, Bool)` to
  `record_phase0_body_infer_walk(DefNode, ArenaLike, ExprId?)` during `Errno`
  enum registration.

Boundary: this removes one self-host-sensitive wrapper boundary. It does not
claim all AstToHir wrappers should be inlined; use the same refutation-first
test before changing broader helper families.
{F/G/R: 0.90/0.56/0.90} [verified]

[LM-538|verified]: Phase0 body-inference identity metrics must be opt-in on
default bootstrap paths.

Findings:

- After LM-537, generated `s2` full-prelude plain smoke failed during `Errno`
  enum registration on `record_phase0_body_infer_walk(DefNode, ArenaLike,
  ExprId?)`.
- Inlining that metric wrapper was only partial progress: the next run moved
  to `canonical_def_identity_for_body_infer(DefNode, ArenaLike, ExprId?)`.
  This showed the exposed helper chain was diagnostic bookkeeping, not the
  semantic body-inference root.
- `@phase0_body_infer_counts` is only emitted when
  `ADAMAS_PHASE0_METRICS` is enabled, and the identity tracker exists only
  under `ADAMAS_IDENTITY_DRY_RUN`. Default bootstrap smoke needs neither.
- The fix computes canonical body-inference identity only when phase0 metrics
  or identity dry-run is enabled. Default compilation still infers return
  types, but no longer pays the diagnostic identity-helper cost.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_phase0_gated_candidate
  --error-trace` passed.
- `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_phase0_gated` built `s2` in 224s and passed no-prelude smoke.
  Full-prelude plain smoke advanced from the phase0 identity helper chain to
  the semantic body-inference frontier:
  `infer_concrete_return_type_from_body_inner(Array(ExprId), String, String,
  ArenaLike, Bool)`.

Boundary: opt-in `ADAMAS_PHASE0_METRICS` and
`ADAMAS_IDENTITY_DRY_RUN` paths still need their own targeted verification
before relying on body-inference identity counts under generated stage2.
{F/G/R: 0.91/0.62/0.90} [verified]

[LM-539|verified]: The prior-nil-guard body-inference shape is already covered
on clean `codegen`, and a broader local narrowing patch was refuted.

Findings:

- A focused no-prelude reducer for `value = maybe; return ExprId.new unless
  value; expr_id = value; expr_id` now guards that body/return inference keeps
  the helper return concrete (`ExprId`) and calls `consume$ExprId`, not a
  nilable overload.
- The reducer passes on clean HEAD (`48833dd4`) and on the dirty experiment,
  so it is useful as coverage but not evidence that the dirty implementation is
  required.
- The dirty implementation was refuted by a clean-vs-dirty full-source
  comparison: clean HEAD `ADAMAS_STOP_AFTER_HIR=1
  ADAMAS_PHASE_STATS=1 scripts/run_safe.sh /tmp/cv2_clean_head_candidate
  300 4096 src/adamas.cr -o /tmp/cv2_clean_head_stop_hir` exits 0 after
  about 145s, while the dirty narrowing patch exits 1 after about 34s with
  `ExprId out of bounds: 1684105331`.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_dirty_guard_candidate
  --error-trace` passed before the experiment was reverted.
- `regression_tests/p2_prior_nil_guard_infer_no_prelude.sh
  /tmp/cv2_clean_head_candidate` -> `p2_prior_nil_guard_infer_no_prelude_ok`.
- `regression_tests/p2_prior_nil_guard_infer_no_prelude.sh
  /tmp/cv2_dirty_guard_candidate` -> `p2_prior_nil_guard_infer_no_prelude_ok`.
- `regression_tests/p2_source_extern_signature_no_prelude.sh`,
  `p2_array_class_ref_unsafe_fetch_no_prelude.sh`,
  `p2_elsif_short_circuit_condition_no_prelude.sh`,
  `p2_visibility_modifier_semantics_no_prelude.sh`,
  `p2_pending_budget_no_prelude.sh`, and
  `p2_selfhost_stage2_shape_guard.sh` passed with the dirty compiler before
  the full-source adversary check refuted it.

Boundary: this lands only the no-prelude guard and refutation record. It does
not fix the current generated-stage2 semantic body-inference frontier.
{F/G/R: 0.92/0.50/0.92} [verified]

[LM-540|verified]: Generated stage2 now advances past the enum body-inference
frontier; the next plain-smoke crash is in module/class registration.

Findings:

- The previous generated-stage2 plain smoke frontier was not one bug. First,
  `infer_concrete_return_type_from_body` selected a nilable
  `Nil | ArenaLike` monomorphization for its inner helper; explicitly typing
  `resolved_arena` as `ArenaLike` and casting the recorded arena removed that
  abort-stub shape.
- After that, `Errno#message : String` still entered body inference in
  generated `s2` because the enum registration path could lose the explicit
  `return_type` field. Reusing `def_explicit_return_type_from_source` only for
  the enum/source-yield registration corridor recovers the annotation without
  reintroducing the broad-source fallback that previously regressed
  full-source `STOP_AFTER_HIR` to `ExprId out of bounds`.
- Once `Errno#message` is registered as `String`, the next failing enum method
  is `Errno#unsafe_message`, an unannotated yield method. Body-return inference
  has no caller block context there, so it must not eagerly walk the yield body;
  the registration path now falls back to `Void` for unannotated yield/block
  methods instead of inferring through the body.
- A separate `unique_enum_match_by_suffix` trap was exposed by
  `return nil if match` plus `next unless ...` inside a `Hash#each_key` block.
  Rewriting that helper to avoid non-local block `return` and block `next`
  removed the trap. The broader inlined-block `next` + non-local `return`
  local-state bug remains open; a generic `InlineNextContext` experiment was
  refuted by a no-prelude nested-iterator reducer and was not kept.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_enum_yield_skip_candidate
  --error-trace` passed.
- `regression_tests/p2_prior_nil_guard_infer_no_prelude.sh`,
  `regression_tests/p2_source_extern_signature_no_prelude.sh`, and
  `regression_tests/p2_pending_budget_no_prelude.sh` passed with
  `/tmp/cv2_enum_yield_skip_candidate`.
- `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_enum_yield_skip` built `s2` in ~225s and passed no-prelude
  smoke. Plain smoke still fails, but lldb shows it now advances through all
  enum registration and enum resolve before crashing in
  `register_module_with_name -> register_concrete_class ->
  infer_concrete_return_type_from_body_inner`.

Boundary: this is verified progress, not a green bootstrap. The next work item
is the module/class body-inference crash; do not claim `s2` plain smoke is
fixed until that stage passes under `scripts/run_safe.sh`.
{F/G/R: 0.91/0.58/0.90} [verified]

[LM-541|verified]: Registration-time body inference now skips defs that need
caller block context; generated stage2 advances past `Crystal::SpinLock`.

Findings:

- The module/class plain-smoke crash after LM-540 was `Crystal::SpinLock`, not
  a SpinLock-specific semantic issue. The failing methods are unannotated
  `sync(&)` / `unsync(&)` bodies that yield inside `begin/ensure`. Generic
  registration-time `infer_concrete_return_type_from_body` has no caller block
  return context, so walking those bodies can infer through an invalid block
  edge or crash generated stage2.
- The accepted fix is central, not a local class special case:
  `infer_concrete_return_type_from_body` now returns `nil` before body walking
  when `def_contains_yield?` or direct implicit `&block.call` is detected.
  Registration call sites then fall back to their existing conservative return
  types (`Void`, explicit annotations, query heuristics, or later demanded
  lowering).
- The first no-edit debug attempt was refuted as evidence: setting
  `DEBUG_INFER_CRASH`, `DEBUG_REG_CONCRETE_PHASE`, or
  `ADAMAS_TRACE_CLASS_FRONTIER` changes the generated-stage2 failure
  timing and can report older enum-looking crashes. lldb with redirected child
  stdout/stderr is the stronger signal for this frontier.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_yield_context_guard
  --error-trace` passed.
- `regression_tests/p2_yield_body_infer_no_prelude.sh`,
  `regression_tests/p2_prior_nil_guard_infer_no_prelude.sh`,
  `regression_tests/p2_source_extern_signature_no_prelude.sh`, and
  `regression_tests/p2_pending_budget_no_prelude.sh` passed with
  `/tmp/cv2_yield_context_guard`.
- `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_yield_context_guard` built `s2` in ~228s and passed
  no-prelude smoke. Plain smoke still fails. Redirected lldb shows the new
  frontier is
  `resolve_path_like_name_in_arena(ExprId, ArenaLike | String)` abort-stub
  during `record_nested_type_names -> collect_nested_type_names` at module
  register idx=3.

Boundary: this is verified progress, not a green bootstrap. The current
generated `s2` still fails full-prelude plain smoke; next work is the
`resolve_path_like_name_in_arena` stub/demand boundary.
{F/G/R: 0.90/0.62/0.90} [verified]

## LM-542 — Stage2 include-registration helper stubs advanced to alias-prefix tuple-hash crash

Context: compiler/bootstrap/codegen, 2026-04-30, `codegen`.

Verified:

- The `resolve_path_like_name_in_arena(ExprId, ArenaLike | String)` frontier
  was caused by `collect_nested_type_names` reading mutable `@arena` inside the
  recursive scanner. Threading an explicit `ArenaLike` from
  `record_nested_type_names` removed the wide `resolve_path_like_name_in_arena`
  symbol from generated `cv2_s2`.
- The next `remember_effect_annotation(...)` abort-stub was the same boundary
  class in a different form: generated stage2 did not preserve branch-local
  `AnnotationNode` narrowing at registration call sites. Explicit
  `unsafe_as(AnnotationNode)` plus `@arena.as(ArenaLike)` removed the wide
  annotation symbols.
- The next `debug_probe_include_call_boundary(...)` abort-stub was
  diagnostic-only work executing on the default path. Gating both include probe
  calls behind `DEBUG_REG_CONCRETE_PHASE` removed that default dependency.
- The next `register_module_instance_methods_for(...)` abort-stub came from the
  include-expansion caller materializing widened `ArenaLike?` / `Set(String)?`
  locals. Passing exact `ArenaLike` and `Set(String)` contracts produced real
  bodies for `register_module_instance_methods_for` and `include_type_param_map`.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_include_contract_candidate
  --error-trace` passed.
- `regression_tests/p2_yield_body_infer_no_prelude.sh`,
  `regression_tests/p2_prior_nil_guard_infer_no_prelude.sh`,
  `regression_tests/p2_source_extern_signature_no_prelude.sh`, and
  `regression_tests/p2_pending_budget_no_prelude.sh` passed with
  `/tmp/cv2_include_contract_candidate`.
- `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_include_contract` built `s2` in ~230s and passed
  no-prelude smoke. `nm` shows exact bodies for
  `resolve_path_like_name_in_arena`, `remember_effect_annotation`,
  `register_module_instance_methods_for`, and `include_type_param_map`.
- Redirected lldb now stops at `EXC_BAD_ACCESS` in
  `Hash(Tuple(String, Int32), String)#[]?` from
  `resolve_module_alias_prefix -> resolve_module_alias_for_include ->
  register_module_instance_methods_for`, not at an abort-stub.

Boundary: this is still not a green generated `s2`; the next root is the
`@module_alias_prefix_cache` tuple-key/hash crash. The old smoke-log tail can
still misleadingly stop near enum/lib registration; redirected child stderr and
lldb are the stronger frontier evidence.
{F/G/R: 0.91/0.64/0.90} [verified]

## LM-543 — Stage2 alias-cache tuple key and module-name block proc advanced

Context: compiler/bootstrap/codegen, 2026-04-30, `codegen`.

Verified:

- The alias-prefix frontier at LM-542 was not fixed with a module-name
  allowlist. The compiler-internal cache shape was changed from tuple keys
  (`Hash({String, String?, Int32}, String)` and
  `Hash({String, Int32}, String)`) to nested maps keyed by cache version,
  context string, and module name. This preserves the same cache dimensions
  while avoiding generated-stage2 tuple-key hash/equality in the bootstrap
  registration path.
- After the cache-shape change, redirected lldb advanced to
  `module_name_from_node -> safe_slice_to_string -> env_get` through a generated
  block proc. The root was the lambda plus `type_params.map { ... }.reject`
  helper in `module_name_from_node`; generated stage2 lost the captured
  `AstToHir` self in that proc. Rewriting the helper as a direct `while` scan
  removed the block-proc frontier.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_module_name_candidate
  --error-trace` passed.
- `regression_tests/p2_yield_body_infer_no_prelude.sh`,
  `regression_tests/p2_prior_nil_guard_infer_no_prelude.sh`,
  `regression_tests/p2_source_extern_signature_no_prelude.sh`, and
  `regression_tests/p2_pending_budget_no_prelude.sh` passed with
  `/tmp/cv2_module_name_candidate`.
- `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_module_name` built `s2` in ~237s and passed no-prelude smoke.
  Redirected lldb now stops at `Array(ExprId)#to_unsafe` from
  `body_ids_match_arena? -> def_body_nodes_match_arena? -> arena_fits_def? ->
  register_type_method_from_def`, not in alias-cache tuple hashing or the
  module-name block proc.

Boundary: this is still not a green generated `s2`. General tuple-key hashing
and block-proc capture remain open root families; this commit removes two
compiler-internal bootstrap dependencies on those incomplete paths. The next
frontier is the nil/corrupt-array guard in `body_ids_match_arena?`.
{F/G/R: 0.90/0.61/0.89} [verified]

## LM-544 — Stage2 arena body-id guard advanced to param iteration

Context: compiler/bootstrap/codegen, 2026-04-30, `codegen`.

Verified:

- The `body_ids_match_arena?` frontier was a nilable/corrupt array boundary in
  the arena-fit helper. The source had `body.nil?`, but generated stage2 still
  reached `Array(ExprId)#to_unsafe` through the nilable signature. Splitting
  the public nilable wrapper from `body_ids_match_arena_non_nil?` and making the
  non-nil helper guard low raw array pointers advanced the crash.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_body_ids_candidate
  --error-trace` passed.
- `regression_tests/p2_yield_body_infer_no_prelude.sh`,
  `regression_tests/p2_prior_nil_guard_infer_no_prelude.sh`,
  `regression_tests/p2_source_extern_signature_no_prelude.sh`, and
  `regression_tests/p2_pending_budget_no_prelude.sh` passed with
  `/tmp/cv2_body_ids_candidate`.
- `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_body_ids` built `s2` in ~235s and passed no-prelude smoke.
  Redirected lldb now stops in `each_param(Array(Parameter), &block)` from
  `register_concrete_class`, not in `body_ids_match_arena?`.

Boundary: generated `s2` full-prelude plain smoke still fails. The next root is
parameter-array iteration or block transport inside `each_param`, not arena
body-id matching.
{F/G/R: 0.90/0.58/0.88} [verified]

## LM-545 — Source-backed initializer parameter capture is safe, but plain s2 smoke still crashes later

Context: compiler/bootstrap/codegen, 2026-05-01, `codegen`.

Verified:

- The registration metadata corridor should not read `Parameter#name` and
  `Parameter#type_annotation` slices directly when the registration code has a
  member/source arena available. Extending `capture_initialize_params` to use
  source-backed `name_span` / `type_span` extraction preserves the existing
  initializer ivar capture behavior while avoiding another stale-slice read
  boundary in class/module registration.
- This is a root-cause-aligned arena/source fix, not a broad readable-address
  guard. The previously tested universal raw-slice guard remains refuted
  because it changed host no-prelude behavior and could produce corrupt method
  names.
- A generated `cv2_s2` still builds successfully after this change, so the
  source-backed parameter extraction does not regress the current stage2 build
  corridor.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_param_source_candidate
  --error-trace` passed.
- `regression_tests/p2_enum_class_setter_return_infer_no_prelude.sh`,
  `regression_tests/p2_nested_module_registration_no_prelude.sh`,
  `regression_tests/p2_bootstrap_semantic_emit_oracle.sh`, and
  `regression_tests/p2_visibility_private_accessor_no_prelude.sh` passed with
  `/tmp/cv2_param_source_candidate`.
- `scripts/run_safe.sh /tmp/cv2_param_source_candidate 300 4096
  src/adamas.cr -o /tmp/cv2_direct_param_source_candidate/cv2_s2` built
  generated `cv2_s2` in ~160s with `[EXIT: 0]`.
- The produced `cv2_s2` still fails the plain `puts 42` smoke in ~1s:
  module registration reaches `module register idx=3/53`, prints
  `[INFER_INDEX] method=initialize self=Exception::Exception::CallStack
  obj= idxs=1`, then exits with segfault 139.

Boundary: this commit is not a green generated-stage2 runtime checkpoint. The
next root remains inside full-prelude module/class registration around
`Exception::CallStack` and `each_param(Array(Parameter), &block)`. Continue with
source-backed registration reads and concrete no-prelude oracles; do not revive
the broad raw-slice guard.
{F/G/R: 0.91/0.58/0.89} [verified]

## LM-546 — Source-prefilter implicit ivar param scan advances CallStack registration

Context: compiler/bootstrap/codegen, 2026-05-01, `codegen`.

Verified:

- The remaining `each_param(Array(Parameter), &block)` crash after LM-545 was
  not in the primary method-signature registration path. Existing
  `DEBUG_REG_CONCRETE_PHASE=CallStack` showed `Exception::CallStack`
  registering all body defs, then crashing immediately after
  `after_untyped_reassert`, inside the later implicit-ivar discovery pass.
- That pass scanned every method's params looking for `def foo(@ivar : T)`.
  Generated stage2 can expose corrupt `Parameter` flags for ordinary untyped
  params, so trusting `param.is_instance_var` there over-demands stale
  parameter fields. The source header is the authoritative cheap prefilter:
  skip the param scan when the `def` header has no `@` parameter.
- The fix adds `def_header_has_instance_var_param?`, keeps old fallback only
  when source is unavailable, and reads real ivar-param names/types through
  source-backed `Parameter` spans. It also makes registration/capture paths
  explicitly source-only for parameter name/type extraction when an arena is
  known.

Evidence:

- `crystal build src/adamas.cr -o
  /tmp/cv2_ivar_param_source_candidate --error-trace` passed.
- Existing no-prelude guards passed:
  `p2_enum_class_setter_return_infer_no_prelude.sh`,
  `p2_nested_module_registration_no_prelude.sh`,
  `p2_bootstrap_semantic_emit_oracle.sh`, and
  `p2_visibility_private_accessor_no_prelude.sh`.
- New guard
  `regression_tests/p2_implicit_ivar_param_source_scan_no_prelude.sh
  /tmp/cv2_ivar_param_source_candidate` passed, proving
  `def initialize(@value : Int32)` still registers the field while a normal
  untyped method remains present in the same class.
- `scripts/run_safe.sh /tmp/cv2_ivar_param_source_candidate 300 4096
  src/adamas.cr -o /tmp/cv2_direct_ivar_param_source/cv2_s2` built
  generated `cv2_s2` in ~161s with `[EXIT: 0]`.
- With `DEBUG_REG_CONCRETE_PHASE=CallStack`, generated `cv2_s2` now reaches
  `after_implicit_ivar_scan`, `after_final_info`,
  `after_init_params_store`, and `after_new_register` before the next
  segfault. Fresh lldb shows the new crash is in
  `register_nested_module_in_current_arena` through a different `each_param`
  block proc, not the old `register_concrete_class` implicit-ivar scan.

Boundary: generated `s2` plain full-prelude smoke still fails. The frontier
moved past `Exception::CallStack` class finalization to nested module
registration after `after_new_register`; continue localizing the new
`register_nested_module_in_current_arena` parameter block before trying `s3b`.
{F/G/R: 0.92/0.61/0.90} [verified]

## LM-547 — Nested module method params moved from raw slices to source-backed spans

Context: compiler/bootstrap/codegen, 2026-05-01, `codegen`.

Verified:

- After LM-546, the next `each_param` / `safe_slice_to_string` crash came from
  `register_nested_module_in_current_arena` PASS 2. That path registered
  nested-module class methods and still read `param.type_annotation` directly
  while resolving method signatures.
- The fix switches that nested-module method param registration to
  `parameter_type_annotation_string(param, member_arena, false)` and then
  qualifies the resulting source text in the module namespace. This preserves
  the existing signature policy while avoiding raw frontend slices when the
  member arena is known.

Evidence:

- `crystal build src/adamas.cr -o
  /tmp/cv2_nested_module_params_candidate --error-trace` passed.
- `p2_enum_class_setter_return_infer_no_prelude.sh`,
  `p2_nested_module_registration_no_prelude.sh`,
  `p2_bootstrap_semantic_emit_oracle.sh`,
  `p2_visibility_private_accessor_no_prelude.sh`, and
  `p2_implicit_ivar_param_source_scan_no_prelude.sh` passed with
  `/tmp/cv2_nested_module_params_candidate`.
- `scripts/run_safe.sh /tmp/cv2_nested_module_params_candidate 300 4096
  src/adamas.cr -o /tmp/cv2_direct_nested_module_params/cv2_s2` built
  generated `cv2_s2` in ~155s with `[EXIT: 0]`.
- `ADAMAS_TRACE_CLASS_FRONTIER=1` on the generated compiler now advances
  past `Float::Float::ParsedNumberStringT` and reaches
  `Float::Float::Bigint` before the next crash.
- Fresh lldb shows the new frontier is not `each_param` or
  `safe_slice_to_string`; it is `infer_type_from_expr_inner` reached from
  `infer_concrete_return_type_from_body` while registering
  `Float::Float::Bigint`.

Boundary: generated `s2` plain full-prelude smoke still fails. The current
frontier has moved from stale parameter slices to eager return/body inference
inside the reparsed/generic `Float::FastFloat` nested-class corridor. Do not
continue patching parameter loops until a new trace points back there.
{F/G/R: 0.92/0.60/0.90} [verified]

## LM-548 — Class initialize lowering preserves Void instead of body type

Context: compiler/bootstrap/codegen, 2026-05-01, `codegen`.

Verified:

- After LM-547, forcing registration-time `initialize` signatures to `Void`
  advanced the generated-stage2 frontier past the `Float::Float::Bigint`
  body-inference crash, but the new no-prelude reducer showed this was
  incomplete: `lower_method` still inferred a class `initialize` return from
  the final body expression and emitted `func @Box#initialize$Int32(...) -> 1`
  when the constructor body ended with a `Bool` helper call.
- The root invariant is semantic, not bootstrap-specific: Crystal
  constructors do not return the final expression. The fix applies that
  invariant in both class registration and actual method lowering:
  `initialize` gets `TypeRef::VOID` before HIR function creation, skips
  annotated/implicit return re-inference in `lower_method`, and emits a
  valueless implicit return terminator for constructor fallthrough.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_initialize_void_candidate
  --error-trace` passed.
- `regression_tests/p2_initialize_return_void_no_prelude.sh
  /tmp/cv2_initialize_void_candidate` passed, proving a constructor whose body
  ends in `Bool` still dumps as `Box#initialize$Int32(...) -> 0`.
- Existing p2 guards passed with the same compiler:
  `p2_enum_class_setter_return_infer_no_prelude.sh`,
  `p2_nested_module_registration_no_prelude.sh`,
  `p2_bootstrap_semantic_emit_oracle.sh`,
  `p2_visibility_private_accessor_no_prelude.sh`, and
  `p2_implicit_ivar_param_source_scan_no_prelude.sh`.
- `scripts/run_safe.sh /tmp/cv2_initialize_void_candidate 300 4096
  src/adamas.cr -o /tmp/cv2_direct_initialize_void/cv2_s2` built generated
  `cv2_s2` in ~162s with `[EXIT: 0]`.
- The generated `cv2_s2` full-prelude `puts 42` smoke no longer dies in
  `Float::Float::Bigint` return/body inference. It now reaches module
  registration and aborts on a demanded missing symbol:
  `STUB CALLED:
  Crystal$CCMIR$CCUnionDescriptor$Hinitialize$$String_Array$LCrystal$CCMIR$CCUnionVariantDescriptor$R_Int32_Int32`.

Boundary: generated `s2` plain smoke is still not clean, and `s3b` should not
be attempted yet. The next root is the missing concrete
`Crystal::MIR::UnionDescriptor#initialize(String, Array(UnionVariantDescriptor),
Int32, Int32)` lowering/demand corridor, not constructor return inference.
{F/G/R: 0.93/0.63/0.91} [verified]

## LM-549 — Macro-expanded record params can slice macro source instead of generated output

Context: compiler/bootstrap/codegen, 2026-05-01, `codegen`.

Observed after LM-548:

- The generated `cv2_s2` full-prelude `puts 42` smoke advances past the
  `Float::Float::Bigint` return-inference frontier and aborts on
  `STUB CALLED:
  Crystal$CCMIR$CCUnionDescriptor$Hinitialize$$String_Array$LCrystal$CCMIR$CCUnionVariantDescriptor$R_Int32_Int32`.
- `Crystal::MIR::UnionDescriptor` is a `record` in
  `src/compiler/mir/mir.cr`. Its real constructor is macro-generated from
  `record UnionDescriptor, name : String, variants : Array(UnionVariantDescriptor),
  total_size : Int32, alignment : Int32, source_file : String? = nil,
  source_line : Int32? = nil`.
- `MacroExpander#reparse` reparses macro output into the macro-definition
  arena and uses `source_sink` to call `store_extra_source(macro_arena, output)`.
  This retains the generated source as an arena extra source, but
  `source_for_arena(macro_arena)` still points at the macro source file.
- `capture_initialize_params` currently recovers parameter names/types via
  `parameter_name_string` / `parameter_type_annotation_string`. Those helpers
  prefer span slicing against `source_for_arena`, so macro-expanded params can
  slice unrelated macro-source text instead of generated output. The diagnostic
  signal before the WIP source-recovery attempt was:
  `[INIT_PARAMS_STORE] class=Crystal::MIR::UnionDescriptor source=class
  params=[Point:Void(0), x=1, @y=2:Void(0), _:Void(0), ...]`.

Fix:

- `parameter_name_string` and `parameter_type_annotation_string` now compute a
  raw token fallback first, but also try the same parameter span against recent
  retained `extra_sources_for_arena` macro outputs before trusting the primary
  arena source. Candidate text is accepted only when it is a plausible
  single-line parameter name/type slice, avoiding `UnionDescriptor`-specific
  stubs or stdlib/runtime edits.
- A first version introduced a new self-host abort-stub frontier because the
  call used a ternary over `source_arena` and registered
  `parameter_span_text_from_extra_sources` with a `Nil | ArenaLike` argument.
  The landed form explicitly narrows `source_arena.as(ArenaLike)` before
  calling the helper, preserving generated-stage2 demand for the real helper
  signature.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_macro_param_source_candidate3
  --error-trace` passed.
- `regression_tests/p2_macro_extra_source_param_recovery_no_prelude.sh
  /tmp/cv2_macro_param_source_candidate3` passed. The reducer fails on the
  prior compiler by emitting `Box#initialize$ass Bo_lize_total_` and bogus
  fields such as `@@def ini`; it now emits
  `Box#initialize$String_Int32_Nil | Int32` and proper `@@total_size` /
  `@@source_line` field sets.
- Existing guards passed with the same compiler:
  `p2_initialize_return_void_no_prelude.sh`,
  `p2_implicit_ivar_param_source_scan_no_prelude.sh`,
  `p2_bootstrap_semantic_emit_oracle.sh`,
  `p2_nested_module_registration_no_prelude.sh`,
  `p2_enum_class_setter_return_infer_no_prelude.sh`, and
  `p2_visibility_private_accessor_no_prelude.sh`.
- `DEBUG_INIT_PARAMS=UnionDescriptor ADAMAS_STOP_AFTER_HIR=1
  scripts/run_safe.sh /tmp/cv2_macro_param_source_candidate2 300 4096
  src/adamas.cr -o /tmp/cv2_uniondesc_trace_candidate2/cv2_s2_stop_hir`
  showed full recovered params:
  `[name:String, variants:Array(Crystal::MIR::UnionVariantDescriptor),
  total_size:Int32, alignment:Int32, source_file:Nil | String,
  source_line:Nil | Int32]`.
- `scripts/run_safe.sh /tmp/cv2_macro_param_source_candidate3 300 4096
  src/adamas.cr -o /tmp/cv2_direct_macro_param_source3/cv2_s2` built
  generated `cv2_s2` in ~153s with `[EXIT: 0]`.
- The generated `cv2_s2` full-prelude `puts 42` smoke no longer aborts on
  `UnionDescriptor#initialize` or the helper stub. It now reaches module
  registration and crashes later with:
  `[INFER_INDEX] method=unlock self=Exception::Exception::CallStack obj= idxs=1`
  followed by `Segmentation fault: 11`.

Boundary: generated `s2` plain smoke is still not clean, and `s3b` should not
be attempted yet. The current frontier is `Exception::CallStack#unlock` during
module registration, not macro-generated record parameter recovery.
{F/G/R: 0.92/0.62/0.89} [verified]

## LM-550 — Exception::CallStack frontier splits into constant block inference and Parameter-field trust

Context: compiler/bootstrap/codegen, 2026-05-01, `codegen`.

Observed after LM-549:

- `scripts/run_safe.sh /tmp/cv2_macro_param_source_candidate3 300 4096
  src/adamas.cr -o /tmp/cv2_direct_macro_param_source3/cv2_s2` built
  generated `s2`; the remaining plain-smoke crash is in the generated compiler
  while registering nested stdlib/compiler types for a trivial `puts 42`.
- Clearing `@current_method` / `@current_method_is_class` around
  `record_constant_definition` moved the diagnostic from
  `[INFER_INDEX] method=unlock self=Exception::Exception::CallStack ...` to
  `[INFER_INDEX] method= self=Exception::Exception::CallStack ...`. This
  falsifies "SpinLock#unlock is the real callee" and confirms stale method
  context leaked into registration-time constant inference.
- Guarding registration-time constant type inference from expressions that
  contain inline blocks/yield removes the `[INFER_INDEX]` on
  `Exception::CallStack::CURRENT_DIR = Process::INITIAL_PWD.try { |dir|
  Path[dir] }`. This confirms `CURRENT_DIR` is a real unsafe inference hazard:
  constant registration is not a callsite and must not infer through block
  bodies.
- The smoke still crashes immediately after `Exception::CallStack` reaches
  `concrete_before_body_loop`, so the constant inference guard is not a complete
  fix.
- `DEBUG_REG_CONCRETE_PHASE='Exception::Exception::CallStack'
  DEBUG_REG_METHOD_PHASE='initialize'` localizes the next stable crash to body
  idx 6, `def initialize(@callstack : Array(Void*) = CallStack.unwind)`, after
  `params_present size=1` and the first `param_entry name=(nil)`.
- A source-param helper experiment was rejected: it introduced a new generated
  stage2 abort-stub for
  `AstToHir#def_param_type_annotations_from_source(DefNode, ArenaLike)`.
  Broadly switching the existing class method registration loop to
  `parameter_type_annotation_string(..., true)` also did not move the frontier.

Current interpretation:

- There are at least two adjacent root patterns, not one bug:
  registration-time expression inference is too eager for block-bearing
  constants, and generated stage2 still exposes unsafe `Parameter` field access
  for instance-var parameters in class method registration.
- Do not reintroduce a new helper with an `ArenaLike` union signature in this
  hot path without proving it is demanded/lowered in generated stage2. The
  previous helper became a stub despite passing host build and no-prelude
  guards.
- The next falsifier should avoid broad source-param helper calls. Prefer a
  minimal instrumentation around the existing parameter loop or a small
  source-backed extraction path that reuses already-lowered helpers, then prove
  it on `Exception::CallStack#initialize` before trying `s3b`.

Evidence:

- Host builds passed for the constant-inference guard candidates:
  `/tmp/cv2_const_block_guard_candidate` and
  `/tmp/cv2_param_fallback_candidate`.
- Existing no-prelude guards passed for both candidates:
  `p2_macro_extra_source_param_recovery_no_prelude.sh`,
  `p2_implicit_ivar_param_source_scan_no_prelude.sh`,
  `p2_initialize_return_void_no_prelude.sh`, and
  `p2_bootstrap_semantic_emit_oracle.sh` where run.
- Generated `s2` builds passed for the candidates under
  `scripts/run_safe.sh ... 300 4096 src/adamas.cr`.
- Generated `s2` plain smoke remains red with `Segmentation fault: 11` at
  `Exception::CallStack#initialize` parameter registration.

Trust: {F/G/R: 0.86/0.55/0.83} [in-progress]

## LM-551 — Stage2 smoke advances through CallStack params, then exposes type-literal Regex and nested Float frontiers

Context: compiler/bootstrap/codegen, 2026-05-01, `codegen`.

Verified/observed after LM-550:

- `parameter_type_annotation_string` and `parameter_name_string` now honor
  `fallback_to_slice=false` strictly. This prevents the class registration
  method-param loop from reading stale raw `Parameter` slices after a
  source-span extraction was explicitly requested.
- `set_function_type_entry` now allows `Void` to replace a previous
  `Unknown`/empty return entry. This preserves the existing invariant against
  overwriting concrete return types with `Void`, while avoiding sticky
  `Unknown` signatures such as `Exception::CallStack#initialize`.
- A narrow `find_ivar_info` helper was added only for optional return-inference
  ivar probes. It moved the lldb frontier away from `Array(IVarInfo)#size`,
  but this is classified as containment, not a complete root fix: layout and
  struct-as-pointer ABI drift can still create bad arrays elsewhere.
- `resolve_type_literal_class_name` no longer uses `String#sub(Regex, "")` for
  stripping `.class` / `.metaclass`. The generated `s2` compiler crashed inside
  `String#bytesize -> String#sub_append -> String#sub(Regex, ...)` while
  resolving type-literal annotations; suffix slicing removes that fragile
  Regex/String path from a compiler hot path without changing semantics.
- Broad param-cache source rewriting was refuted again. The host build, p2
  guards, and generated `s2` build passed, but the produced `s2` crashed almost
  immediately after `prelude exists` on a plain smoke. Do not revive that
  approach without a smaller invariant and a produced-compiler smoke.
- A targeted preseed for methods with instance-var parameters avoids
  immediately overwriting source-backed param infos for `@ivar` initialize
  signatures. It passes host/p2/generated-s2 build checks and, under detailed
  tracing, moves past `Exception::CallStack#initialize` to
  `Float::Float::ParsedNumberStringT`. Boundary: the no-filter generated `s2`
  full-prelude smoke still segfaults quickly, so this is progress evidence, not
  a final bootstrap fix.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_ivar_param_preseed_candidate
  --error-trace` passed.
- Existing p2 no-prelude guards passed:
  `p2_macro_extra_source_param_recovery_no_prelude.sh`,
  `p2_implicit_ivar_param_source_scan_no_prelude.sh`,
  `p2_initialize_return_void_no_prelude.sh`, and
  `p2_bootstrap_semantic_emit_oracle.sh`.
- `scripts/run_safe.sh /tmp/cv2_ivar_param_preseed_candidate 300 4096
  src/adamas.cr -o /tmp/cv2_ivar_param_preseed_s2/cv2_s2` built generated
  `s2` in ~155s with `[EXIT: 0]`.
- Plain generated `s2` full-prelude `puts 42` smoke remains red:
  `scripts/run_safe.sh /tmp/cv2_ivar_param_preseed_s2/cv2_s2 60 4096
  /tmp/cv2_ivar_param_preseed_s2/hello.cr -o ...` exits 139.
- `ADAMAS_TRACE_CLASS_FRONTIER=1` on that produced compiler reaches nested
  module/class registration and crashes at `Float::Float::ParsedNumberStringT`.

Current interpretation:

- The active root-cause pattern is still semantic registration doing too much
  work on unstable generated-stage2 representations. The current subpatterns
  are stale `Parameter` fields, sticky `Unknown` function signatures, fragile
  compiler hot paths through stdlib Regex/String helpers, and duplicated nested
  module qualification (`Float::Float::*`, `Iterator::`, `Indexable::`).
- Next falsifier should target nested module/class qualification before more
  ABI guards: `Float::FastFloat::ParsedNumberStringT` should not become
  `Float::Float::ParsedNumberStringT`. Use no-prelude or small full-prelude
  traces first; do not attempt `s3b` yet.

Trust: {F/G/R: 0.87/0.58/0.86} [in-progress]

## LM-552 — Qualified module wrapper fallback and nested-name joins canonicalized

Context: compiler/bootstrap/codegen, 2026-05-01, `codegen`.

Root cause and fix:

- Generated `s2` reproduced the malformed namespace on a minimal no-prelude
  reducer:
  `module Float::FastFloat; struct ParsedNumberStringT(UC); end; end`.
  Host-built V2 registered `Float::FastFloat::ParsedNumberStringT`, but the
  produced `s2` registered `Float::Float::ParsedNumberStringT`.
- The first source-level root was `module_name_from_node` falling back to
  `definition_name_from_header_text` when generated `s2` lost the parser slice
  for an inner path-wrapper module. That helper stops at the first `:`, so the
  full header `module Float::FastFloat` recovers `Float` instead of the wrapper
  leaf/name needed by registration.
- Switching the module fallback to `definition_leaf_name_from_header_text`
  exposed the second invariant violation: generated `s2` can also return
  already-qualified child names, and registration sites blindly concatenate
  `owner::child`. The reducer then showed
  `Float::FastFloat::Float::FastFloat::ParsedNumberStringT`.
- The root fix adds `qualified_nested_type_name(owner, child)` and uses it in
  the relevant module/class nested registration joins. The helper preserves
  already-qualified children under the same owner and only prefixes genuinely
  relative child names.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_float_ns_fix3 --error-trace`
  passed.
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /tmp/cv2_float_ns_fix3` passed on the host-built compiler.
- `scripts/run_safe.sh /tmp/cv2_float_ns_fix3 300 4096 src/adamas.cr -o
  /tmp/cv2_float_ns_fix3_s2/cv2_s2` built generated `s2` in ~148s.
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /tmp/cv2_float_ns_fix3_s2/cv2_s2` passed on the produced compiler. This is
  the decisive falsifier because the same reducer failed on the previous
  produced `s2`.
- Existing p2 guards also passed on the host-built compiler:
  `p2_macro_extra_source_param_recovery_no_prelude.sh`,
  `p2_implicit_ivar_param_source_scan_no_prelude.sh`,
  `p2_initialize_return_void_no_prelude.sh`, and
  `p2_bootstrap_semantic_emit_oracle.sh`.
- Produced `s2` full-prelude `puts 42` smoke still exits 139, but now reaches
  the correctly named `Float::FastFloat::ParsedNumberStringT` instead of
  `Float::Float::*`. The remaining crash is therefore the next frontier, not
  the namespace-duplication bug.

Quadrumvirate:

- Cassandra: predicted a wrapper/source-fallback failure; verified by produced
  `s2` reducer, not by host-only evidence.
- Daedalus: first leaf-only patch was insufficient and shifted the failure to
  `Float::FastFloat::Float::FastFloat`; the frame shifted from "bad extractor"
  to "bad extractor plus non-idempotent namespace join".
- Maieutic: the critical assumption was that child names are always relative;
  generated `s2` falsified it by returning already-qualified child names.
- Adversary: host-only reducer would have missed the bug; produced-compiler
  reducer is now the required guard.

Trust: {F/G/R: 0.91/0.68/0.90} [verified]

## LM-553 — Self-nested qualified module wrappers no longer recurse through registration

Context: compiler/bootstrap/codegen, 2026-05-05, `codegen`.

Root cause and fix:

- After LM-552 and the pre-scan constant fix, produced `s2` full-prelude
  `puts 42` reached a second `module_enter Float::FastFloat` and then trapped
  before ordinary body pass traces.
- Phase tracing localized the trap to a nested `ModuleNode` inside
  `Float::FastFloat` whose recovered child name and canonical joined name were
  both `Float::FastFloat`. Calling `register_nested_module` on that child sent
  registration back into the same canonical owner.
- A simple skip moved the full-prelude frontier but lost the nested
  `ParsedNumberStringT` struct in the no-prelude namespace reducer. The final
  fix keeps the non-recursion invariant while preserving wrapper-carried direct
  nested types/aliases: self-wrapper names are deleted from the nested-name set,
  recursive self module registration is bypassed, and direct class/enum/alias
  members under the wrapper are registered under the owner.
- A broader attempt to recursively flatten self-wrapper module bodies was
  refuted: it passed host guards but produced `s2` moved back to an early
  module-register Trace/BPT trap. Do not revive that shape without a smaller
  invariant.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_self_nested_final
  --error-trace` passed.
- Host guards passed:
  `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_self_nested_final`,
  `regression_tests/p2_nested_module_registration_no_prelude.sh
  /private/tmp/cv2_self_nested_final`, and
  `regression_tests/p2_self_nested_module_registration_frontier.sh
  /private/tmp/cv2_self_nested_final`.
- `scripts/run_safe.sh /private/tmp/cv2_self_nested_final 300 4096
  src/adamas.cr -o /private/tmp/cv2_self_nested_final_s2/cv2_s2` built a
  generated `s2` compiler with `[EXIT: 0]`.
- Produced `s2` guards passed:
  `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_self_nested_final_s2/cv2_s2` and
  `regression_tests/p2_self_nested_module_registration_frontier.sh
  /private/tmp/cv2_self_nested_final_s2/cv2_s2`.

Current boundary:

- The self-recursive module-registration trap is closed, not the whole
  full-prelude compile. The next visible root pattern is still type-name
  pollution in nested module signature registration, e.g.
  `Float::FastFloat::String`, `Float::FastFloat::Bool`, and earlier
  `Float::FastFloat::UInt64`.

Trust: {F/G/R: 0.89/0.60/0.88} [verified]

## LM-554 — Nested module method annotations preserve top-level builtin names

Context: compiler/bootstrap/codegen, 2026-05-05, `codegen`.

Root cause and fix:

- After LM-553, produced `s2` full-prelude `puts 42` no longer trapped in module
  registration, but `ADAMAS_TRACE_CLASS_FRONTIER=1` showed polluted
  `Float::FastFloat.to_f64?` and `to_f32?` signatures:
  `raw=String resolved=Float::FastFloat::String` and
  `raw=Bool resolved=Float::FastFloat::Bool`.
- `DEBUG_TYPE_EXISTS_TRACE=Float::FastFloat::String` showed
  `type_name_exists?` returning true via `enum_hit=1`, even though
  `DEBUG_ENUM_ARENA=Float::FastFloat` only showed the legitimate
  `CharsFormat` and `ParseError` enums. The actionable invariant is therefore
  not "never resolve nested names", but "method annotations for top-level or
  builtin short names must not trust registry fallback alone".
- `qualify_method_annotation_in_namespace` now preserves an unqualified
  top-level/builtin annotation unless the active namespace chain structurally
  records that nested type in `@nested_type_names`. Legitimate local nested
  annotations such as `ParseError`, `Limb`, `Stackvec(Size)`, and
  `ParsedNumberStringT(UC)` still resolve through the existing nested/alias
  paths.
- A read-only Spark audit independently pointed at the same two candidate
  boundaries: malformed nested-name shadowing and the
  `nested_type_shadow_in_namespace`/`type_name_exists?` fallback for builtin
  names.

Evidence:

- `CRYSTAL_CACHE_DIR=/private/tmp/cv2_cache_annot_structural crystal build
  src/adamas.cr -o /private/tmp/cv2_annot_structural --error-trace` passed.
- Host guards passed:
  `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_annot_structural`,
  `regression_tests/p2_nested_module_registration_no_prelude.sh
  /private/tmp/cv2_annot_structural`,
  `regression_tests/p2_self_nested_module_registration_frontier.sh
  /private/tmp/cv2_annot_structural`, and
  `regression_tests/p2_full_prelude_generic_template_namespace_no_pollution.sh
  /private/tmp/cv2_annot_structural`.
- `scripts/run_safe.sh /private/tmp/cv2_annot_structural 300 4096
  src/adamas.cr -o /private/tmp/cv2_annot_structural_s2/cv2_s2` built a
  generated `s2` compiler with `[EXIT: 0]`.
- Produced `s2` guard passed:
  `regression_tests/p2_full_prelude_generic_template_namespace_no_pollution.sh
  /private/tmp/cv2_annot_structural_s2/cv2_s2`.
- Direct trace evidence on produced `s2` now shows:
  `raw=String resolved=String type=String` and
  `raw=Bool resolved=Bool type=Bool` for both `Float::FastFloat.to_f64?` and
  `Float::FastFloat.to_f32?`.

Current boundary:

- This closes the `Float::FastFloat::String` / `Float::FastFloat::Bool`
  signature pollution. It does not close the full-prelude `puts 42` compile:
  without verbose trace, produced `s2` still times out after 420s in class
  registration after `class register idx=3/104`.

Trust: {F/G/R: 0.88/0.58/0.87} [verified]

## LM-555 — Char class registration stalls in record-time macro-for parsing

Context: compiler/bootstrap/codegen, 2026-05-05, `codegen`.

Observed frontier:

- After LM-554, produced `s2` full-prelude `puts 42` still times out in class
  registration, but the previous `Float::FastFloat::String` / `Bool` signature
  pollution is gone.
- A temporary `ADAMAS_TRACE_CLASS_INDEX` build showed the produced compiler
  completed class registration through `Bool` and then stalled at
  `class register before idx=25/104 name=Char`.
- Existing `DEBUG_REG_CONCRETE_PHASE=Char` localized the stall to
  `record_constants_in_body`: `Char` reaches `after_include_extend_scan` but not
  `after_record_constants`.
- Temporary `DEBUG_RECORD_CONSTANTS=Char` instrumentation localized the member:
  `record_constants_in_body("Char", ...)` reaches a `MacroForNode` from
  `primitives.cr` (`{% for op, desc in {...} %}` for `Char` comparison
  primitives), extracts six values, expands 870 bytes of method-only output,
  then stalls inside `parse_macro_literal_class_body_with_sanitized_fallback`.

Refuted branch:

- Replacing record-time `MacroForNode` handling with a constant-only expansion
  path avoided the `Char` parser stall but made produced full-prelude `puts 42`
  regress to an early module-register `Trace/BPT` around the `Crystal::Hasher`
  area. Do not reuse that broad skip: the macro-for registration side effects
  are still required before class registration completes.

Current boundary:

- The next fix must separate constant recording from method registration more
  carefully: avoid reparsing method-only macro-for output during
  `record_constants_in_body`, while preserving the class/member registration
  effects that the broad constant-only skip removed.

Trust: {F/G/R: 0.82/0.52/0.82} [verified]

## LM-556 — Char primitive macro-for registration moves frontier to Proc

Context: compiler/bootstrap/codegen, 2026-05-06, `codegen`.

Root cause and fix:

- After LM-555, a class-only record-time macro-for split moved the stall out of
  `record_constants_in_body("Char", ...)`, but the ordinary class body loop
  still reached the same `Char` comparison primitive macro and attempted to
  reparse method-only generated text.
- A textual primitive-def fast path was not sufficient in produced `s2`:
  diagnostic expansion showed `def (other : Char) : Bool`, so the macro
  iterable key path had already lost `op.id` before parsing.
- The final fix has two bounded parts. First, class record-time macro-for
  handling only reparses expansion text that can define record-time
  declarations (`class`, `struct`, `module`, `enum`, `alias`, class variables,
  or constant assignments), leaving module macro-for registration unchanged.
  Second, the exact stdlib `Char` `op,desc` six-entry comparison primitive macro
  registers `Char#==`, `Char#!=`, `Char#<`, `Char#<=`, `Char#>`, and
  `Char#>=` directly as `@[Primitive(:binary)]` signatures, with a fallback for
  the produced path where operator IDs are empty.

Evidence:

- `CRYSTAL_CACHE_DIR=/private/tmp/cv2_cache_char_clean crystal build
  src/adamas.cr -o /private/tmp/cv2_char_clean --error-trace` passed.
- Host guards passed:
  `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_char_clean`,
  `regression_tests/p2_self_nested_module_registration_frontier.sh
  /private/tmp/cv2_char_clean`, and
  `regression_tests/p2_full_prelude_generic_template_namespace_no_pollution.sh
  /private/tmp/cv2_char_clean`.
- `scripts/run_safe.sh /private/tmp/cv2_char_clean 300 4096
  src/adamas.cr -o /private/tmp/cv2_char_clean_s2/cv2_s2` built produced
  `s2` with `[EXIT: 0]`.
- `regression_tests/p2_generated_stage2_char_macro_for_frontier.sh
  /private/tmp/cv2_char_clean_s2/cv2_s2` passed. The underlying trace reached
  `concrete_after_body_scan Char`, `concrete_after_new Char`, then
  `class_with_name_enter Proc` and `concrete_before_body_loop Proc`.

Refuted variants and boundary:

- Broad constant-only macro-for skipping avoided the Char parser hang but
  regressed produced full-prelude `puts 42` to an early module-register
  `Trace/BPT` around `Crystal::Hasher`.
- Parser-first and textual primitive signature parsing were refuted by the
  produced expansion itself: `op.id` was already missing from the text.
- This is a moved-frontier fix, not a full-prelude unlock. Produced `s2`
  full-prelude `puts 42` currently exits 139 in the `Proc` class body loop; the
  broader produced MacroHash/key corruption remains a follow-up root, but is no
  longer blocking this specific stdlib Char primitive registration corridor.

Trust: {F/G/R: 0.84/0.48/0.84} [verified]

## LM-557 — Semantic def checks avoid SymbolTable hashing and raw def slices

Context: compiler/bootstrap/codegen, 2026-05-06, `codegen`.

Root cause and fix:

- The first no-prelude reducer was `struct Foo; def call; end; end` under
  generated `s2 --no-codegen`. It crashed in
  `TypeInferenceEngine#find_class_symbol_for_scope` while adding a
  `SymbolTable` to `Set(SymbolTable)`, which called
  `Reference#hash -> Crystal::Hasher#reference` and dereferenced broken hasher
  state.
- Replacing semantic `Set(SymbolTable)` visited guards with small identity
  arrays moved that reducer to green, but `Proc#call(*args : *T) : R` and any
  def with params or return annotations still crashed in
  `SymbolCollector#handle_def -> String.new(Slice(UInt8))`.
- The final fix keeps semantic scope traversal off hash-backed identity sets,
  passes the single-file source into `run_check` via Analyzer/Collector source
  providers, and makes `SymbolCollector#handle_def` read def param names,
  param types, and return annotations from source spans before falling back to
  guarded raw slices.

Refuted branch:

- Reading source from `arena.extra_sources` inside `SymbolCollector` was unsafe:
  produced `s2` crashed in `source_for_span` even on the bare `def call` reducer.
  Source-backed semantic recovery must use the file/provider boundary, not the
  same fragile arena-array path it is trying to avoid.

Evidence:

- `CRYSTAL_CACHE_DIR=/private/tmp/cv2_cache_symbol_final crystal build
  src/adamas.cr -o /private/tmp/cv2_symbol_final --error-trace` passed.
- Host guards passed:
  `regression_tests/p2_generated_stage2_no_codegen_def_semantic_frontier.sh
  /private/tmp/cv2_symbol_final`,
  `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_symbol_final`,
  `regression_tests/p2_full_prelude_generic_template_namespace_no_pollution.sh
  /private/tmp/cv2_symbol_final`, and
  `regression_tests/p2_self_nested_module_registration_frontier.sh
  /private/tmp/cv2_symbol_final`.
- `scripts/run_safe.sh /private/tmp/cv2_symbol_final 300 4096
  src/adamas.cr -o /private/tmp/cv2_symbol_final_s2/cv2_s2` built produced
  `s2` with `[EXIT: 0]`.
- Produced guards passed:
  `regression_tests/p2_generated_stage2_no_codegen_def_semantic_frontier.sh
  /private/tmp/cv2_symbol_final_s2/cv2_s2`,
  `regression_tests/p2_generated_stage2_char_macro_for_frontier.sh
  /private/tmp/cv2_symbol_final_s2/cv2_s2`,
  `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_symbol_final_s2/cv2_s2`, and
  `regression_tests/p2_full_prelude_generic_template_namespace_no_pollution.sh
  /private/tmp/cv2_symbol_final_s2/cv2_s2`.

Current boundary:

- This is a moved-frontier fix, not a full-prelude unlock. Produced `s2`
  full-prelude `puts 42` now reaches `concrete_after_new Proc`, then
  `Char::Reader`, logs
  `[INFER_INDEX] method=byte_at self=Char::Reader obj=nil obj_kind=Node idxs=1`,
  reaches `concrete_after_new Char::Reader`, and exits 139 at the next
  frontier.

Trust: {F/G/R: 0.86/0.55/0.86} [verified]

## LM-558 — Type literal name queries no longer materialize Bool.to_s stubs

Context: compiler/bootstrap/codegen, 2026-05-06, `codegen`.

Root cause and fix:

- Produced `s2` LLVM contained `Bool$Dto_s` and `Bool$Dname` abort stubs.
  The concrete caller was `Pointer(Bool)#to_s(io)` lowering stdlib
  `io << T.to_s` into a static `Bool.to_s` call instead of a type-literal name
  query.
- V2 HIR represents type literals as compile-time values. Calling
  `Class/Object` meta-methods on the runtime placeholder is wrong; for
  `to_s`, `inspect`, and `name`, the lowering must emit the type name string
  unless the type has a real dot-method override.
- Added `lower_type_literal_name_query` and a strict
  `type_literal_class_method_override?` check that only preserves real class
  methods on the owner/parent chain, not broad meta-method fallbacks. Applied
  this to call lowering, no-parens member access lowering, and the static
  member-access helper.

Evidence:

- `CRYSTAL_CACHE_DIR=/private/tmp/crystal_cache_v2_type_literal_name_query4
  crystal build src/adamas.cr -o /private/tmp/cv2_type_literal_name_query4
  --error-trace` passed.
- New guard `regression_tests/p2_type_literal_name_query_no_stub.sh` passed
  and rejects static `NameProbe$Dto_s` / `NameProbe$Dname` stubs in
  no-prelude LLVM IR while requiring the literal `NameProbe` string.
- `scripts/run_safe.sh /private/tmp/cv2_type_literal_name_query4 420 4096
  src/adamas.cr -o /private/tmp/cv2_type_literal_name_query4_s2/cv2_s2`
  built produced `s2` with `[EXIT: 0]`.
- Produced `cv2_s2.ll` had no `Bool$Dto_s` or `Bool$Dname`, and
  `Pointer(Bool)#to_s(io)` emitted the literal `"Bool"` path instead of calling
  a static Bool method.

Refuted branch:

- Re-enabling source-backed return annotations in top-level `register_function`
  did not close the current full-prelude frontier. With the type-literal fix it
  still regressed produced `s2` full-prelude `puts 42` to an earlier class
  registration crash around `class register idx=51/104`.

Current boundary:

- This is a shape/root fix, not a full-prelude unlock. Produced `s2`
  full-prelude `puts 42` still exits 139. With the source-return experiment
  reverted, the current untraced frontier reaches pass2
  `register_functions idx=3/297` and crashes before the next clean phase log.

Trust: {F/G/R: 0.86/0.50/0.86} [verified]

## LM-559 — Stage2 static call emission uses named callees and valid return ABI

Context: compiler/bootstrap/codegen, 2026-05-08, `codegen`.

Root cause and fix:

- Produced `s2` could lower a source-backed class method call such as
  `Exception::CallStack.skip("x")` into MIR carrying the right function id, but
  LLVM emission resolved that id through a self-host-fragile
  `Hash(FunctionId, Function)` lookup. On miss, the backend emitted fallback
  names such as `@func1` instead of the named callee.
- The same frontier exposed empty cached return ABI strings, producing invalid
  LLVM spellings such as `call  @...`.
- HIR now preserves the forced full static method name when lowering recovered
  direct class methods, MIR lowers exact static calls before treating a stale
  receiver value as a runtime receiver, and the LLVM backend uses dense
  function-id lookup plus empty-return normalization.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_funcid_empty_host
  --error-trace` passed.
- `CRYSTAL_CACHE_DIR=/private/tmp/crystal_cache_cv2_funcid_empty
  scripts/run_safe.sh /private/tmp/cv2_funcid_empty_host 300 4096
  src/adamas.cr -o /private/tmp/cv2_funcid_empty_s2/cv2_s2` built
  produced `s2` with `[EXIT: 0]`.
- New guard `regression_tests/p2_stage2_static_call_named_llvm_no_prelude.sh`
  passed on both `/private/tmp/cv2_funcid_empty_host` and produced
  `/private/tmp/cv2_funcid_empty_s2/cv2_s2`. It rejects `@func1`, rejects
  `call  @`, requires
  `call void @Exception$CCCallStack$Dskip$$String(ptr @.str.0)`, and runs
  `llc` on the emitted IR when available.
- Existing namespace guard
  `regression_tests/p2_qualified_module_namespace_no_prelude.sh` passed on
  both compilers, so this did not regress the prior Float/FastFloat namespace
  frontier.

Current boundary:

- This is a static-call/LLVM-ABI root fix, not a clean no-prelude binary
  compile. Produced `s2` no-prelude binary output for the reducer still exits
  139 after LLVM finalizes output, which points at a separate CLI/file-output
  tail or outer-rescue frontier.
- Produced `s2` full-prelude `puts 42` now gets past the old Float namespace
  frontier and crashes later around `Time::Format::Formatter`, so that remains
  a later generic/template registration frontier.

Trust: {F/G/R: 0.88/0.50/0.88} [verified]

## LM-560 — Bootstrap work now has executable spec contracts

Context: compiler/bootstrap/process, 2026-05-08, `codegen`.

Decision:

- Add `docs/specs/` as the first spec-first contract layer for Crystal V2.
  The goal is not a full Crystal language standard. The goal is to turn known
  bootstrap bug families into falsifiable contracts before further
  implementation work.
- Initial documents:
  - `docs/specs/00-bootstrap-contract.md`
  - `docs/specs/01-hir-name-resolution.md`
  - `docs/specs/02-generic-template-registration.md`
  - `docs/specs/03-mir-call-abi.md`
  - `docs/specs/04-llvm-emission.md`
  - `docs/specs/05-falsifier-matrix.md`

Why this matters:

- The project has proven that agents can move the compiler by root-cause
  debugging, but most time is spent discovering edge-case families late.
- The spec layer changes the default workflow from "frontier first, guard
  later" to "contract and falsifier first, implementation second" where the
  contract family is already known.

Operational rule:

- A future meaningful bootstrap fix should satisfy an existing falsifier-matrix
  row or update the matrix with a new row and guard. If a claim has no narrow
  falsifier, keep it as `[MISSING-FALSIFIER]` or `[FRONTIER]`, not VERIFIED.

Trust: {F/G/R: 0.82/0.65/0.82} [verified-docs]

## LM-561 — Self-hostile spec review closed first process gaps

Context: compiler/bootstrap/process, 2026-05-08, `codegen`.

Review findings addressed:

- `[MISSING-FALSIFIER]` could become a permanent parking state. The falsifier
  matrix now requires phase pressure (`current`, `next-touch`, `pre-s2-clean`,
  or `later`) for each non-refuted row.
- The original compiler was named as semantic oracle but not operationalized.
  `00-bootstrap-contract.md` now requires original-vs-stage evidence for
  language-behavior changes, or a stated semantic-line oracle when no
  normalizer exists.
- The active post-LLVM binary-output crash was only a residual note. It now has
  `docs/specs/06-cli-output-contract.md` and CLI-output rows in the falsifier
  matrix.
- Generic identity was too abstract. `02-generic-template-registration.md` now
  defines recommended `GenericTemplateKey` and `GenericInstanceKey` shapes and
  rejects empty owner leaves / repeated adjacent owner segments.
- MIR receiver/static ABI had only an LLVM-level guard. `03-mir-call-abi.md`
  now records the desired MIR-shape guard for the static-call reducer.

Operational impact:

- Fixes in the current CLI/output frontier must not cite `--emit llvm-ir`
  success as binary-output evidence.
- New semantic fixes should include original-vs-stage evidence unless the
  change is explicitly limited to internal stage parity.

Trust: {F/G/R: 0.84/0.70/0.84} [verified-docs]

## LM-562 — Second hostile spec review tightened next-frontier usability

Context: compiler/bootstrap/process, 2026-05-08, `codegen`.

Review findings addressed:

- `G2` in the falsifier matrix was incorrectly marked `current`. Empty or
  repeated generic owner names are important, but they should block the next
  generic-registration touch, not the active CLI/output frontier. It is now
  `next-touch`.
- `06-cli-output-contract.md` named the post-LLVM tail categories but did not
  give the next agent an executable starting recipe. It now includes the
  static-call reducer, adjacent `--emit llvm-ir --no-link` and normal binary
  commands, and a nine-point localization log from LLVM return through process
  teardown.

Operational impact:

- The next CLI/output attempt can begin directly from `06-cli-output-contract.md`
  section 7.
- A claimed tail fix must state last passing and first failing points; a probe
  that changes the frontier must be treated as evidence decay and rerun
  unprobed.

Trust: {F/G/R: 0.85/0.72/0.85} [verified-docs]

## LM-563 — Final hostile spec review aligned active frontier order

Context: compiler/bootstrap/process, 2026-05-08, `codegen`.

Review finding addressed:

- The falsifier matrix still marked the full-prelude generic/template `puts 42`
  frontier as `current`, while `06-cli-output-contract.md` and TODO identify
  the no-prelude post-LLVM CLI/output tail as the next active fix target. This
  could send agents back into full-prelude generic registration before the
  no-prelude binary-output crash is localized.

Fix:

- Reclassified matrix row `G5` from `current` to `pre-s2-clean`. It remains a
  required gate before declaring `s1 -> s2b` clean, but it should not preempt
  the active CLI/output tail work.

Trust: {F/G/R: 0.86/0.72/0.86} [verified-docs]

## LM-564 — Produced stage2 normal CLI output clears the no-prelude tail

Context: compiler/bootstrap/CLI-output, 2026-05-08, `codegen`.

Verified outcome:

- The static-call reducer from `docs/specs/06-cli-output-contract.md` now
  passes both adjacent modes on host and produced `s2`: `--emit llvm-ir
  --no-link` and normal binary output.
- The normal binary path keeps LLVM IR generation in memory, writes the `.ll`
  file through raw `LibC` fd IO outside `LLVMIRGenerator`, and hashes LLVM cache
  inputs with raw `LibC.open/read/close` instead of `File.open`.

Root evidence:

- Before the fix, produced `s2` emitted valid no-prelude LLVM IR and `llc`
  accepted it, but normal binary output exited 139 after the `.ll` write.
- Cursor A2A review correctly pushed the next falsifier toward the tail after
  file close, but local lldb evidence refined the root: `compile_llvm_ir`
  reached `file_sha256`, which used `File.open`; the produced compiler entered
  `Crystal::System::Dir.open` and called `__adamas_raise` with `x0 = NULL`,
  leading the outer rescue path to dereference a nil exception object.
- Refuted branches: backend `generate_to(output)` split, resetting
  `LLVMIRGenerator.@output`, a custom `RawFdOutput`, removing `ensure` around
  close, and deleting the outer `CLI#compile` rescue. Those either did not move
  the C2 guard or regressed the `s1 -> s2` gate.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_cli_tail_final3_host
  --error-trace`
- `CRYSTAL_CACHE_DIR=/private/tmp/crystal_cache_cv2_cli_tail_final3
  scripts/run_safe.sh /private/tmp/cv2_cli_tail_final3_host 600 4096
  src/adamas.cr -o /private/tmp/cv2_cli_tail_final3_s2/cv2_s2`
- Host and produced `s2` guards:
  `p2_stage2_cli_output_tail_no_prelude.sh`,
  `p2_stage2_static_call_named_llvm_no_prelude.sh`,
  `p2_type_literal_name_query_no_stub.sh`, and
  `p2_qualified_module_namespace_no_prelude.sh`.
- `git diff --check`

Boundary:

- This clears the active no-prelude CLI/output tail. It is not a full-prelude
  `puts 42` claim, and it does not fix the deeper nil-exception path in
  `Dir.open`/rescue lowering. The generic/template `pre-s2-clean` row remains
  open.

Trust: {F/G/R: 0.88/0.58/0.88} [verified]

## LM-565 — Bootstrap investigation rules from the C2 cycle

Context: compiler/bootstrap/process, 2026-05-08, `codegen`.

Patterns extracted from the C2 CLI-output tail cycle:

- `FRONTIER_MIRAGE`: absence of an expected trace line does not prove that the
  target function was not entered. In LM-564, the first `DEBUG_LLVM_TAIL` trace
  did not print, but lldb showed that produced `s2` reached
  `compile_llvm_ir -> file_sha256` and then crashed in the `File.open`/`Dir.open`
  corridor.
- `HELPER_PERTURBS_STAGE2`: small helper/refactor changes can perturb the
  produced-stage call graph. Extracting a tiny FNV update helper for
  `file_sha256` regressed self-build with `ExprId out of bounds`, while the
  inline form passed `s1 -> s2`.
- `SIDECAR_IS_FALSIFIER_NOT_JUDGE`: Cursor A2A was useful as a hostile review
  sidecar, especially for pushing on file-close/cache risks, but its output
  remained candidate evidence until local lldb and produced-stage guards
  confirmed or refuted it.
- `CACHE_IS_RUNTIME_SURFACE`: LLVM cache and hash code participates in the
  bootstrap runtime path. It must be covered by produced-stage evidence when it
  is touched.
- `WORKAROUND_SCOPE_DRIFT`: gate-local fixes must avoid wording that claims a
  deeper subsystem is fixed. LM-564 clears the CLI/cache-tail gate while leaving
  the nil-exception `Dir.open`/rescue path as a separate risk.

Process updates:

- `docs/specs/05-falsifier-matrix.md` now has process rows P1-P5 for trace,
  helper, sidecar, cache/IO, and scope-drift checks.
- `docs/specs/06-cli-output-contract.md` now requires stronger control-flow
  anchors for tail work when lldb/breakpoints/IR are practical.

Trust: {F/G/R: 0.82/0.68/0.84} [verified-process]

## LM-566 — Produced stage2 nilable union-wrap codegen clears focused reducer

Context: compiler/bootstrap/MIR-LLVM-union, 2026-05-15, `codegen`.

Verified outcome:

- Produced `s2` now compiles and runs the no-prelude nilable-union reducer:
  `x : UInt32? = nil; if x; 1; else; 0; end`.
- The existing qualified nested-module namespace guard still passes on produced
  `s2`, so the fix does not reopen the LM-552 namespace frontier.
- The top-level bare function-call no-prelude guard also passes on produced
  `s2`.

Root evidence:

- Local LLVM `emit_block` tracing localized the produced-stage hang to non-phi
  instruction id 3 in block 0. MIR showed id 3 was
  `union_wrap %2 as variant 0`, where `%2` was `nil`.
- Grok ACP's read-only audit usefully ranked union emission as high risk, but
  its strongest post-block-helper prediction was falsified by the local trace.
- The root fix avoids stage2-sensitive iterator/string reverse lookups on the
  union-wrap path by carrying ordered union descriptor registrations into MIR
  and using descriptor-backed scalar scans for nil/reference variant lookup.
- The next exposed failure was invalid LLVM local names such as `%3.ptr` and
  `%4.union_ptr`; union-derived temporary names now use the existing sanitized
  local-name base helper.

Evidence:

- `CRYSTAL_CACHE_DIR=/private/tmp/cv2_final_host_cache crystal build
  src/adamas.cr -o /private/tmp/cv2_final_host --error-trace`
- `CRYSTAL_CACHE_DIR=/private/tmp/cv2_final_s2_cache scripts/run_safe.sh
  /private/tmp/cv2_final_host 300 4096 src/adamas.cr -o
  /private/tmp/cv2_final_s2/cv2_s2`
- `regression_tests/p2_nilable_union_wrap_codegen_no_prelude.sh
  /private/tmp/cv2_final_host`
- `regression_tests/p2_nilable_union_wrap_codegen_no_prelude.sh
  /private/tmp/cv2_final_s2/cv2_s2`
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_final_s2/cv2_s2`
- `regression_tests/p2_top_level_bare_function_call_no_prelude.sh
  /private/tmp/cv2_final_s2/cv2_s2`
- `git diff --check`

Boundary:

- This is a focused no-prelude reducer/codegen closure, not a full-prelude
  claim. Produced `s2` full-prelude `puts 42` still does not clear the 60s
  adversary check; it times out during early registration before reaching the
  old Float crash frontier. The broader nilable short-circuit union-phi reducer
  also remains open on produced `s2`.
- The `s1 -> s2` build still prints a non-fatal MIR optimizer overflow for
  `Adamas::Compiler::CLI#file_sha256$String`; that is not solved here.

Trust: {F/G/R: 0.86/0.56/0.86} [verified]

## LM-567 — File.open block return semantics restored for produced LLVM calls

Context: compiler/bootstrap/HIR+LLVM block-call return typing, 2026-05-18,
`codegen`.

Verified outcome:

- `File.open(path, "w") { |file| file.puts "x"; "block-result" }` now returns
  the block value to the caller instead of a `File`-typed/null value.
- The focused guard compiles with the V2 compiler and the produced binary prints
  `block-result` under `scripts/run_safe.sh`.
- Generated LLVM for the focused repro now calls `IO#puts(String)` on the
  `File.open` result instead of `IO#puts(File)`.

Root evidence:

- The first raw LLVM override fix made `File.open$String_String_block` return
  `%block_result`, but the caller still emitted `IO#puts(File)`, proving the
  remaining root was stale HIR call-return typing rather than only a null raw
  return.
- `File.open` is a delegated yield-return wrapper:
  `open_internal(...) { |file| yield file }`; the old yield-return classifier
  recognized only direct tail `yield` / direct begin-ensure passthrough.
- The call site used the synthetic typed key `File.open$String_String_block`
  while the source overload that proves yield-return was registered under the
  default-expanded overload key. Return typing now checks block-overload
  candidates, refreshes stale yield-name cache entries when yield functions are
  added, and recomputes block return at block-to-proc materialization before the
  final HIR `Call` is emitted.

Evidence:

- `CRYSTAL_CACHE_DIR=/private/tmp/cv2_fix_host_cache crystal build
  src/adamas.cr -o /private/tmp/cv2_fix_host --error-trace`
- `regression_tests/p2_file_open_block_return.sh /private/tmp/cv2_fix_host`
- `regression_tests/p2_record_macro_init_defaults.sh /private/tmp/cv2_fix_host`
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_fix_host`
- LLVM adversary check on `/private/tmp/cv2_file_open_return_probe_final.ll`
  showed `call void @IO$Hputs$$String(ptr %r59309, ptr %r59307)`.
- `git diff --check`

Boundary:

- This does not claim exception-safe close for the raw `File.open` override.
  The current override still closes only on the normal path.
- The remaining hardcoded Fiber/Mutex/Formatter raw-layout assumptions from the
  reviewed Claude range remain follow-up risks.

Trust: {F/G/R: 0.84/0.62/0.86} [verified]

## LM-568 — Stage2 LLVM backend no longer integerizes broad-union string payloads or Pointer(T) params

Context: compiler/bootstrap/MIR LLVM backend, 2026-05-18, `codegen`.

Verified outcome:

- Union-vs-concrete comparisons now gate payload compares by the union
  discriminator even when the union has no Nil variant. Generated-stage broad
  unions such as `Array(String)#[]?` no longer choose the first non-Nil payload
  variant (`Float32`) and emit invalid `load float` + integer arithmetic while
  comparing to string literals.
- Pointer-typed function parameters are no longer classified as packed
  `inttoptr` scalars. `Pointer(T)` params now stay address-like, so loads such
  as `value.value` in `Float::FastFloat#from_chars_advanced` emit `load T, ptr`
  instead of `ptrtoint ptr %value to double`.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_pointer_param_fix
  --error-trace`
- `regression_tests/p2_union_concrete_compare_type_guard.sh
  /private/tmp/cv2_pointer_param_fix`
- `regression_tests/p2_pointer_param_not_packed_scalar_no_prelude.sh
  /private/tmp/cv2_pointer_param_fix`
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_pointer_param_fix`
- `regression_tests/p2_file_open_block_return.sh /private/tmp/cv2_pointer_param_fix`
- `regression_tests/p2_nilable_union_wrap_codegen_no_prelude.sh
  /private/tmp/cv2_pointer_param_fix`
- Produced-s2 builds advanced from invalid LLVM at
  `nilable_integer_key_hash_payload_llvm_type` (`load float` then `add i64`) and
  `Float::FastFloat::BinaryFormat_Float64#from_chars_advanced`
  (`ptrtoint ptr %value to double`) to a later generated fallback-stub frontier:
  `Float32#each_key(&block)` returns `ptr %arg0` while `%arg0` is `float`.

Boundary:

- This does not make produced `s2` green. The current generated-stage2
  frontier is invalid fallback stub emission for primitive `each_key` adapter
  blocks, first seen as `ret ptr %arg0` in
  `Float32$Heach_key$$block(float %arg0, ptr %arg1)`.
- The remaining `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer
  arithmetic-overflow diagnostic is still non-fatal and still present.

Trust: {F/G/R: 0.84/0.58/0.86} [verified]

## LM-569 — Stage2 no longer emits malformed primitive `each_key` fallback returns

Context: compiler/bootstrap/MIR LLVM backend, 2026-05-18, `codegen`.

Verified outcome:

- Missing `*#each_key(&block)` fallback stubs no longer return `%arg0` as a
  pointer unless `%arg0` is actually pointer-typed. Primitive impossible-owner
  calls such as `Float32#each_key(&block)` now emit a typed null/zero return
  through `zero_return_for_llvm_type` instead of malformed LLVM
  (`ret ptr %arg0` where `%arg0` is `float`).
- A focused no-prelude oracle now reproduces the old shape with
  `1.0_f32.each_key { |x| x }` and guards that the fallback stub is LLVM-typed.
- The produced-s2 build now gets past the previous `llc` failure in
  `Float32$Heach_key$$block(float %arg0, ptr %arg1)`.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_each_key_fix
  --error-trace`
- `regression_tests/p2_each_key_fallback_primitive_return_shape.sh
  /private/tmp/cv2_each_key_fix`
- `regression_tests/p2_pointer_param_not_packed_scalar_no_prelude.sh
  /private/tmp/cv2_each_key_fix`
- `regression_tests/p2_union_concrete_compare_type_guard.sh
  /private/tmp/cv2_each_key_fix`
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_each_key_fix`
- `regression_tests/p2_file_open_block_return.sh /private/tmp/cv2_each_key_fix`
- `regression_tests/p2_nilable_union_wrap_codegen_no_prelude.sh
  /private/tmp/cv2_each_key_fix`
- `CRYSTAL_CACHE_DIR=/private/tmp/cv2_each_key_s2_cache
  scripts/run_safe.sh /private/tmp/cv2_each_key_fix 300 4096
  src/adamas.cr -o /private/tmp/cv2_each_key_s2/cv2_s2` exited 0 after
  ~175s.
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_each_key_s2/cv2_s2`

Boundary:

- This is a backend containment invariant for dead/missing fallback stubs, not a
  semantic proof that primitive owners should ever demand `each_key`.
  GPT Spark and Cursor both classified the primitive-owner demand as a separate
  upstream unresolved-call/dispatch problem.
- Produced `s2` still does not pass full-prelude `puts 42`: running
  `ADAMAS_TRACE_CLASS_FRONTIER=1 scripts/run_safe.sh
  /private/tmp/cv2_each_key_s2/cv2_s2 60 4096 /private/tmp/cv2_hello.cr -o
  /private/tmp/cv2_hello_bin` exits 139 during early HIR setup, after
  `[STAGE2_DEBUG] pre-scan class/module loops start`.
- The remaining `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer
  arithmetic-overflow diagnostic is still non-fatal and still present during
  the s2 build.

Trust: {F/G/R: 0.83/0.52/0.86} [verified]

## LM-570 — `Slice(T).literal` no longer lowers as a void/null constant on the host path

Context: compiler/bootstrap/HIR primitive lowering, 2026-05-18, `codegen`.

Verified outcome:

- Generic `Slice(T).literal` calls are recognized as the `slice_literal`
  primitive even when the exact `Slice(T).literal$...` specialization was not
  explicitly registered in `@primitive_methods`.
- The HIR primitive path now materializes a concrete `Slice(T)` value instead of
  falling through to a regular empty primitive body with `TypeRef::VOID`.
  It allocates the element buffer, stores literal arguments into it, allocates
  the canonical 16-byte Slice payload, and writes `@size`, `@read_only`, and
  `@pointer`.
- The focused no-prelude host oracle
  `S = Slice(UInt64).literal(1_u64, 2_u64)` no longer emits
  `call void @Slice$LUInt64$R$Dliteral...` and no longer stores `ptr null` into
  `@Object__classvar__S`; the produced test binary exits 0 under `run_safe`.
- Produced `s2` LLVM for the real FastFloat table now stores a concrete pointer
  into `@Float$CCFastFloat$CCPowers__classvar__POWER_OF_FIVE_128` instead of
  `ptr null`, advancing the prior `Slice(UInt64)#to_unsafe` null-self segfault.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_slice_literal_fix_fmt
  --error-trace`
- `regression_tests/p2_slice_literal_no_prelude.sh
  /private/tmp/cv2_slice_literal_fix_fmt`
- `regression_tests/p2_each_key_fallback_primitive_return_shape.sh
  /private/tmp/cv2_slice_literal_fix_fmt`
- `regression_tests/p2_pointer_param_not_packed_scalar_no_prelude.sh
  /private/tmp/cv2_slice_literal_fix_fmt`
- `regression_tests/p2_union_concrete_compare_type_guard.sh
  /private/tmp/cv2_slice_literal_fix_fmt`
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_slice_literal_fix_fmt`
- `regression_tests/p2_file_open_block_return.sh
  /private/tmp/cv2_slice_literal_fix_fmt`
- `regression_tests/p2_nilable_union_wrap_codegen_no_prelude.sh
  /private/tmp/cv2_slice_literal_fix_fmt`
- `CRYSTAL_CACHE_DIR=/private/tmp/cv2_slice_literal_fmt_s2_cache
  scripts/run_safe.sh /private/tmp/cv2_slice_literal_fix_fmt 300 4096
  src/adamas.cr -o /private/tmp/cv2_slice_literal_fmt_s2/cv2_s2` exited
  0 after ~163s.
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_slice_literal_fmt_s2/cv2_s2`
- Static produced-s2 LLVM check:
  `@Float$CCFastFloat$CCPowers__classvar__POWER_OF_FIVE_128` is still declared
  `global ptr null`, but its initializer path now contains
  `store ptr %r3930, ptr @Float$CCFastFloat$CCPowers__classvar__POWER_OF_FIVE_128`
  and no `call void @Slice$LUInt64$R$Dliteral...`.
- `ADAMAS_TRACE_CLASS_FRONTIER=1 scripts/run_safe.sh
  /private/tmp/cv2_slice_literal_fmt_s2/cv2_s2 60 4096
  /private/tmp/cv2_hello.cr -o /private/tmp/cv2_slice_literal_fmt_hello_bin`
  advanced past the previous
  FastFloat segfault and now exits 134 at
  `STUB CALLED: EquivUint$Dnew$BANG$$UInt64`.

Boundary:

- This is not a broad primitive-return repair. It is intentionally scoped to the
  `slice_literal` primitive contract and generic `Slice(T).literal` dispatch.
- Produced `s2` still does not pass full-prelude `puts 42`; the new primary
  frontier is the `EquivUint.new!` abort stub during early prescan.
- Running the new no-prelude `Slice(UInt64).literal` guard with produced `s2`
  currently hits a separate
  `Indexable$LT$R$Hequals$Q$$Indexable_block` abort before IR emission, so the
  new guard is host-path verified only until that produced-stage stub frontier is
  fixed.
- The remaining `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer
  arithmetic-overflow diagnostic is still non-fatal and still present during
  the s2 build.

Trust: {F/G/R: 0.84/0.56/0.86} [verified]

## LM-571 — Generic static type-parameter `new!` lowering keeps concrete long bindings

Context: compiler/bootstrap/HIR generic static-call lowering, 2026-05-19,
`codegen`.

Verified outcome:

- Include-derived function type-param maps now retain concrete long type-param
  bindings such as `EquivUint => UInt64` instead of keeping only one-letter
  params, internal keys, or explicit template-allowed keys. Deferred/caller
  snapshots only keep long concrete keys that are declared by the included
  module's type params, preserving the old caller-context leak guard.
- When a lowered function is looked up through a generic template owner but the
  requested method name carries a concrete generic owner, HIR merges the
  requested owner's concrete type-param map and resolves the lowered owner to
  that concrete generic instance.
- Static type-param primitive numeric constructors such as `U.new!(x)` and
  included-method `EquivUint.new!(x)` lower to the concrete primitive value
  shape instead of unresolved `U$Dnew$BANG` /
  `EquivUint$Dnew$BANG` stubs or void-returning wrapper methods.
- The primitive-constructor cast containment is limited to `new!`; allowing it
  for ordinary `new` miscompiled produced-s2
  `Float::FastFloat::Value128.new(UInt128)` into `inttoptr i128`, so that
  broader variant is refuted.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_generic_static_fix4
  --error-trace`
- `crystal tool format --check src/compiler/hir/ast_to_hir.cr`
- `git diff --check`
- `regression_tests/p2_generic_static_type_param_new_bang_no_prelude.sh
  /private/tmp/cv2_generic_static_fix4`
- `regression_tests/p2_slice_literal_no_prelude.sh
  /private/tmp/cv2_generic_static_fix4`
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_generic_static_fix4`
- `regression_tests/p2_nilable_union_wrap_codegen_no_prelude.sh
  /private/tmp/cv2_generic_static_fix4`
- `scripts/run_safe.sh /private/tmp/cv2_generic_static_fix4 300 4096
  src/adamas.cr -o /private/tmp/cv2_generic_static_s2_fix4/cv2_s2`
  exited 0 after ~161s.
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_generic_static_s2_fix4/cv2_s2`
- Produced-s2 LLVM check:
  `Float$CCFastFloat$Dcompute_product_approximation$$Int64_UInt64_Int32`
  now calls
  `@Float$CCFastFloat$CCValue128$Dnew$$UInt128(i128 %r44)` instead of
  returning an `inttoptr i128` cast.
- Untraced produced-s2 full-prelude `puts 42` advanced from
  `STUB CALLED: EquivUint$Dnew$BANG$$UInt64` to
  `STUB CALLED: Indexable$LT$R$Hequals$Q$$Indexable_block`.

Boundary:

- This is not a broad generic-container or block/proc closure. It specifically
  fixes concrete static type-param owner recovery for `new!`.
- The new no-prelude guard is host-path verified only for now: produced `s2`
  currently aborts at the separate
  `Indexable$LT$R$Hequals$Q$$Indexable_block` frontier before the guard can
  emit IR.
- `ADAMAS_TRACE_CLASS_FRONTIER=1` perturbs the produced full-prelude smoke
  into a pre-scan timeout; the untraced `Indexable#equals?` block stub is the
  cleaner next frontier.
- The remaining `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer
  arithmetic-overflow diagnostic is still non-fatal and still present during
  the s2 build.

Trust: {F/G/R: 0.84/0.55/0.86} [verified]

## LM-572 — Included generic equality block calls rebase to concrete receiver helpers

Context: compiler/bootstrap/HIR block-call target canonicalization, 2026-05-19,
`codegen`.

Verified outcome:

- Full-prelude `Array(Int32)#==` no longer emits a call or abort stub for the
  generic template helper
  `Indexable$LT$R$Hequals$Q$$Indexable_block`.
- Block-call canonicalization now preserves ordinary static value-owner
  behavior, but for `equals?` block calls selected from an included unresolved
  generic owner such as `Indexable(T)`, it retargets to the concrete receiver
  block helper when the receiver's include chain contains the matching generic
  module definition.
- A broader version that applied this to all unresolved generic included-module
  block calls was refuted: it fixed the local oracle but made the full s2 build
  exceed the 4096 MB `run_safe` cap. The accepted fix is intentionally scoped to
  the equality block family that exposed the frontier.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_indexable_host_fix7
  --error-trace`
- `crystal tool format --check src/compiler/hir/ast_to_hir.cr`
- `git diff --check`
- `regression_tests/p2_indexable_equals_block_receiver_rebase.sh
  /private/tmp/cv2_indexable_host_fix7`
- `regression_tests/p2_generic_static_type_param_new_bang_no_prelude.sh
  /private/tmp/cv2_indexable_host_fix7`
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_indexable_host_fix7`
- `regression_tests/array_bool_join_module_super_repro.sh
  /private/tmp/cv2_indexable_host_fix7`
- `scripts/run_safe.sh /private/tmp/cv2_indexable_host_fix7 300 4096
  src/adamas.cr -o /private/tmp/cv2_indexable_s2_fix7/cv2_s2`
  exited 0 after ~164s.
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_indexable_s2_fix7/cv2_s2`
- Produced-s2 comparison: clean produced `s2` aborts the
  `p2_generic_static_type_param_new_bang_no_prelude` source at
  `STUB CALLED: Indexable$LT$R$Hequals$Q$$Indexable_block`; patched produced
  `s2` gets past that abort and exposes a later segfault.
- Produced-s2 full-prelude `puts 42` with
  `ADAMAS_TRACE_CLASS_FRONTIER=1` now advances past the prior
  `Float::FastFloat::ParsedNumberStringT` / `Indexable#equals?` frontier and
  segfaults during `Crystal::SpinLock` registration after
  `concrete_after_pass0`.

Boundary:

- This is not a general block/proc or generic-container closure. The broader
  generic included-module block rebase is a known memory-regression branch.
- The new full-prelude equality guard is host-path verified. Produced `s2`
  reaches the next full-prelude registration/runtime crash before it can pass
  the same guard end-to-end.
- The remaining `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer
  arithmetic-overflow diagnostic is still non-fatal and still present during
  the s2 build.

Trust: {F/G/R: 0.82/0.48/0.86} [verified]

## LM-573 — Proc source-sink closures capture lexical self for implicit receiver calls

Context: compiler/bootstrap/HIR proc literal capture lowering, 2026-05-19,
`codegen`.

Verified outcome:

- Produced `s2` no longer crashes on a no-prelude `macro included` reducer that
  expands a simple instance method while registering an including struct.
- The old produced crash was in
  `AstToHir#extra_sources_for_arena` called from
  `store_extra_source -> MacroExpander#reparse -> expand_macro_expr ->
  register_module_instance_methods_for -> register_concrete_class`.
- The root was the `source_sink` proc in `expand_macro_expr`:
  `->(code : String) { store_extra_source(macro_arena, code) }`. The proc body
  uses an implicit receiver call, but `lower_proc_literal` only captured
  lexical `self` when the body explicitly referenced `self`. Generated stage2
  therefore called `store_extra_source` with a null receiver.
- The fix teaches proc literal capture detection to identify bare
  implicit-receiver calls whose callee name is not a proc parameter or parent
  local, then captures lexical `self` for those procs. This covers
  `store_extra_source(...)` without forcing `self` into every proc literal.

Evidence:

- Clean produced `s2` from LM-572 exits 139 on the new
  `p2_macro_included_proc_sink_self_capture_no_prelude.sh` reducer.
- lldb on the reducer showed
  `extra_sources_for_arena -> store_extra_source -> __crystal_proc_* ->
  MacroExpander#reparse`.
- `crystal build src/adamas.cr -o /private/tmp/cv2_proc_self_host2
  --error-trace`
- `crystal tool format src/compiler/hir/ast_to_hir.cr`
- `regression_tests/p2_macro_included_proc_sink_self_capture_no_prelude.sh
  /private/tmp/cv2_proc_self_host2`
- `regression_tests/p2_generic_static_type_param_new_bang_no_prelude.sh
  /private/tmp/cv2_proc_self_host2`
- `regression_tests/p2_indexable_equals_block_receiver_rebase.sh
  /private/tmp/cv2_proc_self_host2`
- `scripts/run_safe.sh /private/tmp/cv2_proc_self_host2 300 4096
  src/adamas.cr -o /private/tmp/cv2_proc_self_s2b/cv2_s2`
  exited 0 after ~154s.
- `regression_tests/p2_macro_included_proc_sink_self_capture_no_prelude.sh
  /private/tmp/cv2_proc_self_s2b/cv2_s2`
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_proc_self_s2b/cv2_s2`
- Full-prelude `puts 42` with the patched produced `s2` moved past the old
  `Crystal::Once::Operation` source-sink crash and now segfaults during module
  registration in `Hash(String, MacroValue)#key_hash`, with lldb stack:
  `assign_macro_iter_vars -> process_macro_for_in_module ->
  record_constants_in_body -> register_nested_module_in_current_arena`.

Refuted branch:

- Unconditionally capturing lexical `self` for every proc literal fixed the
  macro source-sink reducer but made produced `s2` crash during pass3 on
  unrelated no-prelude main programs. The accepted fix is demand-driven:
  explicit `self`, instance variables, or implicit receiver calls.

Boundary:

- This is not a complete direct proc-literal runtime/codegen closure. A
  no-prelude `-> { marker }` executable compiles/runs with the host compiler,
  but produced `s2` still crashes compiling that broader source; keep that as a
  separate pass3 proc frontier.
- The remaining `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer
  arithmetic-overflow diagnostic is still non-fatal and still present during
  the s2 build.

Trust: {F/G/R: 0.86/0.52/0.86} [verified]

## LM-574 — Macro-for iter variable names are safe strings before MacroValue hash binding

Context: compiler/bootstrap/HIR macro-for registration, 2026-05-19, `codegen`.

Verified outcome:

- Produced `s2` no longer crashes on the no-prelude module macro-for reducer
  during module registration.
- The old produced crash was in
  `Hash(String, MacroValue)#key_hash -> Hash#upsert -> Hash#[]= ->
  assign_macro_iter_vars -> process_macro_for_in_module ->
  record_constants_in_body -> register_module_with_name_in_current_arena`.
- The root was raw `String.new(slice)` conversion of
  `MacroForNode#iter_vars` before binding loop variables into
  `Hash(String, MacroValue)`. In produced `s2`, those raw slice conversions can
  create corrupted `String` keys; the next hash insertion then segfaults.
- The fix centralizes HIR macro-for iter-var extraction through
  `macro_for_iter_var_names`, which uses `safe_slice_to_string` plus
  `identifier_source_name?`, and replaces the raw conversion sites in lib,
  module, enum, class, class-constant, expression lowering, and text expansion
  paths.

Evidence:

- Clean produced `s2` from LM-573 exits with a bus error on the new
  `p2_module_macro_for_iter_var_names_no_prelude.sh` reducer, with the same
  `assign_macro_iter_vars -> process_macro_for_in_module` stack family as the
  full-prelude `puts 42` crash.
- Spark sidecar independently pointed at the raw `String.new(slice)` macro-for
  iter-var conversions; this was used as candidate evidence only and verified
  locally.
- `crystal build src/adamas.cr -o /private/tmp/cv2_macro_for_host_final
  --error-trace`
- `crystal tool format --check src/compiler/hir/ast_to_hir.cr`
- `git diff --check`
- `regression_tests/p2_module_macro_for_iter_var_names_no_prelude.sh
  /private/tmp/cv2_macro_for_host_final`
- `regression_tests/p2_macro_included_proc_sink_self_capture_no_prelude.sh
  /private/tmp/cv2_macro_for_host_final`
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_macro_for_host_final`
- `scripts/run_safe.sh /private/tmp/cv2_macro_for_host_final 300 4096
  src/adamas.cr -o /private/tmp/cv2_macro_for_s2_final/cv2_s2`
  exited 0 after ~162s.
- `regression_tests/p2_module_macro_for_iter_var_names_no_prelude.sh
  /private/tmp/cv2_macro_for_s2_final/cv2_s2`
- `regression_tests/p2_macro_included_proc_sink_self_capture_no_prelude.sh
  /private/tmp/cv2_macro_for_s2_final/cv2_s2`
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_macro_for_s2_final/cv2_s2`
- Produced-s2 full-prelude `puts 42` still exits 139, but the untraced run now
  reaches module register idx=51/114 after the focused macro-for reducer
  passes. lldb under the 90s safe timeout did not reach the crash, so the next
  full-prelude stack is not yet captured. With
  `ADAMAS_TRACE_CLASS_FRONTIER=1`, the frontier reaches File nested error
  classes before the traced run exits 133.

Refuted branch:

- A source-backed fallback parser for `{% for ... in ... %}` iter-var names
  was refuted. It reduced the theoretical silent-skip risk but made the
  `s1 -> s2` compiler build fail during pass3 with
  `ExprId out of bounds: 1597133659`. The accepted fix keeps the previously
  self-hosting safe-slice shape and does not add the fallback.

Boundary:

- This is not a full macro-for semantic closure. A stronger executable
  no-prelude source that dispatches through generated module methods still
  reaches a separate produced-s2 pass3/main crash; keep that as a later
  frontier.
- The remaining `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer
  arithmetic-overflow diagnostic is still non-fatal and still present during
  the s2 build.

Trust: {F/G/R: 0.84/0.50/0.87} [verified]

## LM-575 — Single-variable module macro-for binding uses the stable indexed path

Context: compiler/bootstrap/HIR macro-for variable binding, 2026-05-19,
`codegen`.

Verified outcome:

- Produced `s2` no longer crashes on no-prelude module macro-for reducers that
  bind a single loop variable:
  `{% for name in %w(alpha beta) %}`.
- The reducer crashes at HEAD `b0d127f3` in the same stack family as the
  full-prelude `puts 42` frontier:
  `Hash(String, MacroValue)#key_hash -> Hash#upsert -> Hash#[]= ->
  assign_macro_iter_vars -> process_macro_for_in_module ->
  record_constants_in_body -> register_module_with_name_in_current_arena`.
- Pair-var forms such as `{% for name, i in %w(...) %}` were already stable.
  The difference is the one-variable fallback path:
  `vars[iter_vars[0]] = value`.
- The fix preserves semantics but changes the one-variable path to use an
  indexed `each_with_index` loop over `iter_vars`, matching the stable binding
  shape used by pair/tuple assignment and adding no visible macro variables.

Evidence:

- At `b0d127f3`, produced `s2` exits 139 on:
  - a single-var generated-def reducer,
  - a single-var generated nested-struct reducer, and
  - a single-var generated nested-module reducer.
- At the fix, produced `s2` passes:
  - single-var generated-def reducer,
  - single-var generated nested-struct reducer,
  - pair-var generated nested-struct reducer.
- `crystal build src/adamas.cr -o /private/tmp/cv2_macro_single_loop_host
  --error-trace`
- `crystal tool format --check src/compiler/hir/ast_to_hir.cr`
- `git diff --check`
- `regression_tests/p2_module_macro_for_iter_var_names_no_prelude.sh
  /private/tmp/cv2_macro_single_loop_host`
- `regression_tests/p2_macro_included_proc_sink_self_capture_no_prelude.sh
  /private/tmp/cv2_macro_single_loop_host`
- `scripts/run_safe.sh /private/tmp/cv2_macro_single_loop_host 300 4096
  src/adamas.cr -o /private/tmp/cv2_macro_single_loop_s2/cv2_s2`
  exited 0 after ~182s.
- `regression_tests/p2_module_macro_for_iter_var_names_no_prelude.sh
  /private/tmp/cv2_macro_single_loop_s2/cv2_s2`
- `regression_tests/p2_macro_included_proc_sink_self_capture_no_prelude.sh
  /private/tmp/cv2_macro_single_loop_s2/cv2_s2`
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /private/tmp/cv2_macro_single_loop_s2/cv2_s2`
- Produced-s2 full-prelude `puts 42` no longer reaches the
  `Hash(String, MacroValue)#key_hash` stack under the tested trace path. The
  current full-prelude frontier is a pre-scan timeout under 45s/120s
  `run_safe` gates.

Refuted branches:

- Casting macro values to the abstract `MacroValue` before hash insertion made
  the `s1 -> s2` compiler build fail during pass3 with
  `ExprId out of bounds: 1684105331`.
- Routing all writes through a typed helper still left the single-var reducers
  crashing on produced `s2`.

Boundary:

- This is a codegen-shape hardening for macro variable binding, not a general
  Hash or union ABI fix.
- The remaining full-prelude frontier should be treated as a pre-scan
  progress/hang problem unless fresh evidence again shows a later crash.
- The remaining `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer
  arithmetic-overflow diagnostic is still non-fatal and still present during
  the s2 build.

Trust: {F/G/R: 0.86/0.46/0.88} [verified]

## LM-610 — Warm LSP project-cache docs retain require fallback without background stalls

Context: LSP project-cache semantic fidelity and warm-request latency,
2026-05-20, `codegen`.

Verified outcome:

- Cached foreground documents now keep their filtered `require` paths even
  when project-cache symbols are used for foreground analysis. This restores
  on-demand fallback for symbols that are not present in the saved project
  cache.
- Warm project-cache foreground documents no longer start eager background
  dependency warming. The require paths remain available for on-demand
  definition/signature/completion fallback, but `didOpen` no longer schedules
  a broad dependency parse that can delay the first hover.
- Receiver-scoped constructor signature help now avoids the full
  `resolve_call_method_symbol` dependency-load path first. It handles both
  member-access and `PathNode` constructor calls such as
  `Frontend::Parser.new`, tries cached constructor summaries and direct
  required source files, and only then falls back to full symbol resolution.

Root pattern:

- The previous project-cache path preserved fast foreground analysis by
  skipping dependency analysis, but it also dropped `doc_state.requires`.
  That made warm cached documents semantically narrower than cold documents.
- Restoring `requires` exposed a second scheduling bug: the existing
  background warmer treated cached docs like uncached docs and eagerly parsed
  every require after open.
- Constructor signature help had a separate ordering bug: it resolved the
  receiver symbol before checking lightweight constructor corridors, so a warm
  `Frontend::Parser.new` request could load the whole dependency graph before
  returning one signature.

Evidence:

- Focused regression:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_final_spec scripts/run_safe.sh
  /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp/project_cache_semantic_fidelity_spec.cr --error-trace`:
  3 examples, 0 failures.
- Full LSP suite:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_final_fullspec scripts/run_safe.sh
  /Users/sergey/.local/bin/crystal 300 4096 spec spec/lsp --error-trace`:
  236 examples, 0 failures.
- Server and harness builds:
  `src/lsp_main.cr -o /private/tmp/lsp_main_final_requires` and
  `benchmarks/lsp_harness.cr -o /private/tmp/lsp_harness_final_requires`
  both exited 0 through `scripts/run_safe.sh`.
- Final warm default harness with a populated project cache:
  `initialize` 118.5ms, first `server.cr` `didOpen` 263.1ms,
  `hover handle_completion` 14.7ms, `definition handle_completion` 1 location,
  `signature help Parser.new` 6.0ms / 1 signature,
  bench `definition Lexer` 1 location, bench `signature help Parser.new`
  1 signature, bench `completion parser.` 326 items.

Remaining risk:

- The first warm bench-file `definition Lexer` request can still pay a
  dependency-load cost in the default no-AST-cache sequence; the latest warm
  default run measured 495.5ms. This is now isolated from the restored
  require-fallback correctness fix and should be handled as a follow-up
  constructor/type-definition routing slice.

Trust: {F/G/R: 0.88/0.54/0.88} [verified]

## LM-611 — Warm LSP bench-file navigation avoids first-hit dependency loads

Context: LSP project-cache semantic fidelity and warm-request latency,
2026-05-20, `codegen`.

Verified outcome:

- Warm bench-file `definition Lexer` now resolves directly through the
  foreground document's retained `require` paths and source declaration scan,
  instead of entering full dependency loading on the first request.
- Completion inference for constructor-assigned locals no longer resolves the
  constructor receiver through the dependency-loading resolver before trying
  fallback segments. It uses already-loaded/local symbol state, then falls
  through to the source-backed required-file corridor.
- Cached/shallow class symbols are augmented from their defining source file,
  or from the foreground document's matching `require`, so warm
  `parser.` completion does not collapse to the shallow public cache summary.
  The source scanner now recognizes `def`, `private def`, and `protected def`.
- The project-cache semantic-fidelity regression now includes a private method
  completion guard for the cached require fallback.

Root pattern:

- LM-610 restored `requires`, but the next warm request could still spend the
  first dependency-load cost before reaching the lightweight fallback. The
  bad corridor was `constructor_receiver_class -> resolve_receiver_symbol ->
  resolve_path_symbol -> ensure_dependencies_loaded`.
- Once that load was removed, the next semantic gap was visible: cached class
  summaries and the source scanner were both too shallow for parser-style
  private helper methods.

Evidence:

- Focused regression:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_type_def9_spec
  scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp/project_cache_semantic_fidelity_spec.cr --error-trace`:
  3 examples, 0 failures.
- Full LSP suite:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_type_def9_fullspec
  scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec spec/lsp
  --error-trace`: 236 examples, 0 failures.
- Server and harness builds:
  `src/lsp_main.cr -o /private/tmp/lsp_main_type_def9` and
  `benchmarks/lsp_harness.cr -o /private/tmp/lsp_harness_type_def9` both
  exited 0 through `scripts/run_safe.sh`.
- Warm default harness with a populated project cache:
  `initialize` 112.2ms, first `server.cr` `didOpen` 272.5ms,
  `hover handle_completion` 8.0ms, `definition handle_completion` 1 location,
  bench `definition Lexer` 0.5ms / 1 location, bench
  `signature help Parser.new` 0.6ms / 1 signature, bench
  `completion parser.` 11.1ms / 330 unique method labels.

Boundary:

- This closes the default no-AST-cache first-hit bench navigation latency
  observed after LM-610. It does not claim the broader LSP startup/open path is
  finished; `didOpen` for large foreground files still has parse and
  name-resolution work, and `LSP_AST_CACHE=1` remains opt-in.
- The warm source-backed completion path deduplicates method labels, so its
  count is not expected to match cold full semantic completion counts that may
  include overload duplicates.

WBA framing:

- Window/trigger: a warm cached foreground document has retained `require`
  paths but shallow or missing dependency symbols at the first navigation or
  member-completion request.
- Transport corridor: use the required source file as a bounded source-backed
  semantic corridor for type locations, constructor-assigned local completion,
  and cached class-symbol completion augmentation.
- Boundary: do not parse/load the full dependency graph on the request path;
  source scans are limited to matching required files and preserve already
  collected cached labels.
- Legal move: route first through local/already-loaded symbols and direct
  required-source scans; only fall back to dependency AST loading when the
  source corridor cannot prove the answer.
- Potential decrease: removes the first-hit dependency-load component while
  increasing cached completion coverage from shallow public summaries to
  source-backed method labels.

Trust: {F/G/R: 0.89/0.55/0.90} [verified]

## LM-612 — LSP AST cache is the default foreground cache corridor

Context: LSP warm foreground open latency and cache rollout safety,
2026-05-20, `codegen`.

Verified outcome:

- `ServerConfig.load` now enables AST cache by default. Operators can opt out
  with `LSP_AST_CACHE=0` or config `{"ast_cache": false}`.
- The config loader now applies explicit `false` boolean values for all LSP
  boolean config keys. The previous `if value = ...` pattern skipped false
  values, so config-level opt-outs were ineffective.
- Existing AST-cache foreground safety remains intact: unchanged reopened
  foreground documents can reuse disk AST, while unsaved foreground edits keep
  the edited text instead of reusing the stale disk AST.
- Warm default process-level harness now uses the AST-cache corridor without
  requiring an env flag.

Root pattern:

- After LM-611 removed first-hit dependency-load spikes, `LSP_AST_CACHE=1`
  no longer had the earlier signature/completion deltas in the default harness
  and still cut warm foreground open cost roughly in half for `server.cr`.
- The only rollout blocker found by the new guard was not cache semantics but
  config parsing: explicit false booleans in config files were ignored.

Evidence:

- Focused AST-cache foreground/config spec:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_ast_default_foreground_spec2
  scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp/ast_cache_foreground_integration_spec.cr --error-trace`: 3
  examples, 0 failures.
- Focused project-cache semantic-fidelity spec:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_ast_default_semantic_spec
  scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp/project_cache_semantic_fidelity_spec.cr --error-trace`: 3
  examples, 0 failures.
- Full LSP suite:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_ast_default_fullspec
  scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec spec/lsp
  --error-trace`: 237 examples, 0 failures.
- Server and harness builds:
  `src/lsp_main.cr -o /private/tmp/lsp_main_ast_default` and
  `benchmarks/lsp_harness.cr -o /private/tmp/lsp_harness_ast_default` both
  exited 0 through `scripts/run_safe.sh`.
- Warm default harness with no `LSP_AST_CACHE` env:
  `initialize` 105.7ms, first `server.cr` `didOpen` 149.9ms,
  `hover handle_completion` 8.9ms, `definition handle_completion` 1 location,
  `signature help Parser.new` 6.1ms / 1 signature, bench
  `definition Lexer` 1.1ms / 1 location, bench
  `signature help Parser.new` 0.5ms / 1 signature, bench
  `completion parser.` 10.6ms / 330 unique method labels.

Boundary:

- This flips the default cache corridor, not the project-cache semantic model.
  AST cache still requires recovery mode, matching on-disk source content for
  foreground reuse, cache header/version/compiler/source-mtime validation, and
  an explicit opt-out path.
- The remaining LSP performance candidate is foreground name-resolution /
  indexing work after a fast AST load, not parser AST construction itself.

WBA framing:

- Window/trigger: unchanged foreground files reopened after the first server
  instance has emitted a valid AST cache entry.
- Transport corridor: validated binary AST cache transports the parsed arena
  and roots across server instances, while source text, semantic state, and
  project summaries are recomputed or restored through their own boundaries.
- Boundary: cached AST is legal only under compiler fingerprint, cache
  version, source mtime, and exact foreground source-content checks; unsaved
  edits stay outside the cache corridor.
- Legal move: make the validated corridor default and preserve env/config
  opt-out for rollback.
- Potential decrease: foreground parse work drops from the warm open path while
  semantic request fidelity remains guarded by LM-611 and the LSP suite.

Trust: {F/G/R: 0.90/0.58/0.90} [verified]

## LM-613 — LSP document symbols are lazy on foreground open

Context: LSP warm foreground open latency after AST-cache default,
2026-05-20, `codegen`.

Verified outcome:

- `didOpen` no longer performs the AST document-symbol traversal before
  publishing diagnostics. It stores the opened document without precomputed
  document symbols.
- `textDocument/documentSymbol` now computes AST-backed document symbols on
  first request and stores them back into the document state for reuse.
- `didChange` follows the same boundary: edited documents do not pay the
  document-symbol traversal until the client asks for document symbols.
- A focused regression covers the lazy path: after `didOpen` the document
  symbol cache is empty, `textDocument/documentSymbol` returns the AST-backed
  hierarchy, and the cache is then populated.

Root pattern:

- After LM-612, `server.cr` warm foreground open was no longer parser-bound.
  Debug timing showed the parsed document came from AST cache, semantic
  analysis finished, and then `didOpen` still did extra full-AST work before
  diagnostics and the first request.
- Document symbols are a separate LSP request surface. Precomputing them during
  `didOpen` improved a later request by spending work on every open, including
  clients that do not request symbols immediately.

Evidence:

- Focused regression:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_lazy_docs_spec
  scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp/hover_definition_integration_spec.cr --error-trace`: 4 examples,
  0 failures.
- Full LSP suite:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_lazy_docs_fullspec
  scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec spec/lsp
  --error-trace`: 238 examples, 0 failures.
- Server and harness builds:
  `src/lsp_main.cr -o /private/tmp/lsp_main_lazy_docs` and
  `benchmarks/lsp_harness.cr -o /private/tmp/lsp_harness_lazy_docs` both
  exited 0 through `scripts/run_safe.sh`.
- Warm default harness after the lazy-symbol change:
  `initialize` 106.3ms, first `server.cr` `didOpen` 140.3ms,
  `hover handle_completion` 9.6ms, `definition handle_completion` 1 location,
  `document symbols` 24.0ms / 567 symbols, bench `definition Lexer` 0.3ms /
  1 location, bench `signature help Parser.new` 0.4ms / 1 signature, bench
  `completion parser.` 11.8ms / 330 unique method labels.

Boundary:

- This is a latency-boundary move, not a semantic-analysis shortcut. Opened
  documents still get symbol tables, identifier symbols, type context, line
  offsets, and symbol-location registration during `didOpen`.
- The document-symbol request intentionally pays the AST-symbol traversal when
  requested. This moves optional UI work out of the mandatory open/diagnostics
  corridor.

WBA framing:

- Window/trigger: foreground `didOpen` with a cached AST still performs a
  document-symbol traversal before diagnostics.
- Transport corridor: opened document state carries the parsed arena and text;
  document-symbol hierarchy can be transported lazily on the dedicated request
  path.
- Boundary: diagnostics and navigation state remain available at open; only
  optional document-symbol UI data is delayed.
- Legal move: initialize opened/changed documents without AST document symbols
  and cache them on first `textDocument/documentSymbol`.
- Potential decrease: mandatory foreground-open work shrinks while total
  work remains available when explicitly demanded.

Trust: {F/G/R: 0.89/0.50/0.90} [verified]

### LM-589 — LSP first-request latency now defers CPU-bound UnifiedProject updates

Status: VERIFIED on `codegen`.

After semantic-token range support, direct in-process range collection for
`src/compiler/lsp/server.cr` measured around 4ms, but the first JSON-RPC
request after `didOpen` still measured around 260ms. Debug timing showed the
server-side hover itself completed in about 25ms; the extra wall time came from
a spawned `UnifiedProject update_file` fiber that was CPU-bound and monopolized
Crystal's cooperative scheduler before the first foreground request was
handled.

Accepted change:

- `didOpen` and `didChange` now queue UnifiedProject updates through the
  existing LSP debouncer instead of spawning immediate CPU-bound work.
- The debouncer uses `Time::Instant` consistently and a one-slot nonblocking
  wake channel so queueing does not block the request path.
- Shutdown flushes pending project updates before saving project cache.
- A regression spec proves `didOpen` updates the immediate legacy document
  state while leaving UnifiedProject work pending until the debouncer is
  explicitly flushed.

Refuted / corrected hypotheses:

- Direct semantic-token range collection was not the bottleneck: repeated
  in-process range collection stayed around 4ms.
- `LSP_AST_CACHE=1` did not fix first-request latency; it made first hover
  around 1.9s in the probe, so the simple foreground-recursive-requires
  hypothesis was rejected.
- Grok's prelude-apply hypothesis was useful as a scheduling-family signal,
  but local debug logs showed prelude apply happened before document analysis
  in the accepted run; UnifiedProject update completion was adjacent to the
  delayed first hover.

Evidence:

- Before patch harness probe:
  first hover after `didOpen` around 261ms, second hover around 26ms, range
  around 5ms.
- Server debug log before patch:
  `UnifiedProject update_file: 242.14ms` completed immediately before the first
  hover request; `Hover completed in 25.12ms`.
- After patch harness probes:
  debug-log run first hover after `didOpen` 26.2ms, second hover 55.2ms,
  range 4.9ms; final no-debug run after moving the queue point after
  diagnostics/semantic-refresh publication measured first hover 24.8ms,
  second hover 67.9ms, range 7.2ms.
- Focused spec:
  `crystal build spec/lsp/did_change_integration_spec.cr -o
  /tmp/lsp_did_change_spec --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_did_change_spec 120 1536 --no-color`,
  3 examples, 0 failures.
- Full LSP suite:
  `crystal build spec/lsp/*_spec.cr -o /tmp/lsp_full_spec --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_full_spec 120 1536 --no-color`,
  216 examples, 0 failures.
- `crystal build src/lsp_main.cr -o bin/adamas_lsp --error-trace`
  succeeded for the post-patch harness probe.

Remaining risks:

- Project-cache saves can still land between foreground requests and add
  secondary jitter.
- Shutdown may now spend time flushing a pending project update before saving
  cache; this is outside the interactive foreground request path.

Trust: {F/G/R: 0.86/0.62/0.89} [verified]

### LM-590 — Cache-backed prelude apply no longer repeats cached method registration

Status: VERIFIED on `codegen`.

The LSP background prelude cache path already rebuilds the prelude symbol table,
restores cached expression types, and registers cached method lookup summaries
before sending the loaded `PreludeState` to the main server loop. The foreground
`apply_background_prelude` path then reloaded the same cache and repeated
`register_cached_symbols`, which duplicated CPU work on the LSP foreground
loop.

Accepted change:

- For cache-backed `PreludeState` values, `apply_background_prelude` now sets
  the active prelude state and requests semantic-token refresh without
  reloading the cache and registering cached summaries a second time.
- Parsed/non-cache prelude states still use the existing register/save path.

Evidence:

- Debug probe after the change showed:
  `Applying background-loaded prelude` and `Background prelude applied and
  client notified` at the same timestamp, while cached table rebuild and cached
  expression restore remained in the background load path.
- Focused prelude/navigation specs:
  `crystal build spec/lsp/hover_definition_prelude_spec.cr
  spec/lsp/stdlib_navigation_spec.cr spec/lsp/stdlib_hover_spec.cr
  spec/lsp/did_change_integration_spec.cr -o /tmp/lsp_prelude_fast_spec
  --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_prelude_fast_spec 120 1536 --no-color`,
  8 examples, 0 failures.

Boundary:

- This is a duplicate-work cleanup, not a full open-latency closure. The
  remaining startup/open cost is dominated by synchronous project-cache load,
  background prelude table rebuild/registration, and large-file legacy document
  analysis.

Trust: {F/G/R: 0.76/0.42/0.84} [verified]

### LM-591 — Debounced project updates now wait for foreground request idle

Status: VERIFIED on `codegen`.

After LM-589 moved `UnifiedProject update_file` onto the LSP debouncer, a
broader request-burst harness found a remaining scheduler bug: the debouncer
still fired by wall clock while the client was actively issuing foreground
requests. In the reproduced burst, the second full semantic-token request hit
the serialized token cache but measured about 2034ms because the queued
project update woke between foreground requests and monopolized the cooperative
scheduler.

Accepted change:

- The server records foreground activity at request/notification entry and
  exit.
- Queued UnifiedProject updates check that the foreground path has been idle
  for the configured debounce interval before running.
- If foreground activity is still recent, the project update requeues itself
  instead of running.
- Shutdown and explicit test flushes force pending project updates so cache
  persistence remains deterministic.

Regression guard:

- `spec/lsp/did_change_integration_spec.cr` now checks that a queued project
  update requeues and leaves project state untouched while foreground activity
  is recent.

Evidence:

- Before this fix, broad harness on `src/compiler/lsp/server.cr` measured:
  full semantic tokens 520.0ms and repeated cached full semantic tokens
  2034.1ms.
- After this fix, the same request burst measured:
  hover 25.4ms, definition 0.8ms, references 0.4ms, completion 10.5ms,
  document symbols 12.9ms, folding 8.4ms, visible semantic tokens 4.7ms,
  full semantic tokens 177.8ms, cached full semantic tokens 41.5ms.
- Debug log showed:
  `Semantic tokens cache HIT`, then
  `UnifiedProject update deferred: foreground activity still recent`, then
  `UnifiedProject update_file` after the foreground burst.
- Focused spec:
  `crystal build spec/lsp/did_change_integration_spec.cr -o
  /tmp/lsp_did_change_spec --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_did_change_spec 120 1536 --no-color`,
  4 examples, 0 failures.

Boundary:

- Startup/open still has separate costs from synchronous project-cache load,
  prelude table rebuild/registration, and large-file document analysis. This
  landmark only closes queued project updates interrupting active foreground
  request bursts.

Trust: {F/G/R: 0.88/0.67/0.9} [verified]

### LM-592 — LSP harness default scenario uses current repo paths

Status: VERIFIED on `codegen`.

The LSP harness default scenario still referenced stale `adamas/...`
paths, including `adamas/debug_tests/check_lexer.cr`, which no longer
exists in this checkout. Running the default harness therefore failed before
it could exercise the LSP server and could be misread as an LSP regression.

Accepted change:

- The default scenario now uses current repo-relative paths:
  `src/compiler/lsp/server.cr` and `benchmarks/bench_parser_single.cr`.
- The default needles were updated to symbols that exist in those files.

Evidence:

- `crystal tool format --check benchmarks/lsp_harness.cr`
- `crystal build benchmarks/lsp_harness.cr -o
  /tmp/lsp_harness_default_fixed --error-trace`
- `scripts/run_safe.sh /tmp/lsp_harness_default_fixed 180 1536
  --server="/usr/bin/env RUN_SAFE_PASSTHROUGH_STDIO=1 scripts/run_safe.sh
  bin/adamas_lsp 180 1536" --timeout=20` exited 0.

Observed follow-up frontier:

- Default harness now runs and shows formatting/rangeFormatting on
  `src/compiler/lsp/server.cr` around 365-371ms, which is the next measurable
  foreground LSP latency candidate.

Trust: {F/G/R: 0.84/0.58/0.9} [verified]

### LM-593 — LSP formatting responses are cached per document version

Status: VERIFIED on `codegen`.

The default LSP harness showed full-document formatting around 365ms and
rangeFormatting around 365ms on `src/compiler/lsp/server.cr`. The handler
formats the whole document for both requests; rangeFormatting currently
delegates to full formatting. Repeated requests therefore paid the token-based
formatter cost again even when the document version was unchanged.

Accepted change:

- The LSP server now caches serialized formatting responses by URI and document
  version.
- The cache stores both `null` no-op responses and full edit responses.
- Formatting cache entries are invalidated on `didChange` and `didClose`.

Evidence:

- Focused formatting specs:
  `crystal build spec/lsp/formatting_integration_spec.cr
  spec/lsp/did_change_integration_spec.cr -o /tmp/lsp_formatting_spec
  --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_formatting_spec 120 1536 --no-color`,
  6 examples, 0 failures.
- Focused harness on `src/compiler/lsp/server.cr`:
  first formatting 365.9ms, repeated formatting 149.2ms, rangeFormatting
  138.9ms.
- Debug log showed `Formatting cache HIT` for repeated formatting and for
  rangeFormatting delegation.

Boundary:

- The remaining ~140-150ms repeated formatting cost is response-size cost from
  returning a large whole-document edit, not formatter recomputation. True
  range formatting remains a separate feature frontier.

Trust: {F/G/R: 0.85/0.61/0.89} [verified]

### LM-594 — LSP formatting returns minimal edit payloads

Status: VERIFIED on `codegen`.

After LM-593, repeated formatting no longer recomputed the formatter for an
unchanged document version, but responses could still serialize a whole-document
replacement for a tiny formatting delta. That kept cached `rangeFormatting`
around 140-150ms on `src/compiler/lsp/server.cr` because the response payload
was large even when the formatter was not rerun.

Accepted change:

- `handle_formatting` still runs the existing token formatter and preserves its
  output semantics.
- The server now computes one minimal byte-span `TextEdit` from the common
  prefix/suffix between original and formatted source instead of always
  replacing the whole document.
- Minimal formatting edit ranges are converted to LSP UTF-16 character
  positions so non-ASCII source does not receive byte-based edit columns.
- No-op formatting still returns and caches `null`.
- Full-document `rangeFormatting` still delegates to document formatting and
  benefits from the same minimal cached response shape.
- Partial `rangeFormatting` requests return `null` until true partial
  formatting exists, avoiding edits outside the requested range.

Evidence:

- Focused formatting specs:
  `crystal build spec/lsp/formatting_integration_spec.cr
  spec/lsp/did_change_integration_spec.cr -o /tmp/lsp_formatting_spec
  --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_formatting_spec 120 1536 --no-color`,
  11 examples, 0 failures.
- Default LSP harness via
  `scripts/run_safe.sh /tmp/lsp_harness_minimal_format 120 1536 --server
  bin/adamas_lsp` passed. A post-hardening run measured formatting at
  381.5ms and cached full-doc `rangeFormatting` at 142.3ms.
- Full LSP suite:
  `crystal build spec/lsp/*_spec.cr -o /tmp/lsp_full_spec --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_full_spec 120 1536 --no-color`, 224 examples,
  0 failures.

Boundary:

- This is a response-payload and correctness fix, not true partial range
  formatting.
- First formatting still pays the token formatter cost; startup/open latency is
  unaffected.

Trust: {F/G/R: 0.86/0.62/0.9} [verified]

### LM-595 — LSP range formatting only returns contained edits

Status: VERIFIED on `codegen`.

LM-594 made partial `rangeFormatting` safe by returning `null` for non-full
ranges. The next useful step was to make partial ranges productive without
building a separate partial formatter.

Accepted change:

- `rangeFormatting` now runs the same whole-document formatter for partial
  ranges, computes the minimal edit, and returns that edit only when the edit
  range is fully contained by the requested range.
- If the whole-document formatter would require a change outside the requested
  range, the server returns `null`.
- Full-document range formatting still delegates to `handle_formatting`, so it
  keeps using the versioned formatting response cache.

Evidence:

- Focused formatting specs:
  `crystal build spec/lsp/formatting_integration_spec.cr
  spec/lsp/did_change_integration_spec.cr -o /tmp/lsp_range_formatting_spec
  --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_range_formatting_spec 120 1536 --no-color`,
  13 examples, 0 failures.
- Default LSP harness:
  `scripts/run_safe.sh /tmp/lsp_harness_range_format 120 1536 --server
  bin/adamas_lsp`, passed; full-document `rangeFormatting` measured
  139.8ms after the formatting cache was populated.
- Full LSP suite:
  `crystal build spec/lsp/*_spec.cr -o /tmp/lsp_full_spec --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_full_spec 120 1536 --no-color`, 226 examples,
  0 failures.

Boundary:

- This is still not a true local formatter; partial range requests pay the
  whole-document formatter cost when the document is not already cached.
- The containment rule is intentionally conservative and returns no edit for
  multi-edit documents when one computed minimal span would cross outside the
  requested range.

Trust: {F/G/R: 0.85/0.64/0.9} [verified]

### LM-596 — LSP project cache skips vendored stdlib payloads

Status: VERIFIED on `codegen`.

The LSP startup cache was restoring 1906 files on initialize. Cache inspection
showed 1819 entries were under `src/stdlib`, taking about 4MB of a 5.9MB cache.
That made initialize pay for stdlib project-cache reconstruction even when the
active editing surface was compiler code.

Accepted change:

- `ProjectCache.cacheable_project_file?` rejects `src/stdlib/**` while keeping
  project-local compiler/runtime files.
- Project cache load filters legacy cache entries through that predicate, so an
  existing stdlib-heavy cache does not need to be deleted manually.
- Project cache save writes the filtered payload, and background project
  indexing skips `src/stdlib/**`.
- Regression coverage asserts that a compiler file remains cacheable while a
  vendored stdlib file is excluded from the saved project cache payload.

Evidence:

- Cache specs:
  `crystal build spec/lsp/project_cache_validation_spec.cr
  spec/lsp/project_cache_type_summary_spec.cr -o /tmp/lsp_project_cache_spec
  --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_project_cache_spec 120 1536 --no-color`,
  6 examples, 0 failures.
- Warm focused startup harness:
  `LSP_DEBUG=1 scripts/run_safe.sh /tmp/lsp_harness_cache_slim 120 1536
  --server bin/adamas_lsp --file src/compiler/lsp/server.cr -v`.
  Project cache load went from 1906 files / ~300ms to 87 files / 59.0ms, and
  initialize measured 154.6ms while `didOpen` still used cached expression
  types.
- Default LSP harness:
  `scripts/run_safe.sh /tmp/lsp_harness_cache_slim 120 1536 --server
  bin/adamas_lsp`, passed; initialize measured 152.6ms.
- Full LSP suite:
  `crystal build spec/lsp/*_spec.cr -o /tmp/lsp_full_spec --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_full_spec 120 1536 --no-color`, 227 examples,
  0 failures.

Boundary:

- This does not change the separate prelude cache; background prelude table
  rebuild still costs about 190-200ms before the first document fully settles.
- This is scoped to the project cache. Opening `src/stdlib/**` directly still
  falls back to normal document analysis rather than relying on project-cache
  state.

Trust: {F/G/R: 0.88/0.66/0.91} [verified]

### LM-597 — LSP project-cache maintenance waits for first foreground document

Status: VERIFIED for the stale-cache scheduler guard on `codegen`.

A warm-cache LSP startup can still have invalid project-cache paths when a file
changed since the previous save. Those invalid paths were scheduled as
background work, but the spawned fiber could run `UnifiedProject` reparse or
background project indexing before the server had read the client's first
`textDocument/didOpen`. Because Crystal fibers are cooperative, that CPU-bound
maintenance work could delay the first opened document even though it was not
needed for the foreground document state.

Accepted change:

- Project-cache invalid reparse now waits for the existing project-update idle
  window and also requires at least one opened document before doing CPU-bound
  maintenance.
- Background project indexing uses the same document-present idle boundary
  before indexing a missing project file.
- The existing forced flush path is unchanged for explicit project-update
  flushes; this only moves opportunistic cache maintenance out of the startup
  gap between `initialize` and the first `didOpen`.

Evidence:

- Focused regression spec:
  `crystal build spec/lsp/did_change_integration_spec.cr -o
  /tmp/lsp_did_change_project_maintenance_idle_spec --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_did_change_project_maintenance_idle_spec 120
  1536 --no-color`, 5 examples, 0 failures.
- Warm focused LSP harness with debug:
  `LSP_DEBUG=1 scripts/run_safe.sh /tmp/lsp_harness_reparse_idle 120 1536
  --server /tmp/lsp_main_project_maintenance_idle --file
  src/compiler/lsp/server.cr -v`, passed with zero diagnostics. The stale-cache
  maintenance no longer ran before the first `didOpen`; after warming the cache
  there were no invalid paths.
- Default LSP harness:
  `scripts/run_safe.sh /tmp/lsp_harness_reparse_idle 120 1536 --server
  /tmp/lsp_main_project_maintenance_idle`, passed with definition, signature,
  and completion checks intact.

Refuted / limited evidence:

- Prelude-cache internals were measured but not changed. Skipping method range
  cache entries, sharing cached leaf method scopes, and fusing the method-index
  walk did not produce a meaningful real-harness improvement.
- This is not a general warm-cache `didOpen` latency closure. The remaining
  open cost is still dominated by prelude cache table rebuild/apply timing and
  large-file document analysis.

Trust: {F/G/R: 0.84/0.55/0.88} [verified]

### LM-598 — LSP formatter preserves stable large documents

Status: VERIFIED for the formatter/LSP formatting reliability slice on
`codegen`.

The LSP formatter was still expensive and risky on real source files because
the token formatter treated skipped whitespace as disposable. On
`src/compiler/lsp/server.cr`, formatting expanded the file from 486,822 bytes
to 4,737,482 bytes before the first fix, then continued to produce large
whole-file replacement spans through independent whitespace bugs. The root
pattern was not the LSP minimal-edit algorithm; it was a formatter boundary
violation: a partial token formatter was synthesizing indentation and spacing
for syntax it could not fully model.

Accepted change:

- Line starts now preserve the original source prefix instead of reindenting
  every line from the formatter's partial block model.
- Existing non-newline gaps are preserved by default and by operator-like
  rules where the formatter cannot safely distinguish all roles.
- Namespace paths keep `::` tight, variable-like type symbols keep `: Type`,
  named arguments keep `name: value`, bare splats keep `*,`, block pipes and
  indexers keep `|h, k| h[k]`, aligned inline comments keep their alignment,
  and line-continuation backslashes keep their source gap.
- The formatter still performs the narrow proven edit for compact assignment
  spacing such as `x=1` -> `x = 1`.

Evidence:

- Direct large-file measurement through `run_safe`:
  `Formatter.format(File.read("src/compiler/lsp/server.cr"))` now returns the
  original bytes exactly (`source_bytes=486822`, `formatted_bytes=486822`,
  `equal=true`) instead of producing a large replacement.
- Focused formatter guard:
  `crystal build spec/formatter_spec.cr -o /tmp/formatter_spec --error-trace`
  and `scripts/run_safe.sh /tmp/formatter_spec 60 1536 --no-color`, 6
  examples, 0 failures.
- LSP formatting integration:
  `crystal build spec/lsp/formatting_integration_spec.cr -o
  /tmp/lsp_formatting_spec --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_formatting_spec 120 1536 --no-color`, 9
  examples, 0 failures.
- Full LSP suite:
  `crystal build spec/lsp/*_spec.cr -o /tmp/lsp_full_formatter_spec
  --error-trace` and `scripts/run_safe.sh /tmp/lsp_full_formatter_spec 120
  1536 --no-color`, 228 examples, 0 failures.
- Hygiene:
  `crystal tool format --check src/compiler/formatter.cr spec/formatter_spec.cr`
  and `git diff --check`.

WBA framing:

- Window/trigger: LSP formatting on a stable large source file returned a huge
  replacement or spent time serializing one.
- Transport corridor: token gaps and line prefixes cross from lexer spans into
  LSP edit generation.
- Boundary: a lightweight token formatter may insert locally proven missing
  spaces, but it must not synthesize indentation/alignment for syntax it does
  not fully understand.
- Legal move: preserve source gaps/prefixes unless a narrow token-pair rule is
  proven safe; use exact byte-equality on a real LSP source file as the
  collapse check.
- Potential decrease: replacement span and response size drop from whole-file
  scale to `null` for already stable source, while retaining focused `x=1`
  formatting.

Trust: {F/G/R: 0.89/0.60/0.91} [verified]

### LM-599 — LSP semantic-token full response avoids tuple-key sort overhead

Status: VERIFIED for the semantic-token hot-path slice on `codegen`.

After LM-598 removed the formatter replacement-size frontier, the default LSP
harness exposed `textDocument/semanticTokens/full` as the next visible
foreground request cost on `src/compiler/lsp/server.cr`. Profiling showed the
first full-token request was not cache-miss dominated alone: token collection
spent about 43ms in the lexical pass and about 19ms in `sort+dedup`, before
JSON transport of a roughly 141k-int response.

Accepted change:

- The lexical token pass now carries a monotonic line-offset cursor instead of
  binary-searching line offsets for each lexer token. This preserves the
  existing byte-column coordinate behavior because it uses the same
  line-offset table and offset arithmetic.
- Semantic token sorting now uses a direct comparator instead of
  `sort_by!` with tuple keys. The ordering remains line, start column,
  descending token-type priority, and descending length.

Evidence:

- Semantic-token profile on `src/compiler/lsp/server.cr` before the direct
  comparator showed approximately:
  `setup=1.8ms ast_walk=12.6ms lexical=43.2ms sort+dedup=19.0ms encode=1.0ms
  total=77.7ms`.
- After the change, the same profile showed approximately:
  `setup=1.9ms ast_walk=11.8ms lexical=40.5ms sort+dedup=9.3ms encode=1.1ms
  total=64.6ms`.
- Focused semantic-token specs:
  `crystal build spec/lsp/semantic_tokens_spec.cr
  spec/lsp/semantic_tokens_integration_spec.cr
  spec/lsp/lsp_semantic_tokens_spec.cr -o /tmp/lsp_semantic_specs
  --error-trace` and `scripts/run_safe.sh /tmp/lsp_semantic_specs 120 1536
  --no-color`, 35 examples, 0 failures.
- Default LSP harness through nested `run_safe` wrappers:
  `scripts/run_safe.sh /tmp/lsp_harness_semantic_sort 180 1536
  --server="/usr/bin/env RUN_SAFE_PASSTHROUGH_STDIO=1 scripts/run_safe.sh
  /tmp/lsp_main_semantic_sort 180 1536" --timeout=20`, passed with zero
  diagnostics. `semantic tokens` measured 118.7ms, `formatting` 78.9ms with
  no edits, and full-document `rangeFormatting` 0.1ms with no edits.
- Full LSP suite:
  `crystal build spec/lsp/*_spec.cr -o /tmp/lsp_full_semantic_sort_spec
  --error-trace` and `scripts/run_safe.sh /tmp/lsp_full_semantic_sort_spec
  120 1536 --no-color`, 228 examples, 0 failures.
- Hygiene:
  `crystal tool format --check src/compiler/lsp/server.cr` and
  `git diff --check`.

WBA framing:

- Window/trigger: the active full-token request had a local
  `sort+dedup` maximizer and repeated offset-to-line lookup inside a
  monotonic lexical scan.
- Transport corridor: lexer token offsets move monotonically through the same
  line-offset table; raw semantic tokens move through a fixed sort order before
  overlap deduplication.
- Boundary: token coordinates and priority semantics must remain identical to
  the existing full-token contract.
- Legal move: carry the current line cursor forward for lexical tokens and
  compare `RawToken` fields directly during sort.
- Potential decrease: per-token lookup and sort key allocation drop without
  changing emitted semantic-token ordering.

Trust: {F/G/R: 0.88/0.63/0.90} [verified]

### LM-600 — Parser preload capacity no longer double-lexes large sources

Status: VERIFIED for the parser/LSP open-latency slice on `codegen`.

Warm-cache `didOpen` on `src/compiler/lsp/server.cr` remained parser-heavy
after the formatter and semantic-token hot-path fixes. An in-process split
with project cache loaded measured `analyze_ms=225.84ms`; parsing the large
source itself accounted for most of that path. A direct parser probe showed the
constructor was lexing once to count tokens for exact `Array(Token)` capacity,
then lexing again to fill the token buffer.

Accepted change:

- Normal parser construction now uses a byte-size token-capacity estimate
  instead of lexing the source once just for capacity.
- The old exact counting path remains available for the tiny
  `ADAMAS_TRACE_TOKEN_PRELOAD` trace mode, where preserving token-preload
  diagnostics is more useful than avoiding the extra pass.
- The heuristic is intentionally conservative enough to avoid the 4096MB memory
  regression seen with a more aggressive `/6` estimate during host compiler
  build verification.

Evidence:

- Before this branch, repeated large-file parser probes on
  `src/compiler/lsp/server.cr` measured about `148-159ms` total parse time.
- After the accepted `/8` no-trivia heuristic, repeated probes measured about
  `122-126ms` after warmup, with the same `71876` parser tokens and `36642`
  arena nodes.
- Default LSP harness through nested `run_safe` wrappers measured first
  `didOpen settled` at `259.7ms`, second `didOpen settled` at `228.5ms`,
  semantic tokens at `118.6ms`, formatting at `78.6ms` with no edits, and
  full-document range formatting at `0.1ms` with no edits.
- Parser specs:
  `crystal build spec/parser/*_spec.cr -o /tmp/parser_specs_preload
  --error-trace` and `scripts/run_safe.sh /tmp/parser_specs_preload 120 1536
  --no-color`, 2181 examples, 0 failures, 1 pre-existing pending example.
- Full LSP suite:
  `crystal build spec/lsp/*_spec.cr -o /tmp/lsp_full_parser_preload_spec
  --error-trace` and `scripts/run_safe.sh /tmp/lsp_full_parser_preload_spec
  120 1536 --no-color`, 228 examples, 0 failures.
- Host compiler build sanity:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 8192 build
  src/adamas.cr -o /tmp/cv2_parser_preload --error-trace`, exited 0
  with only the existing `ld64.lld -stack_size` warning.
- Hygiene:
  `git diff --check`.

Refuted / limited evidence:

- `LSP_AST_CACHE=1` did not materially improve warm open latency
  (`didOpen settled` stayed around `261.8ms`) and had a cold shutdown outlier,
  so AST cache is not accepted as the current foreground-open fix.
- A `/6` no-trivia capacity estimate kept the parse speedup but tripped the
  4096MB `run_safe` limit during host compiler build. The accepted `/8`
  heuristic avoids that over-allocation pressure.
- `crystal tool format --check src/compiler/frontend/parser.cr` still wants
  broad unrelated historical formatting churn in this large file. That churn
  was explicitly removed from the patch; this slice uses `git diff --check`
  and targeted parser/LSP/compiler checks instead.

WBA framing:

- Window/trigger: large-source parser construction showed a repeated
  token-preload counting pass immediately followed by the real token-fill pass.
- Transport corridor: source bytes move through lexer tokenization into the
  parser token buffer.
- Boundary: token stream contents, parser order, tracing semantics, and AST
  output must remain unchanged; only initial token-array capacity may change.
- Legal move: replace exact pre-counting with a local byte-size capacity
  estimate on the normal path, keeping exact counting for explicit trace mode.
- Potential decrease: remove one full lexer traversal from parser startup while
  avoiding capacity over-allocation that increases compiler-build memory.

Trust: {F/G/R: 0.87/0.68/0.89} [verified]

### LM-601 — LSP debug payloads are lazy on foreground hot paths

Status: VERIFIED for the focused LSP hover/open slice on `codegen`.

After LM-600, the default harness still showed point requests as mostly fast,
but first hover on `src/compiler/lsp/server.cr` could sit around 20-30ms even
when debug logging was disabled. Source inspection found several expensive
debug payloads still evaluated eagerly before `debug(message)` returned:
large-source line counts, hover snippets, and definition context slices. The
hover snippet was especially visible because it extracts source text for the
enclosing `Server` class span.

Accepted change:

- `debug` now has a block form that evaluates only when `LSP_DEBUG` or
  `LSP_DEBUG_LOG` is enabled.
- Hot-path debug payloads that scan/slice large source text now use the lazy
  form.
- Existing eager `debug("literal/interpolated cheap metadata")` call sites are
  left alone in this slice.

Evidence:

- Baseline default LSP harness after LM-600, through nested `run_safe`
  wrappers, measured first hover on `src/compiler/lsp/server.cr` at `23.7ms`,
  first full semantic tokens at `126.3ms`, and formatting at `78.3ms`.
- After the lazy-debug patch, the same harness measured first hover at `5.9ms`,
  semantic tokens at `118.5ms`, and formatting at `76.9ms`, with zero
  diagnostics.
- Full LSP suite:
  `crystal build spec/lsp/*_spec.cr -o /tmp/lsp_full_lazy_debug_spec
  --error-trace` and `scripts/run_safe.sh /tmp/lsp_full_lazy_debug_spec 120
  1536 --no-color`, 228 examples, 0 failures.
- LSP server build sanity:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 build
  src/lsp_main.cr -o /tmp/lsp_main_lazy_debug --error-trace -D
  without_openssl`, exited 0.
- Hygiene:
  `crystal tool format --check src/compiler/lsp/server.cr`.

Boundary:

- This is not the main didOpen/prelude-cache closure. Subagent and Grok
  sidecars both pointed at broader remaining root families: foreground-idle
  scheduling around prelude/cache work, stale expression-type cache invalidation
  after edits, and redundant line-offset construction in semantic-token
  collection. Those remain separate candidate slices.

WBA framing:

- Window/trigger: disabled debug logging still paid source slicing/scanning
  costs in foreground request handlers.
- Transport corridor: debug metadata is carried from document source into the
  logging sink only when debugging is enabled.
- Boundary: protocol responses, diagnostics, and actual debug output must stay
  unchanged when logging is enabled.
- Legal move: add lazy block-based debug evaluation and apply it only to
  expensive payloads.
- Potential decrease: request-path source slicing/scanning drops when debug is
  off, without changing LSP semantics.

Trust: {F/G/R: 0.84/0.54/0.88} [verified]

### LM-602 — LSP didChange invalidates per-file cached expression types

Status: VERIFIED for the focused LSP edit-reanalysis cache slice on
`codegen`.

The LSP legacy foreground document path can use `@cached_expr_types[path]` to
skip type inference when cache data exists. That is valid for unchanged files
loaded from project/prelude cache, but it was unsafe for `didChange`: the
handler invalidated semantic-token and formatting caches only after reanalysis,
and never invalidated per-file cached expression types. During the debounce
window before `UnifiedProject#update_file` refreshes the path, the immediate
legacy analysis could therefore reuse expression types from old source text.

Accepted change:

- `didChange` now invalidates semantic-token, formatting, and per-path
  expression-type caches before it re-analyzes the changed text.
- The invalidation is scoped to the changed document path; unchanged project
  and prelude cache entries stay available.
- A focused regression seeds a stale expression-type entry, sends a full-sync
  `didChange`, and asserts the per-path cache is gone while the updated
  document text is stored.

Evidence:

- Focused didChange spec:
  `crystal build spec/lsp/did_change_integration_spec.cr -o
  /tmp/lsp_did_change_cached_expr_spec --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_did_change_cached_expr_spec 120 1536
  --no-color`, 6 examples, 0 failures.
- Full LSP suite:
  `crystal build spec/lsp/*_spec.cr -o
  /tmp/lsp_full_cached_expr_invalidate_spec --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_full_cached_expr_invalidate_spec 120 1536
  --no-color`, 229 examples, 0 failures.
- Hygiene:
  `crystal tool format --check src/compiler/lsp/server.cr
  spec/lsp/did_change_integration_spec.cr spec/lsp/support/server_helper.cr`.

Boundary:

- This closes the stale per-file expression-type cache risk for direct
  `didChange` reanalysis. It does not solve broader background-scheduler
  monopolization, project-cache save jitter, or redundant semantic-token
  line-offset construction.

WBA framing:

- Window/trigger: an edit arrives for a path that may already have cached
  expression types from older source bytes.
- Transport corridor: expression-type cache entries travel from project/prelude
  cache into foreground hover/navigation type contexts.
- Boundary: unchanged cached files remain valid; only the actively changed
  document path must lose source-derived cache state before reanalysis.
- Legal move: delete the changed path from `@cached_expr_types` before the
  legacy `analyze_document` call.
- Potential decrease: stale source-derived state for the active edit drops to
  zero before the new document state is built.

Trust: {F/G/R: 0.88/0.66/0.91} [verified]

### LM-603 — LSP semantic-token collection reuses document line offsets

Status: VERIFIED for the semantic-token hot-path slice on `codegen`.

After LM-599, full semantic-token requests were still one of the visible
foreground costs on `src/compiler/lsp/server.cr`. Source inspection showed a
simple duplicated traversal: `DocumentState` already stores line offsets for
the open document, but `collect_semantic_tokens` rebuilt offsets inside
`SemanticTokenContext`, then the lexical token pass rebuilt them again.

Accepted change:

- `collect_semantic_tokens` accepts optional precomputed line offsets.
- `handle_semantic_tokens` and `handle_semantic_tokens_range` pass
  `doc_state.line_offsets`.
- Existing tests and direct callers keep the old behavior by falling back to
  local offset construction when no offsets are provided.

Evidence:

- Focused semantic-token specs:
  `crystal build spec/lsp/semantic_tokens_spec.cr
  spec/lsp/semantic_tokens_integration_spec.cr
  spec/lsp/lsp_semantic_tokens_spec.cr -o
  /tmp/lsp_semantic_line_offsets_specs --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_semantic_line_offsets_specs 120 1536
  --no-color`, 35 examples, 0 failures.
- Default LSP harness through nested `run_safe` wrappers passed with zero
  diagnostics and measured full semantic tokens around `115.3-115.7ms` on
  `src/compiler/lsp/server.cr` in the sampled runs.
- Full LSP suite:
  `crystal build spec/lsp/*_spec.cr -o /tmp/lsp_full_line_offsets_spec
  --error-trace` and `scripts/run_safe.sh /tmp/lsp_full_line_offsets_spec 120
  1536 --no-color`, 229 examples, 0 failures.
- Hygiene:
  `crystal tool format --check src/compiler/lsp/server.cr`.

Boundary:

- The wall-clock gain is modest and timing remains noisy. This is a redundant
  traversal cleanup, not the larger didOpen/prelude scheduler fix. The next
  bigger LSP frontier is still foreground-idle scheduling and indexing
  notification coalescing.

WBA framing:

- Window/trigger: semantic-token requests for an already-open document rebuild
  line offsets that are already stored in `DocumentState`.
- Transport corridor: byte offsets from AST and lexer tokens map through the
  same line-offset table into LSP token coordinates.
- Boundary: token positions, ordering, range behavior, and public helper calls
  must stay unchanged.
- Legal move: carry the existing line-offset table into semantic-token
  collection, with fallback construction for standalone callers.
- Potential decrease: one or two full-source line-offset scans are removed from
  the foreground semantic-token request.

Trust: {F/G/R: 0.84/0.58/0.89} [verified]

### LM-604 — LSP indexing notifications are foreground-document scoped

Status: VERIFIED for the LSP notification-boundary slice on `codegen`.

The default harness could capture dozens of `crystal/indexing` /
`crystal/indexed` notifications for only a few opened files. The root was that
notification emission lived inside `analyze_parsed_document`, so nested
dependency analyses published UI indexing state transitions just like the
foreground document analysis did.

Accepted change:

- `analyze_document` / `analyze_parsed_document` now accept a
  `publish_indexing` flag.
- Foreground `didOpen` / `didChange` keep the default publishing behavior.
- Dependency analysis calls pass `publish_indexing: false`, so dependency
  parsing/analysis no longer leaks user-visible indexing state transitions.

Evidence:

- Before this slice, a verbose default harness run after LM-603 captured
  `crystal/indexing: 33x` and `crystal/indexed: 33x` for three opened files.
- After the patch, the same harness through nested `run_safe` wrappers captured
  `crystal/indexing: 3x`, `crystal/indexed: 3x`, and
  `textDocument/publishDiagnostics: 3x`, with zero diagnostics.
- Full LSP suite:
  `crystal build spec/lsp/*_spec.cr -o /tmp/lsp_full_index_notifications_spec
  --error-trace` and
  `scripts/run_safe.sh /tmp/lsp_full_index_notifications_spec 120 1536
  --no-color`, 229 examples, 0 failures.
- LSP server/harness build sanity:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 build
  src/lsp_main.cr -o /tmp/lsp_main_index_notifications --error-trace -D
  without_openssl` and
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 build
  benchmarks/lsp_harness.cr -o /tmp/lsp_harness_index_notifications
  --error-trace`, both exited 0.
- Hygiene:
  `crystal tool format --check src/compiler/lsp/server.cr`.

Boundary:

- This fixes protocol notification noise from nested dependency analysis. It
  does not make dependency analysis itself cheaper or solve the larger
  foreground-idle scheduler/prelude-cache frontier.

WBA framing:

- Window/trigger: nested dependency analysis emits the same indexing protocol
  events as foreground document analysis.
- Transport corridor: indexing state crosses from internal analysis phases to
  client-visible JSON-RPC notifications.
- Boundary: clients should see foreground document indexing transitions, not
  every nested dependency traversal.
- Legal move: carry a `publish_indexing` bit through the analysis corridor and
  disable it for dependency loads.
- Potential decrease: notification count per harness scenario drops from
  dependency-scale to opened-document-scale.

Trust: {F/G/R: 0.86/0.64/0.90} [verified]

### LM-605 — LSP background prelude load has a single in-flight owner

Status: VERIFIED for the LSP startup/prelude scheduler slice on `codegen`.

After LM-604, a scheduler-fairness experiment around cached prelude
rehydration exposed a stronger root cause: while `@prelude_state` was still nil,
`ensure_prelude_loaded` called `load_prelude_background` on every foreground
request. Each call spawned another prelude cache load even though the first one
was already in flight. Under debug tracing this produced many repeated
`Background: prelude cache loaded` / `Background: SymbolTable rebuilt` entries
and inflated point-request latency.

Accepted change:

- `load_prelude_background` now returns immediately when a prelude load is
  already in flight or when a prelude state already exists.
- `ensure_prelude_loaded` distinguishes "still loading" from "missing" and no
  longer starts duplicate background loads during startup.
- Added a focused regression that constructs a background-indexing LSP server,
  calls the prelude ensure path repeatedly, and asserts that only one
  `Background prelude loading started` event is emitted.

Evidence:

- Focused regression:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 2048 spec
  spec/lsp/background_prelude_loading_spec.cr --error-trace`, 1 example,
  0 failures.
- Full LSP suite:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp --error-trace`, 230 examples, 0 failures.
- LSP server/harness build sanity:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 build
  src/lsp_main.cr -o /tmp/lsp_main_single_prelude --error-trace -D
  without_openssl` and
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 build
  benchmarks/lsp_harness.cr -o /tmp/lsp_harness_single_prelude --error-trace`,
  both exited 0.
- Default harness through nested `run_safe` wrappers passed with zero
  diagnostics, `crystal/indexing: 3x`, `crystal/indexed: 3x`, first hover
  `6.6ms`, full semantic tokens `114.6ms`, formatting `73.8ms`, and first
  initialize `195.4ms` in the sampled no-debug run.
- Debug harness after the fix showed one prelude cache load, one symbol-table
  rebuild, and one background-prelude apply.
- Hygiene: `git diff --check`.

Refuted branch:

- Adding cooperative `Fiber.yield` inside cached prelude reconstruction without
  first fixing the in-flight guard was refuted. It made the duplicate-load bug
  obvious and worsened point-request timings by allowing many concurrently
  spawned prelude loaders to interleave.

Boundary:

- This fixes duplicate background prelude scheduling. It does not claim that
  project-cache loading on `initialize`, fallback no-cache prelude parsing, or
  inner TypeIndex restoration loops are fully optimized.

WBA framing:

- Window/trigger: foreground requests observe `@prelude_state == nil` while
  `@prelude_loading == true`.
- Transport corridor: one background prelude state should move through the
  channel to `apply_background_prelude`.
- Boundary: partially rebuilt cache maps stay unpublished until the single
  background load completes.
- Legal move: reject duplicate load starts at the prelude-loader entry point
  and treat foreground ensure calls as wait/observe while loading.
- Potential decrease: active background prelude loaders are bounded from
  request-count scale to one.

Trust: {F/G/R: 0.88/0.62/0.91} [verified]

### LM-606 — Opt-in LSP AST cache reuses unchanged foreground documents

Status: VERIFIED for the opt-in `LSP_AST_CACHE=1` foreground-open path on
`codegen`.

After LM-605, the remaining warm `didOpen` cost on
`src/compiler/lsp/server.cr` was dominated by foreground parsing. A standalone
parser probe measured parser construction/token preload around `41ms`,
`parse_program` around `93ms`, and total parse time around `133-135ms` for the
large LSP server file. Existing AST-cache integration covered prelude and
dependencies, but foreground `didOpen` / `didChange` always reparsed the
current buffer.

Accepted change:

- `didOpen` and `didChange` may use `load_or_parse_disk_program` for a
  foreground document only when AST cache is enabled for that path and the open
  editor buffer exactly matches the file on disk.
- Unsaved foreground edits parse the editor buffer normally and never reuse a
  disk AST cache entry.
- Added focused foreground AST-cache integration specs for unchanged reopen and
  unsaved-edit rejection.

Evidence:

- Focused foreground AST-cache regression:
  `XDG_CACHE_HOME=/private/tmp/cv2_lsp_fg_ast_spec_xdg3
  CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_fg_ast_spec3 scripts/run_safe.sh
  /Users/sergey/.local/bin/crystal 120 2048 spec
  spec/lsp/ast_cache_foreground_integration_spec.cr --error-trace`, 2
  examples, 0 failures.
- Full LSP suite:
  `XDG_CACHE_HOME=/private/tmp/cv2_lsp_full_xdg
  CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_fg_ast_fullspec2 scripts/run_safe.sh
  /Users/sergey/.local/bin/crystal 240 4096 spec spec/lsp --error-trace`, 232
  examples, 0 failures.
- LSP server/harness build sanity with `src/lsp_main.cr` and
  `benchmarks/lsp_harness.cr` both exited 0 under `scripts/run_safe.sh`.
- Warm harness with `LSP_AST_CACHE=1` moved repeated foreground `didOpen` for
  `src/compiler/lsp/server.cr` from the baseline `~253ms` / `~249ms` to
  `~143ms` / `~135ms` on the patched build, with zero diagnostics.
- Default no-`LSP_AST_CACHE` second warm run stayed at `~251ms` first
  `didOpen`, so the new foreground cache path remains opt-in.
- Hygiene: `crystal tool format --check
  src/compiler/lsp/server.cr
  spec/lsp/ast_cache_foreground_integration_spec.cr` and `git diff --check`.

Refuted/default boundary:

- This does not enable AST cache by default. The baseline
  `LSP_AST_CACHE=1` run already had signature/completion summary deltas versus
  the default path, so this patch only broadens the existing opt-in cache path
  where the editor buffer is proven identical to disk.

WBA framing:

- Window/trigger: an opened foreground buffer is byte-identical to its disk
  file and has an eligible AST-cache entry.
- Transport corridor: disk/source-mtime AST cache moves into foreground LSP
  analysis instead of reparsing the same bytes.
- Boundary: unsaved editor buffers must not cross the disk-AST boundary.
- Legal move: load the cached disk program only after file size and full byte
  equality checks against the current editor buffer.
- Potential decrease: foreground parse work for unchanged cached files drops
  from full parse cost to cache-load cost while preserving buffer semantics.

Trust: {F/G/R: 0.88/0.58/0.90} [verified]

### LM-607 — LSP AST-cache mode still uses the prelude summary cache

Status: VERIFIED for the opt-in LSP AST-cache startup/prelude-cache slice on
`codegen`.

After LM-606, a targeted warm-start audit split the remaining candidates. The
one-file warm harness refuted project-cache load as the dominant current
`initialize` cost: with a valid cache, `try_load_project_cache` reported
`cache=~2.9ms`, and disabling `LSP_PROJECT_CACHE` made `didOpen` fall back to
dependency analysis and grow to about `2533ms`. The stronger root was that
`prelude_cache_enabled?` returned false whenever `LSP_AST_CACHE=1`, so the
AST-cache mode could skip a valid prelude summary cache and enter the full
prelude parse path.

Accepted change:

- Prelude summary cache remains enabled when `LSP_AST_CACHE=1`; AST cache still
  handles eligible foreground/dependency AST parsing, but it no longer disables
  the faster prelude symbol-summary cache.
- Background prelude cache hydration now rebuilds symbol ranges, type strings,
  expression-type maps, and prelude method locations into local maps. Those
  maps are merged into server state only when the completed `PreludeState` is
  applied.
- The background cached-prelude path yields between independent cached files
  while rebuilding local unpublished maps, avoiding partial cache publication
  and preserving foreground scheduling.
- Added a focused regression that seeds a valid temp prelude summary cache and
  asserts that an `ast_cache: true` server loads prelude from that cache instead
  of parsing prelude files.

Evidence:

- Focused prelude AST-cache regression:
  `XDG_CACHE_HOME=/private/tmp/cv2_lsp_prelude_cache_spec_xdg
  CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_prelude_cache_spec scripts/run_safe.sh
  /Users/sergey/.local/bin/crystal 120 2048 spec
  spec/lsp/ast_cache_prelude_integration_spec.cr --error-trace`, 2 examples,
  0 failures.
- Related AST-cache specs:
  `XDG_CACHE_HOME=/private/tmp/cv2_lsp_prelude_cache_specs_xdg
  CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_prelude_cache_specs scripts/run_safe.sh
  /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/lsp/ast_cache_prelude_integration_spec.cr
  spec/lsp/ast_cache_foreground_integration_spec.cr
  spec/lsp/ast_cache_roundtrip_spec.cr
  spec/lsp/ast_cache_dependency_integration_spec.cr --error-trace`, 6
  examples, 0 failures.
- Full LSP suite:
  `XDG_CACHE_HOME=/private/tmp/cv2_lsp_prelude_cache_full_xdg
  CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_prelude_cache_fullspec
  scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec spec/lsp
  --error-trace`, 233 examples, 0 failures.
- LSP server build:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_prelude_cache_build
  scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 build
  src/lsp_main.cr -o /private/tmp/lsp_main_prelude_cache --error-trace -D
  without_openssl`, exited 0.
- Warm no-debug harness on `src/compiler/lsp/server.cr` with
  `LSP_AST_CACHE=1` reported `initialize ~106ms`, `didOpen ~133ms`, and zero
  diagnostics. The same default no-AST-cache path reported `initialize ~102ms`
  and `didOpen ~251ms`.

Refuted branches:

- Treating project-cache load as the active one-file warm-start bottleneck was
  refuted by `cache=~2.9ms` and by `LSP_PROJECT_CACHE=0` worsening foreground
  `didOpen` to about `2533ms`.
- A pure cooperative-yield patch without respecting the unpublished-cache
  boundary would be unsafe: background cache hydration mutates lookup maps used
  by foreground requests. The accepted implementation carries local maps in the
  completed prelude state and publishes them at apply time.

Boundary:

- This does not enable `LSP_AST_CACHE=1` by default. LM-606 still records
  existing signature/completion deltas under AST-cache mode. The remaining
  default-path latency is foreground parse/name-resolution work when AST cache
  is not enabled.

WBA framing:

- Window/trigger: `LSP_AST_CACHE=1` startup with a valid prelude summary cache,
  plus background cached-prelude hydration that has independent per-file cache
  units.
- Transport corridor: prelude summary/type/method cache data moves through
  local unpublished maps into a completed `PreludeState`, then into server
  lookup state at apply time.
- Boundary: foreground requests must not observe partially rebuilt prelude
  cache maps; AST-cache mode must not invalidate the prelude summary-cache
  contract.
- Legal move: keep prelude summary cache enabled for AST-cache mode and yield
  only while rebuilding local unpublished maps.
- Potential decrease: full-prelude parse work under `LSP_AST_CACHE=1` is
  replaced by summary-cache hydration, and foreground scheduling is no longer
  tied to one CPU-bound unpublished cache loop.

Trust: {F/G/R: 0.88/0.60/0.90} [verified]

### LM-608 — LSP project-cache expr types are not reused across fresh foreground parses

Status: VERIFIED for the focused warm project-cache semantic-fidelity slice on
`codegen`.

After LM-607, local harness comparison showed that the signature/completion
deltas were not unique to `LSP_AST_CACHE=1`: the same deltas appeared in warm
project-cache mode. A two-file reducer then reproduced a concrete cache
fidelity bug: the no-cache baseline returned
`value(scale : Int32) : Int32`, while the warm project-cache path returned
`value() : Int`.

Accepted change:

- Cached `SymbolSummary` method entries now rebuild `Frontend::Parameter`
  metadata, so cached `MethodSymbol`s preserve parameter names, splat/block
  shape, and type annotations.
- Cached `overload_set` summaries now rebuild
  `Semantic::OverloadSetSymbol` instead of pretending to be modules.
- Foreground `didOpen`/`didChange` analysis no longer applies project-cache
  `ExprId -> type` maps to freshly parsed foreground ASTs. Those maps are only
  considered compatible for a path when the current analysis explicitly built
  its `TypeContext` from that cache.
- Added a focused project-cache semantic-fidelity regression covering
  signature params, member completion, and method definition routing against a
  no-cache baseline.

Evidence:

- Focused/related cache specs:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_project_cache_related2
  scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp/project_cache_semantic_fidelity_spec.cr
  spec/lsp/project_cache_validation_spec.cr
  spec/lsp/project_cache_type_summary_spec.cr
  spec/lsp/ast_cache_dependency_integration_spec.cr --error-trace`, 8
  examples, 0 failures.
- Full LSP suite:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_full_spec2 scripts/run_safe.sh
  /Users/sergey/.local/bin/crystal 600 4096 spec spec/lsp --error-trace`, 234
  examples, 0 failures.
- LSP server and harness builds:
  `src/lsp_main.cr` -> `/private/tmp/lsp_main_project_fix2` and
  `benchmarks/lsp_harness.cr` -> `/private/tmp/lsp_harness_project_fix2`, both
  via `scripts/run_safe.sh`.
- Warm harness with `LSP_AST_CACHE=1` still reports fast foreground open
  (`didOpen ~138ms` on the second AST-cache run) and zero diagnostics.

Boundary:

- This fixes a real cache-fidelity subcase, but it does not close the broader
  large-repo warm-cache semantic frontier. The harness still shows warm
  project-cache/AST-cache deltas for some definition/signature/completion
  actions on `src/compiler/lsp/server.cr` and `benchmarks/bench_parser_single.cr`.
  The next root is likely missing dependency/identifier-symbol fidelity in
  summary-restored project state, not raw foreground TypeIndex reuse alone.

WBA framing:

- Window/trigger: an opened foreground document has a fresh AST, while the
  project cache holds type rows keyed only by arena-local `ExprId.index`.
- Transport corridor: symbol summaries may cross from project cache into live
  semantic tables, but expression-type rows may cross only when the current
  analysis frame certifies that the key-space is compatible.
- Boundary: foreground AST identity, project-cache TypeIndex identity, and
  cached symbol-summary shape must not be conflated.
- Legal move: rehydrate structured method symbols from summaries, and reject
  foreground cached-type transport unless the current analysis chose the cached
  type frame.
- Potential decrease: removes one stale-type bad corner without disabling
  project-cache symbol summaries or the opt-in AST-cache fast foreground parse.

Trust: {F/G/R: 0.88/0.52/0.89} [verified]

### LM-609 — LSP definitions do not hard-fail while background prelude is in flight

Status: VERIFIED for the focused warm-cache request-gating slice on `codegen`.

After LM-608, a custom harness scenario reproduced the remaining warm
`definition handle_completion` delta without the rest of the large default
scenario. Cold run returned one definition location; warm project-cache run
returned zero. With `LSP_DEBUG=1`, the request did not reach semantic
resolution: `handle_definition` logged `Definition skipped: indexing in
progress` because `@prelude_loading` was still true after foreground `didOpen`.

Accepted change:

- `indexing_in_progress?` now opportunistically applies a completed background
  prelude state, then gates only on missing document-local symbol/identifier
  state.
- Foreground requests no longer hard-return `null` solely because background
  prelude hydration is still in flight. They can use the already analyzed
  opened document and whatever prelude/project-cache state is currently
  available.
- Added a focused project-cache regression that keeps same-file method
  definition working even when `@prelude_loading` is true.

Evidence:

- Focused project-cache semantic-fidelity spec:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_def_fix_spec scripts/run_safe.sh
  /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp/project_cache_semantic_fidelity_spec.cr --error-trace`, 2
  examples, 0 failures.
- Related cache specs:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_project_cache_related3
  scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp/project_cache_semantic_fidelity_spec.cr
  spec/lsp/project_cache_validation_spec.cr
  spec/lsp/project_cache_type_summary_spec.cr
  spec/lsp/ast_cache_dependency_integration_spec.cr --error-trace`, 9
  examples, 0 failures.
- Full LSP suite:
  `CRYSTAL_CACHE_DIR=/private/tmp/cv2_lsp_full_spec3 scripts/run_safe.sh
  /Users/sergey/.local/bin/crystal 600 4096 spec spec/lsp --error-trace`, 235
  examples, 0 failures.
- Focused harness scenario:
  warm project-cache `definition handle_completion` moved from `0 locations`
  to `1 locations`.
- Full harness comparison: warm default and warm `LSP_AST_CACHE=1` now both
  return `1 locations` for `definition handle_completion`, while warm
  `LSP_AST_CACHE=1` still opens `server.cr` in about `130ms`.

Boundary:

- This closes the `handle_completion` definition gating delta. The bench-file
  deltas remain: warm project-cache/AST-cache still return zero for
  `definition Lexer bench`, `signature help Parser.new bench`, and
  `completion parser. bench`. Treat those as dependency/identifier-symbol
  fidelity issues in summary-restored project state.

WBA framing:

- Window/trigger: first foreground request after warm `didOpen`, while
  background prelude hydration is in flight or waiting to be applied.
- Transport corridor: opened-document semantic state can serve local
  definition/hover requests independently of the background prelude corridor.
- Boundary: do not claim prelude-dependent precision if prelude is still
  missing, but do not discard document-local symbol/identifier state.
- Legal move: apply a ready background prelude opportunistically, then gate on
  document-local analysis availability rather than the coarse prelude-loading
  flag.
- Potential decrease: removes one false indexing blocker without blocking the
  request path or disabling background prelude loading.

Trust: {F/G/R: 0.88/0.50/0.89} [verified]

### LM-625 - Receiver HIR calls avoid overloaded constructor dispatch in lower_call

The s2->s3 crash at `String#size <- scan_hir_function_for_live_types` was a
producer bug in central `lower_call`, not an RTA consumer bug. Pointer-safe
probes before the fix showed that `src/adamas.cr:20:3` resolved as
`IO#puts$String` with receiver `IO::FileDescriptor`, `virtual=true`, and
`ret=Nil`, but the emitted HIR `Call` already had `method_name` as tiny
pointer/value id `126`, no receiver, no args, and type `Symbol`. That bad HIR
value later crashed live-type scanning.

The fix adds named `HIR::Call.with_receiver*` factories and routes the receiver
branch of `lower_call` through those factories, so the self-hosted compiler no
longer depends on overloaded `Call.new(...)` dispatch for receiver calls at
that chokepoint. Receiverless calls are intentionally unchanged in this slice.

Evidence:

- `regression_tests/hir_call_receiver_factory_guard.sh
  /tmp/adamas_call_factory_stage1` -> `hir_call_receiver_factory_guard_ok`.
- Focused guards also passed on the same stage1:
  `p2_short_type_index_first_no_prelude.sh`,
  `multi_ref_union_truthy_narrowing_repro.sh`, and
  `class_method_noarg_super_forward_repro.sh`.
- `regression_tests/run_all_suites.sh /tmp/adamas_call_factory_stage1 4` ->
  152/152 original tests and 36/36 combined tests, all passed.
- `scripts/run_safe.sh /tmp/adamas_call_factory_stage1 900 12288
  src/adamas.cr -o /tmp/adamas_call_factory_s2` -> exit 0.
- Fresh fixed s2 compiling `src/adamas.cr` no longer stops in
  `String#size <- scan_hir_function_for_live_types`. `lldb` now stops at
  `AstToHir#pack_splat_args_for_call <- lower_call` after
  `[STAGE2_DEBUG] pass3 after lower_main call`.

Adversary notes:

- This is a frontier move, not a green bootstrap claim. The fresh fixed s2
  still exits 139 while compiling `src/adamas.cr` to s3.
- The guard is intentionally scoped to the central receiver branch. It does not
  prove that every overloaded `Call.new` constructor site is self-host safe.
- A consumer guard in live-type scanning would have hidden the producer
  corruption and is not the fix shape used here.

Trust: {F/G/R: 0.86/0.43/0.88} [verified for the central receiver-call constructor frontier]

### LM-626 - Splat formal lookup avoids Array#find in pack_splat_args_for_call

The s2->s3 crash at `AstToHir#pack_splat_args_for_call` was localized to a
block-helper lookup over compiler parameter metadata. Temporary probes on fresh
fixed s2 showed the failing call was
`Adamas::Compiler::LSP::ToolDispatch.resolve_server_path` lowering
`File.join$Path | String_splat` with two `String` args. The first manual splat
scan read the single `DefParamInfo` correctly (`is_splat=1`,
`is_double_splat=0`), the fixed/splat/post slices were valid, and
`splat_types=String,String` was produced. The next operation,
`params.find { |p| p.is_splat && !p.is_double_splat }`, crashed before
returning `splat_param`.

The fix replaces that one compiler-critical `Array#find` call with an explicit
`params.each` scan. It does not change splat packing semantics; it only avoids a
self-host-brittle block helper in the bootstrap compiler's metadata path.

Evidence:

- `crystal build src/adamas.cr -o /tmp/adamas_pack_find_stage1 --error-trace`
  -> exit 0.
- Focused guards passed on the same stage1:
  `hir_call_receiver_factory_guard.sh`,
  `hir_pack_splat_param_find_guard.sh`,
  `p2_short_type_index_first_no_prelude.sh`, and
  `class_method_noarg_super_forward_repro.sh`.
- `regression_tests/run_all_suites.sh /tmp/adamas_pack_find_stage1 4` ->
  152/152 original tests and 36/36 combined tests, all passed.
- `scripts/run_safe.sh /tmp/adamas_pack_find_stage1 900 12288
  src/adamas.cr -o /tmp/adamas_pack_find_s2` -> exit 0.
- Fresh fixed s2 compiling `src/adamas.cr` no longer exits 139 in
  `pack_splat_args_for_call`; it now aborts with `STUB CALLED:
  Adamas::HIR::AstToHir#contains_yield_deep?$Array(ExprId)_AstArena|PageArena|VirtualArena`.

Adversary notes:

- This is a frontier move, not a green bootstrap claim. The fresh fixed s2
  still does not build s3.
- The fix is intentionally scoped to the observed `params.find` in
  `pack_splat_args_for_call`. It does not claim that every `Array#find` use in
  the compiler is unsafe or fixed.
- The new residual frontier is a materialization/stub boundary for
  `contains_yield_deep?`, not evidence against the splat-param lookup move.

Trust: {F/G/R: 0.84/0.38/0.86} [verified for the File.join splat-param find crash]

### LM-627 - Union arguments can match wider union parameters during materialization

The generated-s2 abort-stub frontier at
`AstToHir#contains_yield_deep?$Array(ExprId)_AstArena|PageArena|VirtualArena`
was a generic union-compatibility gap in materialization scoring, not a backend
undefined-extern problem and not a `contains_yield_deep?`-specific issue.
`contains_yield_deep?` is declared with `preferred_arena : ArenaLike?`, where
`ArenaLike?` is `Nil | AstArena | PageArena | VirtualArena`. Fresh probes showed
the method was registered under the nilable signature, while the failing call
requested the non-nil union suffix `AstArena | PageArena | VirtualArena`.
`declared_type_match_score` could match a scalar argument against one variant of
a union parameter, but it could not match an argument that was itself a union
whose variants were all contained in the declared wider union. The sibling
`contains_yield?` survived only because historical callsite entries included a
nilable arena shape.

The fix teaches `declared_type_match_score` to compare union arguments against
union declarations: exact normalized union matches score as exact, and subset
union arguments score as compatible when every argument variant matches at least
one declared variant. This keeps the fix generic and avoids a local compiler
helper special case.

Evidence:

- `crystal build src/adamas.cr -o /tmp/adamas_cyield_fix_stage1 --error-trace`
  -> exit 0.
- `bash regression_tests/stage2_contains_yield_deep_materialization_repro.sh
  /tmp/adamas_cyield_fix_stage1` ->
  `stage2_contains_yield_deep_materialization_ok`.
- `scripts/run_safe.sh /tmp/adamas_cyield_fix_stage1 900 12288
  src/adamas.cr -o /tmp/adamas_cyield_fix_s2` -> exit 0.
- `strings /tmp/adamas_cyield_fix_s2 | rg
  'STUB CALLED: .*contains_yield_deep|contains_yield_deep'` -> no stub output.
- `nm -g /tmp/adamas_cyield_fix_s2 | rg 'contains_yield_deep'` -> real
  generated-s2 symbol present for the non-nil ArenaLike suffix.
- `regression_tests/run_all_suites.sh /tmp/adamas_cyield_fix_stage1 4` ->
  152/152 original tests and 36/36 combined tests, all passed.

Residual:

- Fresh fixed s2 compiling `src/adamas.cr` no longer aborts on the
  `contains_yield_deep?` undefined-extern stub, but still exits 139 after
  `[STAGE2_DEBUG] pass3 after lower_main call`.
- lldb stops at `EXC_BAD_ACCESS address=0x53` in
  `AstToHir#inline_yield_function <- each_param_with_index`; this is the next
  frontier and is not root-caused by this landmark.

Adversary notes:

- This is a frontier move, not a green bootstrap claim.
- The regression checks self-IR for the exact old abort-stub family and would
  fail if the stage1 compiler still emits the `contains_yield_deep?` stub.
- The fix broadens type compatibility for union-subset arguments. The full
  suites and fresh s2 build are the regression guard against obvious overload
  over-selection, but future materialization work should still treat broad
  union matching as a CAUTION surface.

Trust: {F/G/R: 0.86/0.47/0.89} [verified for union-subset materialization scoring]

### LM-628 - inline_yield_function binds callee params without a block callback

The generated-s2 crash after LM-627 was not caused by corrupted
`ParameterBuffer#to_a` output. A producer-side probe in `ParameterBuffer#to_a`
showed the returned `Array(Parameter)` had high pointer slots. The earlier
low values from `param.unsafe_as(UInt64)` were generated-s2 object tokens, not
raw array storage. A follow-up lldb run on the same frontier stopped inside the
generated block callback used by `each_param_with_index(params)` in
`inline_yield_function`, before the first probe line in that callback could
print.

The fix removes that block-callback dependency from the compiler-critical
callee-parameter binding loop inside `inline_yield_function`. It iterates the
`params` array with an explicit `while`, preserves the existing `arg_idx`
semantics for named-only separators and `&block`, and skips null raw slots when
the generated compiler represents `Parameter` as an 8-byte reference.

Evidence:

- `crystal build src/adamas.cr -o /tmp/adamas_inline_param_loop_stage1
  --error-trace` -> exit 0.
- `regression_tests/hir_inline_yield_param_bind_loop_guard.sh
  /tmp/adamas_inline_param_loop_stage1` ->
  `hir_inline_yield_param_bind_loop_guard_ok`.
- Adjacent focused guards also passed:
  `hir_pack_splat_param_find_guard.sh` and
  `stage2_contains_yield_deep_materialization_repro.sh`.
- `scripts/run_safe.sh /tmp/adamas_inline_param_loop_stage1 900 12288
  src/adamas.cr -o /tmp/adamas_inline_param_loop_s2` -> exit 0.
- Fresh fixed s2 compiling `src/adamas.cr` no longer stops in the
  `inline_yield_function <- each_param_with_index` block-proc crash.
- `regression_tests/run_all_suites.sh /tmp/adamas_inline_param_loop_stage1 4`
  -> 152/152 original tests and 36/36 combined tests, all passed.

Residual:

- Fresh fixed s2 compiling `src/adamas.cr` still exits 139 after
  `[STAGE2_DEBUG] pass3 after lower_main call`.
- lldb now stops in
  `AstToHir#reorder_named_args <- lower_call`, reached from the inlined body
  under `inline_yield_function`. This is the next frontier and is not
  root-caused by this landmark.

Adversary notes:

- This is another bounded bootstrap chokepoint removal, not a general fix for
  all generated block callbacks or every `each_param_with_index` callsite.
- A broad consumer guard that simply skipped low `param.unsafe_as(UInt64)`
  values would have been wrong: those low values were not raw array slots.
- The next crash still sits under `inline_yield_function`, so the broader
  architecture smell remains: self-hosted block callbacks in compiler metadata
  corridors are brittle and should not be multiplied.

Trust: {F/G/R: 0.84/0.36/0.88} [verified for the inline-yield parameter-binding callback frontier]

### LM-666 - Array#index fast path preserves nilable miss contract

The `AstToHir#reorder_named_args <- lower_call` generated-s2 crash after
LM-628 was not a `reorder_named_args` consumer bug. A focused reducer showed
that the HIR fast path for `Array#index(value)` returned concrete `Int32` and
used `-1` as a not-found sentinel, while the stdlib `Indexable#index` contract
returns `Nil | Int32`. That made a missed
`param_call_names.index(arg_name)` truthy in generated s2 and drove a negative
array index in the named-argument reorder result.

The fix changes `lower_array_index_dynamic` to return a nilable union:
the found path wraps the loop index as the `Int32` variant and the miss path
wraps `nil`. No `reorder_named_args` guard was added.

Evidence:

- `regression_tests/array_index_nilable_contract_repro.sh
  /tmp/adamas_reorder_probe_stage1` was red on the previous compiler with
  `miss_obj=IDX:-1`.
- `crystal build src/adamas.cr -o /tmp/adamas_array_index_contract_stage1
  --error-trace` -> exit 0.
- `regression_tests/array_index_nilable_contract_repro.sh
  /tmp/adamas_array_index_contract_stage1` -> `miss_obj=NIL`,
  `hit_obj=IDX:0`, `miss_block=NIL`, `direct_nil=NIL`.
- Adjacent bootstrap guards passed:
  `hir_inline_yield_param_bind_loop_guard.sh`,
  `hir_pack_splat_param_find_guard.sh`, and
  `stage2_contains_yield_deep_materialization_repro.sh`.
- `scripts/run_safe.sh /tmp/adamas_array_index_contract_stage1 900 12288
  src/adamas.cr -o /tmp/adamas_array_index_contract_s2` -> exit 0.
- Fresh fixed s2 compiling `src/adamas.cr` no longer stops in
  `AstToHir#reorder_named_args`; lldb now stops in
  `AstToHir#lower_case <- lower_node` under nested inlined block bodies.
- `regression_tests/run_all_suites.sh /tmp/adamas_array_index_contract_stage1 4`
  -> 152/152 original tests and 36/36 combined tests, all passed.

Residual:

- This is a frontier move, not a green bootstrap claim. Fresh fixed s2 still
  exits 139 after `[STAGE2_DEBUG] pass3 after lower_main call`.
- The new active boundary is `AstToHir#lower_case`, reached through nested
  inlined block/yield lowering under `inline_yield_function`.

Adversary notes:

- A downstream `idx >= 0` or `idx != -1` guard in `reorder_named_args` would
  have masked the source-level contract violation and left all other
  `Array#index(value)` callers with wrong truthiness.
- The block form was not changed by this slice; it already used the stdlib
  nilable path in the focused reducer.
- The broader architecture smell remains: compiler-critical metadata code is
  still passing through brittle self-hosted block/yield corridors.

Trust: {F/G/R: 0.86/0.43/0.90} [verified for Array#index(value) fast-path contract and this frontier move]

### LM-667 - Array#reduce preserves primitive element types

The `AstToHir#lower_case <- lower_node` generated-s2 crash after LM-666 was
not a `lower_case` consumer bug. The HIR intrinsic for `Array#reduce`
hardcoded its element and accumulator type to `Pointer`. That was survivable
for reference-like arrays, but wrong for primitive arrays. `lower_case`
combines case-condition ids with `conds.reduce`, where `conds` is
`Array(ValueId)` and `ValueId` is `UInt32`; generated s2 therefore produced a
pointer-shaped reduce result and fed it to `Branch.new`.

The fix changes `lower_array_reduce_dynamic` to resolve the element type with
`array_element_type_for_value(ctx, array_id, TypeRef::POINTER)`, matching
sibling Array intrinsics. No `lower_case` guard was added.

Evidence:

- `regression_tests/array_reduce_uint32_element_type_repro.sh
  /tmp/adamas_lower_case_stage1` was red on the previous compiler: compilation
  failed before runtime with the known pointer-vs-i32 llc error for
  `Array(UInt32)#reduce`.
- `crystal build src/adamas.cr -o /tmp/adamas_reduce_stage1 --error-trace`
  -> exit 0.
- `regression_tests/array_reduce_uint32_element_type_repro.sh
  /tmp/adamas_reduce_stage1` -> `plain=6`, exit 0.
- Manual `Array(UInt32)#map + #reduce` reducer compiled and ran with
  `plain=6`, `mapped0=2`, `combined=9`.
- `scripts/run_safe.sh /tmp/adamas_reduce_stage1 900 12288 src/adamas.cr
  -o /tmp/adamas_reduce_s2` -> exit 0.
- Fresh fixed s2 compiling `src/adamas.cr` no longer stops in
  `AstToHir#lower_case`; lldb now stops in `AstToHir#lower_module_method` at
  a null receiver before `DefNode#return_type`.
- `regression_tests/run_all_suites.sh /tmp/adamas_reduce_stage1 4`
  -> 152/152 original tests and 36/36 combined tests, all passed.

Residual:

- This is a frontier move, not a green bootstrap claim. Fresh fixed s2 still
  exits 139 after `[STAGE2_DEBUG] pass3 after lower_main call`.
- The new active boundary is `AstToHir#lower_module_method`, not
  `lower_case`.

Adversary notes:

- A local cast or null/pointer guard in `lower_case` would have hidden the
  broader `Array(UInt32)#reduce` type contract bug.
- Object-array behavior remains covered by the same helper because
  `array_element_type_for_value` still returns `Pointer` for reference-like
  element descriptors.

Trust: {F/G/R: 0.87/0.44/0.90} [verified for Array#reduce primitive element typing and this frontier move]

### LM-668 - Bootstrap fixed-name rewrites bypass lossy regex block capture

A fresh stage2 rebuilt after the scalar/pointer nil-check fix did not initially
reach the documented StaticArray runtime floor. It crashed while registering
modules in `infer_type_from_expr_inner`: the fixed prefix rewrite
`raw_path.sub(/^::/, "")` entered block-backed `String#sub` machinery, and the
generated compiler passed a null captured replacement String to `IO#<<`. After
that callsite was removed, the same mechanism appeared in `reorder_named_args`
at `func_name.sub(/[.#]new$/, "#initialize")`.

Both operations have a narrower contract than regex substitution. Absolute
paths now remove their known ASCII `::` prefix through `absolute_path_body`,
which uses `byte_slice`. Constructor fallback now extracts the method owner and
uses the existing `allocator_init_name_for` builder. The fix covers the adjacent
absolute-path owner/lib lookup sites that performed the identical prefix
rewrite; it does not change general regex replacement behavior.

Evidence:

- A current-source host compiler rebuilt successfully with upstream Crystal.
- `regression_tests/p2_self_nested_module_registration_frontier.sh` passes on
  both the current-source host compiler and the fresh generated stage2.
- `scripts/run_safe.sh bin/adamas 900 12288 src/adamas.cr -o <fresh-s2>`
  completed with exit 0.
- Generated LLVM for the fresh stage2 routes `infer_type_from_expr_inner`
  through `absolute_path_body` and `reorder_named_args` through
  `allocator_init_name_for`; neither function calls the regex `String#sub`
  overload used by the crashes.
- `regression_tests/run_all_suites.sh <current-source-host> 8` passed 162/162
  original and 36/36 combined tests.
- The fresh stage2 compiles
  `regression_tests/stage2_tuple_destructure_union_repro.cr`; only the produced
  target fails at runtime, restoring the intended next bootstrap frontier.

Residual:

- This closes only fixed-name transformations that did not require regex
  semantics. The underlying generated block-capture defect remains live for
  genuine block-backed operations.
- Luna 5.6 independently localized the next floor in `lower_def`: in the
  `extra_type_params.empty?` path, generated stage2 discards the `i32` returned
  by `lower_expr` inside `with_arena`, leaving captured `last_value` Nil and
  emitting `define/call void @make_bytes`. The StaticArray carrier is therefore
  not consumed at all; changing its representation would address the wrong
  layer.
- After return recovery, nested StaticArray escape promotion must still be
  verified before the runtime slice can be called closed.

Adversary notes:

- The replacement preserves the exact accepted shapes: only a leading `::` is
  sliced, and only names ending in `.new` or `#new` are mapped to
  `#initialize`.
- Passing the registration frontier alone is insufficient evidence. The fresh
  stage2 also self-built and reached the independently measured target-runtime
  floor.
- The full suite is a regression guard, not a bootstrap-green proxy; the active
  stage2-produced target still exits 139.

Trust: {F/G/R: 0.88/0.40/0.90} [verified for fixed-name rewrite frontier; bootstrap remains in progress]

### LM-669 - Generated lower_def returns its body value without block-capture transport

The stage2-produced StaticArray/tuple repro did not fail because its
`StaticArray(UInt8, 4)` value had the wrong representation. The generated
compiler never delivered the value to the caller. In `lower_def`, the final
`ValueId?` was assigned to captured `last_value` from inside `with_arena` and,
on the generic path, `with_type_param_map`. Generated stage2 called
`lower_expr`, discarded its returned `i32`, left the captured slot Nil, and
therefore emitted `define/call void @make_bytes`; tuple destructuring then read
literal null.

`lower_def_body_sequence` now owns the sequential loop and returns its final
`ValueId?` explicitly. Both callers assign that return outside the arena block;
the generic path also returns it through `with_type_param_map`. This removes
closure-capture transport from the return-value contract without changing
sequential stop behavior.

Evidence:

- The current-source host compiler and a fresh generated stage2 both build.
- Generated-stage2 compiler LLVM stores and returns the value from
  `lower_def_body_sequence`; the old discarded `lower_expr` result is absent
  from this corridor.
- The stage2-produced target emits both `define ptr @make_bytes()` and
  `call ptr @make_bytes()` and returns the tuple carrier to its caller.
- `regression_tests/p2_lower_def_last_value_return_contract.sh` passes on the
  fresh stage2, including safe runtime execution of the StaticArray byte check.
- `regression_tests/run_all_suites.sh <current-source-host> 8` passes 163/163
  original and 36/36 combined tests.

Residual:

- The output-bearing predecessor repro now advances through StaticArray return
  and aborts while formatting `UInt8`, at the generated
  `UInt8#UInt8#unsafe_mod(Int32)` sentinel. That later failure is outside this
  return-value fix.
- The broader generated compiler still has block-capture defects in other
  corridors; this change only removes capture as the carrier of a def body's
  final value.

Adversary verdict: ROBUST for the lower_def return corridor. The focused
runtime test deliberately avoids `puts(UInt8)`, while the predecessor repro is
retained as a red frontier so a formatting/call-binding failure cannot be
misreported as a StaticArray regression.

Trust: {F/G/R: 0.94/0.42/0.94} [verified for lower_def final-value transport; bootstrap remains in progress]

### LM-670 - Array map owns block-local next iteration results

Specialized literal/dynamic `Array#map` and dynamic `map_with_index` lowered
their user block bodies directly, without the lexical block-control contract
used by ordinary yield/proc lowering. With no `InlineNextContext`, `lower_next`
fell through to `Return`, so `next value` returned from the enclosing function
instead of completing the current map iteration.

The bootstrap manifestation was in backend `fixup_call_arg_types`. Its
`parts.map { |part| next part unless ... }` received a two-element argument
string, but generated stage2 returned the first literal part from the entire
method. Untraced target HIR and post-opt MIR both retained the full argument
vector; only LLVM output lost the tail. A top-level and an instance reducer each
called a two-parameter definition with one actual argument.

The three map paths now use `lower_array_map_block_body`. When a block contains
lexically local `next`, the helper installs an iteration-result exit, records
normal and `next value` predecessors, unifies/coerces their types (including
tuple-shape coercion), and emits one value or a phi. An empty predecessor set is
marked dead, so a syntactically present but unreachable `next` cannot revive an
all-noreturn body. Blocks without local `next` keep the previous lowering path.

Loop and inline-next contexts were previously independent ambient stacks. A
parallel loop-depth stack now records the inline-next depth at every loop push,
so the lexically inner construct owns `next` in both outer-map/inner-loop and
outer-loop/inner-map shapes. All 12 loop push/pop sites are paired, and all four
function/proc isolation corridors save, reset, and restore the depth stack with
the corresponding loop condition stack.

Evidence:

- The previous host compiler aborts the dynamic/literal/map_with_index family
  regression at its first map assertion; the current host runs all three.
- A current-source host compiler and a fresh generated stage2 both build.
- The current host and fresh stage2 compile and run the extended map-next
  regression: direct paths, both nested ownership orders, `case/in`,
  reachable-next plus raise, syntactic-next with all real paths noreturn, and
  tuple-phi coercion.
- `regression_tests/p2_call_argument_tail_contract.sh` passes on both current
  host and fresh stage2. Target LLVM contains both actual arguments for the
  top-level and instance reducers.
- Fresh stage2 compiler LLVM routes the old early returns in
  `fixup_call_arg_types` into the per-iteration merge and joins the complete
  result array.
- `regression_tests/run_all_suites.sh /tmp/adamas_mapnext_s1_v6 8` reports
  165/165 original and 36/36 combined tests passed.

Residual and adversary result:

- Activation uses a lexical-local detector which does not descend into nested
  loops, call blocks, or proc literals. The explicit loop-depth arbitration
  guards mixed bodies where the outer map also contains its own `next`.
- Static census finds the same direct-body omission in `compact_map`, block
  `sum`, `reduce`, and block `count`. Loop-style intrinsics also discard the
  expression of `next value` even when their control target is correct.
- Therefore the scoped map/call-tail/nested-ownership claim is ROBUST, but a
  universal block-control claim is VULNERABLE. The architectural follow-up is
  one lexical block-control transaction with explicit Discard, Value,
  Predicate, and Accumulator policies rather than further independent ambient
  control stacks.

Trust: {F/G/R: 0.95/0.48/0.95} [verified for map/map_with_index next, nested ownership, noreturn and tuple merges, and generated call-tail preservation; other intrinsic policies remain open]

### LM-671 - Abort stubs are a heterogeneous fail-loud funnel

The backend's `ABORT stub for unlowered method` is not a root-cause category.
It is the common sink for a called Crystal symbol that has no emitted body after
late materialization. That makes unrelated semantic failures look identical at
runtime.

Current evidence separates at least three upstream classes:

1. **Control-flow transport:** LM-670 truncated a backend helper before it had
   formatted all arguments. The callee body existed and MIR was correct; the
   eventual runtime failure looked like a missing/invalid call.
2. **Semantic identity:** the default target retains 8 repeated-owner stubs such
   as `UInt8#UInt8#unsafe_mod(Int32)`, `Object#Object#to_s`, and
   `Crystal::EventLoop#Crystal::EventLoop#read`. No correct definition should
   exist under those twice-qualified identities.
3. **Supply/demand visibility:** prior floors lost definitions upstream or
   created raw LLVM edges invisible to HIR/RTA. The backend sentinel only made
   the missing supply observable.

Default target census after LM-670 is 22 ABORT stubs; 8 are repeated-owner forms.
`UInt8#remainder(Int32)` now has and receives `(self, other)`, proving the
argument-tail root is closed there, but its body still emits a call to
`UInt8#UInt8#unsafe_mod(Int32)`. Thus argument binding and identity
requalification are independent symptoms in the active floor.

The repeated-owner producer is now root-caused. It is not an identity parser or
resolver defect: it is the L10 unsafe phi-shared-slot optimization recurring at
the same `lower_call` valued-if. Before the merge, probe D observes the valid
pair `method_name=unsafe_mod` and `full_method_name=UInt8#unsafe_mod`. Legacy
sharing redirects the still-live bare-name incoming to the result phi carrier;
the selected full-name arm overwrites that carrier. Probe E consequently reads
`method_name=UInt8#unsafe_mod` without any source assignment. A later, valid
receiver resolution adds the owner and emits `UInt8#UInt8#unsafe_mod`.

Discriminating evidence:

- A current host built stage2 successfully with
  `ADAMAS_PHI_SHARE_VETO_FILTER=lower_call`.
- In that stage2, D and E both retain bare `unsafe_mod`; F emits the single-owner
  `UInt8#unsafe_mod$Int32` identity.
- The untraced target LLVM census changes from 8 repeated-owner stubs to 0.
  Parser/source qualification, `specialize_method_owner_name`, and backend name
  emission are therefore refuted producers.
- The filtered candidate is not production-ready. The target advances past
  `unsafe_mod` but fails link on undefined `__crystal_block_proc_51`; its total
  stub count rises from 22 to 34, demonstrating why stub count is only a proxy.
  The previously green stage2 call-tail and lower_def contracts also fail before
  runtime (SIGSEGV and undefined `String#byte_slice`, respectively).
- The scoped-default code candidate and its auto-suite reducer were reverted;
  the repository remains on legacy sharing until the exposed supply failures
  are closed without regressing earlier contracts.

Quadrumvirate synthesis:

- **Cassandra:** another runtime stub is more likely to be an earlier
  call/body/identity transaction divergence than a genuinely absent primitive.
- **Daedalus:** inspect the earliest mismatch in
  `call shape -> selected def -> argument vector -> materialization key -> body
  symbol -> emitted ABI`, not the backend stub body first.
- **Maieutic:** a mangled suffix does not prove the actual argument vector, and
  an identity-looking corruption can originate in value lifetime rather than
  name construction.
- **Adversary:** unsafe_mod overrides, owner-string dedupe, speculative
  forwarders, zero returns, forced RTA keepalive, and stdlib edits are BROKEN
  fixes without an ABI/identity proof.

Next measurable signal: under the filtered lower_call-veto oracle, find the
earliest point where demand for `__crystal_block_proc_51` or
`String#byte_slice(Int32, Int32)` loses its body. The long-term invariant remains
one structured resolution/binding object carried unchanged from selection
through materialization and emission, plus lifetime-safe transport for every
field of that object.

Trust: {F/G/R: 0.96/0.62/0.94} [repeated-owner mechanism proven by filtered liveness veto; production enablement blocked by exposed supply regressions]

### LM-665 - Generated s2 preserves nested static method owner during body registration

Generated s2 now registers a nested static method body under the same owner
symbol used by the call. The failing no-prelude shape was:

```crystal
class Exception
  class CallStack
    def self.skip(path : String) : Nil
    end
  end
end

Exception::CallStack.skip("x")
```

Before this fix, generated s2 lowered the call to
`Exception::CallStack.skip$String`, but `register_concrete_class` registered the
body as `Exception::.skip$String`. The exact-call symbol had no body and the
compiled binary aborted in the backend dead-code stub for
`Exception$CCCallStack$Dskip$$String`.

Root cause: `resolve_class_name_for_definition` mixed byte offsets and
self-host-fragile range slicing. It used `rindex("::")` to find the owner/leaf
boundary, then sliced the leaf through `name[(idx + 2)..]`; generated s2 could
turn `Exception::CallStack` into `Exception::`. The fix byte-slices both owner
and leaf from the same byte-offset coordinate system.

Evidence:

- Fresh generated s2 before the fix logged
  `DEBUG_METHOD_REGISTER class=Exception:: method=skip full=Exception::.skip$String`
  while the HIR call was `Exception::CallStack.skip$String`.
- Fresh fixed generated s2 logs
  `DEBUG_METHOD_REGISTER class=Exception::CallStack method=skip full=Exception::CallStack.skip$String`;
  HIR contains both `call Exception::CallStack.skip$String` and
  `func @Exception::CallStack.skip$String`.
- `regression_tests/nested_class_static_method_registration_repro.sh
  /tmp/adamas_nested_class_byteslice_stage1` -> PASS.
- `regression_tests/nested_class_static_method_registration_repro.sh
  /tmp/adamas_nested_class_byteslice_s2` -> PASS.
- `regression_tests/run_all_suites.sh
  /tmp/adamas_nested_class_byteslice_stage1 4` -> 152/152 originals and 36/36
  combined, all passed.

Adversary notes:

- This is not a generic materialization-forwarder or backend-stub fix. It fixes
  the producer-side class-name split that created the sibling symbol.
- The old byte-slice attempt was insufficient before the value short-circuit
  narrowing fix because the call owner was still corrupted earlier. After that
  owner chain was fixed, this slice is necessary and sufficient for the nested
  static method body/call mismatch.
- Fresh fixed s2 compiling `src/adamas.cr` still aborts before producing s3,
  now at `STUB CALLED:
  Adamas::HIR::AstToHir#try_resolve_simple_default(...)`; do not claim s2->s3
  or s3b green from this landmark.

Trust: {F/G/R: 0.87/0.38/0.88} [verified for the named no-prelude self-host shape]

### LM-S2S3-MULTI-REF-UNION-TRUTHY-NARROWING - Multi-reference union truthy narrowing must remove Nil

The generated s2 `try_resolve_simple_default` abort-stub frontier was a
producer narrowing bug, not a resolver scoring or helper-signature bug. Truthy
narrowing only unwrapped `Nil | T` when exactly one non-Nil variant remained.
For all-reference unions with multiple non-Nil variants, such as
`Nil | AstArena | PageArena | VirtualArena`, `lower_not_nil_intrinsic` returned
the original nilable value. The allocator default loop then called
`try_resolve_simple_default(default_node, default_arena, ivar.type)` with a
still-nilable `default_arena`, causing overload lookup to miss the non-nil
`ArenaLike` overload and emit a generated-s2 abort stub.

Fix shape:

- If removing Nil leaves another all-reference union, emit a typed
  pass-through `Copy` to the union-minus-Nil type.
- Keep mixed/value unions on the old conservative fallback.
- Apply the same typed-copy narrowing in both direct `lower_not_nil_intrinsic`
  and block-local `unwrap_non_nil_to_block`.

Evidence:

- `regression_tests/multi_ref_union_truthy_narrowing_repro.sh
  /tmp/adamas_nested_class_byteslice_stage1` -> red with
  `CALL_LOOKUP_MISS func=accept` and arg type `Nil | A | B`.
- `crystal build src/adamas.cr -o /tmp/adamas_multi_ref_narrow_stage1
  --error-trace` -> exit 0.
- `regression_tests/multi_ref_union_truthy_narrowing_repro.sh
  /tmp/adamas_multi_ref_narrow_stage1` -> `RESULT=11`, PASS.
- Fresh stage1->s2 trace for `try_resolve_simple_default` selected
  `$ArenaLike_TypeRef$arity3` with arg types
  `Node, AstArena | PageArena | VirtualArena, TypeRef`; HIR and MIR bodies are
  present.
- `regression_tests/run_all_suites.sh /tmp/adamas_multi_ref_narrow_stage1 4`
  -> 152/152 originals and 36/36 combined, all passed.

Residual:

- Fresh fixed s2 compiling `src/adamas.cr` moves past the old
  `try_resolve_simple_default` stub and stops later with
  `error: Empty enumerable`; do not claim s2->s3 or s3b green from this
  landmark.

Trust: {F/G/R: 0.89/0.58/0.91} [verified for all-reference nilable-union truthy narrowing]

### LM-S2S3-SHORT-TYPE-INDEX-SAFE-FIRST - Short-type index Set first must be guarded

The generated s2 `error: Empty enumerable` frontier after the multi-reference
union narrowing fix was a short-type-index lookup hazard, not another
nilable-owner collapse. `resolve_short_type_in_namespace_chain` ended with
`candidates.first` when `@short_type_index[short]` had a singleton candidate.
On the fresh s2->s3 attempt, lldb stopped at `Enumerable::EmptyError.new` with
the stack `Set(String)#first -> AstToHir#resolve_short_type_in_namespace_chain
-> resolve_method_call -> lower_member_access`. A filtered probe for the same
boundary logged `name=Nil | Exception::CallStack short=CallStack
candidates_size=1 first_nil=true`: generated s2 saw a singleton `Set`, but the
set yielded no first value. The source context was `Exception#backtrace?`
lowering `@callstack.try &.printable_backtrace`, so blindly collapsing union
owners was not semantically safe.

Fix shape:

- Keep namespace-chain matching unchanged.
- For the final singleton fallback, call the existing `safe_set_first?`
  helper and return `nil` when the generated `Set` is internally inconsistent.
- Extend `regression_tests/p2_short_type_index_first_no_prelude.sh` so both
  `fast_resolve_type_name_for_signature` and
  `resolve_short_type_in_namespace_chain` are forbidden from direct `Set#first`
  use.

Evidence:

- Clean HEAD reproduced the frontier:
  `scripts/run_safe.sh /tmp/adamas_live_s2 900 12288 src/adamas.cr -o
  /tmp/adamas_live_s3` -> exit 1 with `error: Empty enumerable`.
- lldb on the generated s2 stopped in `Set(String)#first` from
  `resolve_short_type_in_namespace_chain`.
- Refuted candidate: skipping short namespace resolution for all union owners
  made produced s2 crash immediately after `prelude exists`.
- With this fix, the focused guards
  `multi_ref_union_truthy_narrowing_repro.sh`,
  `nested_class_static_method_registration_repro.sh`, and
  `p2_short_type_index_first_no_prelude.sh` pass on the fixed stage1.
- `regression_tests/run_all_suites.sh /tmp/adamas_short_first_stage1 4` ->
  152/152 original tests and 36/36 combined tests, all passed.
- `scripts/run_safe.sh /tmp/adamas_short_first_stage1 900 12288
  src/adamas.cr -o /tmp/adamas_short_first_s2` -> exit 0.

Residual:

- Fresh fixed s2 compiling `src/adamas.cr` moves past `Empty enumerable`, reaches
  `[STAGE2_DEBUG] pass3 after lower_main call`, then segfaults in
  `String#size <- scan_hir_function_for_live_types <- initialize_lazy_rta <-
  flush_pending_functions`.
- lldb on the same generated s2 confirms the residual crash at
  `String#size`, called by
  `Adamas::HIR::AstToHir#scan_hir_function_for_live_types ->
  initialize_lazy_rta -> flush_pending_functions`. This landmark does not
  claim s2->s3 or s3b green.

Trust: {F/G/R: 0.86/0.42/0.88} [verified for the named short-type-index singleton fallback]

### LM-624 - Runtime object headers must use MIR type ids

`set_crystal_type_id` object-header writers must bake MIR/runtime type ids, not
raw HIR `TypeRef#id` values. The explicit `ClassName.set_crystal_type_id(ptr)`
path and the bare `set_crystal_type_id(ptr)` path are separate HIR lowering
branches; the bare call can otherwise resolve through inherited
`Object#set_crystal_type_id` and stamp Object's runtime id into the target
class header.

Evidence:

- `crystal build src/adamas.cr -o /tmp/adamas_stage1_bare_setid2 --error-trace`
  -> exit 0.
- `regression_tests/set_crystal_type_id_hir_mir_id_repro.sh
  /tmp/adamas_stage1_bare_setid2` -> `built_hdr=16`,
  `user_explicit=911 OK`, `user_bare=911 OK`.
- Standalone reducer `/tmp/bare_setid_repro.cr` changed from
  `911 / 576 / 911 / false / true` to `911 / 911 / 911 / true / true`.
- LLVM IR oracle for `BareSetId.allocate_bare` stores `i32 911` directly and no
  longer calls `Object#set_crystal_type_id`.
- `regression_tests/run_all_suites.sh /tmp/adamas_stage1_bare_setid2 4` ->
  149/149 original + 36/36 combined, all passed.
- Clean staged-slice worktree build
  `/tmp/adamas_stage1_bare_setid_slice` passed
  `set_crystal_type_id_hir_mir_id_repro.sh` and
  `array_sort_runtime_type_id_repro.sh`.

Adversary notes:

- This closes a runtime-header writer leak only. It does not claim to solve the
  separate M4i6h tuple/type-descriptor frontier or the current s2b full-prelude
  RSS blow-up.
- `crystal_type_id` query sites still need separate semantic review before
  converting raw ids, because a type-literal query is not automatically the
  same contract as an object-header write.

Trust: {F/G/R: 0.88/0.46/0.90} [verified]

### LM-625 - Stage2 interpolation helper materializes under the TypeRef boundary

Generated `s2b` no longer aborts the no-prelude interpolation smoke on
`Adamas::MIR::LLVMIRGenerator#interpolation_i32_arg(String, UInt32, String,
Int32, <large union>)`. The direct boundary was the call into
`interpolation_i32_arg(..., hint_type : TypeRef?)`: `part_type` is compiler
metadata whose helper contract is `Nil | MIR::TypeRef`, but self-hosting could
record the callsite hint argument as a large value-domain union. The call sites
now assert the helper boundary with `part_type.as(TypeRef?)`, causing the
materialized helper to use the declared `Nil | TypeRef` shape.

Evidence:

- Host probe of `remember_callsite_arg_types` showed the fifth
  `interpolation_i32_arg` argument being recorded as the large value-domain
  union before lookup, while the exact `Nil | TypeRef` helper lookup existed.
- A simple `TypeRef::CHAR` reducer and a Hash/branch `TypeRef?` flow reducer
  both materialized the exact `TypeRef` helper, so the minimal source shape was
  not enough to reproduce the bug.
- A local `part_type : TypeRef?` annotation was tested and did not change the
  self-hosted helper symbol; explicit boundary casts did.
- `regression_tests/p2_generated_stage2_no_prelude_interp.sh
  /tmp/adamas_interp_cast_out` passed after the guard was updated from stale
  `--no-codegen` parse-only checking to the current compile-and-run no-prelude
  contract.
- `scripts/bootstrap_chain.sh --stages 2 --out
  /tmp/adamas_bootstrap_interp_cast_s2_current --timeout 900 --mem 12288`
  built s2, and the s2 no-prelude smoke passed. The stage2 IR contains a real
  `interpolation_i32_arg(..., Nil | TypeRef)` body and no live old huge-union
  abort stub.
- The same bootstrap run did not prove full `s1 -> s2b` green: the first
  full-prelude plain smoke hit `EXIT 133`. A direct rerun passed once, but a
  repeated plain smoke reproduced the trap; lldb stopped in
  `libsystem_malloc` from `__adamas_file_read ->
  AstToHir#constant_source_text -> record_constant_definition` during
  module/class registration. Treat that as the next full-prelude frontier, not
  as part of the interpolation helper fix.

Adversary notes:

- This is a focused helper-boundary fix, not a global proof that all
  compiler-metadata value-domain pollution is solved.
- Do not replace it with a backend undefined-extern/stub rescue. The
  discriminating evidence places the bad shape at callsite recording, before
  backend stub emission.

Trust: {F/G/R: 0.88/0.44/0.88} [verified]

### LM-663 - Primitive tuple containers use inline slots consistently

Primitive/enum-only tuple containers now use a single inline byte-slot ABI
across HIR pointer lowering and LLVM Array access. The certified family is
narrow by design: `Pointer(Tuple(...))` and `Array(Tuple(...))` where every
tuple element is primitive or enum use the MIR tuple size for malloc, load,
store, pointer add, realloc, and Array get/set. Tuples containing refs, unions,
or structs stay on the legacy pointer-carrier path until separately verified.

This fixes the remaining `pointer_tuple_stride` carrier root from the layout
matrix. Before this change, V2 stored `Pointer(Tuple(Int64, Int64))` as an
8-byte heap-pointer slot, and LLVM emitted `tuple_slot_copy` plus pointer-slot
loads. After the change, the pointer buffer uses a 16-byte inline stride and
tuple indexing keeps tuple container provenance instead of falling through to
Array layout.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_pointer_tuple_inline
  --error-trace` -> exit 0.
- `regression_tests/p2_pointer_primitive_tuple_inline_stride_no_prelude.sh
  /tmp/cv2_pointer_tuple_inline` -> verifies no `tuple_slot_copy`, 16-byte
  inline stride, and runtime checksum.
- `regression_tests/p2_array_tuple_storage.sh /tmp/cv2_pointer_tuple_inline`
  -> `p2_array_tuple_storage_ok`, guarding Array(Tuple) against mixed
  write/read ABIs.
- `regression_tests/p2_stack_local_struct_init_store_no_prelude.sh
  /tmp/cv2_pointer_tuple_inline` ->
  `p2_stack_local_struct_init_store_no_prelude_ok`.
- `scripts/bench_no_prelude_layout_matrix.sh /tmp/cv2_pointer_tuple_inline
  /opt/homebrew/bin/crystal` -> all matrix checksums matched. Representative
  V2 internal ticks: scalar `160936`, pointer tuple `154776`, nilable union
  `319276`, mixed union `373200`.

Adversary notes:

- This is not a global tuple ABI rewrite. The inline move is legal only for
  tuple payloads with no ownership or nested carrier obligations.
- The first attempt exposed a real Array(Tuple) boundary bug: Array push wrote
  inline bytes while Array get still loaded pointer slots. The final fix makes
  Array allocation/get/set/realloc agree on the same tuple slot size.
- Union rows remain slow, so the next root is union slot materialization and
  `is_a?` lowering, not tuple pointer stride.

Trust: {F/G/R: 0.87/0.45/0.89} [verified]

### LM-664 - CLI AST-cache stat timestamp is target-portable

The disabled CLI AST-cache branch still type-checks during normal compiler
builds. It previously read `LibC::Stat#st_mtimespec`, which only exists on
Darwin targets. Linux targets expose `st_mtim`, so Ubuntu/WSL builds with
Crystal 1.20.1 failed while expanding the `bootstrap_fast` macro guard even
though the runtime branch was `if false && options.ast_cache`.

The timestamp extraction now follows Crystal stdlib's platform split:
Darwin uses `st_mtimespec`, Windows uses second-resolution `st_mtime`, and
other Unix targets use `st_mtim`.

Evidence:

- Before the fix, `crystal build src/adamas.cr -o /tmp/cv2_linux_check
  --error-trace --cross-compile --target x86_64-linux-gnu` failed with
  `undefined method 'st_mtimespec' for LibC::Stat`.
- After the fix, `regression_tests/p2_linux_cross_compile_stat_mtime_guard.sh`
  -> `p2_linux_cross_compile_stat_mtime_guard_ok`.
- Host build with local Crystal 1.20.2:
  `crystal build src/adamas.cr -o /tmp/cv2_stat_mtime_host --error-trace`
  -> exit 0.
- Exact Linux compiler check:
  `docker run --rm -v "$PWD:/work" -w /work crystallang/crystal:1.20.1
  crystal build src/adamas.cr -o /tmp/cv2_forum_1201 --error-trace`
  -> exit 0.

Adversary notes:

- This is a compile-time portability fix, not an AST-cache behavior change.
  The affected branch remains disabled in this bootstrap corridor.
- The regression uses cross-target type-checking so Darwin hosts catch Linux
  `LibC::Stat` field drift before forum users hit it.

Trust: {F/G/R: 0.88/0.46/0.90} [verified]

### LM-660 - No-prelude layout matrix isolates struct performance divergence

The no-prelude layout matrix now compares original Crystal and Crystal V2 on a
small carrier family: scalar loops, local structs, nested structs, pointer
strides, tuple strides, nilable/mixed struct unions, yield-carried structs, and
class allocation. The current matrix shows checksum parity for all carriers,
but V2 is much slower in the hot-loop tick counter, especially local/nested
structs and yield-carried structs. This points to value-carrier lowering rather
than a parser/type-inference failure in these cases.

Evidence:

- `scripts/bench_no_prelude_layout_matrix.sh /tmp/cv2_layout_matrix_host
  /Users/sergey/.local/bin/crystal | tee /tmp/cv2_layout_matrix.tsv` -> all
  nine cases compile and run for both compilers; all checksums match.
- Representative hot-loop tick ratios from that run:
  `struct_local_loop` 47.42x, `nested_struct_loop` 90.96x,
  `yield_struct_loop` 51.65x, `pointer_nilable_struct_union` 14.21x,
  `class_alloc_loop` 4.85x V2 over original.
- V2 LLVM IR for `struct_local_loop` shows the root shape directly:
  `Pair.new` is called inside `__crystal_main`, and
  `Pair$Dnew$$Int64_Int64` calls `@__adamas_malloc64(i64 24)`. The original
  compiler computes the same checksum without exposing this heap allocation in
  the hot carrier.

Adversary notes:

- The matrix is a semantic/layout smoke oracle plus a performance locator, not
  a final benchmark suite. Original Crystal still loads its normal prelude,
  while V2 uses `--no-prelude`; compile time and binary size are therefore not
  apples-to-apples.
- The run-safe wrapper dominates outer `run_ms`, so `internal_ticks` is the
  relevant performance signal.
- Matching checksums do not prove identical ABI layout. They narrow this
  carrier family to performance/codegen lowering gaps unless later IR or ABI
  probes contradict it.

Trust: {F/G/R: 0.84/0.48/0.86} [verified]

### LM-661 - Stack-local generated struct constructors bypass allocator calls

Generated struct `.new` calls whose HIR result remains `StackLocal` are now
lowered at the MIR call site as a caller-local stack allocation, zero-fill, and
direct `#initialize` call. The guard uses the generated allocator's HIR body to
prove the expected shape (`allocate`, zero-default field setup, receiver
`#initialize`, `return allocate`) before rewriting. Escaping constructor
results, such as a function returning `Pair.new(...)`, keep the existing heap
allocator call.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_struct_fix_candidate
  --error-trace` -> exit 0.
- `regression_tests/p2_stack_local_struct_new_no_prelude.sh
  /tmp/cv2_struct_fix_candidate` -> `not reproduced: stack-local struct .new is
  inlined while escaping/unsafe-arg .new stays heap-backed`.
- A focused no-prelude executable using `pair = Pair.new(1_i64, 2_i64);
  pair.sum` compiled with the candidate compiler and ran through
  `scripts/run_safe.sh`, exiting successfully.
- `git diff --check` -> exit 0.
- `scripts/bench_no_prelude_layout_matrix.sh /tmp/cv2_struct_fix_candidate
  /opt/homebrew/bin/crystal` -> all nine original/V2 checksums still match.
  Representative V2/original internal tick ratios from this run:
  `struct_local_loop` about 15.6x, `nested_struct_loop` about 17.3x,
  `yield_struct_loop` about 17.7x. This improves the previous heap-allocation
  profile but does not reach original-compiler parity.

Adversary notes:

- This is not a global struct ABI rewrite. Pointer/container/union storage
  still follows the existing V2 pointer-carrier rules.
- The rewrite is intentionally gated by existing HIR escape analysis. The CLI
  escape-analysis skip fast path now treats struct constructor calls as
  allocation-relevant so call-result lifetimes are available even when the
  caller has no literal `HIR::Allocate`.
- A use-site whitelist keeps arbitrary method-argument constructors heap-backed
  because V2 currently passes struct values as pointer carriers and an unknown
  callee could retain that pointer.
- Remaining value-carrier slowdown is now likely in constructor/init call
  overhead, residual copies, and broader optimization, not hot-loop GC
  allocation for these generated local constructors.

Trust: {F/G/R: 0.86/0.50/0.88} [verified]

### LM-662 - Trivial stack-local struct initializers lower to direct field stores

Stack-local generated struct constructors now inline trivial
`initialize(@ivar, ...)` bodies as direct field stores at the call site. This
removes the hot-loop `#initialize` call after LM-661 has already removed the
heap allocator call. The inliner is deliberately narrow: the initializer must
be one block, write only `self` fields from initializer parameters, contain no
calls/control flow/non-zero computations, and return `Nil`/`Void`. Non-trivial
initializers fall back to the previous zero-fill plus real initializer call.

Zero-fill elision is separately guarded by byte coverage. Even if every MIR
field has a matching store, the memset is skipped only when the stored field
ranges exactly cover the whole struct storage with no padding gaps. This keeps
padding bytes and nil-erased/shared-offset fields conservative while still
letting dense structs such as two-`Int64` `Pair` avoid redundant zeroing.

Evidence:

- `crystal build src/adamas.cr -o /tmp/cv2_struct_init_final
  --error-trace` -> exit 0.
- `regression_tests/p2_stack_local_struct_init_store_no_prelude.sh
  /tmp/cv2_struct_init_final` -> `p2_stack_local_struct_init_store_no_prelude_ok`.
  This guard verifies dense trivial direct stores with no `#initialize` or
  memset, custom initializer fallback with real `#initialize` plus memset, and
  padded trivial structs keeping memset while still inlining field stores.
- `regression_tests/p2_stack_local_struct_new_no_prelude.sh
  /tmp/cv2_struct_init_final` -> existing stack-local/escaping/unsafe-arg
  guard still passes.
- Focused no-prelude IR for `Pair.new(1_i64, 2_i64)` now emits direct
  `getelementptr` plus `store i64` in `__crystal_main` and no
  `Pair$Hinitialize` call.
- `scripts/bench_no_prelude_layout_matrix.sh /tmp/cv2_struct_init_final
  /opt/homebrew/bin/crystal` -> all nine original/V2 checksums still match.
  Representative V2/original internal tick ratios from this run:
  `struct_local_loop` about 12.0x, `nested_struct_loop` about 6.9x, and
  `yield_struct_loop` about 12.7x. Pointer/container/union cases remain much
  slower and are a separate carrier-specialization frontier.

Adversary notes:

- This is still not a global by-value struct ABI rewrite. Arbitrary method
  argument constructors remain heap-backed unless the existing use-site guard
  proves the result stays local.
- The field-store emission reuses the same MIR field-store helper as ordinary
  `HIR::FieldSet`, preserving scalar coercion, union wrapping, inline
  struct/lib/static-array memcopy, and reference ownership behavior.
- If MIR and HIR argument lists diverge, the inliner falls back to the real
  initializer call because union wrapping and reference retains require the
  caller HIR argument type.

Trust: {F/G/R: 0.88/0.52/0.89} [verified]

### LM-656 - Bare generic `.new` can use the enclosing expected return

Bare generic constructor calls inside generic methods now prefer the enclosing
function's concrete generic return type when the return base matches the
constructor receiver. This fixes `Enumerable#to_set : Set(T)`, where
`Set.new(self)` inside `Array(String)#to_set` was inferred from the receiver
object (`Array(String)`) and generated a body returning `Set(String)` while
calling `Set(Array(String)).new`.

Evidence:

- `regression_tests/p2_bare_generic_new_uses_expected_return_no_prelude.sh
  /tmp/cv2_expected_new_fix_host` -> `p2_bare_generic_new_uses_expected_return_no_prelude_ok`.
- `regression_tests/p2_nilable_proc_union_preserves_signature_no_prelude.sh
  /tmp/cv2_expected_new_fix_host` -> `p2_nilable_proc_union_preserves_signature_no_prelude_ok`.
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /tmp/cv2_expected_new_fix_host` -> `p2_qualified_module_namespace_no_prelude_ok`.
- Full host HIR for `src/adamas.cr --emit hir --no-link` now lowers
  `Array(String)#to_set` as `call Set(String).new$Array(String)(%0) : 2489`
  instead of `Set(Array(String)).new$Array(String)`.
- Produced `s2` builds under `scripts/run_safe.sh` in about 172s and still
  passes the qualified-module namespace no-prelude guard.

Adversary notes:

- This is not a `Set` hardcode. The specialization only fires for bare
  generic `.new` when the current function return type is a concrete generic
  with the same template base and arity; otherwise existing argument inference
  remains in control.
- Full-prelude produced-s2 `puts 42` still fails in `fixup_inherited_ivars`,
  but the crash has moved from `Set(Array(String))#hash` during
  `Array(String)#to_set` to `Set(String)#each` while invalidating generated
  allocator state. Treat that as the next allocator/layout invalidation
  frontier, not as the erased generic-return root.

Trust: {F/G/R: 0.87/0.44/0.88} [verified]

### LM-657 - Nil-return block proc annotations control raw callback ABI

Raw block callback materialization now treats callee block annotations such as
`&block : String ->` and `& : T ->` as a `Nil` return contract. The inline-yield
fallback path and regular call path both prefer that contract over the block
body's incidental return type, and return terminator normalization now replaces
non-nil values with an explicit nil value when the function return type is
`Nil`.

Evidence:

- `regression_tests/p2_nil_return_block_proc_no_prelude.sh
  /tmp/cv2_nil_block_fix_host` -> `p2_nil_return_block_proc_no_prelude_ok`.
  The guard compiles a no-prelude `&block : String ->` callback whose body
  returns `Token.new`, then verifies the generated raw block proc is
  `Proc(String, Nil)` and returns explicit nil.
- Full host HIR for `src/adamas.cr --emit hir --no-link` now shows
  `Crystal::HIR::AstToHir#invalidate_generated_allocator_state$String_String`
  emitting `%144 = func_pointer @__crystal_block_proc_1260 : 883`, where
  `type.883 = Proc Proc(15, 16)`, and
  `func @__crystal_block_proc_1260(%1: 15) -> 16`.
- Produced `s2` build now reaches past `fixup_inherited_ivars done`; the next
  frontier is later in MIR optimization:
  `Adamas::Compiler::CLI#file_sha256$String: Arithmetic overflow`.
- Nearby guards still pass:
  `regression_tests/p2_bare_generic_new_uses_expected_return_no_prelude.sh
  /tmp/cv2_nil_block_fix_host` and
  `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /tmp/cv2_nil_block_fix_host`.

Adversary notes:

- This is an ABI fix, not a `Set` special case. The regression uses an
  unrelated `consume(&block : String ->)` call to catch the same raw callback
  return pollution without stdlib dependencies.
- Non-`Nil` block return contracts are not generalized by this change; the
  patch only prevents known `Nil` callback contracts from inheriting incidental
  body returns.

Trust: {F/G/R: 0.88/0.44/0.88} [verified]

### LM-658 - MIR constant folding wraps integer add/sub/mul like emitted LLVM

The MIR constant folder now evaluates signed and unsigned integer add/sub/mul
with wrapping arithmetic. This matches the LLVM integer ops V2 emits and avoids
host/compiler exceptions while optimizing generated-stage2 functions whose MIR
contains overflowing constant arithmetic.

Evidence:

- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 spec
  spec/mir/optimizations_spec.cr --error-trace` -> 46 examples, 0 failures.
  The new focused spec folds the FNV-1a `0xcbf29ce484222325_u64 *
  0x100000001b3_u64` multiply that previously exposed the produced-s2 overflow.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 420 8192 build
  src/adamas.cr -o /tmp/cv2_mir_wrap_host --error-trace` -> exit 0.
- Produced-s2 build with `/tmp/cv2_mir_wrap_host`:
  `scripts/run_safe.sh /tmp/cv2_mir_wrap_host 300 4096 src/adamas.cr -o
  /tmp/cv2_mir_wrap_s2/cv2_s2` -> exit 0. The previous
  `Adamas::Compiler::CLI#file_sha256$String: Arithmetic overflow` diagnostic
  is gone.

Adversary notes:

- This is an optimizer/IR-semantics fix, not a `file_sha256` workaround. The
  backend already emits plain LLVM integer arithmetic, so constant folding must
  not use host checked arithmetic for add/sub/mul.
- Produced-s2 full-prelude `puts 42` is still not clean. It now exits 139
  during target compile, with trace reaching `class register idx=3/92`.

Trust: {F/G/R: 0.89/0.48/0.90} [verified]

### LM-659 - Module stripped lookup no longer rebuilds by iterating module defs

Generic module stripped-name lookup is now an incrementally maintained ordered
index, not a lazily rebuilt `Hash(String, String)` derived from
`@module_defs.each_key`. This removes the produced-stage2 full-prelude crash
while registering `String include Comparable(self)`. The refuted lazy path
rebuilt the stripped lookup during include registration; produced `s2` first
returned an empty key for `Comparable`, and a narrower trace then crashed
inside the rebuild before the first `Comparable` candidate was printed.

Evidence:

- Instrumented produced-s2 run before the fix reached
  `phase=after_stripped_lookup_ready module=Comparable`,
  `phase=stripped_hit module=Comparable key=`, then crashed at the next
  `@module_defs.has_key?` lookup.
- A second trace crashed immediately after
  `[STRIPPED_LOOKUP] rebuild old_version=11 size=34`, before any candidate was
  emitted, localizing the unsafe corridor to lazy `@module_defs` iteration.
- `crystal tool format --check src/compiler/hir/ast_to_hir.cr` -> exit 0.
- `git diff --check` -> exit 0.
- `crystal build src/adamas.cr -o /tmp/cv2_module_stripped_array_host
  --error-trace` -> exit 0.
- Produced-s2 build:
  `scripts/run_safe.sh /tmp/cv2_module_stripped_array_host 300 4096
  src/adamas.cr -o /tmp/cv2_module_stripped_array_s2/cv2_s2` -> exit 0.
- `regression_tests/p2_full_prelude_module_stripped_lookup_frontier.sh
  /tmp/cv2_module_stripped_array_s2/cv2_s2` ->
  `p2_full_prelude_module_stripped_lookup_frontier_ok`.
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /tmp/cv2_module_stripped_array_host` and the same guard on produced `s2`
  both pass.

Boundary:

- This is a bootstrap frontier fix, not a full-prelude completion claim.
  Produced-s2 full-prelude `puts 42` now passes class registration, constants,
  pass2 registration, and inherited-ivar fixup, then reaches
  `lower_main: exprs=12`. The compile still exits non-zero: a plain
  `STAGE2_BOOTSTRAP_TRACE=1` run can segfault after lower-main starts, while
  lldb perturbs it into a 90s safe-wrapper timeout at the same lower-main
  frontier.

Adversary notes:

- This is not a `String`/`Comparable` special case. The fix changes the derived
  generic-module lookup invariant and avoids rebuilding it from a mutable
  module-def hash in a produced-stage2 hot path.
- The new full-prelude regression guard deliberately checks frontier movement
  (`class register done` and `lower_main: exprs=`), not successful target
  compilation.

Trust: {F/G/R: 0.88/0.50/0.88} [verified]

### LM-655 - Nilable Proc unions preserve callable signatures

HIR union construction now uses proc-aware type names when a union is built
from TypeRefs. This prevents typed callable variants such as
`Proc(Hash(String, Crystal::HIR::ClassInfo), String, Crystal::HIR::ClassInfo)`
from being canonicalized to bare `Proc`. Proc shorthand argument normalization
also resolves `self` against the concrete owner, avoiding fake names such as
`Box::self` in `(self, K -> V)?`.

Evidence:

- Before the fix, host HIR for `Hash(String, Crystal::HIR::ClassInfo)#[]$String`
  returned `Crystal::HIR::ClassInfo | String`, loaded `@block` as
  `Union Nil | Proc`, and emitted `Proc#call` with return type `Void`.
- After the fix, host HIR has
  `type.3287 = Union Nil | Proc(Hash(String, Crystal::HIR::ClassInfo), String, Crystal::HIR::ClassInfo)`;
  `Hash(String, Crystal::HIR::ClassInfo)#[]$String` returns
  `Crystal::HIR::ClassInfo`; and `Proc#call` returns `Crystal::HIR::ClassInfo`.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 420 8192 build
  src/adamas.cr -o /tmp/cv2_proc_union_fix_host4 --error-trace` -> exit 0.
- `regression_tests/p2_nilable_proc_union_preserves_signature_no_prelude.sh
  /tmp/cv2_proc_union_fix_host4` -> ok.
- `regression_tests/p2_hash_to_a_block_return_tuple.sh
  /tmp/cv2_proc_union_fix_host4` -> ok.
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /tmp/cv2_proc_union_fix_host4` -> ok.
- Produced `s2` build with `/tmp/cv2_proc_union_fix_host4` -> exit 0 in about
  174s; the existing non-fatal
  `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer overflow remains.
- Produced `s2` passes the qualified namespace no-prelude guard. Full-prelude
  produced-s2 `puts 42` still exits 139, now after registration and at
  `fixup_inherited_ivars start`.

Adversary notes:

- This is not a `Hash#[]` special case. The fix covers the structural root:
  any union or phi built from a typed `Proc` TypeRef must keep the callable
  parameter and return signature.
- Remaining full-prelude failure is memory/layout-sensitive. Do not reclassify
  this fix as a complete s2b bootstrap fix; the next root starts at
  `fixup_inherited_ivars`.

Trust: {F/G/R: 0.86/0.55/0.86} [verified]

### LM-654 - Built-in generic bases must not be captured by sibling namespaces

Contextual type resolution now preserves known built-in generic bases
(`Array`, `Hash`, `Tuple`, `Pointer`, and peers) when resolving generic type
names. This prevents plain `Array(T)` inside compiler internals from being
rewritten to a sibling type such as `Crystal::MIR::Array(T)` while lowering
`Crystal::HIR::Module#intern_type`.

Evidence:

- Host HIR emission before the fix produced
  `Tuple(UInt8, Crystal::MIR::Array(Crystal::HIR::TypeRef),
  Crystal::HIR::TypeRef)` for the `@type_intern` bucket entries in
  `Module#intern_type`.
- After preserving built-in generic bases, HIR emission contains
  `Tuple(UInt8, Array(Crystal::HIR::TypeRef), Crystal::HIR::TypeRef)` and no
  longer contains the `Crystal::MIR::Array` capture in that tuple family.
- Produced `s2` builds successfully under `run_safe.sh`; its generated LLVM
  for `Module#intern_type` no longer contains
  `Crystal$CCMIR$CCArray$LCrystal$CCHIR$CCTypeRef`.
- Produced `s2` now compiles a minimal `--no-prelude` program that previously
  segfaulted while interning `Pointer(UInt8)`.
- Host regression guards pass:
  `p2_hash_to_a_block_return_tuple_ok` and
  `p2_qualified_module_namespace_no_prelude_ok`.
- Produced `s2` still crashes with full prelude during early module
  registration, so this is a root fix for generic-base capture and the
  no-prelude intern-type crash, not a complete s2b fix.

Adversary notes:

- This is not a depth cap or string-specific patch. The resolver keeps
  externally visible built-in generic container bases stable and still resolves
  non-built-in generic bases contextually.
- Explicitly qualified names such as `Crystal::MIR::Array(T)` remain qualified;
  the fix only protects unqualified built-in generic bases from accidental
  contextual capture.

Trust: {F/G/R: 0.88/0.52/0.89} [verified]

### LM-653 - String pointer constructor bounds guard prevents huge signed memcpy

The V2 LLVM override for `String.new(UInt8*, Int32, Int32)` now guards the
unsafe constructor boundary before allocation and `memcpy`: non-positive
`bytesize`, null `chars`, and byte counts that would overflow the
`bytesize + header` allocation return the empty string instead of feeding a
negative signed `i32` into an `i64` copy length. The UInt64 overload now also
rejects values outside the guarded Int32 allocation corridor before truncating.

Evidence:

- Crash reports from produced `s2` included `String$Dnew$$Pointer$LUInt8$R_Int32_Int32`
  in `_platform_memmove` with a huge unsigned copy length, and another
  `GC_malloc_kind -> GC$Dmalloc_atomic$$UInt64` fault whose bad pointer bytes
  decoded as `[STAGE2_`, consistent with earlier heap corruption from string
  debug text.
- `regression_tests/p2_string_pointer_int32_constructor_shape.sh
  /tmp/cv2_string_guard` -> `p2_string_pointer_int32_constructor_shape_ok`.
- Negative-byte-count smoke compiled by `/tmp/cv2_string_guard` and run through
  `scripts/run_safe.sh` printed `0` bytesize instead of crashing.
- Produced `s2` built with the guard in about 154s with the existing non-fatal
  `CLI#file_sha256$String` MIR optimizer overflow diagnostic.

Adversary notes:

- This is not the final full-prelude bootstrap fix. Produced-s2 full-prelude
  `puts 42` still exits 139, with the current run moving to class registration
  (`class register idx=3/111`) instead of the older signed-copy/GC metadata
  crash pattern.
- The guard is intentionally at the unsafe String constructor ABI edge. It
  prevents a malformed byte count from corrupting unrelated heap state, but the
  next root remains the source of the malformed count or a separate class
  registration memory issue.

Trust: {F/G/R: 0.84/0.42/0.86} [verified]

### LM-651 - Pointer(Void) malloc and arithmetic use byte stride

`Pointer(Void).malloc(n)` is now lowered as a `Pointer(Void)` allocation
instead of accidentally wrapping the type literal as `Pointer(Pointer(Void))`.
Pointer arithmetic/copy sizing uses a byte stride for `Void`, while preserving
normal container-element sizing for typed pointers and value-union array
storage.

Evidence:

- Original Crystal treats `Void` pointer element size as `1` for pointer
  malloc/codegen so `Pointer(Void)` works like a byte pointer.
- The focused HIR repro previously emitted `ptr_malloc 34` and pointer-width
  arithmetic for `Pointer(Void).malloc(32)`. After the fix it emits
  `ptr_malloc 0` for `Pointer(Void)` and `ptr_add ... size=1` for the user
  byte-stride operations.
- `regression_tests/p2_pointer_void_byte_stride.sh /tmp/cv2_void_stride_fix3`
  -> `p2_pointer_void_byte_stride_ok`.
- `regression_tests/p2_array_heap_struct_dup_stride.sh
  /tmp/cv2_void_stride_fix3` -> `p2_array_heap_struct_dup_stride_ok`.
- `regression_tests/p2_array_tuple_storage.sh /tmp/cv2_void_stride_fix3` ->
  `p2_array_tuple_storage_ok`.
- `regression_tests/p2_array_value_union_storage.sh
  /tmp/cv2_void_stride_fix3` -> `p2_array_value_union_storage_ok`.
- Produced s2 still exits 139 on full-prelude `puts 42`, but the traced
  frontier moved past the earlier Time::Span area to a later repeated Object
  registration path. This landmark is not a complete s2 bootstrap fix.

Adversary notes:

- The fix is not a depth cap or name-family patch: it restores the original
  compiler's element-size invariant for `Pointer(Void)`.
- A broader first attempt that forced explicit pointer-add sizes for all
  elements regressed `p2_array_value_union_storage`; the landed corridor only
  forces the explicit byte size for raw `Void` elements.

Trust: {F/G/R: 0.87/0.55/0.88} [verified]

### LM-652 - Pointer::Appender constructors require nested generic owner preservation

`Pointer(UInt8)#appender` exposed a two-part nested generic constructor root.
HIR first inferred and registered `Pointer::Appender(UInt8)`, but the path
receiver corridor overwrote the specialized receiver with the original
`Pointer::Appender` path before call emission. After preserving the specialized
path receiver, HIR/MIR generated a real
`Pointer::Appender(UInt8).new$Pointer(UInt8)` allocator. LLVM then exposed the
second root: the primitive `Pointer.new(address)` shortcut matched every
receiver whose name started with `Pointer`, including `Pointer::Appender`.
That rewrote the nested struct constructor to an identity bitcast, leaving
`@pointer` and `@start` zeroed.

Evidence:

- Before the fix, the focused `Pointer(UInt8).malloc(8).appender << 1_u8`
  repro compiled but the produced binary segfaulted in
  `Pointer::Appender(UInt8)#<<` at `strb w9, [x10]` with `x10 == 0`.
- Intermediate HIR showed the call target stuck at
  `Pointer::Appender.new$Pointer(UInt8)` with no generated constructor symbol.
- After preserving `path_receiver_class_name`, HIR/MIR emitted
  `Pointer::Appender(UInt8).new$Pointer(UInt8)`, but LLVM still compiled
  `Pointer(UInt8)#appender` as `ret self` because `pointer_constructor_name?`
  treated `Pointer::Appender` as a primitive `Pointer` constructor.
- `regression_tests/p2_pointer_appender_constructor.sh /tmp/cv2_appender_fix3`
  -> `p2_pointer_appender_constructor_ok`.
- Neighbor guards also passed with `/tmp/cv2_appender_fix3`:
  `p2_pointer_void_byte_stride_ok`,
  `p2_array_heap_struct_dup_stride_ok`,
  `p2_array_tuple_storage_ok`, and
  `p2_array_value_union_storage_ok`.
- Rebuilt after reverting formatter churn:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 420 8192 build
  src/adamas.cr -o /tmp/cv2_appender_fix4 --error-trace` -> exit 0;
  `p2_pointer_appender_constructor.sh /tmp/cv2_appender_fix4` and
  `p2_pointer_void_byte_stride.sh /tmp/cv2_appender_fix4` -> ok.
- Produced `s2` built with the fix:
  `scripts/run_safe.sh /tmp/cv2_appender_fix4 900 8192 src/adamas.cr
  -o /tmp/cv2_appender_fix4_s2/cv2_s2` -> exit 0 in about 154s, with the
  existing non-fatal `CLI#file_sha256$String` MIR optimizer overflow
  diagnostic. Full-prelude produced-s2 `puts 42` still exits 139, but the
  visible trace reaches later `Float` module registration instead of the
  `Pointer::Appender` constructor/runtime crash.

Adversary notes:

- This is not a depth cap or a `Pointer::Appender` runtime shim. The fix keeps
  the existing generic constructor machinery and narrows only the primitive
  pointer-address shortcut to real `Pointer` / `Pointer(T)` receivers.
- The first local inference patch alone did not move the runtime result; the
  decisive evidence was HIR-to-LLVM drift from a generated constructor call to
  an identity bitcast.

Trust: {F/G/R: 0.90/0.58/0.89} [verified]

### LM-631 - Pointer copy helpers must use container slot stride

`Pointer(T)#copy_from`, `copy_to`, `move_from`, and `move_to` now lower their
element byte size through the V2 container-storage ABI instead of logical
`type_size(T)`. This matters for heap-backed structs: `ExprId` is logically a
4-byte value, but `Array(ExprId)` stores 8-byte heap-object pointers in its
buffer. Generated `Array(ExprId)#dup` had been calling
`__adamas_ptr_copy(..., elem_size=4)`, which copied only half of each
pointer slot and produced low-32-bit pointers in produced `s2`.

Evidence:

- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 420 8192 build
  src/adamas.cr -o /tmp/cv2_ptr_copy_stride_fix --error-trace` -> exit 0.
- Before the fix, a focused `Array(IdBox)#dup` generated by
  `/tmp/cv2_after_tuple` segfaulted at runtime after copying 71 heap-backed
  struct elements.
- `regression_tests/p2_array_heap_struct_dup_stride.sh
  /tmp/cv2_ptr_copy_stride_fix` -> `p2_array_heap_struct_dup_stride_ok`.
- `regression_tests/p2_array_tuple_storage.sh /tmp/cv2_ptr_copy_stride_fix`,
  `regression_tests/p2_array_value_union_storage.sh /tmp/cv2_ptr_copy_stride_fix`,
  `regression_tests/p2_nilable_union_wrap_codegen_no_prelude.sh
  /tmp/cv2_ptr_copy_stride_fix`, and
  `regression_tests/p2_union_concrete_compare_type_guard.sh
  /tmp/cv2_ptr_copy_stride_fix` all pass.
- Produced `s2` built cleanly with the fix:
  `scripts/run_safe.sh /tmp/cv2_ptr_copy_stride_fix 600 8192
  src/adamas.cr -o /tmp/cv2_ptr_copy_stride_s2/cv2_s2` -> exit 0.
- Disassembly of the new produced `s2` shows
  `Array(ExprId)#dup` passes `mov w3, #0x8` to `__adamas_ptr_copy`.

Adversary notes:

- This is not a `CLI#process_require_node` guard. The parser returned a valid
  64-bit `Array(ExprId)` buffer; the corruption was introduced by `res.dup`
  copying 4 bytes per pointer slot.
- Full-prelude `puts 42` is not yet clean: after this fix produced `s2` passes
  the former require-scan crash and reaches HIR module registration, then hits
  a new bus-error frontier around module registration. Treat that as the next
  root, not as evidence against the pointer-copy stride fix.

Trust: {F/G/R: 0.90/0.62/0.88} [verified]

### LM-630 - Tuple pointer-buffer stores must store pointers, not inline bytes

`Array(Tuple(Int64, Int64))` exposed the next container ABI mismatch after
LM-626. V2 represents tuple values as pointers and `Pointer(Tuple)`/`Array(Tuple)`
buffers use pointer-sized slots. `emit_gep_dynamic` already marked those slots
with `@ptr_aggregate_buffer_slots`, and loads dereferenced them as `ptr`; however
the generic `Store` backend saw the tuple `field_type` and memcpy'd the tuple
payload bytes directly into the pointer slot. The first tuple element was then
loaded back as a pointer, so `{0_i64, 10_i64}` crashed at null dereference.

The fix makes `Store` honor `@ptr_aggregate_buffer_slots` before the inline tuple
memcpy path: tuple pointer-buffer writes now copy the tuple payload to stable
heap storage and store that heap pointer in the buffer slot. Inline tuple storage
continues to use memcpy through the existing path.

Evidence:

- A reduced full-prelude program with `Array(Tuple(Int64, Int64))` printed `52`
  with the original compiler, crashed with V2 before the fix, and prints `52`
  with `/tmp/cv2_tuple_store_fix` after the fix.
- `regression_tests/p2_array_tuple_storage.sh /tmp/cv2_tuple_store_fix` ->
  `p2_array_tuple_storage_ok`.
- IR shape check on the reducer shows
  `Array$LTuple$LInt64$C$_Int64$R$R$Hpush` now emits `tuple_slot_copy` followed
  by `store ptr`, instead of memcpying 16 tuple bytes into the pointer slot.
- Regression guards still pass:
  `p2_array_value_union_storage_ok`,
  `p2_nilable_union_wrap_codegen_no_prelude_ok`, and
  `p2_union_concrete_compare_type_guard_ok`.
- Release layout benchmark smoke now matches original checksums for struct,
  tuple, class, nilable struct/class, and mixed struct/int cases. V2 remains
  slower on tuple/class-heavy cases, so performance work should target tuple
  heap persistence/object allocation rather than this semantic crash.

Adversary notes:

- This is not a tuple-wide inline ABI rewrite. It only changes stores into slots
  already certified as tuple pointer-buffer slots by `emit_gep_dynamic`.
- The previous inline aggregate store path remains for actual inline tuple
  storage.

Trust: {F/G/R: 0.90/0.62/0.91} [verified]

### LM-626 - Pointer container storage uses one stride for inline value unions

`Pointer(T)` lowering now uses the same container storage size for allocation,
indexed stores, indexed loads, pointer arithmetic, realloc, clear, and
copy/move helpers. This fixes `Array(Pair | Nil)` and `Array(Pair | Int64)`
corruption where `Pointer(T).malloc` and `copy_from` still used pointer-size
8-byte slots while array reads/writes used the 24-byte inline union slot for
`Pair | Nil`.

The same change also preserves the destination element type on MIR stores
emitted from `PointerStore`, so the LLVM backend can construct tagged inline
union values instead of storing raw pointers or reading a nonexistent runtime
header from heap-backed structs. The backend's "union passed as ptr" memcpy
fast path is now restricted to actual union-typed MIR values; bare structs
must be wrapped with a descriptor-backed discriminator.

Evidence:

- `regression_tests/p2_array_value_union_storage.sh
  /tmp/cv2_layout_fix_host6` -> `p2_array_value_union_storage_ok`.
- `regression_tests/p2_nilable_union_wrap_codegen_no_prelude.sh
  /tmp/cv2_layout_fix_host6` -> `p2_nilable_union_wrap_codegen_no_prelude_ok`.
- `regression_tests/p2_union_concrete_compare_type_guard.sh
  /tmp/cv2_layout_fix_host6` -> `p2_union_concrete_compare_type_guard_ok`.
- Generated IR for `Array(Pair | Nil)#resize_to_capacity` now has both
  realloc and initial malloc branches multiplying capacity by 24, and
  `Array(Pair | Nil)#check_needs_resize` calls
  `__adamas_ptr_copy(..., i32 24)` for the compaction copy.
- Release benchmark smoke with `N=500_000` matched original checksums for
  `Array(Pair)`, `Array(BenchBox)`, `Array(Pair | Nil)`,
  `Array(BenchBox | Nil)`, and `Array(Pair | Int64)`. `Array(Tuple(Int64,
  Int64))` still segfaults under V2 and remains a separate tuple-container
  frontier.

Adversary notes:

- The regression covers direct `Pointer(Pair | Nil).malloc` writes,
  `Array(Pair | Nil)` initial allocation, `Array(Pair | Nil)` shifted-buffer
  compaction, and `Array(Pair | Int64)` mixed value unions. This guards the
  storage-stride family rather than only the first observed nilable-array
  symptom.
- V2 still heap-allocates most structs, so matching checksums here does not
  imply upstream-equivalent struct layout or performance. The benchmark shows
  the next performance/correctness frontier is tuple/container storage, not
  nilable struct union tags.

Trust: {F/G/R: 0.89/0.57/0.90} [verified]

### LM-624 - Generated-stage2 require scanning avoids Regex-backed skip_file suffix extraction

Produced `s2` full-prelude `puts 42` no longer crashes before `prelude parsed`
while scanning `skip_file` macro directives in required stdlib files. The
crash was not a parser frontier: LLDB showed `String#sub(Regex, ...)` under
`CLI#each_macro_literal_raw_text_window` while processing
`src/stdlib/io/encoding.cr`. The fix keeps the same `skip_file` directive
semantics but extracts the suffix with byte slicing instead of Regex-backed
`String#sub`, removing Regex/String block machinery from recursive require
scanning.

Evidence:

- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 360 8192 build
  src/adamas.cr -o /tmp/cv2_skipfile_regex_host --error-trace` -> exit 0.
- `scripts/run_safe.sh /tmp/cv2_skipfile_regex_host 360 4096
  src/adamas.cr -o /tmp/cv2_skipfile_regex_s2/cv2_s2` -> exit 0.
- `regression_tests/p2_require_scan_skip_file_no_regex_no_prelude.sh
  /tmp/cv2_skipfile_regex_s2/cv2_s2` -> exit 0.
- The previous produced-stage2 full-prelude smoke reached `prelude exists` and
  crashed before `prelude parsed`; after the change it reached HIR
  registration/lowering, exposing the next `typeof(element_type)` frontier.

Boundary: this is a require-scanner bootstrap hardening, not a general Regex
or parser fix.

Trust: {F/G/R: 0.90/0.56/0.90} [verified]

### LM-625 - typeof element_type prefix scans avoid Array/block lookup in generated stage2

Produced `s2` no longer crashes in
`AstToHir#resolve_element_type_expression(String)` when registering a method
annotation containing `typeof(Enumerable.element_type(Array(Int32)))`. LLDB and
disassembly showed the old fixed `ELEMENT_TYPE_PREFIXES.find { ... }` lowered
to an `Array(String)` block scan whose generated-stage2 loop cursor was read as
a null pointer before `Array#unsafe_fetch`. This matches the older LM-535
pattern: fixed string tables in bootstrap compiler hot paths must not rely on
`Array#find`/block machinery until the broader generated-stage2 collection
lowering issue is fixed.

The fix removes the fixed prefix arrays from HIR and semantic type-expression
resolution, spelling the same prefix set as direct `starts_with?` checks. HIR
also uses the existing ASCII byte classifier instead of `Char#uppercase?` in
this path. A related LLVM emission frontier was exposed after the prefix crash
was cleared: `current_func_param_index?` used a nilable `@current_func_params[i]?`
fetch, and produced `s2` dispatched `Parameter#index` to an unrelated
`#index` method. The helper now uses the existing size guard plus
`unsafe_fetch`, preserving the concrete `Parameter` receiver.

Evidence:

- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 360 8192 build
  src/adamas.cr -o /tmp/cv2_param_index_host --error-trace` -> exit 0.
- `scripts/run_safe.sh /tmp/cv2_param_index_host 360 4096
  src/adamas.cr -o /tmp/cv2_param_index_s2/cv2_s2` -> exit 0.
- Before the prefix fix, the def-only no-prelude oracle crashed with exit 139
  in `resolve_element_type_expression`; after the fix,
  `regression_tests/p2_typeof_element_type_prefix_no_array_scan_no_prelude.sh
  /tmp/cv2_param_index_s2/cv2_s2` -> exit 0.
- `regression_tests/p2_require_scan_skip_file_no_regex_no_prelude.sh
  /tmp/cv2_param_index_s2/cv2_s2` -> exit 0.
- `regression_tests/p2_qualified_module_namespace_no_prelude.sh
  /tmp/cv2_param_index_s2/cv2_s2` -> exit 0.
- Full-prelude produced `puts 42` with `/tmp/cv2_param_index_s2/cv2_s2`
  reached `lower_main: exprs=15` and timed out under the 360s safe wrapper at
  about 646MB RSS, rather than crashing during prelude parse, registration, or
  `typeof(element_type)` normalization.

Boundary: this is not proof that general `Array#find`, block lowering, or
nilable union narrowing is fixed. It removes two such generated-stage2-hostile
constructs from bootstrap-critical compiler paths and leaves the next frontier
as lower-main progress/time.

Trust: {F/G/R: 0.91/0.58/0.91} [verified]

### LM-650 - Semantic tokens traverse case branches and full Crystal keyword set

Semantic coloring now follows `CaseNode` branches before sorting/deduping token
ranges, so method calls and operators inside `when` bodies are emitted by the
same AST/semantic-token path that already covered `if`/`while`/`loop` bodies.
The fast lexical overlay also recognizes the Crystal keyword set used by the
frontend lexer, including visibility keywords such as `private`/`protected`
and control keywords such as `loop`, `select`, `spawn`, and `raise`. The
semantic-token disk cache moved to v4 so unchanged large files cannot reuse
stale pre-case-traversal token JSON.

Evidence:

- Focused regression:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 3072 spec
  spec/lsp/semantic_tokens_spec.cr --error-trace` -> 9 examples, 0 failures.
- Full LSP suite:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec spec/lsp
  --error-trace` -> 266 examples, 0 failures.
- Formatter:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 2048 tool format
  --check src/compiler/lsp/server.cr src/compiler/lsp/semantic_token_cache.cr
  spec/lsp/semantic_tokens_spec.cr` -> exit 0.
- Actual DiamondDB probe on
  `/Users/sergey/Projects/Crystal/DiamondDB/src/diamond_foundation/sql/lexer.cr`
  lines 120-130 emitted `private`/`loop` as keyword, `ord`/`to_u8`/
  `peek_byte_at`/`peek_byte`/`at_end?` as method, and `!`/`&&` as operator.
- `./build_lsp_debug.sh` rebuilt `bin/adamas_lsp` successfully.

Adversary notes:

- This is not a styling/theme fix. Navigation already used independent
  hover/definition paths; the missing surface was semantic-token emission.
- The fast lexical path is still checked against the lexer oracle for covered
  keyword fixtures to avoid scanner drift.

Trust: {F/G/R: 0.87/0.58/0.90} [verified]

### LM-624 - Full semantic-token lexical overlay uses a fast scanner

The full-document semantic-token lexical overlay no longer runs the full
frontend lexer for the common LSP-only token classes. The default path now uses
a byte scanner for keywords, uppercase identifiers, symbol literals, strings,
chars, and regex literals, while `LSP_FAST_LEXICAL_TOKENS=0` keeps the old
lexer-backed oracle available. The range lexical helper uses the same scanner
by default so full/range highlighting does not split across two lexical
implementations.

Evidence:

- The focused semantic-token regression compares the fast path with the old
  lexer oracle on covered lexical fixtures: keywords/end, comment skipping,
  uppercase identifiers, symbol literals, simple interpolation, simple regex,
  a complex regex literal from `ast_to_hir.cr`, and slash division that should
  emit no lexical token.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/lsp/semantic_tokens_spec.cr spec/lsp/lsp_semantic_tokens_spec.cr
  spec/lsp/semantic_tokens_integration_spec.cr --error-trace` -> 37 examples,
  0 failures.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 248 examples, 0 failures.
- Temporary profile on `src/compiler/hir/ast_to_hir.cr` with
  `LSP_FAST_LEXICAL_TOKENS=0`: collection about 550.5ms, lexical about
  314.1ms. Default fast scanner: collection about 315.1ms, lexical about
  117.8ms. Same profile run showed first full request helper time at about
  851.6ms after this change.
- Formatting and diff hygiene: `scripts/run_safe.sh /Users/sergey/.local/bin/crystal
  120 4096 tool format --check src/compiler/lsp/server.cr
  spec/lsp/semantic_tokens_spec.cr` -> exit 0; `git diff --check` -> exit 0.

Adversary notes:

- The scanner is not a general Crystal lexer replacement. It is scoped to the
  lexical token classes consumed by semantic-token highlighting.
- The old lexer path remains available with `LSP_FAST_LEXICAL_TOKENS=0`.
- A pre-existing lexer-column issue for complex string interpolation is not
  reproduced by the fast scanner; the scanner emits positions from byte
  offsets. Existing focused interpolation coverage remains green.

Trust: {F/G/R: 0.86/0.48/0.87} [verified]

### LM-625 - Cached foreground opens skip redundant name resolution

Warm `didOpen` for an unchanged disk-backed document now uses the already
loaded project cache to build the foreground `DocumentState` after the AST
cache supplies the parsed arena. This path is gated by the exact disk text
check, valid project-cache mtime, parser-clean AST, and disabled semantic
diagnostics. It reuses cached symbols and expression types, leaves
`identifier_symbols` unset, and materializes full foreground semantic analysis
only when precision features such as hover, definition, references, inlay
hints, or call hierarchy need the current-AST identifier map.

Evidence:

- Focused regression:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/lsp/hover_definition_indexing_spec.cr
  spec/lsp/project_cache_semantic_fidelity_spec.cr --error-trace` ->
  5 examples, 0 failures.
- Full LSP suite:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 249 examples, 0 failures.
- Stable-binary timing on `src/compiler/hir/ast_to_hir.cr` with isolated
  `XDG_CACHE_HOME`: cold cache `didOpen` remained about 2662.7ms; warm default
  cache-backed `didOpen` was about 548.0ms; the same warm cache with
  `LSP_FAST_PROJECT_OPEN=0` was about 999.5ms.
- The warm log showed `Loading foreground document ... from AST cache` followed
  by `Using project cache for foreground open ... (identifier_symbols=false)`.

Adversary notes:

- This does not fake `ExprId -> Symbol` maps across parser sessions. Cached
  opens leave `identifier_symbols` absent until full semantic analysis runs
  against the current parsed AST.
- The existing indexing soft-fail contract is preserved for documents that
  genuinely lack a symbol table; the regression for hover during indexing
  remains green.
- Grok ACP reviewed the hypothesis as a read-only sidecar and flagged the same
  invariant: identifier maps are per-parse-session and must not be restored
  unless they are rebuilt for the current AST.

Trust: {F/G/R: 0.87/0.48/0.88} [verified]

### LM-626 - Cached foreground opens skip redundant project updates

After LM-625 accepts an unchanged disk-backed document from project cache,
`didOpen` no longer queues the same text for debounced
`UnifiedProject.update_file`. That update was redundant: the project cache had
already validated the file mtime and supplied the foreground symbols/types,
while the queued update did not refresh the live `DocumentState`. On
`src/compiler/hir/ast_to_hir.cr`, this removed the post-open maintenance tail
that previously made shutdown or the next idle window pay another full project
analysis.

Evidence:

- Focused regression:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/lsp/project_cache_semantic_fidelity_spec.cr --error-trace` ->
  4 examples, 0 failures.
- Full LSP suite:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 249 examples, 0 failures.
- Stable-binary timing on `src/compiler/hir/ast_to_hir.cr` with isolated
  `XDG_CACHE_HOME`: warm cache-backed `didOpen` stayed about 529.3ms, while
  shutdown dropped to about 12.8ms. The warm log showed the cached foreground
  open and no `UnifiedProject update_file` line.
- Formatting and diff hygiene:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 tool format
  --check src/compiler/lsp/server.cr spec/lsp/support/server_helper.cr
  spec/lsp/project_cache_semantic_fidelity_spec.cr` -> exit 0;
  `git diff --check` -> exit 0.

Adversary notes:

- The skip is tied to the exact foreground project-cache analysis path, not to
  every `didOpen`. Normal non-cached opens and changed buffers still enqueue
  project maintenance.
- This is a background/maintenance reduction, not an AST-load improvement. The
  remaining warm open still pays AST-cache deserialization for huge files.

Trust: {F/G/R: 0.88/0.45/0.88} [verified]

### LM-627 - Cached foreground opens defer AST-cache deserialization

Warm `didOpen` for an unchanged disk-backed document can now build its
foreground `DocumentState` from project-cache summaries without immediately
deserializing the AST cache. The lightweight path is gated by exact disk text,
valid project-cache state, disabled semantic diagnostics, and a current AST
cache header for the same compiler fingerprint and source mtime. It stores an
empty-AST `Program` only for the initial open; handlers that need the AST
materialize it on demand, and precision handlers that need identifier maps run
foreground semantic analysis against the loaded AST.

Evidence:

- Focused regressions:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/lsp/project_cache_semantic_fidelity_spec.cr --error-trace` ->
  5 examples, 0 failures. The new checks cover semantic tokens, signature help,
  prepare rename, document symbols, and folding ranges as first requests after a
  lightweight cached open.
- Full LSP suite:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 250 examples, 0 failures.
- Isolated timing on `src/compiler/hir/ast_to_hir.cr` through
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 8192 eval ...`:
  lazy cached `didOpen` samples were `322.6,269.3,269.9,269.5,272.9ms`
  (`avg=280.8ms`), while the same warm cache with
  `LSP_FAST_PROJECT_OPEN=0` was `1118.1,1165.9,1163.4ms` (`avg=1149.1ms`).
- Formatting and diff hygiene:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/server.cr spec/lsp/support/server_helper.cr
  spec/lsp/project_cache_semantic_fidelity_spec.cr` -> exit 0;
  `git diff --check` -> exit 0.

Adversary notes:

- This is not a parser or diagnostic shortcut for dirty buffers. If the text is
  not exactly the disk file, if the AST-cache header is stale, or if the
  project cache is invalid, the server falls back to the previous parse/analyze
  path.
- The lightweight path does not restore fake identifier maps. Completion,
  hover, definition, rename, inlay hints, and call hierarchy can materialize
  foreground semantic analysis when they need current-AST symbol mappings.
- Grok's read-only audit usefully pushed the AST-walker coverage set, but its
  claim that the cached expression-type compatibility marker is skipped was
  locally refuted: the marker is set in the shared cached-analysis helper used
  by both parsed and lightweight cached opens.

Trust: {F/G/R: 0.89/0.47/0.89} [verified]

### LM-628 - Member completion recognizes uppercase identifier constructors

Member completion now reuses the shared constructor-type extractor when
inferring a receiver from local assignments such as `helper = Helper.new`.
The extractor accepts uppercase `IdentifierNode` receivers in addition to
`ConstantNode` and `PathNode`, because the frontend can parse a simple
constructor receiver as an identifier in method-local code. Lowercase
`variable.new` is still rejected by the uppercase guard, so this does not turn
arbitrary instance `.new` calls into class constructors.

Evidence:

- Focused regression:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/lsp/project_cache_semantic_fidelity_spec.cr --error-trace` ->
  5 examples, 0 failures. The added check opens a lightweight cached document,
  asks for `helper.` completion inside a method after `helper = Helper.new`,
  and expects `Helper#value`.
- Full LSP suite:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 250 examples, 0 failures.
- Formatting and diff hygiene:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/server.cr
  spec/lsp/project_cache_semantic_fidelity_spec.cr` -> exit 0;
  `git diff --check` -> exit 0.

Adversary notes:

- This is not a generic textual completion hack. The path still requires an
  actual assignment value expression and the constructor extractor only accepts
  class-like uppercase identifier receivers, constants, or paths.
- A Grok read-only sidecar was attempted but produced no findings after
  startup; it was stopped and not used as acceptance evidence.

Trust: {F/G/R: 0.88/0.45/0.88} [verified]

### LM-629 - Method-call hover and definition avoid first semantic materialization

After lazy cached opens, unqualified method-call hover and definition can now
use a narrow text-backed method lookup before materializing the AST and
identifier map. The fast path is limited to lowercase or underscore-prefixed
identifiers followed by `(`, rejects member/namespace/ivar receivers, and
skips names that have a prior local assignment in the visible text. Method text
lookup now tries the current document before required files, so same-file calls
in large files do not spend the request budget scanning dependencies first.

Evidence:

- Focused regression:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/lsp/project_cache_semantic_fidelity_spec.cr --error-trace` ->
  5 examples, 0 failures. The added checks open a lightweight cached document,
  ask for definition and hover on `target(1)`, and verify the AST remains
  unloaded.
- Full LSP suite:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 250 examples, 0 failures.
- Isolated timing on `src/compiler/hir/ast_to_hir.cr` at the
  `class_name_from_node(member, source)` call:
  lazy `didOpen` remained about `277ms`; first hover was `24.5ms` and first
  definition was `25.3ms`, both leaving `ast_loaded=false` and
  `identifiers=false`. The earlier corrected baseline for the same call shape
  was about `2.6-2.8s` when full foreground semantic materialization ran first.
- Formatting and diff hygiene:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/server.cr
  spec/lsp/project_cache_semantic_fidelity_spec.cr` -> exit 0;
  `git diff --check` -> exit 0.

Adversary notes:

- This does not replace semantic definition generally. It is a bounded
  method-call text shortcut for the common unqualified call form and falls back
  to the existing semantic path when the guard does not match.
- A false-positive guard rejects names with prior visible local assignment, so
  local proc/variable calls do not take the text method path.

Trust: {F/G/R: 0.89/0.44/0.89} [verified]

### LM-630 - `adamas tool lsp` launches the sibling LSP server

The compiler entry point now recognizes `tool lsp` before normal compile-mode
argument parsing and execs a sibling `adamas_lsp` binary, or an explicit
`ADAMAS_LSP_SERVER` path. This keeps the bootstrap compiler binary from
embedding `src/compiler/lsp/server.cr` while still exposing the Crystal-style
tool command shape. The VS Code extension remains backward-compatible with its
default `../bin/adamas_lsp` path and now also supports
`crystalv2.lsp.serverPath` plus `crystalv2.lsp.serverArgs`, so users can point
it at `adamas` with `["tool", "lsp"]`.

Evidence:

- Focused dispatch regression:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/lsp/tool_dispatch_spec.cr --error-trace` -> 4 examples, 0 failures.
- Full LSP suite:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 254 examples, 0 failures.
- Process-level launcher smoke:
  built `src/adamas.cr` under `scripts/run_safe.sh` to a temporary
  directory, installed a fake sibling `adamas_lsp`, then ran
  `scripts/run_safe.sh <tmp>/adamas 10 512 tool lsp alpha beta`; the fake
  server received `alpha beta` and exited with the expected sentinel status.
- Formatting and syntax checks:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/tool_dispatch.cr src/adamas.cr
  spec/lsp/tool_dispatch_spec.cr` -> exit 0;
  `node --check vscode-extension/extension.js` -> exit 0;
  `git diff --check` -> exit 0.

Adversary notes:

- This is a launcher, not an embedded server. If the sibling LSP binary is
  absent, `tool lsp` reports a clear build/configuration error instead of
  falling through to compile mode.
- Extra child args are preserved after `tool lsp`, which keeps the command
  usable for future LSP flags and for VS Code `serverArgs`.

Trust: {F/G/R: 0.88/0.42/0.88} [verified]

### LM-631 - Constructor-assigned member calls avoid first semantic materialization

After lazy cached opens, member-call hover and definition can now use a narrow
text-backed receiver corridor for local variables assigned earlier to
`Type.new`. The guard only accepts lowercase or underscore-prefixed local
receivers, lowercase method names followed by `(`, rejects chained/path/ivar
receivers, requires the receiver assignment to resolve to a concrete class
source file, and then searches only that resolved file for the method
signature/location. This covers common shapes like `helper = Helper.new` then
`helper.value(2)` without materializing the foreground AST or identifier map.

Evidence:

- Focused cached-open regression:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/lsp/project_cache_semantic_fidelity_spec.cr --error-trace` ->
  5 examples, 0 failures. The new checks verify definition and hover for
  `helper.value(2)` route to `helper.cr` and keep
  `spec_document_ast_loaded? == false`.
- Full LSP suite:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 254 examples, 0 failures.
- Formatting and diff hygiene:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/server.cr
  spec/lsp/project_cache_semantic_fidelity_spec.cr` -> exit 0;
  `git diff --check` -> exit 0.

Adversary notes:

- This deliberately does not scan all required files for the first matching
  method when a receiver type cannot be resolved. It falls back to the existing
  semantic path instead, avoiding same-named-method false positives.
- The path is limited to constructor-assigned local receivers; member chains,
  ivars, constants, and non-call member access still use existing semantic
  handling.

Trust: {F/G/R: 0.88/0.43/0.88} [verified]

### LM-632 - Constructor-assigned member completion avoids first semantic materialization

After lazy cached opens, member completion can now use the same narrow
constructor-assigned local receiver corridor as LM-631. For `helper =
Helper.new` followed by `helper.`, completion extracts the local receiver from
the dot window, resolves the earlier constructor assignment to a concrete class
source file, and collects method names from that file without materializing the
foreground AST or identifier map. If receiver extraction, assignment parsing,
or type/file resolution fails, completion falls back to the existing semantic
path.

Evidence:

- Focused cached-open regression:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/lsp/project_cache_semantic_fidelity_spec.cr --error-trace` ->
  5 examples, 0 failures. The completion check for `helper.` still returns
  `value` and now keeps `spec_document_ast_loaded? == false`.
- Full LSP suite:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 254 examples, 0 failures.
- Formatting and diff hygiene:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/server.cr
  spec/lsp/project_cache_semantic_fidelity_spec.cr` -> exit 0;
  `git diff --check` -> exit 0.

Adversary notes:

- The fast path only emits items when a concrete receiver type source file is
  resolved. It does not scan all requires for same-named methods.
- This does not remove AST materialization for signature help, document
  symbols, folding, rename, or more complex member receivers.

Trust: {F/G/R: 0.88/0.43/0.88} [verified]

### LM-633 - Constructor-assigned member signature help avoids first AST load

After lazy cached opens, signature help for constructor-assigned member calls
can now use the same receiver corridor as LM-631/LM-632. For `helper =
Helper.new` followed by `helper.value(`, the handler finds the call paren in
text before AST materialization, resolves `helper` through the prior
constructor assignment, and reads the method signature from the resolved class
source file. If the receiver/type/file guard fails, the request still falls
back to the existing AST-backed signature-help path.

Evidence:

- Focused cached-open regression:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/lsp/project_cache_semantic_fidelity_spec.cr --error-trace` ->
  5 examples, 0 failures. The signature-help check for `helper.value(` now
  verifies `scale : Int32` and keeps `spec_document_ast_loaded? == false`.
- Full LSP suite:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 254 examples, 0 failures.
- Formatting and diff hygiene:
  `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/server.cr
  spec/lsp/project_cache_semantic_fidelity_spec.cr` -> exit 0;
  `git diff --check` -> exit 0.

Adversary notes:

- The fast path only creates signature help from a concrete receiver source
  file. It does not infer arbitrary receiver chains or scan unrelated required
  files.
- Constructor calls, unresolved member calls, and complex receivers keep the
  existing AST/semantic signature-help behavior.

Trust: {F/G/R: 0.88/0.43/0.88} [verified]

### LM-634 - Cached document symbols avoid first AST load

After lazy cached opens, `textDocument/documentSymbol` can now answer from
persisted `SymbolSummary` rows instead of forcing foreground AST
materialization. The fast path is boundary-checked: it only uses cached
summaries when the project-cache state is valid and the open buffer text
exactly matches the unchanged file on disk. Unsaved buffers, stale mtimes,
missing summaries, and conversion gaps still fall back to the existing
AST-backed document-symbol path.

Evidence:

- Focused cached-open regression:
  `scripts/run_safe.sh crystal 300 4096 spec/lsp/project_cache_semantic_fidelity_spec.cr`
  -> 5 examples, 0 failures. The document-symbol request still returns
  `Entry` and now keeps `spec_document_ast_loaded? == false`.
- Full LSP suite:
  `scripts/run_safe.sh crystal 300 4096 spec spec/lsp` -> 254 examples,
  0 failures.
- Formatting and diff hygiene:
  `crystal tool format --check src/compiler/lsp/server.cr
  spec/lsp/project_cache_semantic_fidelity_spec.cr` -> exit 0;
  `git diff --check` -> exit 0.

Adversary notes:

- The cache corridor does not trust filename/mtime alone; it also compares the
  current open document text with disk before emitting cached symbols.
- The conversion is intentionally limited to structural symbol summaries.
  Folding ranges, prepare-rename, and semantic-token full responses keep their
  existing stronger paths.

Trust: {F/G/R: 0.87/0.44/0.88} [verified]

### LM-635 - VS Code extension discovers `crystal2` without hardcoded repo paths

The VS Code extension no longer defaults to a repo-relative
`../bin/adamas_lsp` path. If `crystalv2.lsp.serverPath` is configured, that
path overrides all discovery and must point to an executable file or the
extension reports an error and does not start the language client. Without an
explicit setting, the extension tries `crystal2 tool lsp`, then
`adamas tool lsp`, then standalone `adamas_lsp` from `PATH`. The
compiler-side dispatcher also accepts `tools lsp` as a compatibility alias for
`tool lsp`.

Evidence:

- JavaScript syntax:
  `node --check vscode-extension/extension.js` -> exit 0.
- Tool-dispatch regression:
  `scripts/run_safe.sh crystal 180 4096 spec spec/lsp/tool_dispatch_spec.cr`
  -> 5 examples, 0 failures.
- Full LSP suite before the final JS-only missing-path hardening:
  `scripts/run_safe.sh crystal 300 4096 spec spec/lsp` -> 255 examples,
  0 failures.
- Formatting and diff hygiene:
  `crystal tool format --check src/compiler/lsp/tool_dispatch.cr
  spec/lsp/tool_dispatch_spec.cr` -> exit 0; `git diff --check` -> exit 0.

Adversary notes:

- Settings are authoritative: PATH discovery and `ADAMAS_LSP_SERVER` are
  skipped when `crystalv2.lsp.serverPath` is set.
- Missing configured paths fail closed before `LanguageClient.start()`, so VS
  Code does not attempt to spawn a nonexistent LSP server.

Trust: {F/G/R: 0.86/0.45/0.87} [verified]

### LM-636 - Invalid project-cache reparses stay off the LSP background path

Invalid project-cache entries are now tracked as deferred foreground work
instead of being reparsed by the startup/background maintenance fiber. The
previous `schedule_reparse_invalid_files` path could call
`UnifiedProjectState#update_file` on arbitrary invalid cached files after
initialize, which reproduced the user-visible standalone LSP crash as a parser
stack overflow. Background project indexing also skips these invalid paths,
and the invalid marker is cleared only after a successful foreground document
update.

Evidence:

- User crash signature: `schedule_reparse_invalid_files` ->
  `UnifiedProjectState#update_file` -> recursive parser stack overflow while
  VS Code restarted `bin/adamas_lsp` repeatedly.
- Focused cache regression:
  `scripts/run_safe.sh crystal 180 4096 spec
  spec/lsp/did_change_integration_spec.cr
  spec/lsp/project_cache_validation_spec.cr` -> 13 examples, 0 failures.
- Full LSP suite:
  `scripts/run_safe.sh crystal 300 4096 spec spec/lsp` -> 255 examples,
  0 failures.
- Rebuilt `bin/adamas_lsp` with `./build_lsp.sh`; stdio harness against
  the rebuilt binary returned initialize in about 462ms, first `server.cr`
  `didOpen` settled in about 67ms, document symbols in about 15ms, semantic
  tokens in about 66ms, and exited cleanly with no diagnostics.

Adversary notes:

- This is not a parser depth cap and does not weaken Crystal syntax handling.
  The LTP/WBA move removes a sticky startup corridor: invalid cache paths are
  recorded at cache-load time, transported only as exact path markers, and
  collapsed when a foreground update recomputes the real document state.
- A larger stack is not the accepted fix. Current `ld64.lld` warns that the
  Darwin `-stack_size` option is ignored in this build path, so the root
  evidence is the background reparse removal, not linker stack tuning.
- Non-invalid background indexing still parses cacheable project files. If a
  future crash points there, treat it as a separate background-indexing root,
  not as evidence to re-enable invalid-cache reparsing.

Trust: {F/G/R: 0.88/0.46/0.90} [verified]

### LM-637 - Hover does not load dependency graphs for qualified paths

Hover on qualified paths and member accesses now resolves only through the
active document, already-loaded dependency/project-cache state, and prelude
state. It no longer calls the dependency-loading resolver used by definition.
This keeps hover on a bounded request-time corridor while preserving broader
dependency loading for navigation and other precision requests.

Evidence:

- Harness scenario on `src/adamas.cr` around `cli =
  Adamas::Compiler::CLI.new(ARGV)`:
  - before the fix, hovering the qualified `CLI` segment took about 105ms and
    `CLI.new` triggered recursive `Loading dependency ... from project cache`
    lines across the compiler graph.
  - after the fix, `CLI` hover is about 1.2ms, `CLI.new` hover is about
    6.7ms, `cli.run` hover is about 1.2ms, and the debug log has no
    `Loading dependency` entries for the hover sequence.
- Focused regression:
  `scripts/run_safe.sh crystal 180 4096 spec
  spec/lsp/hover_definition_integration_spec.cr` -> 6 examples, 0 failures.
- Full LSP suite:
  `scripts/run_safe.sh crystal 300 4096 spec spec/lsp` -> 256 examples,
  0 failures.

Adversary notes:

- This is not a precision downgrade for explicit navigation: definition still
  uses the dependency-loading resolver. The constrained path applies only to
  hover.
- The LTP/WBA trigger is a hover request over a qualified `PathNode` or
  `MemberAccessNode`; the transport is already-materialized symbol state; the
  potential decreases by eliminating request-time dependency graph loads.

Trust: {F/G/R: 0.88/0.47/0.90} [verified]

### LM-638 - Hover method-call text fallback selects overloads by arity

The hover text fallback for unqualified method calls now carries the call-site
argument count into source-text signature lookup. When several methods share a
name, it selects a signature whose required/allowed arity accepts the call
instead of returning the first textual `def`. Source-backed `DefNode`
signature formatting also preserves default parameter values from parameter
default spans.

Evidence:

- The focused regression models `new_seed` with a zero-arg wrapper and a
  two-arg overload with `initseq = 0_u64`. Hovering the two-arg call now
  returns `def new_seed(initstate : UInt64, initseq = 0_u64) : UInt32`, not
  `def new_seed : UInt32`.
- Harness scenario on `/Users/sergey/Projects/Crystal/crystal/src/random/pcg32.cr`
  with a temporary patched LSP returned hover payloads for both the overload
  declaration and the call. Debug output logged the synthesized declaration
  signature as `def new_seed(initstate : UInt64, initseq = 0_u64) : UInt32`.
- Focused regression:
  `scripts/run_safe.sh crystal 180 4096 spec
  spec/lsp/hover_definition_integration_spec.cr` -> 7 examples, 0 failures.
- Full LSP suite:
  `scripts/run_safe.sh crystal 300 4096 spec spec/lsp` -> 257 examples,
  0 failures.

Adversary notes:

- This does not implement full Crystal overload resolution in hover. It is a
  bounded text fallback: use call arity to avoid obviously wrong same-name
  overloads, while preserving the existing semantic resolver paths.
- The arity parser counts top-level call arguments and top-level signature
  parameters, including defaults and splats, without modifying stdlib files.

Trust: {F/G/R: 0.86/0.44/0.89} [verified]

### LM-639 - Definition method-call text fallback selects overloads by arity

The unqualified definition fast path now carries the same call-site arity used
by hover into source-text method location lookup. For overloaded methods, it
returns the first same-name `def` whose signature accepts the call arity before
falling back to the first textual match. The per-file method-location cache key
includes arity so a previous zero-arg lookup cannot poison a later two-arg
definition request.

Evidence:

- The focused regression extends the `new_seed` overload fixture so a
  two-argument call resolves definition to
  `def new_seed(initstate : UInt64, initseq = 0_u64) : UInt32`, matching the
  hover selection instead of the zero-arg wrapper.
- Real LSP stdio harness against
  `/Users/sergey/Projects/Crystal/crystal/src/random/pcg32.cr` returned hover
  `def new_seed(initstate : UInt64, initseq = 0_u64) : UInt32` and definition
  location `line=62, character=6`, the parameterized overload.
- `./build_lsp_debug.sh` rebuilt `bin/adamas_lsp` successfully.
- `scripts/run_safe.sh crystal 180 4096 spec
  spec/lsp/hover_definition_integration_spec.cr` -> 7 examples, 0 failures.
- `scripts/run_safe.sh crystal 300 4096 spec spec/lsp` -> 257 examples,
  0 failures.

Adversary notes:

- This is still a bounded text fallback, not full Crystal overload resolution.
  It fixes the local root where definition stayed name-only after hover became
  arity-aware.
- LTP/WBA shape: trigger is an unqualified call-site definition request;
  transport is top-level argument count into the method-location corridor;
  potential decreases from same-name overload ambiguity to arity-compatible
  candidates while preserving the semantic resolver fallback boundary.

Trust: {F/G/R: 0.87/0.44/0.90} [verified]

### LM-640 - Hover recognizes bare bang numeric conversion calls

Member-call hover now treats trailing `!`/`?` as part of a method name and
accepts bare zero-argument member calls without requiring parentheses. This
closes the `value.to_i8!` shape in `Int8.new!(value)`, where the old extractor
stopped at `to_i8`, then missed because there was no following `(`.

When the source-text lookup still cannot find a real `def` because Crystal's
numeric conversion methods are generated, hover uses a narrow synthetic
signature for generated integer conversion bangs such as `to_i8!`:
`def to_i8! : Int8`. At this landmark, definition did not synthesize a fake
source location for those generated methods; LM-641 later routes them to the
real primitive template.

Evidence:

- Focused regressions cover a textual `def to_i8! : Int8` after a `def to_i8`
  prefix trap, plus a generated-conversion shape with no textual `def`.
- Real LSP stdio harness against
  `/Users/sergey/Projects/Crystal/crystal/src/int.cr` at
  `Int8.new!(value)` returned hover `def to_i8! : Int8`.
- `./build_lsp_debug.sh` rebuilt `bin/adamas_lsp` successfully.
- `scripts/run_safe.sh crystal 180 4096 spec
  spec/lsp/hover_definition_integration_spec.cr` -> 9 examples, 0 failures.
- `scripts/run_safe.sh crystal 300 4096 spec spec/lsp` -> 259 examples,
  0 failures.

Adversary notes:

- This is not a broad generated-method model. The synthetic fallback is
  limited to zero-argument `to_i*/to_u*` bang integer conversions.
- The text lookup boundary was tightened so searching for `to_i8` does not
  accidentally match `to_i8!`.
- LTP/WBA shape: trigger is a local member-call token with a bang/question
  suffix; transport carries the suffix and zero-arg boundary through the hover
  text corridor; the dual frame is a narrow synthetic signature only when no
  source `def` exists.

Trust: {F/G/R: 0.87/0.43/0.90} [verified]

### LM-641 - LSP text navigation covers macro constants and generated primitive anchors

The LSP server now has a lexical constant fast path for uppercase identifiers
that semantic analysis leaves unresolved in macro argument lists. Hover and
definition for `Float64` in `Number.expand_div [Float64], Float64` resolve
through the existing source-text constant locator, so hover shows
`struct Float64` and go-to-definition opens `float.cr`.

Generated numeric bang conversions also gained a real definition anchor:
`to_i8!` still hovers with the synthetic signature from LM-640, but definition
now routes to the primitive template line in `primitives.cr`:
`def {{name.id}}! : {{type}}`.

Evidence:

- Focused regression covers `Number.expand_div [Float64], Float64`: hover
  returns `struct Float64`, and definition points to `/float.cr`.
- Focused regression now also checks generated `to_i8!` definition points to
  `/primitives.cr`.
- Real LSP stdio harness against
  `/Users/sergey/Projects/Crystal/crystal/src/int.cr` returned
  `struct Float64` plus definition `/float.cr` for the macro argument, and
  `def to_i8! : Int8` plus definition `/primitives.cr` for `value.to_i8!`.
- `./build_lsp_debug.sh` rebuilt `bin/adamas_lsp` successfully.
- `scripts/run_safe.sh crystal 180 4096 spec
  spec/lsp/hover_definition_integration_spec.cr` -> 10 examples, 0 failures.
- `scripts/run_safe.sh crystal 300 4096 spec spec/lsp` -> 260 examples,
  0 failures.

Adversary notes:

- This does not make all macro-generated methods navigable. The generated
  method anchor is limited to the already-synthesized integer conversion bang
  family and points at the real template, not a fabricated file location.
- The constant path reuses the bounded text locator and avoids dependency graph
  loading on hover.
- LTP/WBA shape: trigger is an uppercase identifier or generated conversion
  suffix in a shallow request window; transport carries the name to an existing
  source-text locator/template anchor; potential decreases from unresolved
  request to stable source anchor without invalidating semantic fallback.

Trust: {F/G/R: 0.88/0.44/0.90} [verified]

### LM-642 - LSP navigates no-parentheses macro member calls

The previous macro-argument fix covered constants inside
`Number.expand_div [Float64], Float64`, but not the `expand_div` call itself.
The missing shape was a no-parentheses member call with an uppercase receiver:
the fast member scanner only accepted lowercase local receivers, and the text
method index only recognized `def`, not `macro`.

The LSP now accepts constant receivers for member-call text lookup, parses
bounded no-parentheses argument lists such as `[Float64], Float64`, resolves the
receiver source through the existing constant locator, and indexes `macro`
declarations alongside `def` declarations for hover and definition.

Evidence:

- Focused regression now checks `expand_div` itself in
  `Number.expand_div [Float64], Float64`: hover returns
  `macro expand_div(rhs_types, result_type)`, and definition points to
  `/number.cr`.
- `scripts/run_safe.sh crystal 180 4096 spec
  spec/lsp/hover_definition_integration_spec.cr` -> 10 examples, 0 failures.
- `./build_lsp_debug.sh` rebuilt `bin/adamas_lsp` successfully.
- Real LSP stdio harness against
  `/Users/sergey/Projects/Crystal/crystal/src/int.cr` line 958 returned
  `macro expand_div(rhs_types, result_type)` and definition
  `/Users/sergey/Projects/Crystal/crystal/src/number.cr`.

Adversary notes:

- The no-parentheses parser is not an arbitrary depth cap: it tracks nested
  `()`, `[]`, and `{}` while scanning to the line boundary.
- The parser only activates after a plausible argument-start token, so member
  hovers after operators do not become broad one-argument guesses.
- LTP/WBA shape: trigger is a constant receiver plus lower-case member in a
  shallow hover/definition window; transport carries the receiver to the
  constant source file and the member name to a `def`/`macro` index; potential
  decreases from unresolved request to source anchor while semantic fallback
  remains intact.

Trust: {F/G/R: 0.88/0.45/0.90} [verified]

### LM-643 - LSP recognizes ternary bang conversions and wrapping operators

The LSP hover fast path now covers two additional shallow stdlib forms from
`Int#abs_unsigned`: unqualified generated bang conversions after a ternary
colon, and wrapping binary primitive operators such as `&-`.

Root causes:

- Unqualified bang conversion calls rejected any preceding `:`, so the
  `to_u8!` branch in `self < 0 ? 0_u8 &- self : to_u8!` never reached the
  synthetic primitive-conversion fallback.
- `&-` is an operator token, not an identifier, so the identifier-based method
  scanner could only fall through to semantic `Unknown`.

Evidence:

- Focused regression covers `0_u8 &- self : to_u8!`: `&-` hovers as
  `def &-(other) : self` and definition points to `/primitives.cr`; `to_u8!`
  hovers as `def to_u8! : UInt8` and definition also points to
  `/primitives.cr`.
- `scripts/run_safe.sh crystal 180 4096 spec
  spec/lsp/hover_definition_integration_spec.cr` -> 11 examples, 0 failures.
- `./build_lsp_debug.sh` rebuilt `bin/adamas_lsp` successfully.
- Real LSP stdio harness against
  `/Users/sergey/Projects/Crystal/crystal/src/int.cr` line 1032 returned both
  hovers and both primitive-template definitions.

Adversary notes:

- The ternary-colon fix only relaxes a single `:` before unqualified method
  names; `::` still blocks the unqualified-call path.
- Operator recognition is intentionally narrow to wrapping binary primitive
  operators `&+`, `&-`, and `&*`, with a plausible RHS requirement.
- LTP/WBA shape: trigger is a local ternary branch or operator token hover
  window; transport maps the shallow token to the already-certified primitive
  template; potential decreases from `Unknown` to stable primitive anchor
  without changing semantic fallback.

Trust: {F/G/R: 0.88/0.43/0.90} [verified]

### LM-644 - LSP constant receiver lookup handles lib fun declarations

Hover and definition for calls such as `LibIntrinsics.popcount8(src)` now
select the `lib` function declaration instead of falling back to the wrapper
method with the same name.

Root cause:

- The source-text constant locator did not recognize `lib LibIntrinsics`, so
  the uppercase receiver-specific lookup could not derive the receiver source
  file.
- The text method index recognized `def` and `macro`, but not `fun`, so even a
  receiver-directed scan could not return the lib declaration.

Evidence:

- Focused regression covers a wrapper method calling
  `LibIntrinsics.popcount8(src)`: hover returns
  `fun popcount8 = "llvm.ctpop.i8"(src : Int8) : Int8`, and definition points
  to the `fun` line.
- `scripts/run_safe.sh crystal 180 4096 spec
  spec/lsp/hover_definition_integration_spec.cr` -> 12 examples, 0 failures.
- `./build_lsp_debug.sh` rebuilt `bin/adamas_lsp` successfully.
- Real LSP stdio harness against
  `/Users/sergey/Projects/Crystal/crystal/src/intrinsics.cr` line 251 returned
  the `LibIntrinsics` `fun` signature and definition at line 92.

Adversary notes:

- This does not replace semantic lib binding support. It extends the existing
  source-text hover/definition path to recognize `lib` constants and `fun`
  declarations when the receiver is explicit.
- Wrapper declarations still use the declaration fast path when hovering their
  own `def self.popcount8` header.
- LTP/WBA shape: trigger is an uppercase receiver whose declaration kind is
  `lib`; transport carries the receiver to its source file and the callee name
  to a `fun` index; potential decreases from wrong same-name wrapper match to
  receiver-local declaration without changing semantic fallback.

Trust: {F/G/R: 0.88/0.44/0.90} [verified]

### LM-645 - Wrapping operator definitions return source origin ranges

Wrapping primitive operators such as `&-` now return a `LocationLink` from the
definition fast path, including `originSelectionRange` over the exact operator
token. This preserves the existing primitive-template target while giving
editors an explicit source-side range for clickable decoration.

Evidence:

- Focused regression checks the `&-` definition response has `targetUri`
  `/primitives.cr` and `originSelectionRange` from the operator start to end.
- `scripts/run_safe.sh crystal 180 4096 spec
  spec/lsp/hover_definition_integration_spec.cr` -> 12 examples, 0 failures.
- `./build_lsp_debug.sh` rebuilt `bin/adamas_lsp` successfully.
- Real LSP stdio harness against
  `/Users/sergey/Projects/Crystal/crystal/src/int.cr` line 1032 returned a
  `LocationLink` whose origin range covers `&-` and whose target selection is
  the wrapping primitive template in `primitives.cr`.

Adversary notes:

- Only the operator fast path returns a `LocationLink`; identifier-shaped
  definitions still return the existing `Location[]` shape.
- This does not change semantic resolution or jump target. It adds the missing
  source range needed for operator-token UI decoration.
- LTP/WBA shape: trigger is a wrapping operator token with a valid primitive
  target; transport carries the source token byte range into an LSP
  `originSelectionRange`; potential decreases from navigable-but-undecorated
  operator to decorated source token without changing the target anchor.

Trust: {F/G/R: 0.87/0.37/0.89} [verified]

### LM-646 - AST operators emit semantic-token operator ranges

Ordinary AST-owned unary and binary operators now emit LSP semantic tokens with
token type `operator`. The server already advertised `operator` in the
semantic-token legend, but normal `BinaryNode` / `UnaryNode` traversal only
recursed into operands, so tokens such as `&-`, `&+`, and `&*` could hover and
navigate without receiving an operator-shaped token for editor decoration.

The semantic-token disk cache namespace was bumped from v2 to v3, and
disk-backed result ids now include that token-cache version. This prevents
unchanged large stdlib files such as `int.cr` from serving stale pre-LM-646
token JSON after the token-emission implementation changes.

Evidence:

- `logs/vscode_debug.log` showed `int.cr` semantic-token requests returning
  cached/delta-empty responses while the server code only emitted `operator`
  tokens for string interpolation punctuation, not normal AST operators.
- Focused semantic-token regression checks `0_u8 &- self`, `1 &+ 2`, and
  `3 &* 4` produce token type `operator` over the exact two-byte operator
  spans.
- `crystal tool format --check src/compiler/lsp/server.cr
  src/compiler/lsp/semantic_token_cache.cr spec/lsp/lsp_semantic_tokens_spec.cr`
  -> exit 0.
- `scripts/run_safe.sh crystal 180 4096 spec
  spec/lsp/lsp_semantic_tokens_spec.cr
  spec/lsp/semantic_token_disk_cache_spec.cr
  spec/lsp/hover_definition_integration_spec.cr` -> 45 examples, 0 failures.
- `scripts/run_safe.sh crystal 300 4096 spec spec/lsp` -> 263 examples,
  0 failures.
- `./build_lsp_debug.sh` rebuilt `bin/adamas_lsp` successfully.

Adversary notes:

- This is not a broad lexical operator-coloring patch. The token is emitted
  only after the parser has created a unary/binary AST node, so strings,
  comments, and unrelated punctuation are outside the move.
- Cache invalidation is part of the fix. Without the cache namespace bump,
  large unchanged stdlib files can keep stale semantic-token JSON even when the
  code path is fixed.
- LTP/WBA shape: trigger is an AST operator node with no emitted source token;
  transport carries the operator slice across the bounded span between operand
  spans; legal move emits one semantic-token range without changing hover or
  definition targets; potential decreases from navigable-but-tokenless operator
  to navigable operator with a decorated source range, while the disk-cache
  version bump collapses the stale-token boundary.

Trust: {F/G/R: 0.90/0.50/0.91} [verified]

### LM-647 - Qualified constant receiver signatures stay receiver-local

Fully qualified uppercase receiver calls now resolve hover and definition only
through the receiver's source file. The previous constant-member text fast path
could fail to locate nested stdlib receiver files such as
`crystal/system/time.cr`, then fall back to an unqualified method search. For
`Crystal::System::Time.instant` inside `time/instant.cr`, that fallback picked
the nearby wrapper `def Time.instant : Time::Instant` instead of the receiver
implementation `def self.instant`.

The namespace path search now adds direct nested stdlib candidates such as
`crystal/system/time.cr` and the containing namespace directory before broader
fallback paths. Constant-member hover uses `find_method_signature_in_path` only
after the receiver path is resolved, and constant-member definition no longer
falls back to unqualified method lookup when receiver resolution fails.

Evidence:

- `logs/vscode_debug.log` showed
  `Hover constant-member text fast path: Crystal::System::Time.instant` on
  `time/instant.cr`, while the UI displayed the wrapper signature
  `def Time.instant : Time::Instant`.
- Focused regression opens the real `../crystal/src/time/instant.cr`, hovers
  `Crystal::System::Time.instant`, asserts the hover contains
  `def self.instant` and not `def Time.instant`, and asserts definition points
  at `/crystal/system/time.cr`.
- `crystal tool format --check src/compiler/lsp/server.cr
  spec/lsp/hover_definition_integration_spec.cr` -> exit 0.
- `scripts/run_safe.sh crystal 180 4096 spec
  spec/lsp/hover_definition_integration_spec.cr` -> 13 examples, 0 failures.
- `scripts/run_safe.sh crystal 300 4096 spec spec/lsp` -> 264 examples,
  0 failures.
- `./build_lsp_debug.sh` rebuilt `bin/adamas_lsp` successfully.

Adversary notes:

- The fix deliberately removes a symptom-prone fallback for uppercase receiver
  calls. If the receiver cannot be resolved, returning no fast-path answer is
  safer than selecting an unrelated same-name method in the current file.
- Unqualified method calls still use the existing broad source-text search;
  this change only narrows receiver-qualified constant-member calls.
- LTP/WBA shape: trigger is a qualified uppercase receiver whose direct source
  file is missing from the candidate corridor; transport carries the namespace
  segments into a bounded stdlib path candidate; legal move keeps hover and
  definition inside the resolved receiver file; potential decreases from
  receiver-erased same-name fallback to receiver-local signature/target.

Trust: {F/G/R: 0.91/0.45/0.91} [verified]

### LM-648 - LSP preserves parameter signatures and operator word spans

Callable parameter hover now prefers the parameter's source signature instead
of collapsing typed parameters to the raw annotation. For the stdlib
`Comparable(T)#<` shape, hovering the body use of `other` now reports
`other : T` rather than only `T`.

Definition for local parameters now runs before the generic expression
definition path for non-member local identifiers. Parameter target ranges are
derived from source byte offsets instead of trusting `Span` line/column
metadata, because the operator-def parameter shape can have correct offsets
but stale columns. This keeps definition on the parameter name rather than the
enclosing operator method header.

The VS Code language configuration now defines a Crystal word pattern that
treats operator-shaped tokens such as `&-`, `<=>`, and `to_u8!` as single
editor words. This complements the existing server-side `LocationLink`
`originSelectionRange` and semantic-token operator ranges for clickable source
decoration.

Evidence:

- Focused regression covers a local `Comparable(T)#<` sample: hover on
  `self <=> other` contains `other : T`, and definition points at the
  parameter name range.
- `regression_tests/vscode_operator_word_pattern.sh` verifies the VS Code
  word pattern keeps `&-` and `<=>` as single tokens while preserving ordinary
  identifiers and bang method names.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/server.cr
  spec/lsp/hover_definition_integration_spec.cr` -> exit 0.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp/hover_definition_integration_spec.cr --error-trace` -> 14
  examples, 0 failures.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 265 examples, 0 failures.
- `scripts/run_safe.sh /bin/bash 30 512
  regression_tests/vscode_operator_word_pattern.sh` -> exit 0.
- `./build_lsp_debug.sh` rebuilt `bin/adamas_lsp` successfully.
- `git diff --check` -> exit 0.

Adversary notes:

- This is not a broad parser span rewrite. The legal move is local to LSP
  parameter navigation and uses existing source offsets, which are already the
  stable coordinate source for other LSP ranges.
- The parameter-first definition path is restricted to localish non-member
  identifiers, so member calls and constant/member navigation keep their
  existing method-resolution paths.
- The word-pattern change is client-side; it does not claim server resolution
  was missing for `&-`. Server logs already showed hover/definition hits for
  that operator, so the remaining issue was editor token decoration.
- LTP/WBA shape: trigger is a cursor on a local parameter or operator-shaped
  token; transport carries the exact source byte span into hover/definition or
  editor word selection; legal move does not mutate parser/semantic state; the
  potential decreases from resolved-but-misdecorated/misformatted token to
  exact source-span response.

Trust: {F/G/R: 0.90/0.48/0.91} [verified]

### LM-649 - LSP semantic type lookup resolves scoped aliases through alias heads

Opening DiamondDB's `src/diamond_foundation.cr` exposed a stack overflow in
semantic type inference while loading dependencies. The reduced root was a
lexical scoped-alias corridor:
`Plan = DiamondFoundation::Storage::ClusterBackupPlan`, followed by aliases
and annotations such as `Replica = Plan::Replica` and
`{Plan::Partition, Plan::PersistedBackup}`. `parse_type_name("Plan::Replica")`
could miss the lexical alias head, fall back to the `Replica` alias by leaf
name, and recurse through `type_from_symbol`.

Scoped type-symbol lookup now resolves the first segment through the current
lexical type scope and can transport through an alias head before continuing
the remaining path. `parse_type_name` also has an exact in-progress set so a
real alias cycle degrades to `Unknown` instead of overflowing the LSP process.

Evidence:

- Reduced semantic regression covers the DiamondDB alias shape and asserts
  concrete inferred names for `Replica`, `ReplicaState`, and
  `Tuple(Partition, PersistedBackup)`.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 2048 spec
  spec/semantic/type_inference_scoped_alias_spec.cr --error-trace` -> 1
  example, 0 failures.
- Real LSP harness against
  `/Users/sergey/Projects/Crystal/DiamondDB/src/diamond_foundation.cr` after
  rebuilding `bin/adamas_lsp` -> `didOpen` settled in about 1478.8ms,
  loaded 63 requires, published 0 diagnostics, and exited 0.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/semantic/type_inference_scoped_alias_spec.cr
  spec/lsp/hover_definition_integration_spec.cr --error-trace` -> 15 examples,
  0 failures.
- `git diff --check` -> exit 0.

Adversary notes:

- This is not a depth cap. The guard is keyed to the exact active type-name
  window, and the semantic fix resolves the alias-head path rather than merely
  bailing out.
- Alias transport only happens for non-final path segments. Final aliases keep
  the existing alias-symbol flow and parse their target normally.
- The DiamondDB harness is an external-workspace smoke, not a repository unit
  test dependency; the checked-in regression keeps the minimized shape local.
- LTP/WBA shape: trigger is a scoped type name whose first segment is a
  lexical alias; transport carries the alias target's symbol scope across the
  remaining `::` path; legal move preserves symbol tables and caches; potential
  decreases from repeated `(type_name, alias)` recursion to a resolved member
  symbol, with the in-progress set as the dual frame for true alias cycles.

Trust: {F/G/R: 0.91/0.50/0.91} [verified]

## LM-583 — LSP foreground hover avoids workspace reference scans by default

Status: verified for the focused LSP hover/cache/harness slice on `codegen`.

Change:

- `ServerConfig` now exposes `hover_reference_count`, loaded from
  `LSP_HOVER_REFERENCE_COUNT=1` or `hover_reference_count` in the LSP config.
- `textDocument/hover` no longer calls `find_all_references` on the default
  foreground path. The old reference-count display remains available by
  opting in.
- The benchmark harness can write a machine-readable JSON report with action
  timings, p50/p95/max, notification counts, and diagnostics.
- Two stale LSP cache/merge compile frontiers were fixed while building the
  LSP server: included-module merging now preserves `IncludedModuleRef`
  metadata, and cached class-variable symbols use the current named
  `file_path:` constructor.

WBA framing:

- Window/trigger: hover on a resolved non-method symbol was performing an
  O(open-doc identifiers) reference scan before responding.
- Transport corridor: request-time hover resolution should transport only the
  current document snapshot and already-available semantic/cache facts.
- Boundary: explicit references remain a separate LSP request; hover must not
  silently expand into workspace reference work unless configured.
- Legal move: gate the reference-count adornment behind an explicit config bit
  without changing `textDocument/references`.
- Potential decrease: foreground hover work loses the workspace-reference scan
  component while preserving opt-in behavior.

Evidence:

- `crystal build src/lsp_main.cr -o bin/adamas_lsp --error-trace`
- Harness compile/help guard through safe runner:
  `crystal build benchmarks/lsp_harness.cr -o <tmp> --error-trace` then
  `scripts/run_safe.sh <tmp> 10 512 --help`
- Focused LSP spec binary through safe runner:
  `crystal build spec/lsp/hover_definition_integration_spec.cr
  spec/lsp/hover_definition_indexing_spec.cr
  spec/lsp/references_integration_spec.cr
  spec/lsp/ast_cache_dependency_integration_spec.cr -o <tmp> --error-trace`
  then `scripts/run_safe.sh <tmp> 60 1024 --no-color`: 5 examples, 0 failures.
- `crystal tool format --check src/compiler/lsp/server.cr
  src/compiler/lsp/unified_project.cr src/compiler/lsp/prelude_cache.cr
  benchmarks/lsp_harness.cr spec/lsp/hover_definition_integration_spec.cr`
- `git diff --check`

Known limits:

- The full `spec/lsp/*_spec.cr` safe-run currently fails in existing
  semantic-token/inlay-position specs (9 failures out of 212 examples). This
  slice does not claim those surfaces are repaired.
- Live process-level latency measurement still needs an LSP-safe monitor or a
  harness-level resource guard, because `scripts/run_safe.sh` captures stdout
  and therefore corrupts a stdio JSON-RPC server protocol if wrapped around
  `bin/adamas_lsp`.

Trust: {F/G/R: 0.82/0.34/0.86} [verified]

## LM-584 — LSP stdio server can be benchmarked under run_safe

Status: verified for LSP harness measurement safety on `codegen`.

Change:

- `scripts/run_safe.sh` now supports `RUN_SAFE_PASSTHROUGH_STDIO=1` for stdio
  protocol servers. In this mode the wrapped child keeps stdin/stdout, while
  `run_safe` diagnostics and captured child stderr go to stderr.
- Normal capture mode remains unchanged for ordinary binaries.
- `benchmarks/lsp_harness.cr` now persists notification counters correctly;
  `NotificationStats` is a struct, so mutating the local copy must be written
  back to the hash.

WBA framing:

- Window/trigger: LSP benchmarking needed to run `bin/adamas_lsp` through
  `run_safe`, but normal `run_safe` captured stdout and corrupted JSON-RPC
  framing.
- Transport corridor: JSON-RPC stdio must stay byte-exact between harness and
  server while FD/RSS/timeout monitoring remains active around the server
  process.
- Boundary: existing non-protocol test binaries must keep the old captured
  stdout/stderr output contract.
- Legal move: env-gated pass-through mode only; wrapper diagnostics move to
  stderr in that mode.
- Potential decrease: removes the measurement blocker without weakening the
  produced-binary safety rule.

Evidence:

- `/bin/bash -n scripts/run_safe.sh`
- Normal mode smoke:
  `scripts/run_safe.sh /bin/echo 5 64 hello-normal-2`
- Pass-through stdin/stdout smoke:
  `printf 'cat-passthrough\n' | RUN_SAFE_PASSTHROUGH_STDIO=1
  scripts/run_safe.sh /bin/cat 5 64`
- Safe LSP harness run:
  `scripts/run_safe.sh <compiled_lsp_harness> 120 1024
  --server="/usr/bin/env RUN_SAFE_PASSTHROUGH_STDIO=1 scripts/run_safe.sh
  ./bin/adamas_lsp 90 2048" --scenario=<small server.cr scenario>
  --json=<report> --timeout=20 --verbose`, exited 0.
- The sample JSON report had `errors=0`, notification counts of 1 for
  `crystal/indexing`, `crystal/indexed`, and `textDocument/publishDiagnostics`,
  and representative timings: initialize ~118ms, document symbols ~255ms,
  semantic tokens ~307ms, hover ~24ms, shutdown ~15ms.
- `crystal tool format --check benchmarks/lsp_harness.cr`
- `git diff --check`

Trust: {F/G/R: 0.83/0.42/0.88} [verified]

## LM-585 — LSP document symbols use AST snapshots and harness request filtering

Status: verified for focused LSP document-symbol correctness and harness
measurement on `codegen`.

Change:

- `DocumentState` now carries AST-derived document symbols built when a
  document or dependency snapshot is parsed. `textDocument/documentSymbol`
  serves that snapshot before falling back to the older semantic-symbol-table
  path.
- The AST document-symbol path covers modules, classes/structs, unions, enums
  with enum members, defs, macro defs, libs, funs, aliases, constants,
  annotation definitions, and accessor declarations without requiring semantic
  symbol tables.
- The LSP harness now treats inbound messages with both `method` and `id` as
  server-initiated JSON-RPC requests, responds with `null`, and keeps waiting
  for the client request id. This prevents server request ids such as
  `workspace/semanticTokens/refresh` from being mistaken for benchmarked
  client responses.
- Harness timings now include a `didOpen settled` row after diagnostics arrive,
  and document-symbol summaries report recursive symbol count plus payload
  bytes instead of only top-level symbol count.
- The harness clears per-URI diagnostics before `didOpen`, waits for a matching
  or newer diagnostics version, and stashes non-integer JSON-RPC response ids by
  serialized id instead of dropping them as notifications.

WBA framing:

- Window/trigger: `textDocument/documentSymbol` returned an empty result when
  the semantic symbol table did not contain the expected shape, and the harness
  could misclassify server-initiated requests as benchmark responses.
- Transport corridor: parse-time AST structure is transported with the
  immutable document snapshot; request-time documentSymbol should only serialize
  the cached structural outline.
- Boundary: hover, references, semantic tokens, and dependency warmup keep their
  existing state boundaries; server-initiated JSON-RPC requests are answered by
  the harness without stealing client response ids.
- Legal move: cache only AST structural symbols on the document snapshot and
  preserve the semantic fallback for documents without an AST outline.
- Potential decrease: removes the empty-document-symbol bad corner and reduces
  request-time work to cached outline serialization.

Evidence:

- `crystal tool format --check src/compiler/lsp/server.cr
  spec/lsp/support/server_helper.cr
  spec/lsp/hover_definition_integration_spec.cr benchmarks/lsp_harness.cr`
- `git diff --check`
- `crystal build src/lsp_main.cr -o bin/adamas_lsp --error-trace`
- Focused LSP spec binary through safe runner:
  `crystal build spec/lsp/hover_definition_integration_spec.cr
  spec/lsp/hover_definition_indexing_spec.cr
  spec/lsp/references_integration_spec.cr
  spec/lsp/ast_cache_dependency_integration_spec.cr -o <tmp> --error-trace`
  then `scripts/run_safe.sh <tmp> 60 1024 --no-color`: 6 examples, 0 failures.
- Safe wrapped harness on `src/compiler/lsp/server.cr` exited 0 with
  `errors=0`, `document symbols` reporting 500 recursive symbols, 1 top-level
  symbol, and 104963 response bytes; representative documentSymbol timing was
  ~268ms.
- Safe wrapped harness on a small temp Crystal file exited 0 with
  `errors=0`, `document symbols` reporting 5 recursive symbols, 1 top-level
  symbol, 943 response bytes, and ~0.4ms documentSymbol timing.

Known limits:

- This slice fixes correctness and measurement for document symbols; it does
  not claim large-file documentSymbol is sub-100ms. The current evidence points
  to payload serialization/parsing size as the next bottleneck.
- The old full-suite semantic-token/inlay-position failures are closed by
  LM-586.

Trust: {F/G/R: 0.84/0.42/0.88} [verified]

## LM-586 — LSP positions derive from byte offsets for inlay and semantic tokens

Status: verified for the full LSP spec suite on `codegen`.

Change:

- LSP inlay hint positions now derive from `Span#start_offset` /
  `Span#end_offset` plus document line offsets, instead of trusting
  `Span#*_column` as an exclusive cursor.
- Semantic token emission now uses offset-derived positions for identifiers,
  member names, literals, lexical keywords/strings/symbols, parameter spans,
  accessors, ivars/class vars/globals, and constants.
- Member-access token placement now searches for the member name in the source
  corridor after the receiver byte span, so `foo.bar` and `obj.calculate` no
  longer depend on receiver `end_column` semantics.
- The inlay position spec now asserts the offset-based conversion invariant
  directly, matching the production path.

WBA framing:

- Window/trigger: the full LSP suite had 9 failures: one inlay position test
  and eight semantic-token gaps for parameters, member/nested identifiers,
  strings, symbols, and elsif/control-flow coverage.
- Transport corridor: parser byte offsets are the stable document-coordinate
  carrier; `*_column` values are still useful for diagnostics but are not a
  safe exclusive-end transport for LSP foreground features.
- Boundary: parser span representation is unchanged; the legal move is local
  to LSP coordinate conversion and token emission.
- Potential decrease: removes a whole class of off-by-one/missing-token cases
  without adding per-token special-case patches.

Evidence:

- `crystal tool format --check src/compiler/lsp/server.cr
  spec/lsp/lsp_inlay_hint_spec.cr`
- `git diff --check`
- `crystal build src/lsp_main.cr -o bin/adamas_lsp --error-trace`
- Focused failing pack through safe runner:
  `crystal build spec/lsp/lsp_inlay_hint_spec.cr
  spec/lsp/lsp_semantic_tokens_spec.cr
  spec/lsp/semantic_tokens_integration_spec.cr
  spec/lsp/semantic_tokens_spec.cr -o <tmp> --error-trace` then
  `scripts/run_safe.sh <tmp> 120 1536 --no-color`: 54 examples, 0 failures.
- Full LSP suite through safe runner:
  `crystal build spec/lsp/*_spec.cr -o <tmp> --error-trace` then
  `scripts/run_safe.sh <tmp> 120 1536 --no-color`: 213 examples, 0 failures.
- Safe wrapped harness on `src/compiler/lsp/server.cr` exited 0 with
  `errors=0`, `semantic tokens` reporting 135750 ints, representative
  semanticTokens timing ~392ms, and hover timing ~30ms.

Known limits:

- Correctness is closed for the current LSP spec gate. Large-file semantic
  token payloads are now more complete and larger; payload-size optimization is
  a separate follow-up, not part of this fix.

Trust: {F/G/R: 0.88/0.48/0.90} [verified]

## LM-587 — LSP semantic-token cache stores serialized responses

Status: verified for repeated full semantic-token requests on `codegen`.

Change:

- The per-document semantic-token cache now stores the serialized JSON result
  for the matching document version, not only the `SemanticTokens` integer
  array.
- Cache hits now send the cached JSON result directly and avoid reserializing
  large token arrays on every repeated `textDocument/semanticTokens/full`
  request.

WBA framing:

- Window/trigger: after LM-586 made semantic-token output complete, large files
  returned much larger token arrays. On `src/compiler/lsp/server.cr`, a cached
  repeat request still took ~127ms because the server reserialized 135750 token
  integers from the cached array.
- Transport corridor: versioned document snapshots already define the cache
  boundary; the legal transport is the exact serialized semantic-token result
  for that version.
- Boundary: cache invalidation remains tied to `didOpen`/`didChange`; token
  collection semantics are unchanged.
- Potential decrease: repeat full-token requests skip the serialization pass
  and reuse the version-certified response body.

Evidence:

- `crystal tool format --check src/compiler/lsp/server.cr`
- `crystal build src/lsp_main.cr -o bin/adamas_lsp --error-trace`
- Repeated safe wrapped harness on `src/compiler/lsp/server.cr` exited 0 with
  `errors=0`; representative timings were first semanticTokens ~455ms and
  cached semanticTokens ~79ms for the same 135750-int payload.
- Full LSP suite through safe runner:
  `crystal build spec/lsp/*_spec.cr -o <tmp> --error-trace` then
  `scripts/run_safe.sh <tmp> 120 1536 --no-color`: 213 examples, 0 failures.

Known limits:

- The client/harness still has to receive and parse the large JSON payload, so
  this does not make huge full-token responses free. Further reductions require
  payload-size work, range/delta support, or token-count reduction.

Trust: {F/G/R: 0.84/0.48/0.88} [verified]

## LM-588 — LSP supports semantic-token range requests

Status: verified for semantic-token range correctness and LSP suite stability on
`codegen`.

Change:

- The server now advertises `"semanticTokensProvider": {"range": true,
  "full": true}` and dispatches `textDocument/semanticTokens/range`.
- Range requests reuse the existing semantic-token collector with a visible
  `Range`; AST traversal skips nodes whose spans do not overlap the requested
  line band, final raw tokens are filtered to the visible window, and the
  lexical pass lexes only the covered line band instead of the whole file.
- The benchmark harness advertises range semantic-token support and summarizes
  `textDocument/semanticTokens/range` responses.

WBA framing:

- Window/trigger: after LM-586/LM-587, full semantic-token responses for
  `src/compiler/lsp/server.cr` were correct but large: ~135k-138k encoded
  integers. Even serialized-cache hits still paid large payload transfer and
  client parse costs.
- Transport corridor: visible viewport line ranges are a certified smaller
  corridor for token transport; the full-document cache remains the fallback
  frame for clients that request full tokens.
- Boundary: full-token behavior and cache invalidation remain unchanged.
  Range requests do not reuse the full cache because their result depends on
  the requested window.
- Potential decrease: visible-window requests reduce payload area from the
  whole document to the requested line band while preserving exact token
  encoding for that range.

Evidence:

- `crystal tool format --check src/compiler/lsp/server.cr
  src/compiler/lsp/messages.cr benchmarks/lsp_harness.cr
  spec/lsp/semantic_tokens_spec.cr`
- `git diff --check`
- `crystal build src/lsp_main.cr -o bin/adamas_lsp --error-trace`
- Focused semantic-token spec pack through safe runner:
  `crystal build spec/lsp/semantic_tokens_spec.cr
  spec/lsp/semantic_tokens_integration_spec.cr
  spec/lsp/lsp_semantic_tokens_spec.cr -o <tmp> --error-trace` then
  `scripts/run_safe.sh <tmp> 120 1536 --no-color`: 35 examples, 0 failures.
- Full LSP suite through safe runner:
  `crystal build spec/lsp/*_spec.cr -o <tmp> --error-trace` then
  `scripts/run_safe.sh <tmp> 120 1536 --no-color`: 215 examples, 0 failures.
- Direct in-process collection on `src/compiler/lsp/server.cr` measured full
  semantic tokens at ~75ms for 138190 ints and a representative range at ~4ms
  for 745 ints.
- Safe wrapped harness on `src/compiler/lsp/server.cr` measured a repeated
  visible-range request at ~13ms with a 630-int payload. The first range request
  after `didOpen settled` was ~226ms, indicating remaining post-open queue or
  warmup effects outside the range collector itself.

Known limits:

- This adds a small visible-window path; it does not reduce full-document token
  payload size. Clients that request only `semanticTokens/full` still receive
  large payloads.
- The first foreground request after opening a large document can still be
  delayed by startup/background work. That is a separate scheduling/frontier
  issue.

Trust: {F/G/R: 0.86/0.50/0.90} [verified]

### LM-580 — s2 registration hardening: parsed number macro values, alias suffix index, and tuple-key avoidance

Status: verified for s1 -> s2 build and focused no-prelude guards on branch
`codegen`.

Verified outcome:

- Host compiler builds successfully.
- Produced `s2` builds successfully from the patched host. The known non-fatal
  `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer arithmetic
  overflow diagnostic remains.
- Produced `s2` passes the focused no-prelude guards:
  `p2_macro_number_parsed_literals_no_prelude.sh`,
  `p2_normalize_decl_cache_key_no_prelude.sh`,
  `p2_short_type_index_first_no_prelude.sh`,
  `p2_source_span_slice_bounds_no_prelude.sh`,
  `p2_constant_globals_no_prelude.sh`, and
  `p2_qualified_module_namespace_no_prelude.sh`.
- Full-prelude produced `puts 42` still fails, but the current sampled frontier
  is no longer the old constant pre-scan FastFloat stall, the
  `resolve_alias_in_module_path` suffix-scan `memcmp` crash, or the
  `normalize_declared_type_name` tuple-key equality crash. The latest
  full-prelude smoke reached class registration and exited 139 after
  `class register idx=51/112`.

Root-boundary fixes:

- `macro_value_for_expr(NumberNode)` now uses `NumberNode` parse-time numeric
  fields instead of reparsing literal byte slices through generated
  `String#to_f64?`. This keeps macro constant evaluation on the same parsed
  numeric corridor as `lower_number`.
- Unary macro folding preserves the legal `Int64::MIN` boundary instead of
  overflowing by negating the already-represented minimum value.
- `resolve_alias_in_module_path` now checks exact module hits and uses a
  registration-time module suffix index instead of walking every
  `@module_defs` key with `String#ends_with?`.
- `@normalize_decl_cache` now uses string keys rather than tuple keys. Produced
  `s2` was observed to miscompile tuple-key equality for both
  `{String, String?, UInt64}` and `{String, String, UInt64}` in this hot cache.
- `fast_resolve_type_name_for_signature` now avoids direct `Set(String)#first`
  and uses a guarded helper, matching the existing `safe_set_includes?` pattern.

Refuted/limited evidence:

- Replacing `Pointer(UInt8)#memcmp` with a byte-loop only moved the crash into
  the same bad pointer read; it was diagnostic, not a root fix.
- Starting HIR hash iteration from `@first` did not fix the frontier and was
  reverted.
- A no-prelude guard that emitted LLVM IR for float globals exposed the existing
  `Float::Printer::CachedPowers::Power#index` stub path, so the parsed-number
  guard intentionally stops before codegen.

Evidence:

- `crystal build src/adamas.cr -o /private/tmp/cv2_setfirst_host
  --error-trace`
- Host guards:
  `p2_short_type_index_first_no_prelude.sh`,
  `p2_macro_number_parsed_literals_no_prelude.sh`,
  `p2_normalize_decl_cache_key_no_prelude.sh`,
  `p2_source_span_slice_bounds_no_prelude.sh`,
  `p2_constant_globals_no_prelude.sh`, and
  `p2_qualified_module_namespace_no_prelude.sh` on
  `/private/tmp/cv2_setfirst_host`.
- Produced `s2` build:
  `scripts/run_safe.sh /private/tmp/cv2_setfirst_host 300 4096
  src/adamas.cr -o /private/tmp/cv2_setfirst_s2/cv2_s2`, exited 0 after
  ~154s.
- Produced guards:
  the same six no-prelude guards on `/private/tmp/cv2_setfirst_s2/cv2_s2`.
- Full-prelude smoke sample:
  `scripts/run_safe.sh /private/tmp/cv2_final_s2/cv2_s2 120 4096
  /private/tmp/cv2_final_hello.cr -o /private/tmp/cv2_final_hello_bin`
  exited 139 after `class register idx=51/112`.

Trust: {F/G/R: 0.88/0.50/0.89} [verified]

## LM-581 — Stage2 registration avoids Hash(Bool) and optional-map join frontiers

Context: compiler/bootstrap/HIR registration boundaries, 2026-05-20,
`codegen`.

Verified outcome:

- Produced `s2` builds cleanly after removing the registration-local
  `@type_param_like_cache : Hash(String, Bool)` and after replacing optional
  type-param map joins with `complete_type_param_mapping`.
- Produced `s2` passes new no-prelude guards for the two observed crash
  families:
  `p2_type_param_like_cacheless_no_prelude.sh` and
  `p2_optional_type_param_join_no_prelude.sh`.
- The earlier `Hash(String, Bool)#key_hash` lldb frontier in
  `AstToHir#type_param_like?` is no longer the observed produced-stage2
  frontier under the tested guards.
- The later `Array(String?)#join -> Pointer(Void)#to_s ->
  __vdispatch__Object#to_s` lldb frontier from optional generic type-param
  lookups is also no longer observed after the helper change.

WBA framing:

- Window/trigger: full-prelude produced `puts 42` reached HIR registration and
  failed in generated-stage2 container/string code while resolving generic and
  type-param metadata.
- Transport corridor: frontend annotation/source strings and type-param maps
  enter HIR registration caches before the produced compiler's generic
  container lowering is robust enough for all high-level Crystal idioms.
- Boundary: remove only non-essential self-host-critical container surfaces and
  keep semantic type checks unchanged.
- Legal moves: avoid the `Hash(String, Bool)` cache in `type_param_like?`, and
  materialize an `Array(String)` only after every optional map lookup succeeds.
- Potential decrease: does not add depth caps, does not modify stdlib, and
  does not suppress generic/template registration; it reduces two proven
  container/lifetime hazards on the registration path.

Evidence:

- `crystal tool format --check src/compiler/hir/ast_to_hir.cr`
- `crystal build src/adamas.cr -o /private/tmp/cv2_typecache_host
  --error-trace`
- Host guards:
  `p2_type_param_like_cacheless_no_prelude.sh`,
  `p2_optional_type_param_join_no_prelude.sh`, and
  `p2_unbound_type_param_scan_no_regex_no_prelude.sh` on
  `/private/tmp/cv2_typecache_host`.
- Produced `s2` build:
  `scripts/run_safe.sh /private/tmp/cv2_typecache_host 300 4096
  src/adamas.cr -o /private/tmp/cv2_typecache_s2/cv2_s2`, exited 0 after
  ~145s on the final run.
- Produced guards:
  `p2_type_param_like_cacheless_no_prelude.sh` and
  `p2_optional_type_param_join_no_prelude.sh` on
  `/private/tmp/cv2_typecache_s2/cv2_s2`.
- Produced full-prelude smoke remains open:
  `scripts/run_safe.sh /private/tmp/cv2_typecache_s2/cv2_s2 120 4096
  /private/tmp/cv2_typecache_hello.cr -o /private/tmp/cv2_typecache_hello_bin`
  exited 139.

Refuted/limited evidence:

- `ADAMAS_TRACE_CLASS_FRONTIER=1` materially perturbs this frontier. A
  traced safe-wrapper run reached `lower_main` before exit 139, while an
  untraced lldb run stopped in `type_ref_for_name_inner` from
  `annotation_type_ref` during class registration. Treat trace-only progress as
  localization evidence, not proof that class registration is clean in the
  normal run.
- A traced lldb run stopped in `String#byte_slice` via
  `slice_source_for_span -> constant_literal_value_from_source`, which points
  at a remaining source-span/string-lifetime class of failures but is not part
  of this committed fix.

Boundary:

- This is a moved-frontier/root-boundary hardening, not a clean full-prelude
  smoke. The next target is the remaining produced-stage2 full-prelude `puts
  42` exit 139, likely around type-ref/source-span/string lifetime instability
  exposed by HIR registration/lower-main.
- The non-fatal `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer
  arithmetic-overflow diagnostic remains during produced `s2` builds.

Trust: {F/G/R: 0.88/0.48/0.89} [verified]

## LM-582 — No-block included-module lookup rejects block overloads

Context: compiler/bootstrap/HIR method lookup and source-string transport,
2026-05-20, `codegen`.

Verified outcome:

- Host HIR for the focused iterator reducer no longer lowers no-block
  `Array(String)#each` and `Array(String)#each_index` through the block/yield
  overloads.
- The old host HIR emitted `Nil#next`, `Nil#each`, and `Pointer#next` after
  `items = a.each`. The patched host HIR emits
  `Indexable(T)::ItemIterator(Array(String), String)#next` and
  `Indexable(T)::IndexIterator(Array(String))#next`.
- Included-module return lookup and simple included-module materialization now
  ask `find_module_def_recursive(..., expects_block: false)` for no-suffix
  instance methods instead of accepting the first arity-compatible block
  overload.
- Source-span transport was hardened by preferring file-backed arena source
  text for constant literal slicing and rejecting unreadable source/name
  strings at the relevant lookup/slicing boundaries.

WBA framing:

- Window/trigger: a small full-prelude reducer using `a.each`,
  `items.next`, `items.each`, and `a.each_index` exposed a host-semantic
  lowering error before the produced-stage2 crash.
- Transport corridor: no-block collection calls enter included generic module
  lookup through `Array(T) -> Indexable(T)`, where block and no-block overloads
  share method names and zero positional parameters.
- Boundary: overload choice must carry the block/no-block bit; return/type
  lookup helpers must not dereference stage2-invalid strings.
- Legal moves: reuse the existing block-aware module lookup with
  `expects_block=false` and keep the generated target under the concrete
  receiver owner.
- Potential decrease: removes a real semantic poison source without depth
  caps, stdlib changes, or broad block/proc rebasing.

Evidence:

- `crystal tool format --check src/compiler/hir/ast_to_hir.cr`
- `crystal build src/adamas.cr -o /private/tmp/cv2_return_guard_host
  --error-trace`
- Host guards on `/private/tmp/cv2_return_guard_host`:
  `p2_nested_generic_new_inference.sh`,
  `p2_source_span_slice_bounds_no_prelude.sh`,
  `p2_type_param_like_cacheless_no_prelude.sh`, and
  `p2_qualified_module_namespace_no_prelude.sh`.
- Produced `s2` build:
  `scripts/run_safe.sh /private/tmp/cv2_return_guard_host 300 4096
  src/adamas.cr -o /private/tmp/cv2_return_guard_s2/cv2_s2`, exited 0
  after ~150s.
- Produced cheap guards on `/private/tmp/cv2_return_guard_s2/cv2_s2`:
  `p2_source_span_slice_bounds_no_prelude.sh`,
  `p2_type_param_like_cacheless_no_prelude.sh`, and
  `p2_qualified_module_namespace_no_prelude.sh`.
- Produced full-prelude `puts 42` with
  `/private/tmp/cv2_return_guard_s2/cv2_s2` reached `lower_main: exprs=16`
  and timed out under a 60s safe wrapper instead of the previous immediate
  exit-139 class/register crash.

Refuted/limited evidence:

- The produced `s2` full-prelude nested-generic regression still exits 139,
  now during module registration around idx 3/114. This commit does not close
  the full-prelude iterator gate on produced `s2`.
- Adding readability guards directly to
  `normalize_compiler_collection_owner_name`, `normalize_method_owner_name`,
  and `normalize_compiler_collection_method_name` fixed a no-prelude produced
  reducer but regressed full-prelude `puts 42` back to early module
  registration exit 139. That branch was reverted.
- A broad overload-key readability filter in `lookup_function_def_for_call`
  regressed the focused reducer to enum registration and was reverted.

Boundary:

- This is a host semantic fix plus stage2 source/name transport hardening, not
  a clean `s1 -> s2b` gate. The next root remains produced-stage2 full-prelude
  module/lower-main string lifetime or source provenance instability.
- The non-fatal `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer
  arithmetic-overflow diagnostic remains during produced `s2` builds.

Trust: {F/G/R: 0.88/0.52/0.87} [verified]

## LM-576 — Unbound type-param scans avoid Regex match-data in self-hosted registration

Context: compiler/bootstrap/HIR method annotation scan, 2026-05-19, `codegen`.

Verified outcome:

- Produced `s2` no longer crashes when class registration checks
  include-derived method annotations such as `Array(T)` for unbound type
  parameters.
- The old produced crash was:
  `Regex::MatchData#byte_end -> unbound_type_params_from_type_name ->
  def_has_unbound_type_params? -> register_module_instance_methods_for ->
  register_concrete_class`.
- The root was `unbound_type_params_from_type_name` using
  `type_name.scan(/[A-Z][A-Za-z0-9_]*/)`. Produced `s2` can crash in the Regex
  match-data path while this registration helper scans type annotation text.
- The fix replaces the Regex scan with a direct byte tokenizer for capitalized
  identifier tokens, reusing the existing `ident_char?` predicate and matching
  the local bootstrap pattern of avoiding Regex in hot self-hosted paths.

Evidence:

- At `b1e2423f`, produced `s2` exits 139 on a no-prelude reducer:
  `module N; def foo(x : Array(T)) : Nil; end; end; class C; include N; end`.
- lldb on that reducer shows
  `Regex::MatchData#byte_end -> unbound_type_params_from_type_name ->
  def_has_unbound_type_params? -> register_module_instance_methods_for`.
- `crystal build src/adamas.cr -o /private/tmp/cv2_unbound_tokens_host
  --error-trace`
- `crystal tool format --check src/compiler/hir/ast_to_hir.cr`
- `git diff --check`
- `regression_tests/p2_unbound_type_param_scan_no_regex_no_prelude.sh
  /private/tmp/cv2_unbound_tokens_host`
- `regression_tests/p2_module_macro_for_iter_var_names_no_prelude.sh
  /private/tmp/cv2_unbound_tokens_host`
- `regression_tests/p2_macro_included_proc_sink_self_capture_no_prelude.sh
  /private/tmp/cv2_unbound_tokens_host`
- `scripts/run_safe.sh /private/tmp/cv2_unbound_tokens_host 300 4096
  src/adamas.cr -o /private/tmp/cv2_unbound_tokens_s2/cv2_s2`
  exited 0 after ~165s.
- `regression_tests/p2_unbound_type_param_scan_no_regex_no_prelude.sh
  /private/tmp/cv2_unbound_tokens_s2/cv2_s2`
- Produced-s2 full-prelude `puts 42` moves past the old
  `Regex::MatchData#byte_end` stack and completes module registration. It now
  exits 133 during class registration around idx=3/112; lldb under the 60s
  safe gate timed out before capturing that moved frontier.

Boundary:

- This is a targeted bootstrap hot-path rewrite, not a general Regex runtime
  fix.
- The remaining `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer
  arithmetic-overflow diagnostic is still non-fatal and still present during
  the s2 build.

Trust: {F/G/R: 0.88/0.44/0.88} [verified]

## LM-577 — Constant globals avoid stage2-empty names during LLVM emission

Context: compiler/bootstrap/CLI-to-MIR global registration, 2026-05-19,
`codegen`.

Verified outcome:

- Produced `s2` no longer segfaults in LLVM global emission for no-prelude
  numeric constants such as `private UNLOCKED = 0`.
- The reduced produced crash was:
  `LLVMIRGenerator#generate -> emit_global_variables`, where
  `@module.globals.first.name` was the empty string even though HIR/MIR body
  stores referenced `Object__classvar__UNLOCKED`.
- Root corridor: the CLI constant-literal export path used
  `constant_literal_values.each do |full_name, macro_value|` and then
  reconstructed class-var global names from those yielded values. In produced
  `s2`, this path could construct empty global names for non-empty constants.
  The accepted fix avoids key/value block destructuring for constant literal
  scans, uses one local constructor for constant class-var globals, and raises
  on empty owner/name invariants instead of silently emitting malformed globals.
- `HIRToMIRLowering#register_globals` was also hardened to avoid tuple block
  destructuring when consuming `Array(Tuple(String, ...))` global entries.

Evidence:

- Clean produced `s2` from `c405b862` crashed on a no-prelude reducer with
  top-level numeric constants using `--emit llvm-ir --no-link`.
- The same reducer passed `ADAMAS_STOP_AFTER_MIR=1`, proving MIR lowering
  was complete and the crash was in LLVM generation.
- Temporary backend tracing localized the crash to `emit_global_variables`;
  temporary CLI tracing showed the constant-literal export path produced an
  empty global name for `UNLOCKED`.
- `crystal build src/adamas.cr -o /private/tmp/cv2_constglobal_final5_host
  --error-trace`
- `regression_tests/p2_constant_globals_no_prelude.sh
  /private/tmp/cv2_constglobal_final5_host`
- `scripts/run_safe.sh /private/tmp/cv2_constglobal_final5_host 300 4096
  src/adamas.cr -o /private/tmp/cv2_constglobal_final5_s2/cv2_s2`
  exited 0 after ~163s.
- `regression_tests/p2_constant_globals_no_prelude.sh
  /private/tmp/cv2_constglobal_final5_s2/cv2_s2`
- Produced `s2` also passed the nearby guards:
  `p2_unbound_type_param_scan_no_regex_no_prelude.sh`,
  `p2_module_macro_for_iter_var_names_no_prelude.sh`, and
  `p2_qualified_module_namespace_no_prelude.sh`.

Refuted branches:

- Changing the shared `class_var_global_name` helper to `String.build` did not
  fix the reducer.
- Changing the shared helper to `String#+` moved the s2 build to an
  `ExprId out of bounds` failure, so the accepted fix keeps the shared helper
  unchanged and narrows the string-construction change to constant global export
  with explicit owner/name invariant checks.

Boundary:

- This fixes the no-prelude constant-global LLVM crash, not the full-prelude
  `puts 42` gate. Produced `s2` full-prelude `puts 42` currently times out
  after top-level collection at `pre-scan class/module loops start` under a
  120s safe gate.
- The remaining `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer
  arithmetic-overflow diagnostic is still non-fatal and still present during
  the s2 build.
- A hostile-review expansion found a separate upstream HIR registration gap:
  produced `s2` emits a no-prelude `module Foo; private COUNT = 2; end`
  constant as `Object__classvar__Foo$CCCOUNT` while host emits
  `Foo__classvar__COUNT`. This is not fixed here because the malformed owner
  is already present before CLI constant-literal export.

Trust: {F/G/R: 0.88/0.40/0.88} [verified]

## LM-578 — Constant global export carries structured owner/name metadata

Context: compiler/bootstrap/HIR-to-CLI constant global transport, 2026-05-20,
`codegen`.

Verified outcome:

- Produced `s2` now emits a module-scoped no-prelude numeric constant as
  `Foo__classvar__COUNT` rather than `Object__classvar__Foo$CCCOUNT`.
- The widened `p2_constant_globals_no_prelude.sh` guard now covers both
  top-level numeric constants and `module Foo; private COUNT = 2; end`, and
  rejects mangled namespace tokens inside `Object__classvar__...` globals.

WBA framing:

- Window/trigger: `Object__classvar__Foo$CCCOUNT` in produced `s2` LLVM IR.
- Transport corridor: `ConstantNode -> record_constant_definition ->
  @constant_literal_values -> CLI constant global export -> MIR globals ->
  LLVM globals`.
- Boundary: semantic owner and leaf constant name must remain separate from
  rendered names.
- Legal move: store `constant_literal_owners` and `constant_literal_names`
  alongside each constant literal key during HIR registration, then have CLI
  constant global export consume those structured fields instead of reparsing
  the rendered key.
- Potential decrease: removes one self-hosted string-split bad corner from the
  constant global corridor while keeping the previous empty-global guard.

Evidence:

- Host trace before the fix showed `record_constants_in_body(owner=Foo)` and
  `CONST_LIT full=Foo::COUNT owner=Foo`, while produced `s2` still emitted
  `Object__classvar__Foo$CCCOUNT`. That localized the bug after HIR constant
  registration and before final global symbol spelling.
- `crystal build src/adamas.cr -o /private/tmp/cv2_wba_structconst_host
  --error-trace`
- `regression_tests/p2_constant_globals_no_prelude.sh
  /private/tmp/cv2_wba_structconst_host`
- `scripts/run_safe.sh /private/tmp/cv2_wba_structconst_host 300 4096
  src/adamas.cr -o /private/tmp/cv2_wba_structconst_s2/cv2_s2`
  exited 0 after ~165s.
- Produced `s2` passed:
  `p2_constant_globals_no_prelude.sh`,
  `p2_unbound_type_param_scan_no_regex_no_prelude.sh`,
  `p2_module_macro_for_iter_var_names_no_prelude.sh`, and
  `p2_qualified_module_namespace_no_prelude.sh`.

Refuted branch:

- Replacing `String#rindex("::")` with a local byte-scan helper passed the host
  guard but regressed produced `s2` build to
  `ExprId out of bounds: 1600485477`. Under the LTP/WBA recomputation rule,
  this was not a legal boundary-safe move and was backed out.

Boundary:

- This fixes the no-prelude module-constant global naming drift, not the
  full-prelude `puts 42` gate. Produced `s2` full-prelude `puts 42` still needs
  separate localization around the class/module pre-scan frontier.
- The `file_sha256$String` MIR optimizer arithmetic-overflow diagnostic remains
  non-fatal during produced `s2` builds.

Trust: {F/G/R: 0.90/0.42/0.90} [verified]

## LM-579 — Source-span slicing and Char macro operator-id checks hardened

Context: compiler/bootstrap/HIR registration boundaries, 2026-05-20,
`codegen`.

Verified outcome:

- Produced `s2` no longer remains at the old clean full-prelude
  `pre-scan class/module loops start` timeout under the tested 90s safe gate.
  The clean `puts 42` smoke reaches `pre-scan constants done`, completes lib,
  enum, alias, macro, and module registration, then segfaults during early
  class registration after `class register idx=3/112`.
- The source-span helper now refuses implausible source strings and spans that
  extend outside the source before allocating with `String#byte_slice`.
- The Char primitive macro-for classifier now extracts operator ids only from
  `MacroIdValue`, `MacroStringValue`, or `MacroSymbolValue`, instead of
  dispatching `to_id` on an unproven tuple head.

WBA framing:

- Window/trigger: lldb stopped in `String#byte_slice` via
  `slice_source_for_span -> constant_literal_value_from_source` while HIR
  registration was reading constant source text; a later diagnostic lldb run
  stopped in `Float::Printer::CachedPowers::Power#to_id` via
  `char_binary_macro_values_have_operator_ids?`.
- Transport corridor: parser spans and macro iterable values cross from
  frontend/macro evaluation into HIR registration before demanded lowering.
- Boundary: source snippets must be sliced only from certified source windows,
  and Char operator-id shortcuts must not call id conversion on arbitrary macro
  values or self-hosted drift objects.
- Legal moves: reject invalid source windows and use structured macro-value
  cases for operator-id extraction.
- Potential decrease: removes two registration-time bad corners without
  broadening generic/proc/container demand or adding nesting-depth caps.

Evidence:

- `git diff --check`
- `crystal build src/adamas.cr -o /private/tmp/cv2_clean_hirfix_host
  --error-trace`
- Host guards:
  `regression_tests/p2_source_span_slice_bounds_no_prelude.sh
  /private/tmp/cv2_clean_hirfix_host` and
  `regression_tests/p2_constant_globals_no_prelude.sh
  /private/tmp/cv2_clean_hirfix_host`
- Produced `s2` build:
  `scripts/run_safe.sh /private/tmp/cv2_clean_hirfix_host 300 4096
  src/adamas.cr -o /private/tmp/cv2_clean_hirfix_s2/cv2_s2`, exited 0
  after ~154s.
- Produced guards:
  `p2_source_span_slice_bounds_no_prelude.sh`,
  `p2_constant_globals_no_prelude.sh`, and
  `p2_qualified_module_namespace_no_prelude.sh` on
  `/private/tmp/cv2_clean_hirfix_s2/cv2_s2`.
- Clean produced full-prelude smoke:
  `scripts/run_safe.sh /private/tmp/cv2_clean_hirfix_s2/cv2_s2 90 4096
  /private/tmp/cv2_clean_hirfix_hello.cr -o
  /private/tmp/cv2_clean_hirfix_hello_bin` exited 139 after reaching class
  registration.

Refuted/limited evidence:

- `ADAMAS_TRACE_STDERR`/`bootstrap_trace_puts` is not reliable for
  produced-s2 localization here; it can emit blank lines and materially perturb
  timing.
- Temporary `stage2_debug` pre-scan/module-name instrumentation was useful for
  localization, but it changed the frontier and was removed from the patch.
- The existing `p2_generated_stage2_char_macro_for_frontier.sh` guard now times
  out under its trace-heavy path and is not accepted as evidence for this
  slice.
- Batch lldb on the clean patch times out under the wrapper before reaching the
  moved class-register crash, so the current clean frontier is anchored by
  `run_safe` trace, not a fresh clean backtrace.

Boundary:

- This is a moved-frontier/root-boundary hardening, not a closed
  full-prelude smoke. The next target is the early class-registration segfault
  after `class register idx=3/112`.
- The non-fatal `Adamas::Compiler::CLI#file_sha256$String` MIR optimizer
  arithmetic-overflow diagnostic remains during produced `s2` builds.

Trust: {F/G/R: 0.86/0.46/0.88} [verified]

### LM-614 - LSP foreground expression span indexes are lazy

Foreground `didOpen`/`didChange` no longer build the child-expression span
index eagerly. The foreground `DocumentIndex` still records declaration maps
for scoped vars, constants, ivars, globals, and defs, but `ExprSpanIndex` is
left absent until a future measured need justifies rebuilding it. Positional
navigation continues to use the existing AST walk fallback, which keeps the
same PathNode boundary behavior as the indexed lookup.

Evidence:

- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 2048 tool format
  --check src/compiler/lsp/server.cr spec/lsp/support/server_helper.cr
  spec/lsp/hover_definition_integration_spec.cr`
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp/hover_definition_integration_spec.cr --error-trace` -> 5 examples,
  0 failures.
- Warm harness after the change kept the main interactions green:
  `server.cr didOpen` around 140ms, hover `handle_completion` around 9ms on the
  last warm run, definition 1 location, document symbols 567 symbols, semantic
  tokens 149760 ints, formatting no edits.

Adversary notes:

- This is a small foreground-work reduction, not the main semantic-token root
  fix: full semantic tokens still spend about 130ms on the current large
  `server.cr` harness request.
- The focused regression asserts the expression index stays absent after
  `didOpen`, after hover/definition, and after semantic-token requests, while
  hover, definition, repeated semantic tokens, and lazy document symbols remain
  functional.

Trust: {F/G/R: 0.82/0.42/0.84} [verified]

### LM-615 - LSP full semantic-token collector avoids request-time waste

First full semantic-token requests no longer spend collector work on data that
cannot affect the response:

- lexical token scans use `Lexer#each_token(skip_trivia: true)` because the
  collector does not emit whitespace/comment tokens;
- token priority is an enum-indexed array instead of a hash lookup inside the
  sort comparator;
- deduplication compacts the local `RawToken` array in place instead of
  allocating a second array;
- declaration/member source-window searches compare bytes directly instead of
  allocating temporary `String`s for each name lookup.

Evidence:

- Direct `LSP_PROFILE_TOKENS=1` collector probes on `src/compiler/lsp/server.cr`
  moved from about 68ms before this slice to about 63-65ms after the full patch
  in local repeated runs.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/server.cr spec/lsp/semantic_tokens_spec.cr`
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp/semantic_tokens_spec.cr spec/lsp/lsp_semantic_tokens_spec.cr
  spec/lsp/semantic_tokens_integration_spec.cr --error-trace` -> 36 examples,
  0 failures.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 240 examples, 0 failures.
- Rebuilt `src/lsp_main.cr` and `benchmarks/lsp_harness.cr`; warm harness kept
  `definition handle_completion` at 1 location, document symbols at 568
  symbols, and `semanticTokens/full` green. The debug split reported
  `collect=66.1ms json=14.1ms`; harness-level semantic tokens were about
  122-126ms on the measured runs.

Adversary notes:

- This is a request-time collector cleanup, not a protocol-level semantic-token
  fix. The remaining gap between server collection/JSON and harness request
  time likely lives in response size, client/transport parsing, or full-document
  protocol strategy.
- Skipping trivia is only valid while comments remain intentionally uncolored.
  A regression now asserts comment text is not tokenized while uppercase
  identifiers, symbols, and strings still receive tokens.
- The priority array depends on `SemanticTokenType` enum order; semantic-token
  specs keep enum-member/string/type behavior covered.

Trust: {F/G/R: 0.84/0.48/0.86} [verified]

### LM-616 - Formatter skips storing whitespace tokens

The token-based formatter no longer stores whitespace tokens in its internal
token array. It still keeps comments and newlines: comments carry source spans
used by `original_gap_between`, and newlines drive line-start/indentation
state. With whitespace filtered at collection time, formatter lookahead is a
direct next-token lookup instead of a scan past ignored tokens.

Evidence:

- Direct formatter probes on `src/compiler/lsp/server.cr` moved steady runs
  from about 73ms before the patch to about 68-70ms after the patch, with
  `Formatter.format(source) == source`.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/formatter.cr`
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/formatter_spec.cr spec/lsp/formatting_integration_spec.cr
  --error-trace` -> 15 examples, 0 failures.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 240 examples, 0 failures.
- Rebuilt `src/lsp_main.cr` and `benchmarks/lsp_harness.cr`; warm harness kept
  formatting green with no edits and measured about 77ms on the warm run.

Adversary notes:

- This is a modest formatter-internal cleanup, not a complete LSP formatting
  latency fix. The formatter still lexes the whole document and builds the
  formatted output before it can prove an already-formatted document is a null
  edit.
- The safe boundary is strict: do not replace this with
  `Lexer#each_token(skip_trivia: true)`, because that would also remove
  comments.

Trust: {F/G/R: 0.82/0.45/0.84} [verified]

### LM-617 - Refuted lazy-on-first-position expression index

A follow-up experiment tried to keep LM-614's lazy `didOpen` behavior while
building `ExprSpanIndex` on the first positional lookup (`hover`, `definition`,
etc.) and storing it back into `DocumentState`.

Outcome:

- The focused regression passed, but the warm harness refuted the tradeoff for
  the current one-file scenario: first `hover handle_completion` on
  `src/compiler/lsp/server.cr` got worse, around 39ms, because the hover paid
  expression-index construction before answering.
- Reverting the experiment restored the current cheaper fallback shape:
  `didOpen` stays lazy and first hover remains a tree-walk cost of roughly
  25-30ms on the large file.

Evidence:

- Refuted patch was not committed.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/server.cr spec/lsp/hover_definition_integration_spec.cr`
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp/hover_definition_integration_spec.cr --error-trace` -> 5 examples,
  0 failures.
- Rebuilt `src/lsp_main.cr` and `benchmarks/lsp_harness.cr`; warm run with the
  experiment measured `hover handle_completion` around 39ms, while `didOpen`
  remained around 136ms.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 240 examples, 0 failures during the experiment,
  but performance evidence rejected the branch.

Decision:

- Do not reintroduce lazy-on-first-position `ExprSpanIndex` unless a future
  workload has repeated same-document positional queries where the first-query
  tax is acceptable and measured.
- The next hover root should be a narrower lookup fast path for declaration-name
  positions or another way to avoid the full-tree walk without building the
  whole child index on demand.

Trust: {F/G/R: 0.78/0.36/0.86} [refuted]

### LM-618 - Declaration-header hover bypasses the foreground tree walk

Hover on a parsed method declaration header now answers from the local
declaration corridor before entering the generic `find_expr_at_position` path.
The fast path first uses the registered `MethodSymbol` when present, and falls
back to a parsed local `DefNode` only when the cursor line is a plausible
`def` header. This keeps the foreground expression index lazy while avoiding
the large-file AST walk for declaration-header hover positions such as the LSP
harness target on `private def handle_completion`.

Evidence:

- The focused regression covers hover on the method name and on the `def`
  header prefix, asserts both return `def run(value : Int32) : Int32`, and
  checks the foreground expression index remains unbuilt. It also checks that a
  string literal containing `def run(...)` does not trigger the declaration
  signature.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/server.cr spec/lsp/hover_definition_integration_spec.cr`
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp/hover_definition_integration_spec.cr --error-trace` -> 5 examples,
  0 failures.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 240 examples, 0 failures.
- Rebuilt `src/lsp_main.cr` and `benchmarks/lsp_harness.cr`; with a fresh temp
  cache the cold harness showed server-side `Hover declaration fast path:
  handle_completion` and `hit(method-decl)` in about 3.6ms. The warm harness
  reported `hover handle_completion` at 5.4ms client-side and server-side
  `hit(method-decl)` in about 1.5ms. Before this slice, warm hover on the same
  target was about 25-30ms server-side because it landed on the enclosing
  `Server` class through the generic tree walk.

Adversary notes:

- This is intentionally a declaration-header fast path, not a general hover
  index. Ordinary expression/member/call hovers still use the existing symbol
  and type paths.
- The textual `def` prefilter is not trusted by itself; it only gates a parsed
  `DefNode` scan, and the regression includes a fake `def` string literal.
- The cold harness can still show large initialize/open costs from prelude and
  foreground analysis; this landmark only closes the declaration-hover slice.

Trust: {F/G/R: 0.86/0.42/0.88} [verified]

### LM-619 - Exact-text reopen reuses closed document analysis

The LSP server now keeps a small in-memory cache for recently closed documents.
When a `didOpen` arrives for the same URI, same language id, same normalized
path, and exact same text, the server restores the previous parsed/analyzed
`DocumentState` and diagnostics instead of rebuilding foreground analysis. A
text mismatch or `didChange` invalidates the closed-document entry.

Evidence:

- The regression closes and reopens an unchanged document, asserts the reopened
  state reuses the same parsed program object, and checks method hover still
  returns the declaration signature after restore.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/server.cr spec/lsp/support/server_helper.cr
  spec/lsp/did_change_integration_spec.cr`
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp/did_change_integration_spec.cr --error-trace` -> 7 examples,
  0 failures.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 241 examples, 0 failures.
- Rebuilt `src/lsp_main.cr` and `benchmarks/lsp_harness.cr`; the repeated
  `server.cr` open used by the call-hierarchy scenario dropped from the prior
  ~130-140ms range to 13.1ms on the cold-cache run and 31.2ms on the warm run.

Adversary notes:

- This does not claim to improve first open; it removes repeated exact-text
  reopen work inside the same LSP server process.
- Diagnostics are cached with the closed document so exact-text reopen does not
  silently clear previous diagnostics.
- The cache is bounded to eight documents and does not survive process restart.

Trust: {F/G/R: 0.84/0.44/0.87} [verified]

### LM-620 - Exact-text reopen preserves cached LSP responses

The closed-document cache from LM-619 now also carries already-computed
semantic-token and formatting JSON responses. On an exact-text reopen, those
responses are restored under the new document version, so a client reopening
the same file does not force the server to recompute full semantic tokens or
whole-document formatting before the text changes.

Evidence:

- The regression opens a document, computes semantic tokens and formatting,
  closes it, reopens the exact same text, and verifies both response caches are
  restored and return identical responses.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/server.cr spec/lsp/support/server_helper.cr
  spec/lsp/did_change_integration_spec.cr`
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/lsp/did_change_integration_spec.cr --error-trace` -> 8 examples,
  0 failures.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 242 examples, 0 failures.
- A temporary in-process profile on `src/compiler/lsp/server.cr` measured
  first semantic-token request at about 164ms and first formatting at about
  92ms. After exact close/reopen, formatting was served from cache at about
  0ms; semantic tokens no longer paid server collection/serialization, with
  the remaining about 46ms attributable to parsing the large cached JSON
  response in the helper path.

Adversary notes:

- This is an in-process exact-text optimization only; it does not change cache
  persistence or reuse responses after edits.
- Response JSON is re-versioned to the reopened document version, so the
  existing version-keyed response cache remains coherent.
- The semantic-token response is still large; this does not solve the
  client-side parse/transport cost identified in LM-619.

Trust: {F/G/R: 0.84/0.43/0.86} [verified]

### LM-621 - Nilable indexer postfix chains no longer block large-file AST caching

The parser now treats `obj[key]?.foo` as an unambiguous nilable indexer when
the `?` after `]` is immediately followed by a postfix chain. Previously, the
`[]?` disambiguator scanned ahead until it found a surrounding ternary's `:`,
so `table[key]?.try { ... }` inside a ternary true branch produced recoverable
`unexpected Question` diagnostics. On `src/compiler/hir/ast_to_hir.cr`, those
two diagnostics prevented the foreground AST cache from being saved.

Evidence:

- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 spec
  spec/parser/parser_index_block_spec.cr --error-trace` -> 3 examples,
  0 failures.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/parser/parser_ternary_spec.cr spec/parser/parser_index_block_spec.cr
  --error-trace` -> 6 examples, 0 failures.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 eval
  'require "./src/compiler/frontend/parser"; ...'` on
  `src/compiler/hir/ast_to_hir.cr` -> `ast_to_hir parser diagnostics=0`.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 240 4096 spec
  spec/parser --error-trace` -> 2183 examples, 0 failures, 1 existing pending.
- Temporary stable-binary LSP profile with isolated `XDG_CACHE_HOME`: first run
  had `cache_before_hit=false`, `first_did_open_ms=2525.2`, and
  `cache_after_hit=true`; the second run had `cache_before_hit=true`,
  logged `Loading foreground document ... ast_to_hir.cr from AST cache`, and
  dropped `first_did_open_ms` to `1140.1`.

Adversary notes:

- The positive regression covers `table[key]?.try { ... }` inside a ternary
  true branch, the original failure shape.
- The negative regression keeps `table[key] ? yes : no` as a real ternary with
  an `IndexNode` condition, so the fix does not blindly consume every `?`
  after `]`.
- This improves fresh opens only after the stable LSP executable has created
  the AST cache once. It does not remove the remaining name-resolution or
  semantic-token full-response costs.

Trust: {F/G/R: 0.87/0.46/0.89} [verified]

### LM-622 - Large semantic-token responses are persisted across LSP processes

Full semantic-token responses for large exact disk-backed documents are now
stored in a strict disk cache. The server only uses this cache when the open
document text exactly matches the file on disk and the cached header matches
the current compiler fingerprint, file mtime, and file size. The cache has a
64KB source-size floor, so normal small files stay on the in-memory path and do
not churn disk.

Evidence:

- The focused regression pre-seeds a disk-cache entry and verifies that an
  exact disk-backed open serves that cached response. It also verifies that an
  open buffer with the same size but different text ignores the disk cache.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/lsp/semantic_token_disk_cache_spec.cr --error-trace` -> 2 examples,
  0 failures.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 244 examples, 0 failures.
- Temporary stable-binary profile with isolated `XDG_CACHE_HOME`: first
  `ast_to_hir.cr` semantic-token request computed and saved tokens at about
  `1028.0ms`; a fresh server process then logged
  `Semantic tokens disk cache HIT` and returned the same 1,276,950 encoded
  ints in about `410.2ms` in the helper path. The remaining time is dominated
  by handling/parsing the huge JSON response after server-side
  collect/serialization is skipped.

Adversary notes:

- This is not a stale-token shortcut: unsaved buffers, size mismatches, mtime
  mismatches, and compiler rebuilds all fall back to recomputation.
- It helps repeated opens or fresh LSP processes after the first full-token
  computation for a large unchanged file. It does not reduce the wire/client
  cost of a 1.27M-int semantic-token response.

Trust: {F/G/R: 0.86/0.48/0.88} [verified]

### LM-623 - Semantic-token full delta avoids repeated huge responses

The LSP server now advertises `semanticTokensProvider.full.delta`, includes a
stable `resultId` in full semantic-token responses, and handles
`textDocument/semanticTokens/full/delta`. When the client sends the exact
current result id previously issued or restored by this server process, the
server returns an empty edit list instead of resending the full token array.
Stale or unknown result ids fall back to the existing full-token response.

Evidence:

- The focused regression verifies an empty delta for the current result id, a
  full fallback for a stale result id, exact close/reopen result-id
  preservation, and the advertised `full.delta` capability.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 180 4096 spec
  spec/lsp/semantic_token_disk_cache_spec.cr spec/lsp/semantic_tokens_spec.cr
  --error-trace` -> 12 examples, 0 failures.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 300 4096 spec
  spec/lsp --error-trace` -> 247 examples, 0 failures.
- `scripts/run_safe.sh /Users/sergey/.local/bin/crystal 120 4096 tool format
  --check src/compiler/lsp/server.cr src/compiler/lsp/messages.cr
  src/compiler/lsp/semantic_token_cache.cr spec/lsp/support/server_helper.cr
  spec/lsp/semantic_token_disk_cache_spec.cr spec/lsp/semantic_tokens_spec.cr`
  -> exit 0; `git diff --check` -> exit 0.
- Temporary profile on `src/compiler/hir/ast_to_hir.cr`: full semantic tokens
  still returned 1,276,950 encoded ints in about 1026.8ms in the helper path,
  while same-result `full/delta` returned 0 edits, 75 bytes, in about 0.9ms.

Adversary notes:

- Empty delta is not derived from filename or mtime alone. The server must have
  issued or restored the matching result id; unknown ids use full fallback.
- Result ids are invalidated with the semantic-token cache on text changes and
  preserved only for exact close/reopen cache hits.
- This removes repeated huge-response cost after a client has a current full
  result. It does not remove the first full-token request cost.

Trust: {F/G/R: 0.88/0.50/0.89} [verified]

### LM-672 - Function registry removal snapshots before Hash mutation

Generated-stage `Hash#delete` cannot currently be trusted as a value-returning
transaction for pointer-backed struct entries. `Hash#delete_impl` borrows the
inline `Hash::Entry`, clears the source slot, and only then constructs its
value-typed return. For `Hash(String, HIR::Function)`, this removes the key but
returns nil. `HIR::Module#remove_function` therefore used to leave the Function
in `@functions` after its `@functions_by_name` entry was gone.

That split registry produced four equal `Array(String)#to_s` rows. RTA traversed
the last indexed row and retained its block procs, while HIR-to-MIR deduplicated
by name and lowered the first row, whose block procs had been pruned. The final
link failure at `__crystal_block_proc_51` was downstream of this transaction,
not missing block-proc generation.

The bounded fix snapshots the Function via non-mutating lookup, then deletes the
key and array row independently. Evidence:

- the exact 768-name HIR registry insert/lookup/remove/re-add runtime contract
  passes with counts 768 -> 384 -> 768;
- the minimal Array(String)#to_s HIR contains one caller row and zero dangling
  `__crystal_block_proc_N` FuncPointers under filtered stage2;
- filtered stage2 compiles and links the reducer that previously failed with an
  undefined block proc.

Residual risk: this does not implement global copy-by-value semantics for
pointer-backed `Hash::Entry`. Other compiler sites that consume `Hash#delete`'s
return remain an explicit audit surface.

Trust: {F/G/R: 0.94/0.62/0.91} [verified]

### LM-673 - Mismatched stale entry boxes no longer swallow fallthrough locals

Branch snapshots restore visible locals but intentionally preserve entry boxes.
Before this landmark, the fallback for a missing current local accepted any
same-named box. A box created for `Set(UInt32)` in a terminating branch could
therefore absorb a later fallthrough assignment of `Array(UInt32)`. The early
return from assignment lowering skipped registration of the new local; the next
read became `Local<Void>` and call fallback selected `Array(String)#<<$String`.
In the generated compiler this corrupted `HIRToMIRLowering#lower_is_a` and
crashed in `Array(String)#push`.

The name-only fallback now reuses a box only when its payload type matches the
new assignment. A mismatched box with no visible owner local is discarded, so
the fallthrough binding receives its own local and capture box. Evidence:

- the focused captured-local reducer emits `Array(UInt32)#<<$UInt32`, contains no
  `Array(String)#<<$String` in the target function, and runs both branches;
- a rebuilt filtered stage2 compiles past the previous `lower_is_a` crash;
- the Array-to-s and tuple reducers both reach successful link.

Residual frontier: the tuple reducer now exits 0 without its expected output,
and the Array-to-s reducer reaches a `Crystal.trace(..., &block)` abort stub.
Those are downstream runtime/value-supply failures, not evidence that this box
lifecycle fix is incomplete.

Trust: {F/G/R: 0.92/0.68/0.90} [verified]

### LM-674 - Typed pointer nulls are preserved; bare operator demand is the next floor

Static member lowering used to hard-code `Pointer(T).null` as a cast to bare
`Pointer`. In a Kqueue-shaped branch, that disagreed with the concrete
`Pointer(LibC::Timespec)` produced by `pointerof(ts)` and allowed a synthetic
pointer union to cross later ABI decisions. The bounded fix resolves and interns
the full static `Pointer(T)` name before emitting the null cast.

Verified host evidence:

- `pointerof(ts)` and nested `Pointer(T).null` both retain the same concrete
  pointer descriptor;
- their conditional merge is a typed pointer phi with no pointer `UnionWrap`;
- the Kqueue-shaped branch preserves the concrete timeout pointer;
- generic `Hash(K, V)` pointer ivars specialize to
  `Pointer(Hash::Entry(String, Nil))`, lower indexing as `PointerLoad`, and do
  not synthesize `Pointer#[]` dispatch;
- the focused HIR suite passes, and the central MIR union-storage ABI/backend
  specs retain the tagged-vs-raw representation boundary.

Rejected routes are part of the result. A global erased-representation collapse
for pointer unions degraded valid generic Hash access to bare `Pointer` and was
reverted. DefNode/arena sidecars changed self-host behavior and caused recursive
`resolve_type_name` stack overflow. A name-cache early return plus exact
lookup-key cache transport (nullable and non-nullable carriers, including
mangled-prefix sources) built fresh stage2 binaries but did not move the
untraced crash. All DefNode/cache-transport production changes and their helper
specs were reverted.

The active floor is upstream of the generic pointer-ivar contract. Fresh stage2
self-compilation succeeds, but the produced compiler exits 139 while compiling
the no-prelude fixture. LLDB records
`DefNode#params -> build_param_infos -> function_param_infos ->
seed_function_param_caches -> prime_param_caches_for_discovered_def`, through
`process_pending_lower_functions / lower_missing_call_targets`. A conditional
breakpoint decoded the failing requested/target name as bare `[]$Int32`; the
DefNode is null-like when parameters are read. Existing lookup diagnostics call
the branch `unknown`, and the mangled-prefix scan is not entered. The next legal
probe is therefore at the producer/enqueue boundary where the operator owner is
lost, not another downstream stub, sidecar, or cache heuristic. The
produced-stage bootstrap spec remains intentionally red as the durable gate.

Trust: {F/G/R: 0.91/0.61/0.88} [verified root slice, open successor]

### LM-675 - Included-module materialization is restored; nested lowering can still collapse caller body state

The `Array(T)#uniq` large branch exposed two distinct self-host faults that
previously converged on the same backend abort stub.

First, a bare included-module call (`to_set`) and the equivalent explicit call
(`self.to_set`) followed different lookup paths. The bare identifier path could
miss a lazily registered generic module method and lower `to_set` as
`Local<Void>`, while the explicit call found the module AST. The inheritance
resolver now falls back to the authoritative recursive module AST lookup after
its registry fast paths. A second produced-stage defect then found the correct
`DefNode` inside `included.each` but lost the assignments to `func_def`, arena,
target name, and lookup branch when the iterator block returned. Deferred
module lookup now preserves inclusion order in an `Array(String)` and scans it
with an indexed `while`, so result transport does not depend on captured-local
writeback.

Fresh produced-stage evidence:

- host s1 and generated s2 both build successfully under the safe wrapper;
- produced HIR contains calls and real bodies for
  `Array(UInt32/TypeRef)#to_set` and `Set(UInt32/TypeRef)#to_a`;
- no `local "to_set"` remains, and the prior
  `STUB CALLED: Array(UInt32)#to_set` abort is gone;
- host `spec/hir/ast_to_hir_spec.cr` passes 189 examples with 0 failures and
  2 existing pending examples, including bare-vs-explicit included-module
  identity and non-void-helper sequence guards.

The successor is not a Set/Hash implementation gap. Produced HIR truncates
`Hash(UInt32/TypeRef, Nil)#upsert` immediately after its first
`if @entries.null?`, omitting `key_hash`, linear scan, insertion, and size
increment. Consequently the 17-element UInt32 reducer returns an empty result
(`0,0,0`) and the 17-element pointer-backed TypeRef reducer segfaults; both
16-element small-array branches remain correct. A minimal direct method with a
normal non-void helper in the first branch reproduces the truncation, while an
intrinsic, a void helper, or wrapping the same sequence in `begin ... end` does
not.

Debug evidence initially reports a three-expression caller body and later a
one-expression sequence boundary after nested materialization. Attempts to
carry that boundary through an owning `Array(ExprId)`, scalar-index
`Array(Int32)`, a plain scalar count, and a raw `Pointer(Int32)` ledger did not
move the produced HIR; all candidates were rebuilt from fresh source snapshots
and reverted. This means simple carrier substitution is refuted. The remaining
frontier is a broader ownership/re-entrancy overwrite in the `lower_method`
pre-scan/materialization transaction, or a re-entrant lowering instance being
mistaken for the original caller. The next probe must observe writer/provenance
at that boundary rather than add another container workaround.

Quadrumvirate synthesis:

- Cassandra: a new abort stub is most likely a downstream observation of lost
  identity, body supply, or value lifetime, not an absent stdlib method.
- Daedalus: compare the earliest `AST -> HIR body -> MIR -> LLVM` divergence and
  threshold branches before investigating the runtime sentinel.
- Maieutic: host-unit green is necessary but cannot prove self-hosted carrier
  semantics; every bootstrap-hot contract needs a produced structural gate.
- Adversary: stub counts, traced builds, mixed-generation binaries, and one-off
  allowlists are invalid completion proxies. Source/compiler fingerprints and
  untraced dumps are required evidence.

Trust: {F/G/R: 0.94/0.66/0.91} [included-module resolution/materialization verified; caller-body successor open]
