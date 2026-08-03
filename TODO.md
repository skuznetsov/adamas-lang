# Adamas Bootstrap TODO

Updated: 2026-08-02 (bare reference-generic instance dispatch is runtime-
verified for direct erased receivers; registered runtime-reference and
same-template concrete generic-struct unions preserve their callsite return ABI
without mutating the anchored function ABI, while unsupported bare-template
return annotations fail closed;
the unconsumed cross-arena lowering bridge is rejected;
T9 focused HIR-to-MIR-to-LLVM continuity and source-bound full-compiler HIR
continuity are green through exact-target body lowering, while full-source
MIR/LLVM continuity remains blocked by B4-F and the historical full-G9 symptom
is stale and unreproduced. Exact guarded method
declaration shapes replace in place; local keyed decisions reject replaced
same-arena method objects; T1 remains red. Source-authoritative typed-hash
contracts now carry the fresh bootstrap through both stage1 smokes. The latest
clean 300-second B4-F run is still measured RED: stage2 remained active until
the 302.83-second safe-runner stop and emitted no `cv2_s2`; the preceding mixed
Pointer/Tuple hash-return and recursive Bool-hash inference frontiers are
closed).

BARE REFERENCE-GENERIC INSTANCE DISPATCH RUNTIME-VERIFIED; REGISTERED
RUNTIME-REFERENCE RETURN UNIONS HIR-VERIFIED AND MIR-GUARDED; UNSUPPORTED
BARE-TEMPLATE COMPOSITION FAILS CLOSED. A bare generic receiver now records an
erased virtual-call shape without materializing a layout-bearing template body.
Concrete reference instances are
registered only after layout alignment, replay the shape independently of the
source inheritance graph, and form the MIR type-id candidate family. Admission
fails closed unless every registered instance has a body and the active
dispatch corridor proves its return and explicit-argument contracts.
Layout-distinct `LayoutBox(Int32/String)`
has structural HIR-offset and MIR-type-id coverage; the true erased `Hash#size`
runtime path emits a five-case dispatcher and returns `1`. Instance-dependent
returns from an all-concrete receiver union specializing one registered
runtime-reference generic template now preserve the union of every target
return at the HIR callsite, including `Nil`, through non-block ordinary calls
that are positional and non-splat, plus zero-argument member access. The
admitted storage kinds are reference
classes, heap `Array`, and heap `Hash`; `StaticArray` and generic structs remain
outside the corridor. Every explicit positional argument must resolve against
every concrete owner, and the canonical owner-specialized formal ABI must be
identical across all targets before the corridor is admitted; only truly
untyped formals derive that ABI from the shared call type. Emitted named, block,
and splat call shapes fail closed until their full per-target ABI is certified.
The concrete dispatch-name
anchor keeps its own function ABI. The `LayoutBox(Int32/String)` bare-receiver
runtime oracle returns `OK`. The all-concrete typed-union corridor is verified
structurally at HIR and guarded against downstream MIR ABI mutation; it does not
yet have a separate runtime oracle.
Heterogeneous returns in mixed-template, unregistered-instance, and
generic-struct unions, plus unresolved return sets, are rejected rather than
inheriting the first target's ABI. Mixed generic/non-generic unions and
homogeneous unsupported unions retain their existing lowering path. A demanded
explicit return annotation containing a
bare generic template, including nullable `T?`
syntax, now fails closed with the original Crystal diagnostic instead of
building an incomplete runtime union dispatcher. Bare generic parameter
restrictions with concrete callsite specializations remain admitted, and an
uncalled definition retains original Crystal's lazy validation behavior. HIR is
**388/0** with two existing pending examples, and MIR is **37/0**. Generic
structs remain static, and bare generic struct return unions fail closed by the
same original-Crystal storage rule. A separate all-concrete, same-template
generic-struct receiver corridor now preserves tagged nullable returns and
explicitly wraps the exact branch ABI for a two-arm heap-backed aggregate/Proc
return; it does not admit a bare generic template or mixed-template receiver.
This is a compatibility guard, not runtime support for bare-generic union
composition; B4-F remains open under the 300-second policy.

T1 OWNERSHIP/NAME-ID SUBSTRATE VERIFIED; CALL RESOLUTION CONTINUITY REMAINS
OPEN. `SemanticIdentityRegistry` is now the compile-session owner for canonical
`NameId` values and the existing semantic type table. `DefInstanceKey` named
arguments use ordered `{NameId, SemanticTypeId}` components, and both it and
`SemanticTypeKey` own their dynamic key arrays without exposing mutable retained
storage. The identity/generic group passes 53 examples, the compiler builds,
and the same-spelling reducer still executes correctly while the exact T1
producer remains deliberately absent (`T1_STATUS=MEASURED_RED`). The semantic
compile path now rejects a shadow reparse unless source, allocation order,
roots, node kinds, spans, and child topology match the original per-file parse;
49 focused aggregate/dispatch examples plus multi-unit/T1 semantic compile
probes pass.
The legacy explicit-receiver overload seam rejects a parser-backed selected
method unless its name, exact parameter storage, and class/instance receiver
kind still match the owning `DefNode`. For positional, no-block r1-r3 calls,
the Analyzer-owned `SemanticIdentityRegistry` now builds and immediately
consumes one local `LocalCallResolution {MethodSymbol, DefInstanceKey}`. A
standalone engine creates the same registry lazily only when this path needs it.
The same local record now also covers the exact T1 r4/r5 shapes: one direct
positional argument plus an explicit inline block selected against one
annotated block parameter, and one required direct named-only argument. The r4
key records the inferred block result type,
matching Crystal's `DefInstanceKey`; the selected definition plus
receiver/positional arguments fixes the declared block parameter shape. Block
inference therefore precedes key construction, while key mismatch still stops
callee-body inference. The r5 key records the AST-ordered shared-registry
`{NameId, SemanticTypeId}` pair. The consumer revalidates selected
`DefIdentity`, receiver/argument IDs, block result, named pair, and AST shape
before the unchanged legacy return/body inference. Combined block-plus-named,
defaulted/external/multiple named arguments, splats, double splats, forwarded
procs, and unannotated blocks deliberately remain on the legacy selector/body
path after the shared parser-backed selected-definition ownership check, rather
than broadening the typed-key guard. The local adapter admits a nominal
receiver only when the same `ClassSymbol` is visible from this engine's global
table or its canonical owner-chain reaches that table, then interns it with
declaration `DefIdentity`; equal local spellings in different owners remain
distinct, and a same-shaped symbol from an independent Analyzer/root table is
rejected. Same-arena class reopenings retain one receiver identity across
distinct method definitions; after a shared context is recollected, stale
receiver and method symbols from the prior arena fail closed while the
replacement symbol remains valid. The local keyed producer and consumer now
also require the exact `MethodSymbol` object to remain current in its declaring
scope. Recollecting the same `Program` leaves the replaced object's AST
`DefIdentity` valid, but no longer mints or consumes a key for that object; the
replacement remains admitted, and the focused identity group passes 19
examples, including current inherited and included-module controls. Reopened
methods whose class/instance kind,
parameter names, external names, type annotations, default presence, and
splat/double-splat/block markers match exactly now replace the previous method
in its existing overload slot. The latest return annotation is selected while
a distinct typed overload remains available; the original Crystal oracle
produces `42`, `42`, `20` for replacement, `previous_def`, and a true overload,
and the corresponding Adamas collector/inference groups pass 33 and 283
examples. This is an exact declaration-shape fail-closed guard, not Crystal's
full restriction ordering: renamed parameters, changed default presence,
semantic restriction equivalence, and the `previous_def` chain remain open.
Cross-arena `MethodSymbol` admission for compiler lowering is rejected at this
boundary. The live compiler inventory found no semantic object flow from the
aggregate reparse Analyzer into `AstToHir`: the semantic prepass consumes its
local result, while HIR independently lowers the original per-file arenas. The
existing `CompileShadowAggregate` unit offsets prove a structural node mapping
after `original_unit_structure_error`, but a map is not a downstream consumer.
LSP symbol-table merging is a separate bounded context and does not authorize a
compiler-lowering bridge. Scope/return/type-parameter metadata, in-place shared
parameter payload mutation, non-`self` explicit receivers, and
generic/union/container types remain outside this narrow guard. This is not the
general `CallResolution`, a `ResolutionId`, T1 telemetry, downstream continuity,
or new selection authority. Phase 3a therefore pauses before `ResolutionId`;
do not add an ordinal call token or another bridge until a genuine compiler
consumer exists in the same coherent slice. The focused T9 union/static generic
materialization guard now passes. Eager return inference fails closed for
`<<`/`>>` when the left operand type is unavailable instead of seeding a
function signature from the right operand. Receiver-layout fallback now
preserves a concrete typed callsite specialization only when it exactly
re-serializes to the already selected symbol; union fallback and the existing
M4i6f tuple-layout repair remain intact. Evidence: host build, focused T9 HIR
guard plus typed MIR/LLVM ABI spec, union/nilable Array runtime storage, late
generic union stride, tuple Array/Pointer runtime guards, and the HIR suite (372
examples, 0 failures/errors, 2 existing pending). A source-bound full-compiler probe now
also reaches and lowers the exact concrete `Array(ArenaLike)#push$AstArena`
body without canonicalizing it to the union symbol. The focused reducer's typed
ABI spec now also preserves exact concrete and union `append -> << -> push`
FunctionIds, receiver/value types and operands, `ret self` MIR bodies, and exact
two-argument LLVM `<< -> push` calls/definitions. A wrong concrete/union MIR
`TypeRef` expectation is RED. This closes the local downstream corridor, not the
full-source route. The next active T9 frontier is
full-source MIR-to-LLVM emitted-symbol continuity after B4-F reachability; the
historical zero-argument symptom is not current evidence. T1 remains red;
B4-F is measured RED at the concrete generic-struct getter-return frontier
under the 300-second policy. The HIR compatibility path now
exposes only
`SelectedCallTarget {symbol_name, def_node}`; the unused `CallShape`,
`ResolutionBinding`, string-round-trip `MethodInstanceKey`, and their unconsumed
assertion paths were removed rather than promoted into semantic authority.

OFFLINE BOOTSTRAP READINESS VALIDATOR VERIFIED; LATEST B4-F MEASURED RED.
`scripts/validate_bootstrap_manifest.sh` independently consumes a
`bootstrap_chain_v3` run directory and an explicitly trusted host compiler.
It rehashes live source/git/harness identity, run/cache identities, every
stage artifact and transcript, successful numeric B7 receipts, and producer
lineage before enforcing the normal two-stage build, no-worker policy, exact
plain/no-prelude semantics, and inclusive stage2 wall budget of <=300 seconds.
The focused validator group passes 27 examples, including post-publication
artifact tampering, semantically wrong or framed but rehashed transcripts,
forged/partial resource evidence, log/receipt mismatch, ambiguous wall rows,
wall/log mismatch, a relaxed caller budget,
lineage/build-policy or smoke-input identity violations, duplicate or symlink evidence, an
untrusted/non-executable host, a run path inside the source scope, and the
300.01-second negative. T8 is executable. Under the current policy, fresh s1
built in 19.60 seconds; s2 stopped semantically after 61.18 seconds at
`Hash::Entry(String, OptionParser::Handler) |
Hash::Entry(String, Proc(Signal, Nil))#value`, not at the time limit. That run
measures B4-F RED and identifies the next lowering contract; the current repair
must produce a new clean run before B4-F can turn green.

BOOTSTRAP EVIDENCE PRODUCER VERIFIED; B4-F REMAINS OPEN.
`scripts/bootstrap_chain.sh` now requires an absent run path and creates the
mode-0700 run directory and empty cache itself. It rejects semantic control
overrides, sanitizes known generic compiler/linker controls, and binds every
stage producer hash to the previous stable output. Stage artifacts, logs,
successful B7 receipts, smoke binaries, and exact plain/no-prelude transcripts
have regular-file/single-link checks and hashes in an atomic
`bootstrap_chain_v3` manifest, with a final revalidation before publication.
Source scope and run/cache identities are endpoint-checked. The focused
integrity/timing group passes 16 examples, including absolute, relative, and
symlink-parent paths into the source scope, and the scoped hostile review is
ROBUST. T8 now rehashes the receipt on disk and enforces <=300 seconds,
numeric resource coverage, normal build policy, and both stage2 semantics;
a real fresh run must still pass it before B4-F can turn green. B6 does not
prove absence of transient
mutate-restore events, external stdlib/toolchain closure, or safety against a
same-UID hostile writer.

RUN_SAFE ROOTED-ANCESTRY RESOURCE OWNER VERIFIED; B4-F REMAINS OPEN.
`scripts/run_safe.sh` now owns a versioned resource row and can publish it to a
new atomic evidence file that target output cannot impersonate. Numeric RSS is
admitted only when every scheduled visible-ancestry snapshot is valid; numeric
FDs additionally require full PID coverage and stable paired topology.
Malformed/unavailable `ps`, empty/malformed/partial `lsof`, and FD topology
fence failure/churn fail the affected metric closed to `unknown`. Malformed
bounds, pre-existing evidence paths, publication races, and target marker
spoofing have negative guards. A liveness-confirmed natural-exit fence now
aborts only its incomplete sample transaction instead of invalidating earlier
stable pairs, while a rootless snapshot of a live target fails closed. The
focused resource/process-tree group passes 19 examples, including timeout,
TERM-ignoring parent, nested
supervisor, and successful-parent descendant cleanup. This is the scoped B7
evidence owner consumed by the B6 manifest and T8 validator; it does not make
B4-F green and does not prove between-sample peaks, detached/reparented process
coverage, or aggregate cap enforcement when host probes are unavailable.

VERIFIED RECORD-MACRO INITIALIZER SLICE (bootstrap successor still open):
record-style macro assignments now retain their right-hand-side text when
`MacroValue#node_identifier_name` renders `AssignNode` values, so generated
initializer parameters keep their defaults. Generated `DefNode` parameter
recovery no longer reverse-scans retained sources by equal span. Each generated
definition is now paired with its exact macro output and arena in a sidecar;
missing or wrong-arena certificates fail closed to the raw-slice path. The
focused same-length foreign-source falsifier, record initializer/default
regression, full HIR **366/0**, macro **30/0**, LLVM backend **88/0**, and
`tuple_to_static_array_shape_repro_ok` runtime oracle are green. This is scoped
to `MacroExpander#expand` output-backed definitions; literal-only macro paths
without a certificate still conservatively fall back.

FORMER 180-SECOND B4-F / INCREMENTAL-SCAN RECEIPT: every compiler stage in
`scripts/bootstrap_chain.sh` is now supervised by `scripts/run_safe.sh`, and
the invalid Bash `break unless` in the wrapper is fixed. A source-matched fresh
s1 built in 21.58s and passed plain/no-prelude smoke. Its s2 timed out at the
then-current 180-second gate (script wall 182.59s, exit 143, no `cv2_s2`);
external snapshots grew from about 663 MiB to 1.20 GiB with FD count 12. This
was a compute/materialization performance RED under the former policy, not an
observed memory/FD runaway, and does not classify the current 300-second gate.

The default-off missing-scan shadow is observational only: production retains
the legacy full scan, budget prefix, and function-count stop. An initial
caller-only carry matched HIR tests but was refuted on the real self-host
workload at iteration 2 (`full=1280`, `shadow=1279`,
`full_only=Fiber#next`). The root contract error was dropping raw demands while
their targets temporarily had bodies or were in progress.

The shadow now keeps exact ordered raw and occurrence-time-admitted demand
segments per live HIR `Function#id`, removes segments for vanished function
identities, and recomputes both ordered vectors without probabilistic
fingerprints or flat backlog carry. Capturing admission at the call occurrence
is required: a later accessor/materialization in the same scan can change the
target body/state before an end-of-scan certificate is sampled. End-of-scan
target certificates still record body presence, lowering state, and queue
membership as invalidation telemetry. The exact queue snapshot is retained
after enqueue, and its metric is explicitly the post-enqueue-to-next-
post-process transition rather than a general queue revision.

Segment replacement/removal/order, monotonic function replacement identity,
occurrence-time admission versus later target state, target body/state/queue,
and bounded-budget regressions are green. The standalone exact-shadow group is
**5/0**; the isolated staged snapshot combined with its base HIR file is
**293/0** with two existing pending examples.

A source-matched bounded self-host gate is green through iteration 3. Exact
full/shadow raw counts were `420/420`, `933/933`, `4705/4705`, and
`12904/12904`; occurrence-admitted and selected counts matched at
`94`, `183`, `982`, and `2036`. All four rows reported `match=1`, and
mismatch count stayed zero. Iterations 1-3 observed the post-enqueue-to-next-
post-process queue transition with prior queue sizes 94, 183, and 982; the
comparison gate exited 0 after about 84 seconds before processing iteration 3.

A same-source cold-cache ON/OFF gate also reached the identical iteration-3
post-enqueue boundary (`funcs=19293`, `missing=2036`, `pending=2036`, exit 0).
Sequential `time -p` walls were 105.20s OFF and 105.16s ON (safe-wrapper child
intervals about 83s each), which is noise-bounded parity evidence, not a
speedup claim. The current source-matched s1 also passes the default-off
no-prelude smoke with the exact `hello world`, `n=42`, and
`noprelude_interp_ok` markers.

Do not promote this shadow to production authority or claim a speedup. Exact
segment changes are still discovered by the authoritative full scan, the
post-process terminal fixed point remains unproven, the A/B timing is
single-sample and cold-cache, and B4-F remains red. The next admissible step is
a mutation-owned function/body/state/queue revision source; repeat same-source
ON/OFF cost and parity at that boundary before using cached segments as
authority. Do not replace the full scan, add arbitrary pruning, or optimize
from raw function count alone.

GUARD-ONLY REVISION DIAGNOSTIC IMPLEMENTED; PRODUCTION PROMOTION REMAINS
REJECTED. Shared monotonic ledgers now cover module function-set/HIR-body,
function body/demand, function-definition/type, lowering-state, and pending-
queue mutations. The default-off shadow samples those eight coordinates before
and after the authoritative full scan and treats cold state, scan invalidation,
false reuse, exact mismatch, legacy function-count termination, and iteration
limits as inconclusive. The staged ownership census passes and the isolated
staged HIR gate is 301 examples, 0 failures, 0 errors, with two existing
pending examples.

The source-matched iteration-3 ON gate preserved exact full/shadow raw counts
of 420, 933, 4709, and 12909 and admitted counts of 94, 183, 982, and 2037,
with zero mismatches and zero false reuse. It also rejected every potential
reuse because the scan itself changed revision coordinates
(`revision_candidates=0`, `revision_scan_invalidated>0`). The matching OFF
boundary reached `funcs=19308`, `missing=2037`, and `pending=0`; single-sample
walls were 157.43s ON and 166.53s OFF and remain noise-only evidence, not a
speedup claim. The staged s1 default-off no-prelude regression is green.

Hostile verdict: ROBUST for the bounded observational guard, VULNERABLE for
universal mutation ownership or cached-scan authority. Public mutable HIR
views, include/class/RTA side metadata, the legacy raw function-count fixed
point, and an integrated same-scan accessor/union materialization falsifier
remain open. Next isolate scan-side mutations and add that integrated falsifier
before considering any production reuse.

RAW-LOCAL ATTRIBUTION DIAGNOSTIC VERIFIED; AVAILABILITY REPLAY REMAINS
REJECTED. The zero full-vector candidates were caused by temporal/global
poisoning: scan-side global bumps invalidate functions sampled earlier, while
enqueue/process changes global function-set/body/definition/type/state/queue
coordinates between iterations. A second default-off comparison now observes
only per-function body/demand input and labels every row
`scope=per_function_raw`, `authority=full_scan`, and `promotion=forbidden`.

The isolated staged HIR gate is 304 examples, 0 failures, 0 errors, with two
existing pending examples. The integrated union-accessor regression passes
through the real missing-call loop: an earlier bodyless
`Outer::Info#kind` occurrence stays admitted when a later union call
materializes the getter, then the next scan reports raw-local stability
together with changed availability. A seeded public `Call#method_name=` bypass
is detected as raw-local false reuse, qualifying the negative detector without
claiming universal mutation ownership.

The source-matched staged iteration-3 gate preserved exact full/shadow raw and
available vectors with zero raw-local false reuse. Raw-local stable counts were
603, 1539, and 7471 at iterations 1-3, while availability mismatches were 198,
345, and 984. This is evidence against promotion: local raw stability is common
but does not certify target availability. The staged compiler build, ownership
census, integrated F3 runner, and default-off no-prelude regression are green.
Next either design an explicit availability/order replay certificate or refute
that route before any production raw-segment skip. B4-F remains red.

PRE-SCAN AVAILABILITY REPLAY REFUTED; FULL SCAN REMAINS AUTHORITATIVE. A
default-off model now snapshots target body/lowering/queue state before the
scan, replays the canonical raw segment against that snapshot, and compares the
prediction with occurrence-time admission. It is labelled
`scope=pre_scan_target_snapshot`, `authority=full_scan`, and
`promotion=forbidden`; any model mismatch or stable false reuse keeps the
terminal verdict inconclusive.

The real same-scan union/accessor regression now runs both occurrence orders.
`direct T -> union materializer T` admits the early bodyless getter, while
`union materializer T -> direct T` materializes it before either occurrence can
be admitted. Both traces end with the same canonical target names and getter
body, but their available segments differ. The pre-scan replay model reports a
mismatch, and the focused helper independently detects an intervening target
materialization against a locally stable observer.

The isolated staged HIR gate is 305 examples, 0 failures, 0 errors, with two
existing pending examples. The source-matched iteration-3 gate preserved exact
full/shadow raw and available vectors. Its ordinary trace observed 603, 1539,
and 7471 stable pre-scan replays at iterations 1-3 with zero model mismatch and
zero stable false reuse. Those zeroes are orientation only: the targeted
two-order F3 counterexample is sufficient to reject universal replay authority.
The compiler build, ownership census, integrated runner, and default-off
no-prelude regression are green.

This is a bounded refutation of canonical per-segment availability replay, not
an implementation gap that one more target epoch can close. A sound route
would need pre-canonical occurrence provenance, side-effect position, ordered
function/block/instruction identity, resolver metadata, target-state
transitions, and RTA/worklist/budget order—effectively a replay transcript.
Next separate mutation-producing canonicalization from pure demand collection,
or design an immutable pre-canonical occurrence index and falsify it before any
production scan reduction. B4-F remains red.

PRE-CANONICAL OCCURRENCE IDENTITY/ORDER BOUNDARY VERIFIED; SEMANTIC REPLAY
REMAINS REJECTED. The default-off missing-scan diagnostic now takes a pure,
immutable `(Function#id, Block#id, Call#id, raw_name)` snapshot before any scan
canonicalization and compares it with the raw identities encountered by the
unchanged authoritative full scan. Owned rewrite plus insertion leaves the old
snapshot unchanged, changes the function demand revision, and makes a fresh
snapshot differ. The focused exact-shadow group passes 15 examples; the
revision ownership census and both-order same-scan union/accessor regression
pass. In F3, the immutable raw order remains distinct after both live calls
canonicalize to `Outer::Info#kind`; demand-first still admits two occurrences,
while materializer-first admits one, and the pre-scan availability replay stays
refuted/inconclusive.

A source-matched diagnostic stopped after iteration 3 in about 105 seconds.
Indexed/observed occurrence counts matched exactly at 7517, 11740, 41080, and
113005; full/shadow raw and available vectors also matched. This is traversal
identity/order evidence only: the same run retained 253, 621, and 1801
raw-stable availability mismatches at iterations 1-3. The index does not carry
argument/block ABI, canonical target identity, resolver metadata, target-state
transitions, or class/include/enum/RTA state, so it cannot authorize replay or
a skipped scan. The run is diagnostic overhead, not a B4-F or speed
certificate. Next classify a read-only per-occurrence transcript of
canonicalization side effects and falsify resolver purity before considering
any reuse. B4-F remains red.

VERIFIED CONSTRUCTOR NAMED-ARGUMENT SLICE (produced-stage successor still
open): source-backed lazy lowering collapsed
`NamedSlotProbe.new(third: 30)` to `NamedSlotProbe.new$Int32(%30)`, so the
allocator forwarded `30` into the first optional initializer slot. Ordinary
function named arguments already preserved their slots, which localized the
defect to class-literal auto-allocator selection rather than parser storage or
general named-argument lowering. Auto `.new` calls now bind against the
resolved `#initialize` parameter names before allocator materialization.
Direct, inherited, and module-extended explicit class-level `new` definitions
retain their one-argument route; their tests deliberately define a conflicting
four-slot initializer so a mistaken allocator route cannot pass by symbol
coincidence. Eager class-method lowering also verifies
`self.new(third: 30)` expands to the four-slot auto allocator.

The focused source-backed examples pass, the complete HIR file passes 288
examples with zero failures/errors and two existing pending examples, and a
source-matched original-Crystal-built host passes
`regression_tests/named_arg_optional_slot_order_repro.sh`: compiler and
produced binary both exit 0 with
`named_arg_optional_slot_order_repro_ok`. The scoped Adversary verdict is
ROBUST for optional-slot auto constructors and the tested explicit-new routing
boundaries.

B4-F was independently MEASURED RED for that slice under the then-current
180-second policy. The infrastructure-corrected fresh chain built s1 in 14.98
seconds and passed exact plain and no-prelude s1
smokes, but s1-to-s2 hit the 180-second safe-run limit (script wall 182.52
seconds, 1,331,216 KB RSS, exit 143) without a `cv2_s2`. A separate
non-acceptance 300-second diagnostic also timed out (2,048,080 KB RSS) without
an artifact. Therefore no produced-stage constructor or callback-ABI claim is
made from this slice, and the callback parameter-scan change remains
IN_PROGRESS behind B4-F despite its historical LLDB root evidence.

CURRENT R0 FRONTIER (architecture admitted, production fix still open): the
current dirty source is sealed reproducibly at base
`c216b9ef66f9c8360278304f684299879ca67392`, tree `1efb635...`, and exactly
seven tracked compiler/spec paths under patch SHA-256
`d7ad2cacb1472d07daf6cc5793bce52a1940ed967bfce2a2322d67a291a967fc`;
snapshot diff-check passes. Manifest:
`/private/tmp/adamas_r0_current_c216_manifest.md`.

Host spawn preflight is GREEN. Under the former 180-second policy, a fresh
`--stages 2 --timeout 180 --mem 12288` chain built `s1` in
14.13s; its plain smoke prints `42` in 20.29s and its no-prelude smoke prints
the exact `hello world` / `n=42` / `noprelude_interp_ok` markers in 0.65s.
The `s2` self-host build is compiler-side performance RED: timeout exit 143,
stage wall 182.54s, externally sampled peak RSS 1361.03 MiB, no `cv2_s2`;
outer chain exit 1 at 219.32s. Stage2 semantic smokes are unavailable because
there is no artifact, not semantic red or green. The host-infrastructure
blocker is refuted. This receipt is red under the former 180-second cap but
does not measure the current 300-second policy. R0 promotion remains blocked
by B4-F and the missing same-source fresh T0 A/B. T8 is an executable
falsifier, but no fresh current-source run has passed it. Historical
231.37/251.91/253.42-second both-smoke receipts fit the numeric budget but
remain stale and cannot certify current source.

SEALED-CURRENT STATS-ON LOCALIZATION (diagnostic only): from the disposable
worktree, the only compiler instrumentation flag was `ADAMAS_PHASE_STATS=1`:
`ADAMAS_PHASE_STATS=1 /usr/bin/time -p scripts/run_safe.sh
/private/tmp/adamas_r0_current_c216_out.8teyio/cv2_s1 180 12288
src/adamas.cr -o
/private/tmp/adamas_r0_current_c216_phase_stats.F9HAyu/cv2_s2`. It timed out
with exit 143 at 182.60s and produced no `cv2_s2`; peak RSS was not captured.
Completed phases were `process_pending` 218 -> 591 (+373) in 555.2ms and
`emit_tracked_sigs` 591 -> 604 (+13) in 235.0ms. The first open phase was
`lower_missing.initial`; its internal passes grew 604 -> 1535 -> 7422 ->
19238 -> 28234 (+27,630 from 604) before timeout, with no phase completion,
timing, or normalized top-prefix. Log SHA-256:
`1cc025cc5930ebd0513382e68dbb400e763002186f227288683d6bc710f79ecd`.
This revalidates/evolves the 2026-04-29 `lower_missing.initial` localization;
the old and current observation definitions differ, so no exact improvement or
regression delta is admitted. Stats-on versus uninstrumented timing is also
diagnostic-only. The current classification is a high-confidence hypothesis
of string-keyed replay/materialization amplification, not causal proof.

The first typed materialization falsifier was RED before `b562b680` on the
focused compiler and historical G9 stage1. Original Crystal lawfully specializes
`Array(ArenaLike)#push` by the actual expression type, so concrete
`push$AstArena` is not itself a bug. The real invariant is continuity from the
selected `Def`/typed instance through coercion, receiver/value arity, body, and
emitted symbol. The focused HIR guard is now green: the explicit-union append
returns `Array`, and concrete `AstArena` reaches the selected concrete
specialization without premature union wrapping. Historical full-G9 LLVM
evidence additionally contained one zero-argument call and one zero-argument
unreachable definition for that `push` target; it is stale until reproduced
from current source. A source-bound stage1 from `6772e562` exposed the current
HIR defect: `exact_lookup` rewrote requested concrete `push$AstArena` to the
union target/body. The bounded exact-reserialization rule and base guard keep
stale/shape-mismatched requests fail-closed. Candidate `4d6c37ac...` preserves
concrete requested/target/materialized names through
`instance_class_info_lower_method`; focused T9 HIR plus typed MIR/LLVM ABI, 43
focused examples, 617 other fast HIR examples (2 existing pending), and
union-value runtime storage pass.
See `docs/compiler_architecture_sdd.md` section 0 for the scoped receipt and
baseline exclusion. The full-source receipt is HIR evidence only; the focused
reducer separately certifies the current HIR/MIR/LLVM corridor. Neither is
compile success or a current full-G9 certificate, and both expire when source
or candidate changes.
The attempted STABLE6 in-process callsite-owner prototype is now refuted and
is not an admitted route. Do not add another large owner or new `AstToHir`
ivars. The next safe route follows this exact concrete symbol through
full-source MIR and LLVM emission once B4-F reachability allows it; the focused
concrete/union control already guards the generic downstream corridor. External
telemetry alone is insufficient authority.
Join actual semantic-instance/body creation, queue growth, wall time, and RSS
before choosing the smallest behavior change. The external analyzer must be
bounded and streaming. Do not fix this by forcing all calls to the union
specialization or by reducing raw function count alone.

CURRENT STABLE6 FRONTIER (refuted in-process prototype, not admitted): the
attempted private `MaterializationReplayShadow` used a typed numeric
`CallSiteRef`, explicit statuses, a composite typed HIR request-shape index,
bounded logs, owner-local scratch, and a final read-only scan. It added no
`HIR::Call` field and changed no fixed-point, queue, lowering, or routing
behavior, but the prototype is removed from main code and preserved only in
`/private/tmp`. Default-OFF is not zero compile-time cost; strict assertion is
not an admission path.

Scoped local evidence remains simple OFF/ON HIR/runtime parity, focused
**17/0**, baseline HIR **286/0 with two existing pending examples**, host
build, and a local adversary verdict **ROBUST** for those checks only.
Full-prelude/union telemetry is intentionally red/noisy and must not be
combined with the separate similar plain run: the audit reducer observed about
**2673 registered, 2568 agree, 404 mismatch, 1 stale, 199 untracked required,
225 unjoined, 1 ambiguous, and 11377 calls**. These are orientation-only proxy
counters; they do not prove duplicate semantic instances or speed.

The system discriminator overrides local admission. On frozen pre-shadow
`c216b9ef...` plus `d7ad2cac...`, phase-stats only timed out at 180 seconds
(`run_safe` exit 143), produced no `s2`, and grew **604 -> 1535 -> 7422 ->
19238 -> 28234 (+27630)** without stack overflow; repeat-control log prefix
`e568...`. With the same binary's STABLE6 ON and OFF, both produced no `s2`
and hit exit 11 stack overflow in `declared_type_match_score`/alias/type-name
work during `lower_missing` p0 around **#800** (ON about **141s**, OFF about
**139s**), with identical growth **604 -> 1544 -> 7430 -> 19246 -> 28369
(+27765)**. ON/OFF log prefixes are `18603d...`/`51146a...`; RSS is
unavailable. ON final-scan-i4 orientation was
`registered=27363`, `agree=42801`, `mismatch=484`, `unjoined=4459`,
`ambiguous=300`, `no_mat=12864`, `calls=60909`, `not_yet=1`.

This is not causal proof of the compiler root, but admission is rejected
because runtime-OFF changes the self-host source/workload and failure class.
The whole-system Adversary verdict is **BROKEN for admission**, despite the
local parity verdict. T1 remains **MISSING** because HIR `TypeRef`/name shape
is not semantic identity. B4-F (<=300 seconds) remains unmeasured/open and no
speed claim is made. Keep the context bridge explicit: `StaleCallSite`,
`UntrackedRequiredCallSite`, and `StaleTransactionRef` are distinct meanings.

VERIFIED STABILITY SLICE (bootstrap successor still open): `PageArena` stored
pages as `Array(StaticArray(TypedNode, 1024))`. Because `StaticArray` is a
value type, `@pages[page_index]` returned a copy; nested assignment populated
that temporary while the owned page retained an uninitialized node slot. The
focused pre-fix `PageArena` spec failed on the first add/fetch with an invalid
node/vtable breakpoint, and the prior HIR seed 6003 crash in
`collect_defined_instance_method_full_names(..., PageArena)` was the same
storage defect rather than a scan-cache identity failure. Pages now use
reference-backed `Array(TypedNode)` carriers with fixed capacity 1024 and
sequential append, preserving GC-visible node ownership without uninitialized
union storage. Focused PageArena tests cover heterogeneous nodes, indices
1023/1024, safe invalid/out-of-bounds lookup, and strict out-of-bounds lookup.
They pass 3/3; the formerly crashing HIR example passes 1/1; the complete HIR
file passes 259 examples with 0 failures/errors and 2 existing pending under
seed 6003; the arena-union ABI spec passes 1/1. This closes the PageArena
storage contract only. Production parsing remains forced to `AstArena`, and
the latest 900-second s1-to-s2 timeout was measured on an older source state;
neither s2b nor later bootstrap stages are claimed green from this slice.

VERIFIED ALLOCATOR BODY-STATE SLICE (bootstrap successor still open): allocator
fallbacks previously treated `FunctionLoweringState::Completed` or a
declaration-only HIR function as proof that an initializer body existed. In an
isolated HEAD worktree, the typed-initializer reducer was RED because the
selected initializer remained bodyless, and the abstract-initializer reducer
was independently RED because a failed rematerialization left stale
`Completed` state. One shared `rematerialize_missing_function_body` transaction
now gates all three allocator fallback sites on authoritative body presence,
marks recursive entry `InProgress`, and keeps `Completed` only when a body was
actually produced. Both focused examples pass, and the isolated B-state-only
HIR file passes 250 examples with 0 failures/errors and 2 existing pending in
default order and under seed 6003. This does not admit the adjacent nilable-tail
ABI specialization, enum provenance, constructor source-order, indexed-loop,
or LLVM carrier changes that remain dirty and independently unverified.

VERIFIED ALLOCATOR OPTIONAL-TAIL HIR SLICE (bootstrap effect still open): a
generated allocator overload named from a concrete member of a declared union
kept the declared union in its own HIR parameter and forwarded call spelling.
On clean `97fb159d` plus only the two focused examples, the concrete
`String` case was RED (`TypeRef::STRING` expected, union id 33 observed).
Allocator overload parameters now specialize only when the call type is an
actual direct union member; initializer spelling follows the same bounded
rule, while a colliding typed name is reused only when it retains the selected
`DefNode` identity and visibility. Concrete String, Nil, omitted-default, and
named-only collision cases pass. The isolated B-ABI-only HIR file passes 252
examples with 0 failures/errors and 2 existing pending in default order and
under `--order 6003`; `git diff --check` is clean. A separately rebuilt host
compiler also passes the no-prelude optional-tail reducer, but the clean host
already passed it. Therefore the reducer is a non-regression signal, not a
RED-to-GREEN runtime oracle. Dynamic union values, larger unions, inheritance,
and splat interactions remain unproven, and no produced-stage or s1-to-s2
bootstrap claim is made from this internal HIR-shape correction.

VERIFIED ENUM IDENTITY HIR SLICES (bootstrap effect still open): generated
typed accessors now retain source-backed enum provenance even when their enum
is registered later, and explicit methods clear stale generated metadata.
Zero-argument union lookup materializes only a registered accessor backed by
an actual ivar; arbitrary bodyless function registrations remain rejected.
Same-enum ternary branches also transfer enum identity to their phi, while
mixed-enum branches do not. In an isolated clean-HEAD run, typed getter, late
sibling enum, nilable-union getter, and same-enum ternary examples were RED;
the explicit-override, bodyless-method, and mixed-enum negatives were already
GREEN. With only the enum hunks all seven focused cases pass, and the complete
HIR file passes 259 examples with 0 failures/errors and 2 existing pending in
default order and under `--order 6003`. Accessor provenance and zero-arg union
materialization are dependency-coupled; ternary phi propagation is a separate
transaction. No direct no-prelude generated-stage reducer was found, so no
bootstrap transition is claimed from these HIR proofs.

VERIFIED LLVM DEFAULT-ARG CARRIER SLICE (bootstrap effect still open): omitted
default arguments triggered a pointer-to-scalar expansion based only on LLVM
types. `Nil`, references, raw pointers, and actual inline structs all share the
`ptr` ABI, so the old rule could read null/object memory as flattened fields and
shift every later argument. On clean `6b9ac1dd` plus tests only, a Nil carrier
was RED with generated `struct_expand` loads from `%owner_nil`, and a zero-sized
Struct was independently RED; the nonzero Struct positive was already GREEN.
Expansion now requires registry-backed nonzero `Struct` or `Tuple` identity in
addition to the existing LLVM/gap checks. All three focused cases pass and the
complete LLVM backend spec passes 84 examples with 0 failures/errors. MIR
NamedTuple maps to Tuple; Reference, Pointer, Union, Nil/Void, and unregistered
pointers are excluded. StaticArray normally remains a zero-sized Struct with
dedicated layout and is excluded, but a future nonzero StaticArray or malformed
Struct/Tuple descriptor is residual taxonomy risk. No bootstrap stage is
claimed from this backend-local proof.

CURRENT CHANGE — concrete value-owner and class-header admission (bounded,
2026-07-14): the root cause crossed the HIR→MIR boundary. HIR final virtual
repair could admit concrete value owners through stale `ClassInfo.is_struct`
metadata, while MIR direct, fallback, module/generic, abstract, and nested
union paths could reuse or create class dispatchers for receivers without a
runtime header. The finite cross-phase invariant is now explicit: a
non-tagged class receiver may enter class virtual repair or class dispatch only
when its authoritative type is runtime-header-backed; inline
Struct/Tuple/NamedTuple/Primitive/Pointer/StaticArray values are filtered before
repair, cache reuse, or dispatcher creation. Tagged/mixed unions remain on
their union-dispatch path.

RED signals on the old behavior included HIR child-wrapper recreation, MIR
Int32 direct/fallback admission, abstract synthesis candidates
`[5,57,58,59]` instead of `[57]`, module candidates
`[58,5,59,60]` instead of `[58]`, nested-union candidates
`[52,53,54,5]` instead of `[52]`, and a stale invalid-root
`__vdispatch__Value#fallback$T34` artifact. The focused HIR/MIR seams are GREEN;
the full HIR file is 248 examples with 0 failures/errors and 2 existing
pending examples, and the full MIR file is 30 examples with 0 failures/errors.

The one bounded fresh original-host census used s1 SHA-256
`72536d42845af7dca662841ceda5c0465ebd9775d0fcd4f6c51b0dcd2713ec83`, host
release build wall 667.54s, and a collector gate with rc 0 and real wall
66.17s. Authoritative request totals moved from the prior raw 5,945 to 2,597
(-3,348, -56.3%); `resolved_body_preserve` moved from 1,034 to 0; appended
owners classified as concrete values were 0 (assertion true). The temporary
HIR census observed 9,415 child-filter attempt events, led by
`Pointer|Pointer=4641`, `Struct|Hash::Entry=1883`, `Struct|Slice=350`, and
`Struct|Set=147`; these are repeated attempts, not unique owners. The prior
broad Object/Reference total 5,911 and this run's child-only total 2,563 use
different definitions, so no exact broad delta is claimed. No full s1→s2
bootstrap claim is made. Residual risk remains in the separate HIR direct
Pointer/StaticArray static-call guard and the surviving lookup-nil/missing-body
reference tail.

CURRENT ACTIVE FLOOR (newest): clean HEAD `ae741456` and a fresh
original-Crystal-built s1 (SHA-256
`7f5799c0c3b411e1719e3bef4e944c4b81606deb8a985c7a625318ec15c54a22`)
do not hang in the initial missing-demand pass, deferred allocators, or the
first final missing-demand pass. The phase gates complete at 48,156 functions
in about 212 seconds, 48,366 functions in about 220 seconds, and 48,498
functions in about 224 seconds respectively. The next gate, immediately after
`repair_missing_concrete_virtual_targets`, does not complete in the former
420-second envelope.

The non-executing final-repair collector is the current factual boundary. It
sees 875 recorded shapes, 564 with a surviving caller, and admits 5,762 repair
requests: 14 roots and 5,748 child owners. Of those requests, 3,014 are direct
declarations and 2,748 are inherited or unresolved; 5,562 candidate names have
not started lowering. Executing the first 20 requests takes 561.7 ms and adds
24 real function bodies. The early sample contains several Array/Hash `hash`
targets, but it does not prove that method family is the global root. The
measured pattern is a mass materialization cost, not one pathological request
or another `lower_missing_call_targets` fixed point.

Two tempting routes are currently refuted. Restricting the missing-demand scan
to main-root reachability and a reachable-allocation fixed point improved small
reducers but did not move three authoritative full gates; that experiment was
fully reverted. A host-unit `KeyHash(K)#key_hash(key)` fixture retained its
concrete key type and did not even record the broad virtual demand required by
the hypothesis, so it was removed rather than accepted as a false RED test.

The unmodified 900-second completion falsifier is now RED: the same fresh s1
timed out with exit 143, 12 file descriptors, no s2 artifact, and the same last
normal lower-main/deferred-allocator lines. The safe wrapper's internal progress
counter reported about 714 seconds; that counter excludes monitor-probe time
and does not weaken the real 900-second wall-clock timeout.

NEXT: add a pure test seam around final-repair request collection/execution and
make the stale-snapshot hypothesis measurable. In particular, a request admitted
before another request restores a shared resolved body must be revalidated before
paying for lowering; the test must count actual repair executions, not merely
assert the unchanged final function set. If that does not materially reduce the
authoritative request/run boundary, pivot to richer receiver-flow provenance.
Do not prune by method name, owner-count threshold, or an inferred
`Hash#key_hash` special case. Keep heavy self-host runs delegated and bounded;
use focused `spec/*` tests as the fast regression layer before every new
bootstrap attempt.

VERIFIED PHASE FIX (bootstrap successor still open): final repair now
rechecks the same candidate-body and resolved-body predicates immediately
before each lowering. A focused Parent/ChildA/ChildB fixture is RED without
the guard (`expected 1, got 3`) while proving that only the restored Parent
body survives; with the guard it executes one repair and keeps both inherited
child wrappers absent. The complete HIR spec file passes 243 examples with
zero failures or errors and two existing pending examples. This establishes
stale redundant work and local semantic preservation. A fresh original-built
s1 is 44,315,920 bytes with SHA-256
`b7ef111dc7ae508e88741c7eb03ffb24c7f62676d95ff9b77c457642866e0255`.
Its ordinary post-virtual-repair gate exits 0 at 54,655 functions with 1,468
pending entries (wrapper progress about 418 seconds); the same boundary was
previously unreachable. The legacy execution-probe branch bypasses the new
helper and is not a post-fix oracle.

BOOTSTRAP SUCCESSOR: the sole unmodified full run of that s1 still times out at
900 seconds with exit 143 and no s2 artifact. The final-repair gate proves the
old floor moved, while the remaining 1,468-entry `final_missing`
`process_pending_lower_functions` pass is now the leading bounded hypothesis,
not yet a verified exact stop point. NEXT: use
`ADAMAS_PENDING_PROCESS_CONTEXT_FILTER=final_missing` with the existing
pass/first-item/pass-items-done stop gates. Do not repeat a full build until the
pending corridor is localized and a focused spec or falsifier moves it.

CURRENT ROOT SLICE: `Hash#key_hash` accepted a generic `Tuple#hash` target after
checking only the live `Crystal::Hasher` parameter. A concrete
`Tuple(String, UInt64, UInt64, Int32)` key and a bare `Tuple` receiver both map
to LLVM `ptr`, but they do not share element metadata or byte geometry. The
backend could therefore call a generic body that reads the concrete key with a
default/stale tuple layout. A RED backend spec now constructs exactly this
receiver mismatch. The accepted boundary requires an equal receiver `TypeRef`;
when no compatible target exists, a compact direct fallback handles only the
compiler-hot `Tuple(String, UInt64, UInt64, Int32)` shape through
`LayoutContract.tuple_slot_layout` rather than falling through to the bare
generic body. Other Tuple and NamedTuple shapes stay on their typed paths.

The admitted fallback uses byte offsets `0/8/16/24`, loads
`ptr/i64/i64/i32`, hashes String through its concrete
`hash(Crystal::Hasher)` target, reduces UInt64 like `Hasher.reduce_num`, and
permutes the scalar leaves. The focused RED test and the full backend file pass
80 examples. A fresh host s1 (`b14ef801...`) compiles and runs an exact produced
reducer with independently allocated equal String values; observed values are
`true, 17, 17, 29, 2` (the produced `puts` path concatenates them).

The nested-map carrier from the previous candidate is removed. The original
exact `{String, UInt64, UInt64, Int32}` cache key is restored because nested
maps, scalar-id tuples, bounded buckets, and composite String tokens all missed
the practical self-build gate or weakened identity/complexity guarantees. The
cache specs now cover nine distinct body and arena identities, class/instance
isolation, copied Set results, and version invalidation; focused cache specs pass
4 examples and the full HIR file passes 242 examples with two existing pending.

BOOTSTRAP STATUS REMAINS OPEN: the final source-matched s1 timed out while
building s2 at 420 seconds (exit 143, no s2 artifact). A bounded HIR cross A/B
then timed out identically at 300 seconds for both old-s1/current-source and
current-s1/old-source. The required old-s1/old-source control succeeded in the
same environment: exit 0 after about 101 seconds inside `run_safe`, producing a
91,804,121-byte HIR artifact. This refutes environment or timeout drift and
shows that both the current source shape and the current running compiler state
can reproduce the slowdown relative to commit `5e44ccfa`.

NEXT: localize the semantic source delta before another production change. The
HIR file differs from `5e44ccfa` only by comments and formatting of the same
cache key; the only production semantic delta is the bounded tuple-hash ABI
patch in `llvm_backend.cr`. Use source subtraction or a minimal syntax/shape
falsifier for that method under the retained old compiler. Do not raise the
timeout, repeat the full self-build, or claim that the defined-method cache
floor is closed.

REFUTED ROUTES: composite String token, nested Hashes, bounded/linear buckets,
scalar class-id tuples, receiver guard alone, and the pre-adversary direct tuple
hash path. The
object-id lifetime invariant remains: body and arena owners must stay live until
the module-defs version advances and clears both caches.

The Arena-union optional-index floor is CLOSED at its parser root. The source
form `arena.[]?(root_id)` entered `parse_member_access`, but the empty dotted
brackets were sent through the ordinary indexing path. That produced a
zero-argument `arena.[]?()` followed by a call on its nullable result, losing
`root_id` before HIR method materialization. The parser now recognizes the four
parenthesized dotted operator forms `[]`, `[]?`, `[]=`, and `[]?=` as explicit
member calls. Suffix punctuation must be lexically adjacent, so
`obj.[] ? (a) : b` remains a ternary and `obj.[] = (index, value)` remains an
ordinary index assignment.

CURRENT EVIDENCE: all 83 parser spec files pass (2,193 examples, zero
failures/errors/timeouts). A phase-local HIR spec proves the Arena-like union
emits exactly one virtual `#[]?` call with one `ExprId` argument and no
result-side `#call`. A fresh source-fingerprint-matched host s1 emits that same
shape for the no-prelude probe, and the resulting s1-produced s2 compiler
builds successfully (SHA-256
`8f7e2fe9698534523737087df7cdf4062d4c16af0c1d7d42a369443f20f0cbd3`).
The full HIR sweep remains independently non-green on two
pre-existing files (`as_question_try_spec.cr` output formatting and
`generated_runtime_integration_spec.cr`); neither failure involves this parser
shape. This closes explicit indexer argument transport only; s2b is still NOT
accepted.

CURRENT FLOOR: the fresh s2 compiler now segfaults with exit 139 in about one
second while compiling `stage2_io_puts_bare_oracle.cr`. No consumer binary is
produced. This is the first fail-loud successor after the parser correction;
its owner edge is not yet localized. A host phase-local characterization now
exercises the real `ExprId(Int32)` carrier across all three Arena variants:
HIR has one direct argument, MIR has a two-argument virtual dispatch and three
two-argument variant calls, and LLVM maps receiver plus `ExprId` consistently
to `(ptr, ptr)`. This refutes a general host HIR-to-MIR arity or per-variant
LLVM ABI mismatch. Do not infer that the successor is another union
materialization defect, add a stub, or use debug STDERR probes that can perturb
self-hosted inference.

NEXT: preserve the parser/HIR/MIR/LLVM specs as the fast regression layer, then
obtain a non-perturbing source-matched ownership signal for the new immediate
generated-stage-only segfault. Localize the earliest lost owner/type/arena
boundary before changing production code or paying for another full s2 rebuild.
Do not start s3b until s2b passes the existing structural and runtime gates.

TEST FEEDBACK HARDENING: `run_all_specs.sh` now keeps ordinary specs ahead of
the two known expensive generated-stage files while preserving deterministic,
NUL-safe sorting within both classes. This prevents
`produced_stage_bootstrap_spec.cr` from hiding early unit-spec failures in the
default single-worker run. It is intentionally scheduling order only: with
multiple workers, expensive and ordinary files may still overlap, and compiler
provisioning can still happen before spec execution.

The latest generated-stage constructor-routing defect is CLOSED at its
call-shape transport root. Named arguments reached allocator materialization as
only a boolean flag, so overloads with the same positional types could not be
distinguished by parameter name. In `Set(T)`, that allowed the protected
`using_hash` initializer to replace the public `initial_capacity` initializer.
Allocator generation now carries the exact named-argument names through eager,
pending, and lazy materialization and includes them in `.new` compatibility.
An order-adversarial HIR spec places the protected overload first and proves
that `Set(T).new(initial_capacity: 7)` selects the public body.

CURRENT EVIDENCE: `spec/hir/ast_to_hir_spec.cr` passes 235 examples with zero
failures/errors and two existing pending examples. A fresh host s1 and its
generated s2 both build successfully. The generated LLVM contains no exact
bare `$ExprId` type and routes `Set(String/UInt32).new(Int32)` to the matching
public `initialize(Int32)` bodies. This closes constructor call identity only;
s2b is still NOT accepted.

SUCCESSOR NOTE: the optional-index symptom described at this checkpoint was
later localized to the parser split documented above, not to union method
materialization. Keep the constructor-routing evidence, but use the newer
parser landmark as the active floor.

Previous update: 2026-07-12 (current bootstrap audit and produced-stage boundary).

The previous `Array#find` abort/stub floor advanced, and the successor
`br i1 null` floor is CLOSED at its authority-transport root. Generated HIR for
`Hash(Void, Void)#any?$block` and `Range(Int32, Int32)#bsearch$block` contained
valid `Yield` instructions, but `lower_method` discarded each source
parameter's `is_block` bit when it created the HIR `Parameter`. `lower_yield`
therefore emitted no explicit target, and HIR-to-MIR tried to rediscover the
callback through self-host-sensitive Proc descriptors and String suffix logic.
The finalized target lowered to `const_nil`, then LLVM emitted `br i1 null`.

The fix keeps a parallel `param_info_is_blocks` lane in `lower_method`, passes
the bit to `Function#add_param`, and records the marked function parameter on
each HIR `Yield`. Fresh produced HIR now has `%1 [block]` and
`yield via %1`; the old invalid LLVM branch is no longer reached. Host HIR is
green at 194 examples, 0 failures, 2 pending. A fresh host s1 and s1-produced s2
both build successfully. IMPORTANT: s2b is still NOT accepted. Both the
reference Array-find/next fixture and the TypeRef Set threshold fixture now
advance to a shared `Trace/BPT trap` (exit 133) before target LLVM emission.
The old `lower_main`-tail attribution is now refuted. A fresh retained s2 reaches
the caller-side `pass3 after lower_main call` marker and exits 0 at
`ADAMAS_STOP_AFTER_LOWER_MAIN`; all stop gates through HIR flush, type refresh,
RTA, final HIR, MIR registration, MIR prepare/body lowering, and final MIR also
exit 0. The uninterrupted default-worker and workers=1 paths still trap with
exit 133 before the first observable LLVM-entry marker. These early-return
gates are potentially perturbing in a self-hosted compiler, so the current
frontier is the post-MIR-to-LLVM-entry corridor, not yet a specific statement or
return ABI. `ADAMAS_NO_EXIT_FLUSH=1` does not move the floor, refuting the
synthetic STDOUT/STDERR fall-through flush as the trigger.
LLDB localization is currently unavailable because this machine cannot find
`debugserver`.

REJECTED CURRENT-LEVEL ROUTES: preserving an included-module body silently
selected unresolved generic `Enumerable(T)` semantics and was reverted;
parameter-only `@value_map` recovery did not move the floor and was reverted;
MIR-side `$block` recovery through both `String#ends_with?` and direct ASCII
suffix checks still produced `target=nil` and was reverted. These falsifiers
establish that late rediscovery is the wrong ownership boundary; HIR must carry
the callback identity explicitly.

TEST/ORACLE HARDENING: `compare_bootstrap_stages.sh` can compare only the first
two stages before s3 exists. Its normalizer no longer collapses all SSA ids,
generated callback/cell ids, typed ids, or numeric constants into one token;
those substitutions could declare different def-use graphs equivalent. The
normalizer now removes path noise only, with focused specs. `run_safe.sh` no
longer leaves its watchdog holding captured pipes, but its nested-supervisor
process-tree spec remains genuinely RED: a descendant heartbeat continues after
the outer wrapper exits. Process-group and single-process `setsid` experiments
were falsified and reverted; do not claim the full suite green until a real
session supervisor/descendant cleanup mechanism closes this gate.

NEXT: add one non-perturbing owner-edge/falsifier around the post-MIR-to-LLVM
entry corridor; do not continue lower-main marker churn or infer a root from a
stop flag that changes control flow. Then run the entire produced-stage
capability matrix and strict
s1_bootstrap-to-s2b HIR/MIR/LLVM comparison. Do not start s3b until s2b passes
those gates.

Updated: 2026-07-10 (session-28: typed-pointer preservation is VERIFIED, while
the next produced-stage crash is still OPEN. `Pointer(T).null` was lowered as a
cast to bare `Pointer`, so a Kqueue-shaped `pointerof(ts)` / null branch could
manufacture a pointer union and lose the concrete pointee type. Static member
lowering now resolves and interns the full `Pointer(T)` descriptor. Host HIR
guards cover `pointerof`, nested `Pointer(T).null`, their phi merge, and the
Kqueue shape; a generic `Hash(K, V)` pointer-ivar guard requires specialized
`Pointer(Hash::Entry(String, Nil))` plus `PointerLoad`, and rejects a synthesized
`Pointer#[]` call. The central MIR union-storage classifier and its ABI/backend
specs remain the representation contract.

REJECTED ROUTES: globally collapsing pointer unions by erased runtime
representation changed valid typed-pointer/header semantics and made
`Hash(String, Nil)#get_entry` degrade to bare `Pointer`; it was reverted.
DefNode/arena sidecars (including atomic paired registration and append-only
variants) perturbed self-compilation into recursive `resolve_type_name` stack
overflow and were reverted. Name-cache early return and exact lookup-key cache
transport variants survived host specs and fresh self-builds but did not change
the untraced produced-stage failure; all of those production changes and their
unit helpers were reverted.

CURRENT FLOOR: a fresh stage2 self-build exits 0, then compiling even the
no-prelude generic pointer-ivar fixture exits 139 in
`DefNode#params -> build_param_infos -> function_param_infos ->
seed_function_param_caches -> prime_param_caches_for_discovered_def`, reached
from `process_pending_lower_functions / lower_missing_call_targets`. An LLDB
conditional breakpoint decoded the failing requested/target name as bare
`[]$Int32`; its DefNode is null-like at the parameter read. Built-in lookup
diagnostics report branch `unknown`, and the mangled-prefix scan is not entered.
NEXT: trace where the owner is lost while producing/enqueuing this bare operator
demand. Treat the null-like DefNode as a downstream registry symptom; do not add
another stub, DefNode sidecar, base-name cache heuristic, or stdlib workaround.
The produced-stage bootstrap spec is intentionally red at this floor and is the
durable regression gate. Prev below.)

Previous update: 2026-07-09 (session-27c: deep stub census split the recurring symptom
into a fail-loud backend funnel plus multiple upstream roots. One root is now
CLOSED: specialized literal/dynamic `Array#map` and `map_with_index` lowered a
user block without an `InlineNextContext`, so block-local `next value` became a
`Return` from the enclosing compiler method. In `fixup_call_arg_types`, the
first literal argument executed `next part` and returned only that first string;
HIR and post-opt MIR still contained every call argument, but generated LLVM
called two-parameter functions with one argument. The map lowerers now merge
normal and `next value` iteration results through an explicit typed exit/phi,
including structural tuple coercion. Empty-incoming merges remain dead instead
of reviving an all-noreturn block. A paired loop-depth stack arbitrates lexical
ownership when an outer map with local `next` contains an inner loop, and all
function/proc isolation corridors save/reset/restore it with the loop stack.
VERIFIED: old host compiler fails the dynamic/literal/map_with_index family;
current host and fresh stage2 pass that family plus both nested ownership
orders, `case/in`, all-noreturn, raise-fallthrough, and tuple-phi adversaries;
fresh stage2 self-build succeeds and preserves both arguments in top-level and
instance reducers; full suite 165/165 + 36/36. IMPORTANT BOUNDARY: this is not a
universal block-control fix. `compact_map`, block-`sum`, `reduce`, and
block-`count` still lack an explicit lexical result context.
REPEATED-OWNER ROOT is now PROVEN, but the production fix is BLOCKED. It is not
stringly requalification: it is the already-known L10 phi-shared-slot lifetime
violation recurring in `lower_call`. Probe D sees
`method=unsafe_mod, full=UInt8#unsafe_mod`; the multi-arm valued-if that computes
`base_method_name` feeds the still-live `method_name` into a shared phi carrier;
legacy sharing lets the selected full name overwrite that incoming; probe E
therefore reads `method=UInt8#unsafe_mod` without a source assignment, and the
resolver lawfully adds `UInt8#` again. The discriminating build
`ADAMAS_PHI_SHARE_VETO_FILTER=lower_call` keeps D/E bare and removes all 8
repeated-owner stubs (8 -> 0), proving mechanism and excluding parser,
`specialize_method_owner_name`, and backend name emission. DO NOT SHIP that
filter yet: although stage2 self-build succeeds, the output repro advances to
undefined `__crystal_block_proc_51` (34 total stubs; total count is not the
value), while the prior stage2 call-tail and lower_def contracts regress before
runtime (SIGSEGV / undefined `String#byte_slice`). Candidate was reverted.
NEXT: under the filtered-veto oracle, trace the earliest supply/demand loss for
`__crystal_block_proc_51` and `String#byte_slice`; only then can lower_call's
liveness veto become default without sacrificing closed gates. No owner dedupe,
forwarder, unsafe_mod override, forced keepalive, or stdlib edit.
Prev below.)

Prev (session-27b: the generated-stage2 StaticArray/tuple return
floor is CLOSED at its root. `lower_def` mutated captured `last_value` from
inside `with_arena` / `with_type_param_map`; generated stage2 discarded the
block result, left the capture Nil, and emitted `define/call void @make_bytes`.
`lower_def_body_sequence` now returns the final `ValueId?` explicitly, and both
the non-generic and generic paths assign that result outside the nested block.
VERIFIED: generated compiler IR carries the returned union value; its target IR
emits `define/call ptr @make_bytes`; the focused stage2 runtime contract passes;
host suite 163/163 + 36/36. StaticArray representation mismatch is refuted for
this floor. NEXT: the old output-bearing repro now reaches and aborts in
`UInt8#UInt8#unsafe_mod(Int32)`. This is not a local missing-body problem: HIR
contains `UInt8#remainder(Int32)` with its explicit argument, while generated
LLVM calls the correctly two-parameter definition with only `self`. A custom
top-level and instance two-argument reducer reproduces the same second-argument
loss. In parallel, 8 of 24 target abort stubs use a repeated-owner identity.
Treat stubs as a heterogeneous fail-loud sink; the next root slice is the
call-binding/materialization transaction from selected def and argument vector
through HIR -> MIR -> emitted call ABI, not an `unsafe_mod` override. Prev below.)

Prev (session-27a: fresh stage2 rebuild exposed two earlier
generated-compiler crashes in bootstrap-critical fixed-name rewrites. A
block-backed `String#sub(Regex, replacement)` lost the captured replacement in
self-hosted eager return inference: first `raw_path.sub(/^::/, "")` passed a
null String while registering modules, then
`func_name.sub(/[.#]new$/, "#initialize")` failed after `lower_main`. CLOSED by
expressing those fixed transformations directly: absolute paths now remove the
ASCII `::` prefix with `byte_slice`, and constructor lookup derives
`#initialize` through the existing method-owner/name builder. No general regex
semantics changed. VERIFIED: current-source host rebuild; focused produced-stage2
module-registration guard; fresh stage2 self-build; generated stage2 IR no
longer routes these methods through regex substitution; full host regression
suite 162/162 + 36/36. The fresh stage2 now compiles the tuple/StaticArray repro
again and its produced binary retains the separate runtime failure below.
NEXT (localized independently by Luna 5.6 and then confirmed in uninstrumented
IR): `lower_def` loses its final expression through nested block capture. See
session-27b above for the closed result and the new call-binding frontier.
Prev below.)

Prev (session-26: stage2 `puts "hello"` llc union floor
[tuple-destructure `Int32 | Array(UInt8)` mis-inference] CLOSED via `7d96a08f`
(src/compiler/hir/ast_to_hir.cr). ROOT (NOT tuple element-type extraction — that
was a red herring): in the `tuple_element_type$$..._Int32` monomorphization the
`Int32?` param `index` collapses to a bare Int32, but its `if index` truthiness
was lowered as `binop Ne(index, POINTER-literal-0)` (a pointer nil-check) instead
of always-true. `index != nullptr` is FALSE for index 0, so element 0
(`bytes`) took the `else` branch `merged = union(all tuple elements)` =
`Int32 | Array(UInt8)`, which then `store ptr <union>` into a payload slot ->
llc reject compiling String#ends_with?(Char). The condition value's type
transiently read POINTER during body lowering even though the param signature is
Int32 (final HIR shows `%59 = copy %2 : Int32` yet `Ne(%59, ptr0)`).
IMPORTANT: this is a HEISENBUG — every STDERR/DBG probe I added PERTURBED type
inference and MASKED the bug (traced builds showed index=Int32 -> always-true;
untraced `--emit hir` dump was the only oracle). Also lower_method's own
`if index` folds correctly (index:Int32); the emitted buggy `_Int32` body comes
from a second, degraded lowering path (empty ctx.function.name, no params in
scope) so param-signature/instruction-type guards in lower_truthy_check did NOT
fire (two fix attempts failed for exactly this reason).
FIX (the one that worked): `sanitize_scalar_pointer_nil_checks`, a finalized-HIR
pass (called right after the final lower_missing/repair fixpoint) that folds
`Ne(scalar, POINTER-0-literal)` -> true and `Eq(scalar, POINTER-0-literal)` ->
false. By finalization the operand type is authoritative; a bare Int/UInt/Float/
Char is never null and no valid program compares one to a null pointer, so the
pattern is an unambiguous mis-lowered nil check. Low blast radius (pattern does
not occur in valid code). METHOD: stage1-vs-stage2 `.ll` diff of the `_Int32`
variant (`sext i32 %index; ptrtoint ptr null; icmp ne` vs union variant's
type_id tag check) + `bin/adamas src/adamas.cr --emit hir --no-link` dump
(showed block.14 `%59=copy %2:Int32; %60=literal 0:Pointer; Ne(%59,%60)`).
VERIFIED: run_all_suites 162/162 + 36/36 (net-zero, 0 regressions); stage1 repro
prints 65,3; stage2 self-compile exit 0 + `puts "hello"` compiles/runs exit 0
(empty STDOUT = known program-exit-stdio-flush truncation, unrelated).
NEXT bootstrap floor (START HERE — separate, exposed now that the repro COMPILES):
a stage2-compiled binary of regression_tests/stage2_tuple_destructure_union_repro.cr
segfaults at RUN time on the `uninitialized UInt8[4]` StaticArray value path
(`bytes[0]` / returning a StaticArray from a tuple). host stage1 runs it fine
(65,3). StaticArray value-ABI in self-host. NOT the union floor (union is gone).
Also still-latent (from session-24): strip -> remove_excess -> calc_excess_right
(Char::Reader UTF-8) negative-count self-host bug. Branch
`work/b5-lower-method-owner-edge`. Prev below.

Prev (session-25: stage2-hello SEGFAULT floor [String#bytesize
double-load / "String size 8 vs 12"] CLOSED via `20b9a2a7`
(src/compiler/hir/ast_to_hir.cr). ROOT: String's `@bytesize`/`@length` ivars
are declared ONLY through the param shorthand in
`def initialize_header(@bytesize : Int32, @length : Int32 = 0)`. The self-host
stage2 binary reads that def's `@params_storage` back EMPTY, so the class-body
ivar-capture loop's `each_param` yielded nothing -> String registered with ZERO
ivars -> @bytesize/@length lowered at offset 0 with a boxed double-load (String
size stuck at 8, not 12) -> any stage2-compiled program touching a String
segfaults. FIX: complete the `source_ivar_param_entries` fallback — after
`each_param`, register any TYPED source ivar-entry the parsed pass missed.
VERIFIED: host stage1 byte-identical layout dump; stage2 String size=12
@bytesize@4 @length@8; run_all_suites 161/161 + 36/36. Prev below.

Prev (session-24: Floor B [undefined 3-arg String.new sink] CLOSED
via `0844df31` (src/compiler/mir/llvm_backend.cr). The 3-arg allocator F
(`String$Dnew$$Pointer$LUInt8$R_Int32_Int32`) was a demand-coupled builtin
override emitted per forked LLVM worker only when RTA demanded it, but ~8
delegators (String.new 1-arg/UInt64/Nil-union, String#byte_slice[?],
IO::FileDescriptor/File#gets, Regex::MatchData#[]) call it via raw-LLVM `call`
edges RTA can't see -> delegator demanded + sink un-demanded = llc "use of
undefined value". FIX = reclassify F as a runtime helper (like
__adamas_char_to_string): emit unconditionally in emit_runtime_declarations
(parent, pre-fork) + register in @emitted_functions so plan-dedup drops any
demanded copy -> exactly one definition, no per-worker dup. Body byte-identical.
VERIFIED: stage2 self-compile EXIT=0, stage2 compiles hello with F once + 0
undefined/redefinition, suites 161/161 + 36/36.
INVESTIGATION (this session, owner-directed deep-root): full-C (delete the whole
String-alloc scaffold, use normal lowering) was PROVEN blocked by 3 deep self-host
codegen bugs, NOT the sentinel. (a) i64 GC sentinel PROVEN REDUNDANT -- no-sentinel
falsifier (F alloc without sentinel) -> stage2 self-compile clean + suites
161/161+36/36 (malloc_size-guarded rc on Darwin / no-op rc elsewhere makes ptr-8
sentinel unnecessary). (b) String.new normal lowering -> `Negative capacity`, but
LOCALIZED (manual stack-walk on a --debug self-compiled stage2) to a
strip->remove_excess->calc_excess_right(Char::Reader UTF-8 path) self-host bug that
passes a negative count; F's `bytesize<=0 -> ""` guard was MASKING it. (c) gets
normal lowering -> stub `Pointer$Hgets`; (d) regex MatchData#[] normal -> segfault.
So C-core (keep F as helper, kill demand-coupling) was the correct scoped fix.
NEXT bootstrap floor (START HERE, separate, revealed now that Floor B llc-error is
gone): stage2-compiled hello SEGFAULTs -- stage2 emits `String#bytesize` as
`gep self+0; load ptr; load i32` (double indirection) instead of `gep self+4;
load i32`. This is the "String primitive size 8 vs 12" divergence (MIR pre-registers
String size=8=one pointer, not updated to 12 in self-host) -> field access does a
pointer-double-load. stage1 emits bytesize correctly; NOT caused by the F change.
Chain: puts->IO#<<(String)->String#to_s(IO)->to_slice->bytesize(self=null-ish)->
EXC_BAD_ACCESS. Repro: `/tmp/stage2_ccore /tmp/floorB_hello.cr -o /tmp/h && lldb .. bt`.
Also queued: the strip/Char::Reader negative-count self-host bug (b) above.
Branch `work/b5-lower-method-owner-edge`. Prev below.

Prev (session-23: Floor B ROOT CAUSE CLOSED via ONE fix `91205450`
(src/compiler/hir/ast_to_hir.cr). Floor B was "stage2-compiled hello SIGBUS" —
stack-overflow recursion IO#<<(String) <- Reference#to_s. ROOT (4 layers deep):
the nilable-union comparison handler (~63698) picked BinaryOp vs method dispatch
via `use_primitive = numeric_primitive?(non_nil_type)`. Enums aren't numeric, so
`Nil | Enum` `==`/`!=` took the method-call path, which lowers the unwrapped enum
payload as a REFERENCE -> emits `Object#==/#!=` on `inttoptr(value)` (pointer
identity) instead of `icmp ne i32`. Silently inverts every nilable-enum compare.
Manifested self-hosted only: the lexer's `@last_token_kind : Token::Kind?`
`!= Token::Kind::Def` always read true, so `%(` after `def` scanned as a
percent-literal (percent_literal_allowed? was correct; it never mattered) ->
`def %(other)` (string.cr:5392) swallowed the rest of String's body: to_s/
to_slice/hash/size/... (31 defs) never registered -> `obj.to_s(io)` resolved to
ancestor Reference#to_s whose `io << class.name` recursed -> SIGBUS. stage1
(built by upstream Crystal) lowered the same compare right; the bug was in OUR
emission. FIX = extend `use_primitive` to enums for eq/ne (new `enum_type_ref?`,
detects via the enum table because HIR registers enums as Struct not
TypeKind::Enum) so the unwrapped payload compares with `icmp ne i32`; restricted
to eq/ne to avoid inventing `<`/`>` for non-Comparable enums.
METHOD (the long pole): stage1-vs-stage2 IR diff of the culprit function
(IO#<<$String called Reference#to_s not String#to_s); DEBUG_METHOD_RESOLVE +
DEBUG_SET_FDEF/SET_FTYPE localized the 31 dropped defs to a contiguous
string.cr region starting at `def %`; minimal `class Foo; def %(o);…` reducer
proved `%(` (no space) is the trigger; reading the CLEAN pre-probe stage2 .ll of
percent_literal_allowed? exposed `inttoptr`+`Object$H$NE$$Int32`. Probe rebuilds
were blinded by `ENV["X"]?`/BootstrapEnv self-host quirks + `@byte_size` ivar
misread — the .ll diff was the oracle, not runtime probes.
VERIFIED: nn_enum3 non-nil branch now `icmp ne i32` (was Object#NE+inttoptr);
stage2 registers 330 String methods incl. String#to_s (was 0 past line 5392);
`def %(x)` no longer swallows; run_all_suites 161/161 + 36/36; stage2 self-compile
clean (0 llc/atomic). Branch `work/b5-lower-method-owner-edge`.
NEXT bootstrap floor (START HERE, SEPARATE, previously masked by def-%): stage2
emits a call to `String.new(Pointer(UInt8),Int32,Int32)`
(`String$Dnew$$Pointer$LUInt8$R_Int32_Int32`, the 3-explicit-arg overload) from
the 2-arg `String.new(ptr,bytesize)` default-size delegator, but never
INSTANTIATES the 3-arg body -> llc "use of undefined value" compiling hello.
stage1 defines both. Default-arg overload instantiation gap, reachable now that
String#to_slice is demanded. Repro: `/tmp/stage2_enumfix /tmp/floorB_hello.cr`.)

Prev (session-22: mixed Atomic(Int32)+Atomic(Bool) atomicrmw
mis-type floor CLOSED via ONE fix `7a17260a` (src/compiler/mir/hir_to_mir.cr).
Atomic(Int32) atomicrmw ops (add/sub/and/or/xor/swap/…) were typed i1/Bool
whenever Atomic(Bool) coexisted in the same unit -> invalid LLVM IR
("'%value' defined with type 'i32' but expected 'i1'"). Root: the atomicrmw MIR
interception took the result type from `call.type` (the Ops.atomicrmw(...) : T
return), which generic forall-T inference resolves to a SIBLING T when several
Atomic(T) coexist (Atomic(Bool) drags the Int32 call site's return to Bool/i1).
The value operand stayed correctly i32, so emit_atomic_rmw took the byte-round
(bool-widen) path and emitted `zext i1 <i32 value> to i8` -> llc reject; it also
silently stored i1 into the Nil|Int32 union payload on paths that didn't reach llc.
FIX = derive the atomicrmw result type from the value operand type
(@hir_value_types[call.args[2]]) instead of call.type — atomicrmw's result MUST
equal its value operand type by LLVM semantics, and the operand type is
materialized faithfully; matches the cmpxchg/store branches, which already key off
the operand type. Non-Bool + genuine-Bool call sites byte-identical.
VERIFIED: reducer (Bool.set/get + Int32.add in one unit) compiles clean, runs
true/5/10; regression_tests/atomic_mixed_int_bool_rmw.cr (ALL_OK: add/sub/and/or/
xor/swap/cas over Bool/Int32/Int64 coexisting); session-20/21 atomic regressions
still green; suites 161/161 + 36/36 (run_all_suites.sh); stage2 self-compile
EXIT=0, 0 llc/atomic errors, 32.7MB. A/B PRE-EXISTING: the session-21 binary fails
identically on the repro; off the stage2 hot path. ALL atomic self-host floors now
CLOSED. Next open bootstrap floor = Floor B below (stage2-hello SIGBUS, NOT atomic).
Branch `work/b5-lower-method-owner-edge`.)

Prev (session-21: Atomic#swap + Box no-op floor CLOSED via TWO
fixes; stage2 self-compile STILL BUILDS clean (EXIT=0, 0 llc/atomic errors,
~240s). Session-20 floor A (Atomic(Bool)#swap no-op stub) was a GENERAL macro-
evaluator gap, also silently no-op'ing Box.box/Box.unbox.
(1) macro-if union predicate `6394f582` (src/compiler/hir/ast_to_hir.cr):
try_evaluate_macro_condition (the HIR macro-condition evaluator, ~58015) is
hand-rolled (flag?/has_constant?/type==,</int-compare) and CANNOT walk
Array#all?/any? with a block, so `{% if T.union_types.all? { |t| t == Nil || t <
Reference } %}` was reported unevaluable -> lower_macro_if (~59274) emits a NIL
LITERAL for an unevaluable condition -> whole method body collapses to a nil stub.
Hit Atomic#swap (else branch dropped -> ret void) AND Box.box/Box.unbox
(`T < Pointer || union_types.all?{...}` -> ret null for any reference T; latent
no-op in every callback/closure boxing a ref through Void*). The full MacroExpander
is no fallback: no union_types, no all?/any? block support either. Fix = new
try_evaluate_macro_union_predicate + macro_union_member_type_names: resolve
`<type>.union_types` (macro_condition_type_name + split_union_type_name), bind the
block param to each member via with_type_param_map, reuse try_evaluate_macro_condition
per member (all?=AND, any?=OR). Returns nil (caller falls back) on any unresolved
shape -> strictly additive, zero regression to already-handled conditions.
(2) atomic byte-round operand-width `b1d38645` (src/compiler/mir/llvm_backend.cr):
materializing swap's body exposed a desync -- swap/compare_and_set pass
cast_to(value):Int8 (already i8) while type inference binds the primitive element
type to T=Bool (i1, dropping the .as(Int8*) reinterpret). emit_atomic_rmw/cas keyed
the byte-round off inst.type (i1) -> `zext i1 <op> to i8` on an i8 operand -> llc
"defined with type i8 but expected i1". Fix = new atomic_operand_llvm_type; in the
bool_widen rmw/cas paths, skip the input zext when the operand is already the storage
width; result trunc back to i1 unchanged. Non-bool + genuine-i1 operands byte-identical.
VERIFIED: swap Bool/Int32 (SWAP_OK, INT old=5 now=10), Box(String) round-trip
(BOX back=hello); atomic regression ATOMIC_BOOL_OK (get/set/cas no regress); suites
157/157 + 36/36; A/B (stash+rebuild OLD): swap->SWAP_FAIL, box->BOX_FAIL null on OLD,
both OK on NEW; stage2 self-compile EXIT=0 clean. Regressions:
regression_tests/box_ref_union_macro_predicate.cr, atomic_swap_byte_round.cr.
METHOD: `DEBUG_INFER_BODY_NAME=swap` showed swap tail=MacroIfNode inferred=nil; a
decomposition reducer (split the predicate into .size/==Nil/<Reference/all?) isolated
`.all?`-with-block as the single failing macro op.
NEW floor A (START HERE, PRE-EXISTING, separate root) = Atomic(Int32) atomicrmw
(add/sub/swap/…) mis-typed to i1/Bool when Atomic(Bool) COEXISTS in the same unit ->
llc "'%value' defined with type 'i32' but expected 'i1'". Repro: Atomic(Bool).get/set
+ Atomic(Int32).add in one file (NO swap needed); Atomic(Int32) ALONE is fine. A/B-
proven PRE-EXISTING (OLD compiler fails identically) — NOT this session's regression.
Localization: hir_to_mir.cr:6626 `ret_hir_type = call.type` uses the HIR type of the
Ops.atomicrmw call, which HIR inference resolves to Bool for the Int32 call site when
Bool coexists (generic forall-T return-type contamination across Atomic instantiations).
Off the stage2 hot path (stage2 builds), but silently mis-types the Int32 union payload
store even when it doesn't hit llc.
NEW floor B (session-20, still open) = stage2-compiled hello SIGBUS/stack-overflow in
IO#<<(String) <- Reference#to_s (recursive dispatch, NOT atomic).
Build note: rebuild bin/adamas with CRYSTAL_WORKERS=1 (Crystal parallel scheduler
build deadlock). Branch `work/b5-lower-method-owner-edge`.)

Prev (session-20: atomic self-host floor CLOSED via TWO fixes;
stage2 now BUILDS end-to-end (EXIT=0, no llc/atomic error). Both fixes blocked
stage2's Atomic(Bool) codegen with invalid llc IR:
(1) byte-round sub-byte atomics `80dd3b7b` (src/compiler/mir/llvm_backend.cr):
emit_atomic_load/store/cas/rmw took @type_mapper.llvm_type(inst.type) directly →
`load atomic i1` for Bool ("atomic access must be byte-sized"). Bool stores as i8
(zext-i1→i8 convention), so round the atomic access to i8 with trunc/zext at the
value boundary (load→i8+trunc; store→zext+i8; cas→zext operands+cmpxchg i8+extract
i8+trunc; rmw→zext+i8+trunc). Non-Bool (i32/i64/ptr) unchanged (storage_type==type).
(2) decode Symbol-typed ordering/op args `d7c4ffc0` (hir_to_mir.cr + mir.cr): the
HIR symbol→enum autocast for Atomic::Ops ordering args is applied INCONSISTENTLY
(depends on Ops.* param-type resolution, arena/pass-sensitive), leaving :acquire as
an interned Symbol constant; find_constant_int then read the Symbol *id* (6) as the
ordering → `load atomic ... acq_rel` (invalid on a LOAD — the SECOND, masked error).
Others landed on SeqCst by luck (set emitted seq_cst for :relaxed/:release). Fix:
decode Symbol ordering/op constants BY NAME at the MIR atomic interception (new
MIR::Builder#find_constant to inspect constant TYPE); int path kept for already-
converted enums; covers load/store/cmpxchg/atomicrmw/fence orderings + atomicrmw op.
VERIFIED: reducer + `--emit llvm-ir` (get→monotonic/acquire/seq_cst, set→monotonic/
release/seq_cst, cas→cmpxchg i8+extract{i8,i1}, no `atomic i1` remains anywhere);
regression `regression_tests/atomic_bool_ordering_repro.cr` (ATOMIC_BOOL_OK); suites
157/157 + 36/36; stage2 debug build EXIT=0 (`/tmp/stage2_atomic_check`, 32MB).
NEW floor A (START HERE, separate root) = `Atomic(Bool)#swap` compiles to a NO-OP
STUB: MIR body `%3 = const nil : Nil; ret` (body never lowered) → .ll `define void
@…swap… { ret void }` (returns void, performs no exchange; swap_old prints empty).
get/set/compare_and_set are correct; swap is UNIQUE in using the private `atomicrmw`
wrapper macro (`case ordering … Ops.atomicrmw(…)`) inside `cast_from` → body
materialization / return-type inference drops it to a Nil stub. Does NOT block stage2
compile (valid IR), only Atomic(Bool)#swap runtime semantics.
NEW floor B (stage2 runtime, separate) = stage2-compiled hello SIGBUS/stack-overflow
in `IO#<<(String)` ← `Reference#to_s(IO)` (EXC_BAD_ACCESS at a stack addr; recursive
dispatch, NOT atomic-related). Revealed now that stage2 builds.
Build note: rebuild bin/adamas with CRYSTAL_WORKERS=1 (Crystal parallel Fiber
scheduler build deadlock; main on __psynch_mutexwait, GC-markers idle).
Branch `work/b5-lower-method-owner-edge`.)

Prev (session-18: TWO floors closed in default stage2 hello.
(1) L10 gets_peek CLOSED `937a3350`: emit_gep(_dynamic) now unwraps a union base
when @value_types[base] is missing/ptr but the emitted operand is a union (value
lives in a SHARED cross-block union slot → value_ref hands back a raw union LOAD;
GEP on the union carrier → llc reject). (2) StaticArray/LibC::Stat type-def floor
CLOSED `1b042a24`: unqualified sibling enum members inside enum methods were not
resolving — `case self when Void, Bool, Int32, …` in self-hosted TypeKind#primitive?
fell to is_a? (Void/Bool/… are BOTH members AND types) and matched EVERYTHING, so
primitive?(Struct)=true, so emit_type_definitions skipped Struct-kind defs and
`alloca %StaticArray/%LibC::Stat` were undefined. NEW floor = undefined
`@Object#==$Int32` — ROOT-CAUSED: adjacent string-literal concatenation is NOT
implemented in the parser (`"a" "b"` / `"a" \<nl> "b"` keep only the FIRST literal),
so multi-line synthesizers like the Object#==(T) cross-type stub emit only their
first `"; comment\n"` line, dropping the `define … { ret 0 }`. Suites 156/156 +
36/36 default. START HERE = adjacent string concatenation in parser.cr:10424.)
Branch: `work/b5-lower-method-owner-edge`

## 2026-07-08 — session-18: L10 gets_peek + StaticArray floors CLOSED; NEW floor = adjacent string concat

**L10 gets_peek CLOSED (`937a3350`) — emit_gep union base unwrap.**
`IO#gets_peek`'s `peek.size` (Slice @size @ offset 0, for `Math.min`) is a FieldGet
→ emit_gep. `peek` is the `Nil | Slice(UInt8)` loop var living in a SHARED
cross-block union slot (`%r182.phi_slot`, L10 phi-slot sharing). value_ref(80) loads
the raw UNION from the slot, but `@value_types[80]` is nil so emit_gep defaults
base_type_str to "ptr" and skips the existing union-unwrap → `getelementptr i8, ptr
%rN.fromslot (union), 0` → llc "union … but expected ptr". Fix: when base_type_str
defaults to ptr but `@emitted_value_types[base]` is a union, trust the emitted type
and unwrap the payload. Applied to emit_gep AND emit_gep_dynamic (llvm_backend.cr).

**StaticArray/LibC::Stat floor CLOSED (`1b042a24`) — unqualified sibling enum members.**
Root: inside an enum instance method a bare member name did not resolve to the
member. (a) plain expr (`self == A`, `A.value`): lower_identifier/lower_path fell to
the constant path → null/zero literal. (b) case/when (`case self when Void, Bool`):
emit_case_comparison's `case_condition_type_name` turns any `when <registered type>`
into `self.is_a?(Type)`; Void/Bool/Int32/Char/Symbol are BOTH TypeKind members AND
types, so `when Bool` → `is_a?(Bool)` matched every value → TypeKind#primitive?
returned true for EVERY kind → emit_type_definitions (`!primitive?` gate) skipped
Struct/Reference struct defs → undefined `%StaticArray(UInt8,N)` / `%LibC::Stat`
allocas → llc reject. Fix: emit_enum_sibling_member? (bare member vs @current_class
enum, in lower_identifier + lower_path) + emit_case_enum_member_equality? (bare
`when` member vs SUBJECT's enum, BEFORE case_condition_type_name). Regression:
`regression_tests/enum_bare_sibling_member_in_method.cr` (old bin/adamas FAILs).

**NEW FLOOR — adjacent string-literal concatenation not implemented (START HERE).**
Reducer (compiled by fixed stage1, run): `"aaa\n" "bbb\n" "ccc\n"` → bytesize=4
(only "aaa\n"); `"xx" "yy"` → "xx". parser.cr:10424 (`when Token::Kind::String`)
builds ONE StringNode and advances — no merge of subsequent adjacent String tokens.
`StringNode` holds a materialized `@value : Slice(UInt8)` (already-decoded), so the
fix is: after the first literal, while the next significant token is a plain String
(NOT percent/interpolation), concatenate value slices into a fresh persistent
buffer and extend the span. CAUTION — must respect statement boundaries: `"a"\n"b"`
(bare newline) = SEPARATE; `"a" "b"` (same line) and `"a" \<nl> "b"` (backslash-
continued, newline suppressed) = MERGE. Verify the parser's token stream around
current_token after advance (Whitespace filtered? Newline present? backslash
suppresses Newline?) BEFORE looping, or the compiler's own source (full of `"…" \
"…"` synthesizers) will mis-merge. This is why s2 emits `; Object$H$EQ$$Int32 —
cross-type comparison (always false)` WITHOUT the following `define … { ret 0 }`
(llvm_backend.cr:5774-5779 returns a 4-part adjacent-string literal; s2 keeps line
1 only) → undefined `@Object#==$Int32` (called by synthesized `Object#==$Errno`).
Pre-existing: present in s2_gp AND s2_ewi outputs too, just behind earlier floors.
Artifacts: /tmp/adamas_clean (fixed stage1, both session-18 fixes), /tmp/s2_v3
(stage2), /tmp/hello_s2v3.bin.ll (StaticArray defs present, llc stops at line
10417 Object#==$Int32), /tmp/strcat.cr (adjacent-string reducer).

## 2026-07-08 — session-17: L15 CLOSED; NEW floor = L10 gets_peek (NOT veto-gated)

**L15 root 1 (`af06b47a`) — case/when `.predicate(arg)` drops arguments.**
emit_case_comparison (ast_to_hir ~68416) treated every `?`-suffixed predicate
call in a `when` as a zero-arg enum predicate; enum path + fall-through
`Call.with_receiver(..., [] of ValueId)` both dropped args. `when .includes?("..")`
/ `.starts_with?('/')` lost their arg → `STUB CALLED: String#includes?` (default)
/ degraded `includes?(Char|String)` with unwrapped String (veto) → null-base
`String#==` (bytesize read @ addr 4) in Time::Location.load? = the crash-report
signature. Fix: implicit-subject predicate WITH args → `lower_expr(ctx, cond_expr)`
(normal path, intercepts+coercion), gated on is_implicit_shortcut. DEFAULT-affecting.
Regression: `regression_tests/case_when_predicate_with_args_repro.sh`.

**L15 root 2 (`2e164899`) — emit_array_get each_with_index.all? OOM (the blowup).**
llvm_backend tuple-variable-index path:
`uniform = offsets.each_with_index.all? { |(off, i)| off == i.to_u64 * stride }`
(offsets = Array(UInt64)). Under veto the iterator+block form miscompiles:
WithIndexIterator element UInt64→Float64 + wrapped iterator never terminates →
`all?` spins forever, malloc each turn → OOM compiling even `puts "hello"`.
Fix = plain `while` index loop (no closure, no WithIndexIterator; also cheaper).
The .ips Time::Location NULL+4 and the 190GB `WithIndexIterator(Float64)` blowup
were the SAME L15, env-dependent faces.

**METHOD (safe repro under machine-shared constraint):** `sample <pid>` of the
s2 child WHILE `scripts/run_safe.sh` does the RSS-kill guarding (run_safe in bg;
`pgrep -x <s2_binary>`; `sample PID 1 -mayDie -file`). NEVER lldb+`ulimit -v` on
the blowup — RLIMIT_AS is NOT enforced on macOS/arm64; it ran uncontrolled and
overloaded the machine (owner flagged it; fixed the approach mid-session). Two
throwaway diagnostic guards (regex-new bytesize cap; value_literal_name? bound)
peeled outer layers to reveal the iterator loop, then REVERTED (whack-a-mole).

**NEW FLOOR — L10 gets_peek (START HERE):** default AND veto stage2 now emit
full IR for hello; `llc` rejects `getelementptr i8, ptr %rN.fromslot.K` where
%rN is a `Nil | Slice(UInt8).union` loaded from a phi_slot in `IO#gets_peek`
(hello .ll ~line 16287; union not unwrapped before the GEP that reads slice
`size` for `Math.min`). NOT veto-gated (both configs). Artifacts: /tmp/adamas_ewi
(stage1, both L15 fixes), /tmp/s2_ewi_veto, /tmp/hello_ewi.ll. Fixing it unblocks
hello for both → then veto flip → suites ×2 → replace bin/adamas.

**Parked (latent):** the underlying veto stale-binding that miscompiles
iterator+closure forms is NOT itself fixed — other each_with_index/.map{}/... in
hot codegen remain latent OOM risks. Also: standalone
`arr.each_with_index.all? { |(x,i)| ... }` SIGBUS-crashes in BOTH modes (block
tuple-destructure of the WithIndexIterator element) — separate bug.

This is the active working backlog only. Historical detail is in git history,
especially `65eb6f62^:TODO.md`. Reusable evidence lives in `LANDMARKS.md`.

## 2026-07-07 — session-16: L14 CLOSED (named-arg values invisible to block-proc capture)

**L14 route (proven: l14_scan/l14_create/l14_slots lldb probes, scripts in
session scratchpad 68873b59; NB the bug does NOT reproduce under `env -i` —
the stack garbage then reads as a short string and lookups miss silently;
probe with FULL env):**
1. `collect_proc_body_ident_walk`'s CallNode case walked callee/args/block
   but NOT `node.named_args` → a local referenced ONLY as a named-arg value
   inside a materialized block proc never entered referenced_names → no
   closure cell → lowering the call inside the proc materialized a fresh
   UNINITIALIZED slot and passed its ADDRESS as the argument value.
2. In s2: the `with_isolated_type_param_map` block at ast_to_hir ~74275
   (`lower_method(..., force_class_method:, forced_full_name:
   target_for_lower, forced_method_name:)`) — proc_1758 passed
   `add sp,#0x80/0x88` (never-written slots) as the two String named args
   and read the Bool as `ldrb [self]` (type_id byte). lower_method then
   registered a Function whose name String pointed into a dead stack frame
   → veto-s2 SIGSEGV in Hash(String,Function)#key_hash during
   invalidate_lowered_layout_functions (the session-15 L14 signature).
   IDENTICAL wrong code in DEFAULT s2 (silently creating garbage-named
   Functions) — NOT veto-specific, veto only changed the stack garbage.

**Fix:** walk `named_args.each { |na| walk(na.value) }` in
collect_proc_body_ident_walk, detect_written_captures_walk,
proc_expr_has_implicit_receiver_call?.
**Regression:** `regression_tests/block_proc_named_arg_capture_repro.sh`
(2 cases: string-only-named capture + same-name/Bool shorthand; old
bin/adamas FAILs both — negative control PASSED).

**New veto-s2 floor (L15, next START HERE):** compiling hello with the
clean-rebuilt fixed veto-s2 (/tmp/s2_l14fix_veto2) segfaults ~3s in, after
ALLOC_FLUSH (deferred allocators done), i.e. during MIR/LLVM emission — in
s2's OWN runtime: crash report shows `Time::Location.load?$String_block`
reading NULL+4, single-frame unwind (fp chain gone); under lldb full-shell
env the same binary instead ballooned to ~190GB inside
`emit_array_get` / `Iterator::WithIndexIterator(Float64, UInt64,
Int32)#all?` (phantom-looking instantiation). Unstable site + env
sensitivity ⇒ upstream corruption, likely another latent miscompile family.
Artifacts: /tmp/adamas_l14fix (fixed stage1), /tmp/s2_l14fix_veto2 (+.build.log),
/tmp/hello_l14v2.compile.log, crash report
~/Library/Logs/DiagnosticReports/s2_l14fix_veto2-2026-07-07-212946.ips.
SAFETY: repro ONLY via run_safe (lldb bypasses its guards — two 190GB
processes on 2026-07-07; owner reminder).

**Epidemic parked (same omission family, audit separately):** other
ast_to_hir walkers whose CallNode cases skip named_args — candidates:
collect_local_assignment_types (~22820), collect_yield_arg_lists (~44433),
collect_constant_dependencies (~46920), collect_assigned_vars_in_expr
(~67155), collect_block_param_names_in_expr (~67477), contains_yield_deep?.

**Then:** L15 root-cause → veto default flip → suites ×2 → s2-veto hello →
replace bin/adamas (unchanged plan, now gated on L15).

## 2026-07-07 — session-15: L13 CLOSED (repair-route shape threading + repr agreement)

**L13 route (proven with ADAMAS_TRACE_CALL_EMIT + DEBUG_L13 repair traces;
zero CALL_EMIT hits for the map symbol at lower_call/yield_fallback was the
key negative):**
1. `lower_call` types `mt.zip(inferred)` as raw POINTER (zip blockless-return
   degradation, see below) and binds the BLOCK call to a **getter**
   `Adamas::HIR::AstToHir::GenericOwnerInfo#map` (base=Pointer#map,
   ret=Hash(String,String)). ~14 getter-bound `.map{}` callsites across an s2
   build — "block call binds to blockless def on degraded receiver" is an
   UNGUARDED latent-miscompile family (candidate hardening: resolution must
   require a block-accepting def when the callsite has a block).
2. `repair_receiver_bound_call_targets` (end of lowering) rewrites the target
   to bare `Array(Pointer(Void))#map` and force-lowers the body OUTSIDE any
   callsite (return-type probe) → no `__block_return__`, no U binding →
   `infer_yield_return_type`'s ANNOTATED branch returns nil (bypasses the
   __block_return__ fallback for `& : T -> U`) → yield `call void %_()` +
   `store ptr null` elements.

**Fix (two commits, suites 155/155+36/36 ×2 green):**
- `3e6ac277`: repair pass re-keys rewritten block-call targets through
  shape_keyed_block_target (block return from caller's block terminator,
  FALLBACK to trailing proc arg's Proc descriptor — block regions end in
  Branch; trailing proc trimmed for lookup; template-owner retry); shape
  materialization binds generic U alongside __block_return__; DEBUG_L13
  traces at repair sites + lower_yield.
- `9a748896`: raw `Pointer` arm in a block-return union = D1 degradation
  sentinel → sanitize_degraded_block_return_union collapses {X, Pointer} → X
  for U/__block_return__ (map shape returns Array(TypeRef), elements are
  readable 8-byte ptrs); the proc's REAL compiled return ABI recorded as
  `__yield_call_abi__`; lower_yield emits the Yield with the ABI type and
  coerces (union unwrap) to the declared yield type. Intermediate lesson: the
  unsanitized union stored TAGGED {i32,[2xi32]} elements → consumer 8B-stride
  misread → garbage `0xf414…0496` in Array(TypeRef)#fetch (crash
  shape-shifted, same family).

**New floors after L13:**
- **default-s2 compiling hello:** full IR emitted; llc rejects
  `GEP on Nil|Slice(UInt8)` in `IO#gets_peek` (2 sites, 1 function) — this is
  the KNOWN L10 veto-OFF signature (session-11), expected until veto flips.
- **veto-s2 compiling hello (L14, next START HERE):** SIGSEGV after
  lower_main: `Hash(String, HIR::Function)#key_hash$String` reads a string at
  0x16fe00000 (stack-guard-like) ← function_by_name ←
  has_function_with_body? ← `invalidate_lowered_layout_functions` iterating
  `@module.functions.dup` during `lower_assign` — a Function NAME string in
  s2's own module table is corrupt (or the value slot misread — key_hash /
  union-arg ABI family, cf. s2b_lower_missing_call_targets_key_hash_frontier,
  m4h_union_descriptor_hash_value_confusion). Repro: build s2 with
  `ADAMAS_PHI_SHARE_VETO=1`, compile hello, lldb bt. Artifacts:
  /tmp/adamas_l13f3 (stage1 with L13 fix), /tmp/s2_l13f3 (+_veto),
  /tmp/l13_fix3.log, /tmp/hello_s2.ll (default-build llc reject IR).

**Sibling opened (memory zip_blockless_return_typeof_degradation, reducers
/tmp/t_zip_probe.cr /tmp/t_zip_block.cr):** `a.zip(b)` WITHOUT block returns
`Array(Pointer(Void))` UNIVERSALLY (string-typeof resolver has no case for
`zip(*others) { |e| break e }`; splat local `others` is annotation-typed;
Enumerable.zip is a macro body). zip WITH block also red (`x+y` → Tuple#+
stub). DEBUG_L13Z lever prints typeof context. This is the upstream root of
the L13 receiver degradation — fixing it collapses the whole cascade class.

**Then:** L14 root-cause → veto default flip → suites ×2 → s2-veto hello →
replace bin/adamas (unchanged plan, now gated on L14).

## 2026-07-07 — session-14: L12 CLOSED; L13 = map fallback stores null elements

**L12 fix (two commits):**
- **D1 `8bbba4e0` (root):** `infer_yield_param_types_from_body`'s annotation
  branch never consulted callsite arg types, so `other : Indexable` typed the
  yield-arg `other.unsafe_fetch(i)` through the BARE generic → block param =
  raw Pointer → dispatch synthesized `TRef#==(Pointer)` → Array(struct)#==
  always false → Module#intern_type bucket-hit never recognized. Fix: prefer
  the concrete callsite type via should_use_exact_call_type_for_local_inference?.
- **D2 `a6e73d17` (unsound guard):** lower_is_a's runtime fallthrough read a
  type_id header for STRUCT check targets — structs have no header (offset 0 =
  first ivar). Struct-target checks reaching the fallthrough now resolve to
  constant false instead of reading a field as a tag.
- Regression: regression_tests/array_struct_eq_yield_arg_type.cr (A/B: pre-fix
  eq_ok=false + intern bucket-hit missed; post-fix l12_ok). Suites 155/155 +
  36/36 default AND veto. Both /tmp/test_l12_areq.cr and /tmp/test_l12_intern.cr
  oracles green.

**L13 ROOT-CAUSED (open, fix = next session):** s2 (veto) compiling hello
segfaults in `lower_block_to_block_id`+296 — the inlined cache-key fingerprint
hash loop reads a NULL element of a valid `Array(TypeRef)`. Pre-existing (old
s2 dies at the same consumer via block_param_types_fingerprint). Proven chain
(deterministic under `env -i`; runtime-installed lldb bps — pre-launch `-a`
bps NEVER arm, and StepOutOfFrame-in-callback reads STALE x0, which is what
produced session-13's phantom "intern_type→0x0" hops):
`lower_block_to_block_id(x3=[null])` ← `block_param_types_for_call` returns it
← exit site +9816 = return of `infer_yield_param_types_from_body` ← inferred
def = `Crystal::System.printf$block$arity2_splat` (yields Slice(UInt8)) ←
compute_yield_merged_types `mt.zip(inferred).map{...}` compiled as
**`Array(Pointer(Void))#map(..., @__crystal_block_proc_889)` whose body does
`call void %_()` + `store ptr null`** into every element (same family as L11's
`call void %_()`, but the map path). proc_889 itself returns TypeRef|Pointer
union (zip block params degraded to Pointer — D1-family sibling). All
type_ref_for_name/inner/union_type_for_values returns proven non-null in-vivo.

**Fix locus (next session START HERE):** find the ACTUAL demand/lowering route
of the degraded `Array(Pointer(Void))#map` symbol — inline_yield_fallback_call
is NEVER entered with a map key (DEBUG_L13 trace, zero hits over a full s2
build), so the L11 shape/contract machinery never sees this callsite. Levers:
ADAMAS_TRACE_CALL_EMIT=map, DEBUG_CALL_LOOKUP, grep who lowers the shared
`_`-proc method body (`lower_method` + `__block_return__` absent → void proc
call). Groundwork already in tree (suite-verified): (1) yield_value_consumed?
widens block_call_return_contract_for beyond passthrough (map-like bodies);
(2) generic_proc_annotation? relaxes the annotated-block gate (`& : T -> U`
doesn't pin the return shape; NB `annotation` is a reserved word); (3)
DEBUG_L13 trace at the fallback re-key. These are correct-direction but
UNHOOKED for this route. Parked sibling reducers: /tmp/test_l13_zipmap.cr
(`STUB CALLED: Pointer$Hid` — zip destructure degradation),
/tmp/test_l13_mapfb2/3.cr (triple-nested yield inlines but block gets GARBAGE
yield-arg b.v=1086 — nested inline-yield arg corruption). Memory:
l13_map_fallback_void_contract_null_elements.md (probe methodology inside).

## 2026-07-07 — session-13: L11 CLOSED; L12 = Array(struct)#== always false

**L11 fix (`0bf0a652`, refined root):** deeper than session-12's note — in the s2
body of the ONE shared `with_type_param_map$$Hash(String,String)_block` the block
proc was called as **`call void %_()`** (value discarded) and every `ret` returned
**`zeroinitializer`** of the accreted union → tag0+null payload at EVERY
value-consuming callsite. Root: the inline-yield depth/repeat-guard fallback shared
ONE `_block` symbol keyed only by ARG types; the body's yield/return ABI was stamped
by whichever callsite's `__block_return__` won. Fix rides the existing
shape-specialization machinery (fea7db18, default ON): (1)
`block_call_return_contract_for` accepts ALL yield-passthrough bodies (`return
yield`, tail `yield` incl. begin/ensure ivar-swap); (2) `inline_yield_fallback_call`
re-keys its target through `shape_keyed_block_target` and records `__block_return__`
under the shape name. Regression: regression_tests/block_shape_return_contract.cr
(pre-fix segfault / post-fix ok; needs `struct Box` — class masks the bug, all-ptr
reprs). Suites 154/154 + 36/36 on default AND veto.

**Parked known-red (pre-existing, `ea8f8313`):** phantom generic `Box(Int32)` from a
constructor tail in a fallback block (non-generic Box; phantom lacks ivar metadata;
getter pointer-loads offset 0 → derefs `{type_id,v}` as pointer → crash
`0x{v}0000{tid}`). KNOWN_BUGS.md + regression_tests/phantom_generic_ctor_block_repro.sh.

**L12 ROOT-CAUSED to reducer (fix = next session):** s2 (veto, L11 fix) compiling
hello segfaults at `block_param_types_fingerprint$$Nil|Array(TypeRef)`: array VALID,
ELEMENT = null TypeRef. Chain (each hop proven with lldb python probes, scripts in
scratchpad): `String.new { |buffer| … }` lowering → `block_param_types_for_call` →
`return [type_ref_for_name("Pointer(UInt8)")]` → wrapper returns NULL → inner runs
clean through `after_type_params ids=7` (DEBUG_TYPE_REF_NAME trace) → the null is
returned by **`Module#intern_type`** (probe: `intern_type(desc) -> 0x0`) → intern's
bucket-hit compare `entry[1] == desc.type_params` is ALWAYS false because
**`Array(CustomStruct)#== is ALWAYS false, even `a == a`** (minimal reducer
/tmp/test_l12_areq.cr: `struct_eq=true arr_eq=false self_eq=false`; Int32/String/
UInt8 element types are fine; PRE-EXISTING — reproduces on pre-L11 compilers).
Mechanism, two layers (in-vivo shape = Indexable#equals?):
- **D1 (root):** in `Indexable#equals?(other : Indexable, &)` the yield-arg
  `other.unsafe_fetch(i)` infers through the BARE generic param annotation →
  block param `y` typed raw POINTER (TypeRef 18) instead of the element struct
  (callsite mono knows Array(TRef) — substitution is lost).
- **D2 (unsound guard):** dispatch then synthesizes `TRef#==(Pointer)` whose
  narrowing check reads `load i32 [other+0]` and compares to the struct's type_id
  (932) — but STRUCTS HAVE NO type_id HEADER (offset 0 = first ivar) → reads the
  field value → check always false → `==` returns false.
Open tail: why in-vivo intern_type returned NULL (vs minting a fresh ghost ref) —
one unexplained hop; the reducer chain above is proven regardless.

**START HERE (L12 fix):** (1) D1: make yield-arg type inference substitute the
CALLSITE receiver/arg types for bare-generic def params (the mono suffix
`equals?$$Array(TRef)` has the concrete type; `other : Indexable` must resolve
unsafe_fetch's T through it) — look at block_param_types_for_call → yield-site arg
inference (collect_yield_arg_lists ~44256, infer paths ~22890); (2) D2: the
synthesized `==(Pointer)`/is_a? guard for STRUCT targets must not read a type_id
header from a struct-repr pointer (llvm is_a? emission or the dispatch synth) —
D1 alone removes the trigger, D2 alone is unsound; (3) rerun /tmp/test_l12_areq.cr
(`arr_eq=true self_eq=true`), intern reducer /tmp/test_l12_intern.cr (`b=1118`),
then s2-veto hello; (4) THEN veto default flip → suites ×2 → Sub#gets_peek health →
replace bin/adamas. Census note: true-census = DEBUG_PHI_MISSING=1 (2439/s2; also
fires compiling TINY programs — Deque#resize_to_capacity, Hash#do_compaction,
IO#gets_slow, Char#in_set?$splat, Kqueue#system_run$block); grep `[null, %bb`
over-counts (legit nil-literal incomings) AND many census hits are harmless
(fabricated null == correct nil semantics; e.g. dead backedge after unconditional
`break` in split_generic_type_args — false alarm, verified). Artifacts:
/tmp/adamas_l11fix (stage1+fix), /tmp/s2_l11fix(+.ll), /tmp/s2_l11fix_census.build.log,
/tmp/test_l12_areq{,2,3}.cr, /tmp/test_l12_intern{,2}.cr, scratchpad fp_scan.py /
trfn_probe{,2}.py (lldb python probes: scan array elems / trap null returns).

## 2026-07-07 — session-12: β CLOSED (two roots); L11 = specialize null TypeRef

**β root 1 — loop-phi self-incoming skip (FIXED):** lower_while/lower_loop guarded
`phi.add_incoming` with `if incoming_val != phi.id` ("self-referential PHI would be a
no-op") and skipped entirely when `updated_val` was nil. A variable unchanged on the
backedge path left the loop-header phi with NO incoming for a real predecessor; the
backend then fabricated null/zero (`default_phi_value` llvm_backend ~21720:
`[null, %bbN]`). Fixed at 10 sites (lower_while, lower_loop, until-form, each_char
intrinsic, 6× incr_phi sites): always add the backedge incoming, self when unchanged.

**β root 2 — detached block-body CFG pollution (FIXED):** `lower_block_to_block_id`
lowers the block body into a DETACHED block of the caller function (proc/closure
representation + return-type inference) while the caller's loop stacks were live.
`next`/`break` inside the block wired edges from that dead body into the ENCLOSING
while's cond/exit blocks (in-vivo: lower_super's `each_param do |param| next if …;
break …` = the bb287/bb296 fabricated-null preds), plus a stray `ret` mid-function.
Fixed by suspending loop + inline-next/return stacks around the body lowering
(pattern copied from the method-ptr thunk at ~64965). With empty stacks `next`
lowers as Return (proc semantics), `break` as Unreachable.

**Verification:** reducers v1–v4 (/tmp/test_beta_postloop*.cr recipes in memory);
v4 (yield fn + next/break in block) reproduced 2 fabricated nulls → 0 after fix;
s2-build lower_super had 4 null incomings → 0; whole s2 .ll 500 → 482 (residual =
other shapes, see L11). Suites 152/152 + 36/36 on stage1 default AND under
ADAMAS_PHI_SHARE_VETO=1. New guards: regression_tests/loop_phi_backedge_selfincoming.cr
(runtime) + scripts/loop_phi_backedge_null_incoming_guard.sh (structural, FAILs on
pre-fix compiler with count=2).

**L11 ROOT-CAUSED (same session, probes committed): shared $block return union
missing Nil + raw u2u reinterpret.** s2 (veto build, both β fixes) passes
registration + lower_super, then segfaults: lower_call →
`specialize_type_with_receiver_map(null, …)` (x1=0) at ast_to_hir ~80477 while
lowering `Slice(UInt64)#each$block`. Probe bisection (DEBUG_L11_RT sites A..G):
return_type = Void at site A (after get_function_return_type), Unknown (= null
TypeRef, `get_type_name_from_ref` maps null_ptr? → "Unknown") from site A0b on —
the null is the value RETURNED by `infer_return_type_from_body_without_callsite`
(assigned at the `return_type = inferred` in the unionish-inference block,
~80175). Mechanism, read directly from the s2 .ll of that helper: its then-branch
value is `with_type_param_map(map) do infer_concrete_return_type_from_body(...)
end`; the ONE shared `with_type_param_map$$Hash(String,String)_block` function's
return type accreted `TypeRef | Array(TypeRef)` (NO Nil variant) across its 41
callsites, while this callsite's block returns `Nil | TypeRef`. The callsite
coerces via raw u2u reinterpret (`store TypeRef|Array… ; load Nil|TypeRef` from
the same alloca — no tag remap): the block's nil result has no representation →
non-nil tag with null payload → null TypeRef flows into return_type → crash.
Family: block-call mega-union return leak (5c274a28) + u2u payload conversions
(0b008b47). s1 is clean because host Crystal compiles the same source correctly —
this is a stage1 lowering defect around shared-$block return typing.

Side finds (this census, all real): (a) hash-each deleted-entry skip path
fabricates a 0 for the loop counter phi (seen in rrtfd's debug path — same
missing-incoming family, lower-priority); (b) DEBUG_PHI_MISSING census: 2439 true
fabrications in an s2 build — top: __vdispatch__Object#to_s 696+75,
lower_method 55×3 + 21×3, lower_def 49+14+12, lower_module_method 44,
register_module_instance_methods_for 26+12, emit_hoisted_allocas 24 — these are
if-merge/exit-phi shapes NOT covered by the β loop fixes (begin/ensure-as-branch-
value drops its value: proven instance = resolve_return_type_from_def's
`resolved = if …; @current_class swap; begin type_ref_for_name(…) ensure restore
end; else …` merge phi gets fabricated null for the ensure path; small reducer of
that exact shape did NOT reproduce — trigger conditions unknown yet).

**START HERE (L11 fix):** (1) reducer: yield method called from ≥2 callsites
whose blocks return DIFFERENT types, one of them nilable (Nil|T), the callee
proc-materialized (block captures locals) — expect callee return union to accrete
without Nil and the nilable callsite to mis-reinterpret; (2) fix candidates, in
preference order: include Nil in the accreted `__block_return__`/return union
when any callsite's block can return nil; make the u2u coercion at block-call
returns tag-aware (remap via union descriptors, nil-checking payload) instead of
raw reinterpret; or per-callsite $block return specialization (heavier, 5c274a28
precedent); (3) then the begin/ensure-as-branch-value family (2439 census) —
reduce with with_type_param_map-style ivar-swap ensure inside a valued if;
(4) THEN flip `ADAMAS_PHI_SHARE_VETO` default ON, rebuild s2, verify L10 llc
reject gone (healthy `Sub#gets_peek` lookups), suites ×2, replace bin/adamas.
Artifacts: /tmp/adamas_beta3 (stage1, fixes+probes+detector), /tmp/s2_beta3v3
(+.ll, s2 with probes), /tmp/s2_beta3_veto.build.log (PHI_MISSING census),
scratchpad extracts irwc.ll / rrtfd.ll / lower_call_s2.ll. Levers:
DEBUG_L11_RT=<name-filter>, DEBUG_PHI_MISSING=1, DEBUG_RETURN_DEF, DEBUG_GET_RETURN,
DEBUG_CALL_RETURN.

## 2026-07-07 — session-11: L10 ROOT-CAUSED (phi-carrier slot-sharing clobber); veto gated

**α root (PROVEN):** `prepass_detect_phi_shared_slots` (llvm_backend.cr): a phi with ≥4
cross-block incomings redirects ALL incomings to one shared alloca (`%r<phi>.phi_slot`),
assuming they die at the phi. An incoming that outlives the merge reads the carrier after
the taken arm's def-site store overwrote it. In s2's `lower_call`, the merge of
`base_method_name = if full_method_name … else … method_name … end` had `method_name`'s
value as one of exactly 4 incomings → every later `method_name` read returned
"IO#gets_peek" → per-owner virtual-target lookups became `IO::FileDescriptor#IO#gets_peek`
(MISS) → demand fell back to base `IO#gets_peek` with the un-narrowed `Nil|Slice(UInt8)`
peek param → GEP on the union carrier → the L10 llc reject.
Trace method: DEBUG_CALL_LOOKUP s1-vs-s2 diff → DEBUG_VIRTUAL_TARGETS → DEBUG_CALL_TRACE
bracketing → DEBUG_L10_MNAME probes A–F (committed) → probe-string markers to navigate the
s2-build .ll → carrier mechanics read directly.

**Fix in tree, GATED OFF:** liveness veto — share only incomings with exactly 1 phi use
and 0 non-phi uses (operand enumeration mirrors prepass_detect_cross_block_values +
terminators + RC/Free/Atomic/Mutex/Channel). Vdispatch stack-frame optimization retained.
Levers: `ADAMAS_PHI_SHARE_VETO=1` (everywhere), `ADAMAS_PHI_SHARE_VETO_FILTER=tok,tok`,
`ADAMAS_PHI_SHARE_LEGACY_FILTER=tok,tok`. Default = legacy (zero behavior change).

**Why gated (β family):** enabling the veto exposes PRE-EXISTING stale-binding MIR:
reads referencing an in-loop/in-branch value id on paths where its def never ran; the
shared carrier accidentally provided variable-cell semantics. Proven instance:
`lower_super` post-loop read of `super_method_name` (ast_to_hir ~62128,
`@function_types[resolved_super_name]?`) loads the slot of the IN-LOOP assignment
(~62108) instead of the post-`unless` merge → null on the fallback path → segfault
(identical under veto AND legacy for lower_super — the read is wrong regardless; old s2
never exercised the path because L10 itself cut those demands). Family =
loop-exit-phi-drop / L8 binding-reverts; repair point resolve_loop_backedge_value.

**START HERE (L10 continuation):**
1. β reducer: `x : String? = nil; while c; x = v if p; break if x; …; end;
   unless x; x = fb; end; use(x)` — check post-loop read binds the in-loop id.
   If small shape GREEN, chase in-vivo on lower_super (probe markers + s2-build .ll).
2. Fix post-loop/post-unless local rebinding (loop-exit merge must rebind to merge phi).
3. Flip `ADAMAS_PHI_SHARE_VETO` default ON, rebuild s2, re-verify: registration crash
   (full-veto β site #1) and L10 llc reject both gone; per-owner lookups `Sub#gets_peek`.
4. Suites ×2, replace bin/adamas.
Session artifacts (all /tmp, wiped on reboot — recipes in memory
`l10_phi_slot_sharing_clobber.md`): s2_l9fix2 (baseline), s2_l10probe1, s2_l10fix1/2/3.

## 2026-07-07 — session-10: L9 dig (see memory `l9_nilable_scalar_union_desync.md` for full trail)

L9 chain: `Path.separators` → Nil in s2 → `Nil#any?` miss → block param Pointer →
`starts_with?` mangled_prefix over-demand → Regex cluster mislowered → llc reject.
10-line s2 reducer `/tmp/l9_cs9.cr` (same llc error as x=1). Two roots, both found by
reading the s2-BUILD artifact IR (`/tmp/s2_l9probe2.ll` — the build keeps its own .ll!):

1. **D2 (FIXED in-tree, llvm_backend emit_global_store):** scalar stored into a
   union-typed global emitted `store <union> zeroinitializer` — the value was thrown
   away (confessional comment included). Every write to a block-captured local through
   a closure cell was silently nil'd; in s2 this killed `lower_method`'s `last_value`
   → all demand-lowered functions got return_type=Nil. Fix mirrors the cross-block
   slot_wrap pattern / original Crystal `store_in_union`: alloca union, store variant
   tag (union-descriptor lookup), store payload, load, store. VERIFIED at s2 level:
   `Foo.sepx$Bool = Tuple(Char, Char)` (was Nil), probes SET:4 (was NIL), original
   `$~` llc reject GONE. No small-scale RED oracle exists (needs materialized-block
   context); coverage = s2 pipeline + suites (82150e13 precedent).
2. **D1 (FIXED in-tree, hir_to_mir):** annotated-block helpers
   (`with_inferred_condition_locals`, `& : -> TypeRef?`) whose inline-yield path bails
   (depth/repeat guards at scale) materialize the block; the `_block` monomorph's param
   arrives typed `Nil | Proc(...)` — infer_block_param_id rejected it →
   `lower_yield` silently returned const_nil (masking hazard, now traced via
   ADAMAS_YIELD_NO_BLOCK_TRACE) → every then/elsif branch type inferred through the
   helper dropped at registration. Fix: accept union-Proc block params + unwrap the
   proc payload before call_indirect. (Caller-side wrap writes tag=0 — tolerated, the
   unwrap doesn't trust the tag.)
3. **@[Flags] FIXED in-tree** (register_enum_with_name_in_current_arena + source-window
   annotation detector): implicit values were 0,1,2 → now 1, prev*2, explicit-reset
   honored (original semantic/top_level_visitor.cr). Oracle
   `regression_tests/flags_enum_implicit_values_repro.sh` RED→GREEN.
   NOTE: `starts_with?(/re/)` anchoring STILL broken after this — next layer is
   `Regex::MatchOptions.each` (enum macro-iteration) yielding nothing in
   pcre2_match_options → flag=0 ([[macro_type_reflection_iterable_hir_gap]] family).

**L10 = NEW s2 floor, CONFIRMED persisting after all three fixes (D1+D2+Flags,
commits `b5d5fa7a`+`9226cea5`+`a90f340d`):** llc rejects `IO#gets_peek`:
`getelementptr i8, ptr %r31.fromslot.4` where the value is a `Nil|Slice(UInt8)` UNION
(field access `.size` on the un-unwrapped union carrier after the nil-check branch).
stage1 monomorphizes gets_peek per-owner with `peek : Slice(UInt8)`; s2 lowers base
`IO#gets_peek` with the union param — typing/demand divergence NOT cured by D1.
D1 verification marker (s2 v2): `Foo.sepx$arity1 = Tuple(Char) | Tuple(Char, Char)` —
then-branches now contribute at registration. NOTE: any prelude compile through s2 now
hits L10, so cs9 is no longer a distinguishing reducer.
START HERE (L10): diff stage1-vs-s2 DEBUG_SET_FTYPE/DEBUG_CALL_LOOKUP on `gets_peek`
(who demands the base `IO#gets_peek`, and what types `peek` at its callsites —
`gets(delimiter, limit, chomp)` calls `gets_peek(..., peek)` with `peek = self.peek`
typed Bytes?); then either fix the demand (per-owner monomorph like stage1) or make
FieldGet/receiver lowering unwrap union receivers before member access
(condition-narrowing leak family). bin/adamas replaced with the 3-fix stage1
(backup `bin/adamas.pre_l9fix`); s2 artifact `/tmp/s2_l9fix2` (+its .ll).

**Open siblings found this session (each with reducer/trail in memory):**
- m2 puts-intercept: `puts x` on narrowed union local → Object#to_s vdispatch on raw
  payload → SEGFAULT (`/tmp/l9_m2.cr`); also the to_s STRING is never printed (MIR).
  Fix design: prefer ctx.type_of(lowered arg) over AST inference.
- classvar lazy-init clobber: `@@v = n` before first read is overwritten by the
  deferred initializer on first get (`/tmp/l9_cvar.cr` shape).
- splat+named-block captured write: `taker(1,2) { c = 42 }` → c reads 0 (box-path
  payload loss? `/tmp/l9_cell.cr`).
- bare-nil-init local + block write at top level still lost (`/tmp/l9_ewi2.cr`,
  no cells involved — different root than D2).
- s2 `#{idx}` (2nd block param of each_with_index) interpolates EMPTY; `.class` of
  arena nodes prints base class in s2.
- single-module `--emit llvm-ir` vs chunked build pipeline can DIFFER in
  materialization decisions (probe copies 3 vs 4) — emission-fidelity hazard for
  IR-based debugging: trust `<out>.ll` kept by build_stage2, not a fresh --emit.

## 2026-07-06 — s2 floor LAYER 3 FIXED (sort_by!/stable-sort family), 5 commits `f8408226..b0bbde54`

The sort_by! nested-tuple blocker was FIVE stacked compiler defects, peeled by
reducer bisection (each fix exposed the next):

1. `f8408226` — **ArrayNew alloc stride**: `emit_array_new` sized buffers by an ad-hoc
   LLVM-type switch (8 for tuples) while get/set/PointerStore/realloc/array-literal
   stride by `container_elem_storage_size_u64` (16 for the nested pair) → heap
   overflow in `Array#map` (Guard Malloc pinned the OOB store; Bus error at next malloc).
2. `20b6ada4` — **ctor copy-at-escape**: tuple constructors stored a BORROW of an
   inline buffer slot; sort_by!'s writeback overwrote `@buffer` while sorted pairs
   still pointed into it (elements duplicated/lost).
3. `258e8f4a` — **bare generic-base class-method owner**: `Slice.merge_sort!(self, comp)`
   inside `Slice(T)#sort!` bound to a bare `Slice.merge_sort!$…` monomorph with no
   per-instantiation type-param map → base-key map is first-instantiation-wins
   (T=UInt8 from Bytes) → `Pointer(T).malloc(size//2)` allocated the merge scratch
   buffer at 1 byte/elem for EVERY non-UInt8 element type. Now binds to
   `Slice(X).merge_sort!` when the instantiation defines the method.
4. `4ea2fc66` — **array_get copy-on-load**: the ungated inline-primitive-tuple branch
   of `emit_array_get` returned the raw slot GEP (borrow) — `x, v[0] = v[0], v[1]`
   in `insert_head!` read the overwritten slot through x. Primitive tuples now
   return a heap-carrier copy (tuples are immutable ⇒ always safe); mutable inline
   container structs keep the borrow.
5. `b0bbde54` — **HIR container-element oracle**: `container_element_storage_size`
   returned 8 for every tuple; it feeds `__adamas_ptr_copy/ptr_move` strides
   (`Pointer#copy_from` in `Slice.merge!`) → scratch-buffer under-copy lost one
   element per merge (SBAPI trace: intact at merge! entry, zeros after). Primitive
   tuples now return `hir_tuple_storage_size` (new `hir_primitive_tuple_type?`).

VALIDATED: full suite 152/152 + 36/36 (default); reducer ladder green on default AND
gated incl. 40-element sort_by!/sort!/manual-Schwartzian (`/tmp/np10_sort_by_big.cr`,
`/tmp/sort_repro.cr`); `array_tuple_sort_by_merge_sort_repro.sh` PASS (was RED at HEAD);
`inline_value_tuple_array_alias_fix.sh`: ALL THREE facets (sort / adv1 local-bind /
adv3 construct) now default-fixed — the whole alias reducer family is green ungated.
bin/adamas replaced (backup `bin/adamas.pre_sortfix`).

**Layer 4 FIXED (`66795ee5` 2026-07-06): while+Proc#call loop back-edge counter drop.**
The "memory runaway" was ONE emit_phi call spinning: hir_to_mir's resolve_pending_phis
keyed phi incomings with the FIRST MIR block of a HIR block (@block_map), but the
Proc#call closure/bare diamond leaves the lowered terminator in the MERGE block →
the LLVM layer found no value for the real CFG predecessor and silently defaulted 0
(append_missing) → any `while` whose body tail crosses a Proc#call reset its counter
each pass (NOT `next`-specific). In self-host: emit_phi's union branch calls the
`block_name` proc → infinite loop allocating interpolated strings at ~700MB/s.
Fix: @block_end_map (HIR block → MIR block holding the lowered terminator) used for
phi incoming resolution. Oracle: `regression_tests/while_next_proc_call_backedge_repro.sh`
(RED pre-fix, GREEN post-fix). Suites 152/152 + 36/36. bin/adamas replaced
(backup `bin/adamas.pre_l4fix`). 4th root of the loop-next family (3 of 4 now fixed).
Masking hazard noted: emit_phi's missing-pred default-0 turns MIR phi-key bugs into
silent runtime spins (int phis have no trace; only ptr has ADAMAS_NULL_PHI_TRACE).

**Layer 6 CLOSED (session-8 2026-07-06): the `T#ascii_number?` stub peeled
into FOUR stacked compiler defects, commits `b74939d8..d2a25168`.** The
reducer `"123".each_char.all?(&.ascii_number?)` (/tmp/l6_allq.cr) exposed,
in order (each fix uncovered the next at runtime):
1. `b74939d8` — **include-chain block-param typing**: include-site
   instantiations were dropped at registration (`@class_included_modules`
   holds declared names only, "Iterator(T)"), so block_param_types_for_call
   could not bind T=Char for String::CharIterator → block proc typed `T`
   (opaque ptr, void return) → `T#ascii_number?` stub. Fix: persist
   `@class_include_instantiations` (full-class-name key ONLY — base keys =
   first-instantiation-wins poison) + consume in block_param_types_for_call.
   Oracle `iterator_module_block_param_type_repro.sh`.
2. `160e2b21` — **separator-blind overload selection**: request
   `Iterator.stop` resolved to INSTANCE `Iterator(T)#stop`; instance body
   (`Iterator.stop`) lowered under the class-method symbol → infinite
   self-recursion (Bus error). Fix: prefer same-separator candidates in
   resolve_call_tuple (cross-separator kept only when no same-sep exists —
   extend-self laxity preserved).
3. `a8040086` — **type-literal member inference built Owner#m**: inference
   of `Iterator.stop` died (routed through Iterator(T)#stop) → Stop dropped
   from CharIterator#next's Char|Stop union → return collapsed to bare Char
   → caller's `is_a?(Stop)` loop exit folded away, stop path coerced Stop by
   DEREFERENCE (null crash). Fix: dot-form name first for type-literal
   receivers + generic-key fallback ("Iterator" → "Iterator(T).stop", typed
   at registration).
4. `d2a25168` — **`INSTANCE = new` never initialized**: bare receiverless
   `new` (IdentifierNode) was (a) not in the deferred-const whitelist and
   (b) lowered to a null literal (auto-synthesized allocators have no
   function entry for the identifier fallbacks). Iterator::Stop::INSTANCE
   stayed null forever. Fix: defer IdentifierNode=="new" + lower bare `new`
   as the current class's zero-arg allocator call.
VALIDATED: reducer true/false/true; suites 152/152 + 36/36 ALL PASSED;
bin/adamas replaced (backup `bin/adamas.pre_l6fix`); s2 rebuilt
(/tmp/s2_l6fix) — T#ascii_number? floor GONE.

**Layer 7 CLOSED (session-9 2026-07-06, commit `b43650ea`): block-shorthand
pseudo-methods parsed as plain method calls.** The `MacroValue#as?` stub was
NOT an as?-dispatch synthesis gap — the callsites are
`vars["T"]?.try(&.as?(MacroTupleValue))` and parse_block_shorthand took any
token after `&.` as a plain method name, so `&.as?(A)` became an ordinary
CallNode `tmp.as?(A)` (real method call → abort stub on abstract receivers)
instead of the AsQuestionNode parse_member_access builds for explicit
`.as?`. Bisection: explicit block `{ |x| x.as?(A) }` GREEN, ANY `&.as?`
form RED; `&.as` and `&.responds_to?` equally broken; `&.is_a?` worked by
accident via a name-based lowering intercept. Fix:
`parse_block_shorthand_pseudo_method` routes As/AsQuestion/IsA/RespondsTo
token kinds to the same parsers parse_member_access uses (both Amp and
AmpDot branches). Oracle `block_shorthand_pseudo_method_repro.sh`
(RED→GREEN). Two pre-existing siblings documented there as parity asserts:
(a) yield-method return type drops the nil variant of `as?` (explicit form
equally affected); (b) `responds_to?` folds on the static type, no virtual
expansion. Suites 152/152+36/36; bin/adamas replaced (backup
`bin/adamas.pre_l7fix`); s2 rebuilt → floor MOVED.

**Layer 8 CLOSED (session-9 2026-07-06, commit `a7d7db53`): array
intrinsics dropped tuple-destructured block params.** The spurious
`private method 'empty?' called for Path | String` chain: parser flattens
`|(a, b)|` to flat params [a, b]; each/any/all re-expanded them but
map/map_with_index/select/reject/compact_map/sum/count bound only the
FIRST name to the whole tuple element (rest unbound). In s2 that
miscompiled `merge_if_branch_locals` (`branch_info.map { |(blk, locals)|`)
→ branch-locals lookups nil → is_a?-branch reassignment merge for `part`
in Path#join reverted to the union param → visibility check resolved
private Path#empty?. Trail: DEBUG_ASSIGN_VAR (existing hook) showed both
branch assigns String; new DEBUG_MERGE_VAR silent (wrong merge fn);
IF_FLOW showed flowing=2 + has_key?=Y while the map-destructure read gave
nil → stage1-level reducer RED in one shot (`Tuple#+` stub on `blk + 1`).
Fix: shared refined_array_block_element_type +
bind_array_block_element_params helpers wired into 9 intrinsics. Oracle
`array_intrinsic_block_destructure_repro.sh` RED→GREEN. Kept env hooks:
DEBUG_VIS_RAISE / DEBUG_MERGE_VAR / DEBUG_MERGE_VAR2. Suites 152/152 +
36/36; bin/adamas replaced (backup `bin/adamas.pre_l8fix`); s2 rebuilt →
floor MOVED. Siblings (open): reduce/zip intrinsics also lack destructure
(2-param-by-design, ambiguous flatten — audit later);
select_intrinsic_with_ast (literal-array select) unaudited; Hash
interpolation `#{hash}` prints empty at stage1 level;
ADAMAS_STAGE2_DEBUG backtrace printer segfaults in s2.

**Layer 9 = NEW s2 floor (session-9): s2 emits invalid LLVM IR for the
`$~` magic-var classvar store.** `/tmp/s2_l8fix` compiling `x = 1`:
parallel LLVM worker dies (exit 4) → sequential llc fails at
`/tmp/x_s2_out.ll:10383`: in `String#starts_with?$$Regex_MatchOptions`,
`%r7 = call %"Nil|Regex::MatchData.union" @Regex#match_at_byte_index$$String_Int32_Int32(ptr %re)`
then `store ptr %r7, ptr @$$__classvar__$$$NOT` — TWO defects visible:
(a) the call passes ONLY the receiver (String/Int32/Int32 args dropped);
(b) the `$~` classvar (`$$__classvar__$$$NOT`) store writes a by-value
union with `ptr` store type (decl/store type mismatch). Note stage1
compiling x=1 does NOT lower this function at all (s2 over-demands it —
possibly a third symptom). START HERE: read s2's full IR of that function
(/tmp/x_s2_out.ll:10370+, artifact survives until reboot); find the
stage1 lowering path for `$~ = re.match_at_byte_index(...)` in stdlib
string.cr starts_with? (magic-var assignment through classvar) and for
match_at_byte_index arg materialization; craft a stage1-level reducer
(compile-a-file-that-uses `str =~ /re/`-family with the CURRENT
bin/adamas, inspect ITS .ll) before any s2 instrumentation — L8 proved
the stage1-reducer-first route pays off.

**Layer 5 (CLOSED session-7) was: llc rejects s2 output (`sext i64 to i64`).** Fixed-s2
(`/tmp/s2_l4fix`) compiling `x = 1`: emission completes (peak 2.1GB, no runaway),
llc fails on `%inttoptr.4.ext = sext i64 %r24 to i64` — the arg-coercion guard
`src_bits < 64` (llvm_backend ~23075) evaluates WRONG inside s2 for "i64".
Two instant stage1-level reducers (both pre-existing, RED on bin/adamas AND
bin/adamas.pre_l4fix, ~20s each, no s2 build needed):
- (a) **FIXED `7b92e8d8` (session-7)**: NOT range_to_index_and_count — the
  String#[](Range) compiler INTERCEPT (ast_to_hir ~92030) lowered the slice
  inline as `len = end - begin (+1)`; the parser stores a NilNode end for
  `s[1..]`, nil lowered to 0 → len = 1 - begin → ""/1-char slices (defect-1
  intercept family). Fix: NilNode end → `len = bytesize - begin` (helper
  clamps). `Array#[1..]` goes through the real Array#[](Range) and was
  already green post-D4 (its old SEGFAULT not reproducible). typeof(1..) at
  statement level = Void (parser only makes NilNode end before `)]},;end
  else elsif do {` — newline NOT included, bare `r = 1..` eats the next
  line) — pre-existing, separate. Oracle:
  `regression_tests/string_endless_range_slice_repro.sh`. Suites 152+36.
  bin/adamas replaced (backup `bin/adamas.pre_d5fix`).
- (b) **2026-07-06 sessions 6-7: peeled into a FOUR-defect stack; ALL 4 FIXED.**
  The "wrong id-space tag" hypothesis was WRONG — tags were fine; the chain was:
  1. **FIXED** (ast_to_hir ~77050 + ~82337): the String#to_i/to_i32/to_i64/to_u*
     strtol intercepts fired on BLOCK forms — stdlib `to_i32? = to_i32(...) { nil }`
     got replaced by `__adamas_string_to_i_base` (cannot signal nil) → `"".to_i?`
     returned wrapped Int32(0). Now gated on `!has_block_call`. Companion: the
     numeric-conversion Cast fallback (to_* → Cast) required arg-less/block-less
     calls on primitive receivers (it used to bitcast the STRING POINTER into the
     union payload once the intercept was gated).
     Oracle: `string_to_i_nilable_block_intercept_repro.sh`.
  2. **FIXED** (parser.cr parse_prefix Yield case): `return yield if cond` bound the
     suffix-if to the YIELD (parse_postfix_if_modifier ignored
     @consume_postfix_modifiers) → `return (cond ? yield : nil)` → EVERY statement
     after it dead (gen_to_ lost `Int32.new(info.value)` etc.).
     Surgical fix: only the Yield case honors the flag. NOTE: Super/Break/Next
     prefix cases + assignment sites (1204/1208) have the same latent hole — a
     CENTRAL flag check in parse_postfix_if_modifier broke prelude compile
     (io.cr gets_peek "private method 'bytesize' for Pointer(String)") — needs
     its own investigation before generalizing.
     Oracle: `return_yield_postfix_if_tail_repro.sh`.
  3. **FIXED** (llvm_backend emit_call final value_types update →
     `call_result_type_ref_for_emitted`): emitted-LLVM-string → TypeRef mapping
     erased unsignedness ("i32" → INT32) → `~UInt32.new(0) // base` emitted sdiv
     (-1 sdiv 10 = 0) → to_unsigned_info mul_overflow=0 → every multi-digit parse
     bailed after digit 1 ("64".to_i? == 6). Now prefers callee return / inst.type
     when LLVM widths match. Oracle: `call_result_unsigned_div_repro.sh`.
  4. **FIXED `a482a1e1` (session-7 2026-07-06): record-initialize param SPAN
     POISONING** — NOT slice-lifetime: the probe showed the raw Parameter.name
     slices were INTACT ("value"/"negative"/"invalid"); the garbage came from
     `parameter_span_text_from_extra_sources`, which scans the LAST-16 window
     of the arena's retained expansion texts and returns the first
     plausible-identifier slice from a FOREIGN buffer ("th_ind" ⊂
     "each_with_index"; macros.cr arena had 179 extras, the record expansion
     long out of the window). Spans are bare offsets — they cannot identify
     WHICH retained buffer they index; with fallback_to_slice=false the exact
     raw slice was never even computed. FIX: parameter_name_string /
     parameter_type_annotation_string compute the raw token slice
     unconditionally and, in arenas holding retained macro-expansion sources,
     prefer it over any non-matching span guess (raw slice IS the generated
     source). `""`/`"abc"`.to_i? now skip the if-let; `"64".to_i?` == 64
     end-to-end. Oracle:
     `regression_tests/record_initialize_param_span_poisoning_repro.sh`.
     Suites 152/152 + 36/36. bin/adamas replaced (backup
     `bin/adamas.pre_d4fix`).
  Also observed (separate, minor): `v1.nil?` on `Int32?` from to_i? is STATICALLY
  folded to false (emitted `puts Bool i1 0`) — static nil?-narrowing defect;
  and `.inspect` on plain Int32 locals segfaults via `Object#inspect` vdispatch
  (pre-existing on old bin/adamas too, repro /tmp/l5_insp2.cr).
  Reducers: /tmp/l5_toi.cr, /tmp/l5_disc.cr, /tmp/l5_rec*.cr.

**Known open siblings surfaced by this dig (pre-existing, reducers in session log):**
- `Slice(Int32).new(ptr, size)`-style calls in main bind receiver to the FIRST Slice
  instantiation (Slice(UInt8)) — values <256 masked it (np12).
- User-level `Proc#call` with nested-tuple args returns garbage/empty (np24).
- `&block : {T,T} -> Int32` block params typed `Int32?` → `Int32?#[]` stub (np26)
  = the documented nested-tuple block-param `|_, cost|` family.
- `::Array({ {A,B}, C }).new` nested TupleLiteral parse STUB (`7c2f06b9` not nested-aware).
- `Array(Int32)#sort!(&block)` lowers to the `__adamas_sort_i32_array` intrinsic which
  IGNORES the comparator block (reverse sorts silently wrong?) — verify + fix.

## 2026-07-05 — s2 self-host floor LAYER 2 FIXED (forward const-alias fold), committed `546f2c07`

Layer 2 (the `tuple_slot_layout` crash) was **NOT** the "Array-buffer corruption" the
prior session's notes described — that was a **misdiagnosis from a misattributed crash
offset**. The exact crash instruction (`ldr x8,[cv]; ldr x8,[x8]`) is a **null double-load
of the boxed `POINTER_WORD_BYTES` classvar** in the `else` branch of `tuple_slot_layout`'s
element-size rule (layout_contract.cr:156/158), not `elem.kind` (:117); `elem` was fine.

ROOT: `POINTER_WORD_BYTES = MIR::TARGET_POINTER_BYTES_U64` is a **forward, cross-file
constant alias** — `mir.cr:16 require "../layout_contract"` runs before `Adamas::MIR::
TARGET_POINTER_BYTES_U64` is defined (mir.cr:29). Our single-pass const folder can't
resolve the target at record time, so the alias degrades to an uninitialized boxed
`global ptr null` and crashes on first read. FIX = `reevaluate_alias_constants`
(ast_to_hir.cr): a second-pass fixpoint fold (mirrors `reevaluate_offsetof_constants`)
that retries after all constants are registered, promoting integer/bool aliases to static
`global i64 N`. Validated on a multi-file `require`-ordering reducer (`global ptr null` →
`global i64 8`); the crash moved past `register_tuple_types`. Gate **152/152 + 36/36**,
zero regressions. bin/adamas replaced (pre-fix backup `bin/adamas.pre_alias_fix`).

**Layer 3 = NEW s2 floor (owner-gated P1 inline-tuple ABI):** s2 now crashes (139) in
`func_costs.sort_by! { |_, cost| -cost }` (`emit_functions_parallel`, llvm_backend.cr:18326).
`Array#sort_by!` = `map { |e| {e, yield e} }.sort! { |x,y| x[1] <=> y[1] }` builds the
**nested-tuple pair array `Array(Tuple(Tuple(Int32,Int32),Int32))`** and reads `x[1]` at
offset 8 → Bus error on the default ABI, and **silent corruption with both inline-value
gates ON** (falsifies the earlier "both-ON = GREEN whole sort family" note; only the plain
`sort!` variant is green). Fast reducers: `/tmp/sort_repro.cr` (sort_by! Bus error/corruption),
`/tmp/nested_tuple_repro.cr` (explicit `::Array({nested}).new` hits a SEPARATE parse STUB —
`7c2f06b9` did not cover NESTED tuples). See `s2_selfhost_floor_array_corruption` memory.

## 2026-07-05 — s2 self-host floor LAYER 1 FIXED (union-arg dispatch), committed `82150e13`

The s2 self-host floor (SIGSEGV compiling any prelude program) was TWO stacked bugs.
**Layer 1 (the majority crash) root-caused + fixed:** `try_emit_union_arg_dispatch`
(ast_to_hir.cr) built `UnionIs.new(ctx.next_id, ua, fv)` WITHOUT the union type ref,
so `emit_union_is` fell back to a `variant-0 == nil` null-check. For an all-reference
union with no Nil variant (`ArenaLike = AstArena|VirtualArena|PageArena`) variant 0 is
the FIRST class → every non-null AstArena tested false → dispatched into the sibling
`node_for_expr$$..._PageArena` arg-monomorph → PageArena#[] read the AstArena through
its own layout → garbage node → the `infer_ivars_from_expr` / `infer_type_name_from_node`
wild-pointer crash. Fix = pass `ut` to UnionIs (all-ref header-tid comparison).
Validated: rebuilt stage1+s2, misdispatch gone (ADAMAS_NODE_VALIDITY detector 0/6);
`run_all_suites` 152/152 + 36/36 green.

**Layer 2 — RESOLVED `546f2c07` (see the section above; this description was a
misdiagnosis — the crash was a boxed-const null double-load, not Array-buffer
corruption).** Original (incorrect) session-2 note kept for provenance:
**Layer 2 (was believed OPEN):** `LayoutContract.tuple_slot_layout`+768
NULL-deref ← `register_tuple_types` — an `Array(MIR::Type)` buffer whose size/contents
are unstable between a guard read and `.each` (a SEPARATE root; the layer-1 UnionIs fix
does not touch it). Self-host floor NOT yet cleared. NEXT: instrument tuple_slot_layout
to log the null index + `elements.size` vs the register-site size (detect the flip), then
trace what corrupts the MIR::Type array. Possible sibling: the untouched SECONDARY 2-way→N-way
arity limitation in `try_emit_union_arg_dispatch` (a >2-variant union-arg call misrouting its
3rd+ variant). See knowledge memory `s2_selfhost_floor_array_corruption`.

## 2026-07-05 — inline-tuple ABI step 2 SHIPPED: tuple slot-layout + POD predicate single-sourced (byte-neutral), gate green

Prereq consolidation for the tuple-slot-layout flip (the nested-tuple `@buffer`
alias behind the `sort_by!` blocker below). Two behavior-neutral commits collapse
the drift-prone tuple layout logic onto `LayoutContract` so the flip can later land
in ONE place:

- **`c3d87e12`** — 5 mutually-equivalent Class-T tuple slot-layout sites →
  `LayoutContract.tuple_slot_layout(elements) : {size, align, offsets}`
  (register_tuple_types size/align, lower_allocate offsets, llvm const-index,
  llvm runtime-index). Removes the latent hir-`pointer_word` vs llvm-hardcoded-`8`
  divergence (all route `POINTER_WORD_BYTES`/`POINTER_WORD_ALIGN`). Function takes an
  explicit `Array(MIR::Type)` (register_tuple_types runs before `element_types` is
  populated); site-5 stride block left intact, reading `.offsets`.
- **`93a27be8`** — byte-for-byte-dup `inline_primitive_tuple_type?` (hir == llvm) →
  `LayoutContract.primitive_tuple?` (both files now thin delegators); `pod_tuple?` +
  `INLINE_TUPLE_MAX_BYTES` moved to `LayoutContract`; `pod_tuple? = primitive_tuple? && ≤16`.
  Corrects the census's backwards reconcile direction: the UNBOUNDED, ungated, ACTIVE
  predicate is the shared source; `pod_tuple?` is its bounded, gate-only specialization
  (routing active→bounded would have flipped >16B container storage = not byte-neutral).

DoD: MIR **and** LLVM-IR byte-identical to the clean `2e202c2e` baseline on no-prelude
tuple oracles (homogeneous / mixed-align / nested / union>8 / Float64 / Int16; const +
runtime index paths); full regression gate 152/152 + 36/36.

- **STEP 4 (the geometry flip) — DEPRIORITIZED, OFF-TARGET (VERIFIED 2026-07-05).**
  Empirical grounding showed the documented flip of `tuple_slot_layout`'s `else`
  clause does NOT dissolve the `sort_by!` alias: `tuple_slot_layout` returns ONLY
  geometry (`size/align/offsets`); the tuple constructor store (hir_to_mir.cr:5193)
  does `builder.store(field_ptr, arg_val)` UNCONDITIONALLY (stores the borrow
  pointer). For the 8B blocker shape the geometry is byte-identical either way, so
  the flip is a no-op for the alias — and flipping the inner align 8→4 would ripple
  the OUTER tuple 16→12B (NOT byte-neutral OFF). The alias fix lives in load/store
  copy semantics, which is exactly the P1 behavior slice below — NOT geometry. Step 3
  (SLOT-CONFLICT verifier) is likewise deprioritized.

## 2026-07-05 — sort_by! blocker ROOT-CAUSED = value-tuple PointerCarrier alias; inline-tuple ABI SDD + P0 landed

Frontier from the previous section (`sort_by!`/merge_sort on `Array(Tuple)`)
ROOT-CAUSED and VERIFIED. Root: a value-aggregate tuple element read from a
container is a `PointerCarrier` whose pointer is `array_get`'s **borrow into the
source buffer**, not a copy. `sort_by!` builds `Tuple(Tuple(Int32,Int32),Int32)`
via `map { |e| {e, yield(e)} }`; the nested tuple's inner element aliases `@buffer`;
the writeback then overwrites `@buffer` while `sorted[i][0]` still borrows it →
`[{1,100},{3,75},{3,75}]`. Triple-verified: `.ll` (`load ptr` + `memcpy 8` from a
carrier), runtime probe (`mapped[j].box == &costs[j]`), exact output match. Two
facets, both via HIR `copy`: **A** construction (`{arr[i],k}`, the s2 blocker) and
**B** local binding (`a = arr[i]`, ADV1).

Chosen fix (owner: performant + original-Crystal-like): move value-tuple elements
`PointerCarrier → InlineBytes` (eliminate the heap box), NOT copy-the-box.
Spec: `docs/inline_value_tuple_abi_sdd.md` (Tuple arm of `abi_struct_value_sdd.md`;
refuted-branch-aware — do NOT route tuples through the generic magic-base path,
`abi_rework_quadr_plan.md` §4).

- **P0 DONE** (`680a55d3` spec, `e5687dd4` code): recursive `pod_tuple?` predicate +
  gated (`ADAMAS_INLINE_VALUE_TUPLE`) `InlineValueCopy` classification. Byte-identical
  OFF (MIR identical old-vs-new; .ll differs only in pre-existing `stub_name` hash
  nondeterminism). Census on the blocker: `Tuple(Tuple(Int32,Int32),Int32)` correctly
  classified; 37 pod tuples admitted / 165 excluded; read-provenance **erased tail
  0.7%** → inline slice can be a mostly-local codegen patch (A' falsifier PASSES).
- **P1 — the behavior slice is ALREADY WIRED; both gates together fix the alias
  (VERIFIED 2026-07-05).** No new codegen was needed: `ADAMAS_INLINE_VALUE_TUPLE`
  classifies `pod_tuple?` as an `InlineValueCopy` element candidate (so it enters the
  safe-set + `inline_array_storage_eligible`), and `ADAMAS_INLINE_VALUE_ARRAY_STORAGE`
  is the A' inline-store + copy-on-load slice that breaks the borrow. Bisection: each
  gate alone RED, BOTH ON GREEN.
  - DoD progress: **RED oracle + ADV1 (local-bind) + ADV3 (construct) DONE** —
    `regression_tests/inline_value_tuple_array_alias_fix.sh` (3 facets: legacy
    miscompiles, both-gates fixes). **Full suites 152/152 + 36/36 with both gates ON
    = GREEN (no regression).** REMAINING: s2 bootstrap with gates ON + perf delta.
  - SHIPPING (owner-gated): flipping the two gates default-ON is the ship. Blast
    radius = all pod-tuple + inline-array codegen; suite-clean but pending s2 + perf.
    Decide narrow-default-on vs stay-gated after s2/perf evidence.
- Stopgap (kill-condition fallback, not the goal): copy pod-tuple ctor-arg in
  `lower_allocate` (keeps PointerCarrier, fixes alias, perf-neutral).

## 2026-07-05 (deep night) — s2 STUB CLOSED (::Array(Tuple) call-stub); + u2u payload-width fix; new frontier = sort_by! merge_sort on Array(Tuple)

- `7c2f06b9` CLOSED the s2_v13/v14 STUB manifestation (`Array$Dcall$$Tuple`).
  Root: `::Array({Int32, Int32}).new(n)` — global-scoped generic instantiation
  whose type argument is a bare tuple literal — was misparsed. The parser emits
  bare `Array({...})` as a GenericNode (→ type literal) but the `::`-scoped form
  as a CallNode whose callee is a PathNode and whose `{T,U}` is a TupleLiteral
  *value* node. In `lower_call`, `type_like_call_expr?` gates the
  generic-instantiation path and required every arg to satisfy
  `type_like_expr_id?`, which does NOT classify a TupleLiteralNode as type-like.
  So `::Array({Int32,Int32})` fell through to the "complex callee" fallback
  (ast_to_hir ~76417: `method_name = "call"`), producing a phantom
  `Array.call({0,0})` then `.new()` on the bogus result (HIR:
  `%N = call Array.call$Tuple(Int32, Int32)(%tuple) ; %M = call %N.new()`).
  Fix: new `type_like_call_arg?` — `type_like_call_expr?` now accepts a
  tuple-literal arg whose elements are themselves type-like. Only widens the
  classifier for uppercase/::-scoped bases (always a generic instantiation in
  Crystal); direct value-tuple receivers `{1,2}.size` unaffected (different
  caller ~75571). Pre-existing (reproduces on pre-d7dc440c stage1), was masked
  by the earlier reparse stub. Oracle: `cc_array_tuple_new_call_stub_repro.sh`
  (STUB pre-fix, PASS now). Debug lever used then removed: `DEBUG_CCNEW`.
- `0b008b47` — INDEPENDENT latent corruption caught while investigating:
  the d7dc440c u2u coerce (variant_type_id=-2) copied the union payload with a
  single `load ptr`/`store ptr` = 8 bytes, TRUNCATING wide inline payloads
  (Tuples). Confirmed live in self-host via new `ADAMAS_U2U_TRACE` lever
  (pay_bytes 12/16/24). Fix: memcpy min(src,dst) payload bytes
  (`union_payload_byte_width`/`union_payload_copy_bytes`). NOT the STUB root
  (STUB persisted after this fix).
- Both fixes: suites 152/152 + 36/36. s2_v16 rebuilt (/tmp/s2_v16, both fixes):
  **STUB gone 0/10** (was 2/8). s2 now reaches EMISSION.
- **NEW s2 frontier — TWO remaining crash tails (both on the critical path):**
  1. EMISSION crash (unmasked by the STUB fix): `sort_by!` /
     `Array(Tuple(...))#sort!` → `Slice#merge_sort!` on an array of tuples
     corrupts memory. lldb bt (s2_v16): `__crystal_block_proc_303` (addr 0x60)
     <- `Slice(UInt8)#cmp(Tuple(...))` <- `Slice#merge_sort!` <-
     `Array(Tuple(Tuple(Int32,Int32),Int32))#sort!$block` <-
     `emit_functions_parallel` (which does
     `func_costs.sort_by! { |_, cost| -cost }`). RED oracle
     `array_tuple_sort_by_merge_sort_repro.sh` + reducers /tmp/s_lit_sort.cr,
     /tmp/s_noc_sort.cr. Reproduces WITHOUT `::` and with a plain array literal
     → root is tuple-in-Slice/merge_sort, not the `::` form. Nondeterministic
     (memory corruption): sometimes segfaults, sometimes wrong sort output.
     NOTE existing `sort_by_tuple_key_runtime_repro.sh` PASSES (sorts a
     REFERENCE array by a tuple KEY) — different family; the new bug is an
     array whose ELEMENTS are tuples + destructuring block `|_, cost|`.
     **START HERE** — reduce whether trigger is destructure params vs
     tuple-element Slice ABI in merge_sort; --emit hir/mir on the reducer.
  2. REGISTER-phase arena corruption at `module register idx=3/141`
     (infer_ivars) — the separate @arena object/storage corruption traced to
     d7dc440c, still open (ASLR-nondeterministic; runs that pass registration
     now reach emission and hit tail #1). See
     [[declared_ivar_nil_widen_fix]] / [[vdispatch_variant_underenum_rta_demand_fix]].
- Artifacts: /tmp/s2_v16 (both fixes), /tmp/s2_v15 (u2u only),
  bin/adamas.pre_u2u_memcpy_backup (d7dc440c stage1),
  bin/adamas.pre_declared_ivar_backup (pre-d7dc440c).

## 2026-07-05 (later) — vdispatch variant under-enumeration CLOSED (all-ref union RTA under-demand); s2_v13 arena crash is a SEPARATE @arena-object corruption

- Closed the pre-existing vdispatch under-enumeration family (RED oracle
  `9ae8eae1`). Root: a virtual method call on an all-reference union receiver
  (`ArenaLike = AstArena | PageArena | VirtualArena`) collapses the call name to
  the FIRST concrete variant (`resolve_union_method_call`). Method-level RTA
  keys off that collapsed name, so only the first variant's method was demanded;
  the siblings were never lowered. The generated `__vdispatch__` switch then
  enumerated only the first variant's case (missing variants hit `unreachable`
  → LLVM folds to an arbitrary branch: t0=1 t1=1 t2=1 instead of 1/2/3).
  The three union-variant-lowering sites (instance call ~81530, MemberAccess
  ~94588, indexed `[]` `ensure_index_union_virtual_targets_lowered`) already
  call `lower_function_if_needed` per variant, but lazy RTA deferred the
  siblings: the pending-queue owner gate only keeps method parts recorded as
  virtual receivers, and only the collapsed first variant was recorded.
  Fix: new `rta_record_union_receiver_targets` records ALL variants as virtual
  receivers (bare method part) at all three sites; `rta_method_part_matches_owner?`
  gains a bare-part fallback so arg-typed pending names (`Owner#[]$ExprId`) match
  too (bounded by the existing has-method guard + `rta_live_owner?`). Purely
  additive to RTA demand — can only lower MORE correct functions.
  Oracles: `union_vdispatch_variant_enum_repro.sh` (0-arg, RED→GREEN), new
  `union_vdispatch_indexed_variant_repro.sh` (arg-typed `[]`, RED→GREEN).
  Suites 152/152 + 36/36; combined-suite wall time unchanged (262s vs 262s).
- IMPORTANT — this is NOT the s2_v13 registration crash root. Static check of
  the pre-fix s2_v13.ll shows the arena vdispatch is ALREADY complete:
  `__vdispatch__…AstArena…#[]$…ExprId` and `…#size` both enumerate all three
  global tids (AstArena=735 / PageArena=742 / VirtualArena=739). So
  `arena[expr_id]` in `infer_ivars_from_expr` dispatches correctly; the value it
  returns is garbage (`node = 0x20726f20746e6174` = ASCII "tant or "), so
  either `@arena` is a corrupt/wrong object or a valid arena with corrupt
  storage. The class-dispatch vdispatch has a null guard, and the bad pointer is
  non-null string data (not nil), so this is a memory-corruption / wrong-object
  bug, NOT tid-0/nil dispatch. Traced to d7dc440c (v12 passes registration
  deterministically, v13 corrupts it; sole code delta) but NOT via
  under-enumeration.
  EMPIRICAL CONFIRMATION: s2_v14 (stage1 530a5c1a = the vdispatch fix,
  /tmp/s2_v14 32.3MB) crashes IDENTICALLY to s2_v13 — run1 exit 139 segfault at
  Crystal::Once::Operation expr=15; runs 2-4 exit 134
  `STUB CALLED: Array$Dcall$$Tuple$LInt32$C$_Int32$R`
  (= `Array.call(Tuple(Int32, Int32))`) during infer_ivars for
  `Array(Array(Tuple(UInt64, UInt64, String)))`. So the vdispatch fix is
  orthogonal to s2_v13 and does NOT regress the self-host build (same STUB, not
  a new one). New concrete lead: Array has no `.call` — stage1 miscompiled some
  compiler method to dispatch to the `Array.call` stub instead of the real
  target (proc/tuple↔Array type-confusion, same family as the @arena
  corruption). START HERE for s2_v13: under lldb at the crash, read the
  `@arena` union header + payload BEFORE `arena[expr_id]` (is @arena a real
  arena? does its storage pointer point at live memory?); then bisect which
  stage1-emitted store writes the corrupt value — prime suspects are the
  d7dc440c u2u coerce (`emit_union_wrap` variant_type_id=-2) and the declared-
  ivar widening gate, since @arena is exactly the ivar they changed.

## 2026-07-05 (late night) — s2_v12 reparse STUB CLOSED (declared-ivar Nil-widening); s2_v13 frontier = register-phase type-confusion / Array.call STUB

- `d7dc440c` CLOSED the s2_v12 frontier. Root cause (caught with the new
  `ivar.union.widen` debug hook, -Ddebug_hooks + ADAMAS_DEBUG_HOOKS): both
  InstanceVar branches of lower_assign silently REPLACED a declared ivar
  type with union_type_for_values(existing, value) when the RHS static type
  mismatched and sizes were equal. ONE un-narrowed nilable assignment inside
  a block proc (fn=__crystal_block_proc_227, with_arena family — stage1
  flow narrowing does not survive block-proc capture) permanently poisoned
  AstToHir @arena to Nil|ArenaLike; all later @arena reads demanded
  Nil-widened specs with no matching body (reparse_expr_for_macro + the
  whole stub cluster next to it: reparse_named_arg_for_macro,
  callsite_snippet_for, register_function_def...). Also seen: second widen
  event added String to the same union (Nil|ArenaLike|String Array
  classvars in nm).
  Fix: (1) @declared_typed_ivars registry marked at every explicit
  annotation registration path; widening branches keep declared types
  (hook: ivar.union.declared). (2) coerce_value_to_type union->union via
  UnionWrap variant_type_id=-2 sentinel; emit_union_wrap preserves payload
  + remaps positional tid (mirrors phi/call-return u2u paths).
  Oracle: declared_ivar_nil_widen_repro.sh (RED pre-fix / GREEN; nm check
  for Nil-widened demand). Suites 152/152 + 36/36. Reducer lesson: 6
  shapes of guarded nilable assignment all narrowed correctly — only the
  UNGUARDED assign reproduces; the real-world poison needs block-proc
  capture, don't chase it in a no-prelude reducer.
- NEW pre-existing family found while verifying (RED oracle
  `union_vdispatch_variant_enum_repro.sh`, `9ae8eae1`): __vdispatch__ for
  all-reference unions enumerates only a SUBSET of variants (t0=1 t1=1
  t2=1 instead of 1/2/3); missing variants fall into unreachable default →
  arbitrary dispatch. Same family as the select-0/1 tid sibling
  (llvm_backend ~22004). This also makes .tag-style probes unreliable in
  oracles — use is_a? chains instead.
- **s2_v13 frontier** (stage1 d7dc440c, /tmp/s2_v13, 32.3MB): reparse STUB
  DEAD; `puts 42` now dies with `STUB CALLED: Array$Dcall$$Tuple(Int32,
  Int32)` right after lower_main (plain run), and under lldb an
  EXC_BAD_ACCESS in AstToHir#infer_ivars_from_expr <- infer_ivars_from_body
  <- register_concrete_class <- register_nested_module, reading ASCII
  garbage as pointer (0x20726f20746e6174 = "tant or ") — s2's own execution
  type-confuses a string as a node/pointer during class registration.
  START HERE: two manifestations, likely one miscompile; run /tmp/s2_v13
  twice more to see which is stable; then bisect which stage1-compiled
  function feeds garbage into infer_ivars_from_expr (ADAMAS_TRACE_IVAR_INFER
  filter exists in that function).
  Artifacts: /tmp/s2_v13, bin/adamas.pre_declared_ivar_backup (pre-fix
  stage1), scratchpad nilwiden/ reducers v1-v8.
- Open tails carried over: next-value discard;
  maybe_generate_accessor_for_name ungated; Path#anchor.inspect segfault;
  block-proc capture loses flow narrowing (the poison source — root of a
  future family).

## 2026-07-05 (night) — Path#each_parent brk CLOSED as THREE stacked stage1 miscompiles; s2_v12 frontier = STUB reparse_expr_for_macro (Nil-widened arena arg)

- The s2_v11 frontier (`brk` in Path#next_part_separator_index <-
  Path#each_parent <- Dir.mkdir_p <- emit_functions_parallel) was three
  independent stage1 bugs stacked on one code path; all fixed, one commit
  each, suites 152/152 + 36/36 after each:
  1. `f9ad76a1` inline-yield + next trap: blocks with BOTH `next` and a
     non-local return are force-inlined; inline_block_body pushed a
     yield-continuation block for `next` but the wiring guard
     `unless ctx.get_block(...).terminator` was ALWAYS false (HIR
     Block#terminator is non-nilable, defaults to Unreachable — hir.cr:1688),
     so the continuation stayed an orphan Unreachable and every executed
     `next` trapped. Fix: @yield_cont_next_locals registry (lower_next
     records {block, locals} per next edge) + terminate_if_open wiring +
     merge_yield_cont_locals phi-merge of locals across next/fall-through.
     Oracle: yield_block_next_nonlocal_return_repro.sh. Known limitation:
     `next value` still discards the value (matters only if callee reads the
     yield result).
  2. `aabcae3d` zero-iteration loop-exit: lower_while normal exit registered
     the saved RAW latch value for inline vars (legacy each_with_index
     rescue) — does not dominate the exit when the loop runs 0 times (read
     garbage start_pos=0). Fix: vars_backedge_complete — use the header phi
     when its backedge was patched; raw-value rescue kept only for
     unpatched-phi legacy paths. Oracle:
     inline_loop_zero_iter_exit_value_repro.sh.
  3. `0494ab7c` explicit setter bypass: `obj.field = v` lowered to raw ivar
     FieldSet whenever @field exists (both MemberAccess branches of
     lower_assign), and ensure_accessor_method synthesized a bare ivar-store
     accessor shadowing the not-yet-lowered real def. Char::Reader#pos=
     re-decodes current_char; the stale reader made each_parent print
     "/a/", "/a/b", "/a/b/c". Fix: gate both on
     function_def_overload_keys("Class#field=") — property accessors
     register no DefNode and keep the FieldSet fast path (verified).
     Oracle: explicit_setter_dispatch_repro.sh.
     `path_each_parent_block_tuple_return_repro.sh` is now GREEN.
- Method note: the no-prelude reducer of the SHAPE (struct-each + next +
  non-local tuple return) reproduced harder than full-prelude and made each
  layer visible via --emit hir in minutes. New debug lever:
  ADAMAS_DEBUG_NEXT=1 traces lower_next path/target/depth.
- s2_v12 VERIFIED (stage1 0494ab7c, /tmp/s2_v12, 27.6MB): mkdir_p brk DEAD;
  compiling `puts 42` now aborts ~1s after lower_main with
  `STUB CALLED: Adamas::HIR::AstToHir#reparse_expr_for_macro$$ExprId_
  Nil|AstArena|PageArena|VirtualArena_AstArena|PageArena|VirtualArena`
  (lazy HIR lowering during emission demands it). Analysis: the demanded
  specialization's FIRST arena param is Nil-WIDENED, but the def's
  restriction is `ArenaLike = AstArena | VirtualArena | PageArena` (no Nil,
  ast.cr:4832) -> no matching body -> STUB. Callsites pass `@arena`
  (ast_to_hir.cr:11675) — stage1's ivar-type inference for the self-hosted
  AstToHir apparently widens `@arena` to nilable. Same family as the open
  "union-arg vs restriction" tails.
  START HERE: reduce to no-prelude oracle — class with ivar declared as
  2-3-variant union alias, some path assigning it via `[]?`-style nilable
  lookup, method with the alias restriction called on the ivar; check the
  demanded mangled name for Nil-widening. Then find where stage1 widens the
  ivar type (ivar inference vs assignment-site union) and whether the
  restriction match should strip Nil via flow narrowing at the callsite.
  Artifacts kept: /tmp/s2_v11, /tmp/s2_v12, bin/adamas.pre_yield_next_backup
  (pre-f9ad76a1), bin/adamas.pre_rand_rt_backup.
- Side finding (separate family, NOT in scope): `Path["/a"].anchor.inspect`
  segfaults under stage1 (found while probing; parent/dirname fine).

## 2026-07-04 (late night) — base-name return-cache sibling FIXED (8cab1d05): argful callsites no longer typed from the zero-arg overload

- ROOT (open sibling 2 from the rand family): TWO lossy fallbacks served the
  FIRST def of an overload family regardless of callsite arity —
  `lookup_function_def_for_return` fell back to `@function_defs[base_name]`
  (zero-arg `def rand : Float64`), and `get_function_return_type`'s tail
  returned `@function_base_return_types[base_name]` for TYPED specializations
  (its own comment said "no $ suffix", the code never checked). Every
  `r.rand(n)` was statically Float64 -> interpolation demanded Float64#to_s
  -> Ryu `Printer.shortest` STUB abort in the s2-built compiler (the
  File.tempname parallel-emission blocker).
- KEY LESSON (half the session): typeof/interpolation take types from the
  LOWERED call (`lower_typeof` -> `ctx.type_of`), NOT from
  `infer_type_from_expr` / `resolve_typeof_call_chain`. Two speculative
  patches to the static helpers were reverted after probes showed those
  paths never fire for these expressions. The authoritative owner is
  lower_call's return_type pipeline (~79550) + get_function_return_type
  (~45400). Levers: DEBUG_CALL_TRACE (stage-by-stage, return=<id> at
  before_lower_function), DEBUG_RETURN_DEF (which def served the
  annotation), DEBUG_GET_RETURN (cache state on entry). TypeRef ids:
  4=Int32, 5=Int64, 13=Float64.
- FIX `8cab1d05`: optional `call_arg_count` threaded from lower_call
  (`nil` when block/named-args/splat) through get_function_return_type ->
  lookup_function_def_for_return -> lookup_return_def_from_overloads ->
  resolve_return_type_from_def; predicate `return_def_accepts_positional?`
  (positional_required <= argc <= positional_count; def-side splat/double-
  splat accepted); base cache gated `call_arg_count.nil? || name ==
  base_name`. Default nil = legacy behavior for un-threaded callers.
- Oracle: `regression_tests/rand_overload_return_type_base_cache_repro.sh`
  (red pre-fix Float64/Float64, green Int32/Int32). Suites 152/152 + 36/36.
  Sibling (1) `: Int` return -> Int32 trunc still open (its oracle stays
  RED); sibling (3) param-restriction collapse still open.
- s2_v11 VERIFIED (stage1 8cab1d05, /tmp/s2_v11): `STUB CALLED:
  Printer$Dshortest` DEAD, "Invalid bound" DEAD; **parallel LLVM emission now
  actually runs** and the frontier moved into it. NEW deterministic crash
  (~5s, 2/2 + lldb): `brk #0x1` in
  `Path#next_part_separator_index$$Char::Reader_Bool_Tuple(Char)_|_Tuple(Char,Char)`
  <- `Path#each_parent$block` <- `Dir.mkdir_p(String, Int32)` <-
  `LLVMIRGenerator#emit_functions_parallel` (mkdir for the parallel-emission
  workdir).
  LOCALIZED same night: PRE-EXISTING (identical trap+wrong-output on June-21
  `bin/adamas_fix` AND the pre-8cab1d05 binary — NOT a regression),
  reproducible at STAGE1 with a one-liner:
  `Path["/a/b/c/d"].each_parent { |p| puts p }` compiled by bin/adamas
  prints a single wrong `/a/` (host: `/`, `/a`, `/a/b`, `/a/b/c`) then brk.
  `parent`/`dirname` probes are correct, so the bug is in the
  each_part_separator_index loop chain. The mangled crash-site signature
  decodes to next_part_separator_index(reader : Char::Reader,
  last_was_separator : Bool, separators : Tuple(Char) | Tuple(Char, Char))
  : Nil | Tuple(Char::Reader, Bool, Int32) — the body does a NON-LOCAL
  `return reader, true, start_pos` (bare 3-tuple) from inside the inlined
  `Char::Reader#each` yield block, with `next` in the same block; suspected
  = the open "$block raw-return without union_wrap" + "inline-yield + next"
  families (nilable-tuple return never union-wrapped / loop-next exit path).
  RED oracle ready:
  regression_tests/path_each_parent_block_tuple_return_repro.sh.
  START HERE next session: --emit hir on the one-liner, inspect
  next_part_separator_index return lowering (union_wrap of the tuple at the
  non-local return), then disasm the brk site in the stage1 binary.

## 2026-07-04 (night) — rand(Int64) dispatch ROOT-CAUSED + FIXED: macro fresh-var ate spaced modulo

- ROOT (frontend/parser.cr `macro_variable_start?`): the fresh-macro-var
  predicate used `peek_next_non_trivia`, so a SPACED binary modulo inside a
  macro body (`result % max`) was scanned as fresh var `%max` and rewritten
  to `__macro_max_N`. The corrupted def derailed the recovery parser for the
  rest of the SAME macro-for expansion, so every def after the first lost
  its module owner: of the 10 `Random#rand_int` overloads only `$Int8`
  registered under Random/PCG32 (the others registered ownerless top-level).
  `rand(max : Int)` then resolved `rand_int(max)` via the arity-only
  untyped fallback -> first family key -> `rand_int$Int8`, truncating any
  bound to i8: `rand(0x100000000)` -> "Invalid bound for rand: 0" abort
  (the s2 File.tempname parallel-emission killer), `rand(10_i64)` garbage.
- FIX: require byte adjacency `%name` (original Crystal rule) — span
  end_offset == start_offset; `a % b` is modulo again. 1 predicate, +6 lines.
  Blast radius checked: only random.cr has spaced `%` inside macro-for
  bodies in stdlib (number.cr's are outside).
- Oracle: `regression_tests/macro_percent_modulo_fresh_var_repro.sh`
  (red pre-fix: rand_int$$Int64 missing from IR + bound abort; green now).
  Debug lever used: `-Ddebug_hooks` build + ADAMAS_DEBUG_HOOKS=1 showed
  `method.register full=rand_int$Int64 class=` (ownerless) — registration-
  level truth beats resolve-level tracing for missing-overload families.
- NEW open roots exposed (separate, NOT this fix; both pre-existing):
  1. `def rand(max : Int) : Int` — abstract `Int` RETURN annotation
     resolves to Int32 ("abstract Int defaults to Int32",
     builtin_type_ref_for) -> rand$$Int64 does `trunc i64->i32` on its
     result: rand(0x100000000) returns sign-garbled i32 values. RED oracle
     ready: `regression_tests/rand_int64_abstract_int_return_repro.sh`.
  2. Caller-side static type of `r.rand(n)` is Float64 — return type taken
     from the base-name cache where zero-arg `def rand : Float64` registers
     first (@function_base_return_types). `typeof(r.rand(10))` == Float64,
     interpolation prints garbage while comparisons on the raw value pass.
  3. Param-restriction flavor of (1): single-def `route(x : Int)` collapses
     ALL callsites to route$Int32 + coerces args (no per-type mono); the
     real rand only escaped because multiple typed overloads exist.
- s2_v10 VERIFIED (stage1 92c42aed, 171s build): "Invalid bound for rand"
  is DEAD (0 occurrences on puts42). NEW frontier one step further down the
  SAME File.tempname path: abort ~5s with
  `STUB CALLED: Printer$Dshortest$$Float64_IO` right after lower_main —
  tempname interpolates `#{Random.rand(0x100000000)}`, the call is
  statically typed Float64 by open sibling (2) (base-name return cache
  serves zero-arg `rand : Float64`), so interpolation demands Float64#to_s
  -> Ryu/Dragonbox Printer.shortest which stage1 left as STUB. Fixing (2)
  (per-overload return type instead of base-name cache) should route to
  Int#to_s and unblock parallel emission; sibling (1) sign-garble is
  harmless for tempnames. START HERE next session.

## 2026-07-04 (evening) — flaky s2 HIR segfault ROOT-CAUSED + FIXED (ee576c86): union-wrap struct payload aliasing

- ROOT: `Hash(String, GenericClassTemplate)#[]?` returned a `Nil | GCT` union
  whose payload was an INTERIOR POINTER into the hash entries buffer (V2
  wraps struct payloads as pointers with NO copy). In
  `register_class_with_name_in_current_arena`, `<< existing` pushed that
  alias into `@generic_reopenings["Channel"]`; the next
  `@generic_templates[k] = new_template` rewrote the entry IN PLACE (lldb:
  pushes #2/#3 carried the SAME record ptr with different node values), and
  a later entries realloc left the reopenings array dangling into freed,
  reused, zeroed memory -> NULL ClassNode#body in register_concrete_class.
  ASLR decided what landed in the freed slot -> the flake (v6 0/9, v7 4/9,
  v8 ~7/8). The proc-nil delta only changed allocation timing (latent bug).
- FIX `ee576c86`: `emit_union_wrap` clones struct-kind variant payloads into
  a fresh heap cell ($Dnew shape: 8B immortal RC header + fields) before
  storing the payload ptr. Variant matched by type_id in the union
  DESCRIPTOR (variant_type_id is NOT a positional index into Type#variants —
  first attempt indexed positionally and cloned NoReturn/IO variants ->
  segfault). Filter: kind.struct? && size>0 && fields>0 && !Tuple(.
  Oracle: `regression_tests/hash_struct_union_wrap_alias_repro.sh` (red
  pre-fix: 222/chan2 instead of host 111/chan; POD control stays 1).
  Suites 152/152 + 36/36 green.
- s2_v9 VERIFIED (stage1 `ee576c86` on src/adamas.cr, /tmp/s2_v9): flake
  DEAD — 9/9 puts42 runs complete HIR with zero segfaults (v7 was 4/9,
  v8 ~7/8), and the double `DEBUG_MONO start Channel(Int32)` is gone
  (0 occurrences) — confirms the Set-false-negative re-entry was the same
  root. NEW deterministic frontier (all 9 runs identical): parallel LLVM
  emission fails on the PRE-EXISTING rand(Int64) tail ("Invalid bound for
  rand: 0" — File.tempname -> Random.rand dispatches to
  PCG32#rand_int$$Int8 garbage) -> sequential fallback -> RSS balloons
  >8GB by ~16s -> run_safe kill. Next moves: (a) fix rand(Int64) overload
  dispatch (unblocks parallel emission), (b) the sequential-emission RSS
  balloon (pre-existing, also seen on v7 around func ~500/631).
- SAME-ROOT suspects (verify on s2_v9): the double `DEBUG_MONO start
  Channel(Int32)` (`Hash#find_entry` returns `Entry?` — struct-in-nilable-
  union too, so @monomorphized Set lookups could read dangling Entry
  payloads -> false negatives -> re-entry), and the s2_v3 resolver
  "Empty enumerable" Set(String)#first size==1-but-empty frontier.
- DIRECTION (owner-confirmed): full original-Crystal struct compat —
  PLAN_INLINE_STRUCTS.md Path B; Phase 6 (union payload inline, copy value
  not pointer) SUBSUMES the interim clone (marked INTERIM in
  emit_union_wrap). Sequencing per docs/root_struct_union_call_abi_sdd.md:
  PtrProvenance slice A first, then the synchronized wrap+unwrap+size flip.
  The alias repro script is repr-agnostic and stays as the Phase 6 gate.
  NEW design candidate for Phase 6 (owner liked direction, not yet written
  into the plan): niche/discriminant elision for `Nil | struct-with-
  non-nilable-ref-field` — inline payload, NO tag, null-in-niche-field ==
  Nil; sizeof(Nil|T) == sizeof(T); zeroed memory naturally reads as Nil.
  Tag fallback for POD-without-niche and multi-variant unions. Niche
  predicate must live in LayoutContract (single oracle) consumed by
  wrap/unwrap/is_a?/size/copies. Second design input (owner concern: a
  nilable slot may stay nil forever — unknowable statically): size-tiered
  nilable repr — small T inline+niche, large T stays nullable-pointer
  (with the ee576c86 copy-at-wrap contract); threshold from an
  ACCESS_CENSUS-style read-only census over the self-host build (sizeof
  distribution of Nil|struct slots + store-vs-nil frequency), decision is
  a pure function of the type in LayoutContract.
  PREREQUISITE gate for any inline flip: a recursive-struct checker
  equivalent to the original's
  `../crystal/src/compiler/crystal/semantic/recursive_struct_checker.cr`
  (whole-program pass; walks INLINE-embedding edges only — ivars of struct
  containers, union variants, tuple/named-tuple elements, virtual struct
  subtypes, module includes; references/pointers break the cycle; runs per
  generic INSTANTIATION; recursive aliases count as structs; diagnostic
  suggests classes). V2 today cannot hit infinite size (all structs behind
  pointers) — the checker must land BEFORE or WITH the first inline slice,
  else recursion shows up as a layout-computation hang instead of a
  TypeException.
- lldb TECHNIQUE lessons (cost half the session): (1) address breakpoints
  (`br s -a`) and watchpoints set BEFORE `run` never arm on this macOS —
  set symbol breakpoints (`-n`) pre-launch, address/watchpoints only at a
  live stop on MAPPED memory (wp on unmapped fires one bogus set-time hit,
  then goes permanently dead — looks like "memory is never written").
  (2) heap addresses are NOT stable across runs even under lldb (mmap base
  varies; only the allocation SEQUENCE/low offsets repeat) — never carry
  absolute heap addresses between runs; re-derive in-run via a breakpoint.

## 2026-07-04 — index/proc-nil ABI FIXED (ad4ad0a7) + based-literal truncation FIXED (27fe6cd7)

- `ad4ad0a7`: `& : T ->` had TWO ABI oracles — a `yield`-callee derives the
  yield ABI from the callsite-recorded `__block_return__` (does NOT trust the
  Nil annotation, infer_yield_return_type ~68460), while the caller (LM-657)
  forced the materialized proc to `return nil` from that same annotation.
  Desync dropped the block's value: `[1,2,3].index { |v| v == 2 }` -> 0.
  Fix: force NIL only for no-yield (pure `block.call`) callees in
  `expected_nil_block_return_type_for_def`. Oracle:
  `regression_tests/yield_block_proc_nil_annotation_value_repro.sh`.
  LM-657 guard (p2_nil_return_block_proc) still green; suites fully green.
- `27fe6cd7`: lexer typed ALL suffix-less hex/binary/octal literals I32 —
  `0x100000000` -> 0, `0xFFFFFFFF` -> -1 (decimal path already promoted by
  magnitude). Found because s2-compiled File.tempname raised "Invalid bound
  for rand: 0" from `Random.rand(0x100000000)` and knocked parallel LLVM
  emission into the sequential fallback. Fix: shared
  `based_integer_kind_for_magnitude` (base from prefix byte) + decimal U64
  tail. Oracle: `regression_tests/based_literal_magnitude_promotion_repro.sh`.
- Layer-3 demand-collapse metric moved: s2_v6 448 -> s2_v7 631 defines on
  puts42 (s1 baseline 3361). s2_v7 balloons >16GB during LLVM emission
  around function ~500/631 (killed by run_safe).
- ACTIVE FRONTIER (start here): flaky ~2s HIR segfault in s2_v7/s2_v8 on
  puts42 — NULL ClassNode#body (addr 0x40) in register_concrete_class <-
  monomorphize_generic_class(Channel(Int32)). Crash rates: v6 0/9
  (deterministic llc exit 1), v7 4/9, v8 ~7/8 — appeared with the proc-nil
  delta (ad4ad0a7). ASLR-layout-sensitive: under lldb it crashes 4/4 at the
  SAME address (hasher seed still random there -> seed exonerated).
  CRYSTAL_LOAD_DEBUG_INFO=0 does NOT rescue (mach-o revival theory refuted
  as root; note the lexer fix DID revive the previously-dead Mach-O/DWARF
  self-parse — magics used to be negative I32). Repro:
  `lldb --batch -o 'run /tmp/puts42.cr -o /tmp/x' /tmp/s2_v7` (rebuild
  s2_v7 = ad4ad0a7 stage1 on src/adamas.cr). DEBUG_MONO=1 prints
  "start Channel(Int32)" TWICE before the crash (re-entry suspect).
  Suspect families: shared $block wrapper multi-callsite return-ABI desync /
  uninit sret read (proc-nil fix enlarged non-nil proc returns), or latent
  two-heap GC layout bug the new binary layout exposes.
- NEW open tail (pre-existing, June stage1 crashes too): `Random.rand` with
  an Int64 bound dispatches to garbage — `rand(10_i64)` prints -120.0,
  `rand(0x100000000)` aborts in `Random::PCG32#rand_int$$Int8`. Blocks
  s2 File.tempname (parallel emission) even with correct literals.
- Other pre-existing tails (adversary battery, June binary reproduces):
  `[10,20,30,40].rindex { }` aborts on STUB `Indexable#size`; top-level
  `def f(& : T ->)` + `return x if yield i` returns raw Int32 without
  union_wrap into the Nil|Int32 return (prints empty), and a trailing `-1`
  after `while..end` lowers as `Sub(nil, 1)` (parser-precedence family).

## 2026-07-04 (later) — block-call named-only overload selection FIXED (b380a5cb)

- `[1,2,3].find { }` inlined `Indexable#find(if_none = nil, *, offset : Int,
  &)` — required named-only `offset` unbound -> uninitialized VOID local ->
  garbage loop bounds. Two holes fixed: `yield_function_name_for` module-chain
  BFS (new `skip_required_named` continues past uncallable candidates to
  Enumerable) + `lookup_block_function_def_for_call` (positional-only lookup
  now unconditionally skips `named_required > 0` defs in both loops).
  Oracle: `regression_tests/block_call_named_only_overload_repro.sh`.
  Debug lever: `DEBUG_INLINE_PICK=<substr>`. Suites fully green.
- Dodge-ledger follow-up: `04322d4f` replaced `members.keys.find {...}` with a
  manual `while` — same family; try reverting the dodge once s2 is green.
- Open tails (pre-existing, adversary battery): `index { }` wrong value —
  `& : T ->` block annotation forces materialized proc to RETURN NIL (LM-657
  ABI fix) but Indexable#index body USES `if yield elem`; resolve by condition
  (nil ABI only when callee's yield result is unused) or make the callsite
  inline (skip_inline reason=block_types_known routed it to proc+virtual).
  Range#find -> 5 (host 4) / Range#index -> 0 (host 2), separate family.
  Parser precedence: `puts (1..5).find { }` parses as `puts(1..5).find{}`.

## 2026-07-04 — B5 root cause FIXED; successor frontier active
## (see LM-B5-ENSURE-SKIPPED-ON-EARLY-RETURN, LM-B5-SUCCESSOR-S2-ENUM-REGISTER-NIL-ARENA)

- B5 root cause fixed in `76f3f279`: HIR lowering skipped `ensure` bodies on
  early `return` (plain + inline-return). The 2026-07-03 def/arena-mismatch
  framing resolved: triple was correct; `inline_block_return_type_name`'s
  ensure `@arena` restore never ran. Oracle:
  `regression_tests/ensure_early_return_repro.sh` (red on pre-fix stage1).
  Stage1 gates: run_all_suites fully green; 5 ensure shapes = host crystal.
- Successor layer 1 FIXED in `6ec62e0d`: the emitted ensure body at a
  non-local-return site ran under caller-block locals; inlined with_arena
  restore bound `old_arena` to garbage -> stack address stored into @arena
  -> s2 enum-register crash. Fix: defining-scope locals snapshot OVERLAYED
  on site locals. Oracle cases E+F in ensure_early_return_repro.sh.
- ACTIVE frontier (see LM-B5-SUCCESSOR2-S2-RESOLVER-SET-INCONSISTENT):
  s2 (cv2_s2_v3) fails `puts 42` with "error: Empty enumerable" —
  Set(String)#first in resolve_class_name_in_signature_context with
  size==1 but empty iteration (Set/Hash state inconsistent in s2, or a
  legit-new resolver path exposing a latent miscompile). Iteration oracle:
  s2_v3 on puts42, ~3s. NOTE: ADAMAS_ENSURE_RET_SKIP matches
  ctx.function.name (HIR names) — validate the name format before using it
  for bisection (LLVM-mangled substrings likely never matched).
- Binaries kept for diffing: `tmp/bootstrap_b5_lldb/` (pre-fix s1/s2),
  `tmp/b5_s2_ir.ll` (pre-fix s2 IR), `tmp/ab_ivar_only/` (A/B worktree),
  `tmp/b5_fix_bootstrap/cv2_s2_v3` (current frontier binary).

## 2026-07-03 — START HERE: document surgery + process reset (owner-accepted)

The SDD process was reviewed and reset; read `docs/sdd_process_review_2026_07_03.md`
first. Changes every agent must know:

- `docs/compiler_architecture_sdd.md` is now a ~1,540-line durable spec.
  Section 0 = current frontier + authority-edge state table (replace in
  place, never append); section 6.9 = the 11 owner records actually built.
  The old 12,847-line ledger: `git show 95539f64:docs/compiler_architecture_sdd.md`.
- Retired, do not resurrect: `SliceReceipt`, `BootstrapPotential`, dated board
  refinements, new source-shape guard scripts, push-based behavior-neutral
  owner migrations. Owner extraction is pull-based (only when a behavior fix
  needs the boundary); neutral slices are batched and do not each pay a full
  bootstrap verification.
- Working loop: reducer -> root cause -> fix -> narrow guard -> suites.
  Progress metrics: B5 classification movement + regression coverage growth.
- `docs/specs/05-falsifier-matrix.md` pruned 70 -> 44 rows (behavior oracles
  kept; stale pins L5-L17/O1/G7/G8/C3 and process rows P6-P14 deleted).
- The uncommitted `[B5_CALL_PRED]` probe WIP in `ast_to_hir.cr` was reverted
  (bracket-per-predicate does not scale); the active B5 attack is an lldb
  native-backtrace descent on the cv2_s2 self-build SIGSEGV
  (`AstToHir#lower_method` body loop for `Adamas::Compiler::CLI#run$IO_IO`,
  ~4.8 GB, exit 139). Probe hygiene: `ADAMAS_STOP_AFTER*` gates for passed
  frontiers are removed once B5 is green.
- Open dodge ledger (self-host workarounds that must become root-cause fixes
  with reducers): stage2 miscompiles block-`find` (`04322d4f` replaced
  `members.keys.find {...}` with a manual `while`); collect the rest from
  June commit bodies as they resurface.

## 2026-06-27 — architecture stop-rule checkpoint: do not merge current branch yet

- 2026-07-03 UPDATE: `AstToHir#inline_callee_local_names` now has its own
  scanner/provenance owner helper instead of raw arena and inline-yield block
  stack save/restore code in the scanner body. The pre-slice source-shape
  baseline reported `inline_scan_enter=0`, `inline_scan_restore=0`, and
  `inline_scan_legacy=8`; the current guard with
  `REQUIRE_INLINE_CALLEE_LOCAL_SCAN_SCOPE=1
  scripts/inline_callee_local_scan_scope_source_shape_guard.sh` reports
  `source_shape=inline_callee_local_scan_scope_consumed`, one enter call, one
  restore call, and zero legacy scanner saves. Fresh evidence:
  `crystal build src/adamas.cr -o
  tmp/adamas_inline_callee_scan_scope_stage1 --error-trace` exits 0;
  `scripts/build_bootstrap_stages.sh --out
  tmp/bootstrap_inline_callee_scan_scope --stages 2 --timeout 900 --mem 12288`
  builds and smokes `cv2_s1` and `cv2_s2` clean (`cv2_s2` wall 231.37s, peak
  RSS about 3362 MB); the B4 guard with
  `GENERATED_S2=tmp/bootstrap_inline_callee_scan_scope/cv2_s2 REQUIRE_CLEAN=1
  scripts/generated_stage_llvm_entry_classifier.sh` remains
  `classification=clean_both_modes`; the B5 target-only classifier with that
  `cv2_s2` still reports
  `classification=self_build_hir_pending_target_lower_method_body_lowered_boundary`
  and first bad `ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED`;
  and `regression_tests/run_all_suites.sh
  tmp/adamas_inline_callee_scan_scope_stage1 4` reports all suites passed
  (`152/152` full regressions and `36/36` combined). Scope: this consumes the
  scanner/provenance residual for `inline_callee_local_names`; it is not a green
  B5/s3b claim and does not migrate method-pointer thunks, proc literals, or
  block-to-proc body scopes.

- 2026-07-03 UPDATE: the `MethodBodyLoweringScopeSnapshot` owner model now also
  owns the `AstToHir#lower_module_method` body-lowering seam. The pre-slice
  source-shape baseline for `lower_module_method` reported no helper
  enter/restore calls and 15 legacy body-scope saves; the current guard with
  `REQUIRE_METHOD_BODY_SCOPE=1 REQUIRE_LOWER_DEF_BODY_SCOPE=1
  REQUIRE_LOWER_MODULE_METHOD_BODY_SCOPE=1
  scripts/method_body_lowering_scope_source_shape_guard.sh` reports
  `method_body_scope_owner_consumed` for `lower_method`, `lower_def`, and
  `lower_module_method`, with one enter/restore pair and zero selected legacy
  saves for each. Fresh evidence: `crystal build src/adamas.cr -o
  tmp/adamas_lower_module_method_body_scope_stage1 --error-trace` exits 0;
  `scripts/build_bootstrap_stages.sh --out
  tmp/bootstrap_lower_module_method_body_scope --stages 2 --timeout 900 --mem
  12288` builds and smokes `cv2_s1` and `cv2_s2` clean (`cv2_s2` wall 251.91s,
  peak RSS about 3388 MB); the B4 guard with
  `GENERATED_S2=tmp/bootstrap_lower_module_method_body_scope/cv2_s2
  REQUIRE_CLEAN=1 scripts/generated_stage_llvm_entry_classifier.sh` remains
  `classification=clean_both_modes`; the B5 target-only classifier with that
  `cv2_s2` still reports
  `classification=self_build_hir_pending_target_lower_method_body_lowered_boundary`
  and first bad `ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED`;
  and `regression_tests/run_all_suites.sh
  tmp/adamas_lower_module_method_body_scope_stage1 4` reports all suites passed
  (`152/152` full regressions and `36/36` combined). Scope: this consumes the
  third method-like body-scope owner edge. It is not a green B5/s3b claim and
  does not migrate `inline_callee_local_names`, method-pointer thunks, proc
  literals, or block-to-proc body scopes.

- 2026-07-03 UPDATE: the `MethodBodyLoweringScopeSnapshot` owner model now also
  owns the `AstToHir#lower_def` body-lowering seam. The pre-slice source-shape
  baseline for `lower_def` reported no helper enter/restore calls and 14 legacy
  body-scope saves; the current guard with `REQUIRE_METHOD_BODY_SCOPE=1
  REQUIRE_LOWER_DEF_BODY_SCOPE=1
  scripts/method_body_lowering_scope_source_shape_guard.sh` reports both
  `lower_method_source_shape=method_body_scope_owner_consumed` and
  `lower_def_source_shape=method_body_scope_owner_consumed`, with one
  enter/restore pair and zero selected legacy saves for each. Fresh evidence:
  `crystal build src/adamas.cr -o tmp/adamas_lower_def_body_scope_stage1
  --error-trace` exits 0; `scripts/build_bootstrap_stages.sh --out
  tmp/bootstrap_lower_def_body_scope --stages 2 --timeout 900 --mem 12288`
  builds and smokes `cv2_s1` and `cv2_s2` clean (`cv2_s2` wall 253.42s, peak
  RSS about 3207 MB); the B4 guard with
  `GENERATED_S2=tmp/bootstrap_lower_def_body_scope/cv2_s2 REQUIRE_CLEAN=1
  scripts/generated_stage_llvm_entry_classifier.sh` remains
  `classification=clean_both_modes`; the B5 target-only classifier with that
  `cv2_s2` still reports
  `classification=self_build_hir_pending_target_lower_method_body_lowered_boundary`
  and first bad `ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED`;
  and `regression_tests/run_all_suites.sh
  tmp/adamas_lower_def_body_scope_stage1 4` reports all suites passed
  (`152/152` full regressions and `36/36` combined). Scope: this consumes the
  `lower_def` raw inline-yield/current-return body-scope edge under the already
  selected owner helper. At this checkpoint it was not a green B5/s3b claim and
  did not yet migrate `lower_module_method`, `inline_callee_local_names`, or proc
  body scopes.

- 2026-07-03 UPDATE: the selected B5 body-lowering authority edge now has a
  behavior-neutral owner helper. `AstToHir#lower_method` no longer owns its body
  lowering lifetime through raw local saves/restores of the inline-yield stacks,
  inline arenas, infer-body context, and current-def return type; it now enters
  and restores a `MethodBodyLoweringScopeSnapshot` through the
  `enter_method_body_lowering_scope` / `restore_method_body_lowering_scope`
  helpers. Fresh evidence from the current tree: `REQUIRE_METHOD_BODY_SCOPE=1
  scripts/method_body_lowering_scope_source_shape_guard.sh` reports
  `source_shape=method_body_scope_owner_consumed`; `crystal build
  src/adamas.cr -o tmp/adamas_method_body_scope_stage1 --error-trace` exits 0;
  `scripts/build_bootstrap_stages.sh --out tmp/bootstrap_method_body_scope
  --stages 2 --timeout 900 --mem 12288` builds and smokes `cv2_s1` and `cv2_s2`
  clean (`cv2_s2` wall 240.70s, peak RSS about 3114 MB); `PENDING_TARGET_ONLY=1
  STAGE1_COMPILER=tmp/bootstrap_method_body_scope/cv2_s2 REQUIRE_CLASSIFICATION=1
  STOP_TIMEOUT=900 STOP_MEM_MB=12288 HIGH_RSS_MB=12288
  scripts/generated_stage_self_build_hir_boundary_classifier.sh` still reports
  `classification=self_build_hir_pending_target_lower_method_body_lowered_boundary`
  with clean gates through body-loop start and first bad
  `ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED`;
  `GENERATED_S2=tmp/bootstrap_method_body_scope/cv2_s2 REQUIRE_CLEAN=1
  scripts/generated_stage_llvm_entry_classifier.sh` reports
  `classification=clean_both_modes`; and
  `regression_tests/run_all_suites.sh tmp/adamas_method_body_scope_stage1 4`
  reports all suites passed (`152/152` full regressions and `36/36` combined).
  Scope: this consumes one direct ambient-scope edge in the selected
  `lower_method` body path. At this checkpoint it was not a green B5/s3b claim,
  did not yet migrate `lower_def` or proc body scopes, and did not admit another
  generic body marker. The next architecture move should either migrate the next
  root-sized method-body context edge under the same owner model or return to the
  SDD board for a larger vertical `MethodBodyLoweringContext` /
  `SemanticStateScope` slice.

- 2026-07-03 UPDATE: the B5 pending-target localizer now splits the selected
  `AstToHir#lower_method` call for `Adamas::Compiler::CLI#run$IO_IO` itself.
  Fresh evidence: `PENDING_TARGET_ONLY=1
  STAGE1_COMPILER=tmp/bootstrap_b5_lower_method_localizer/cv2_s2
  REQUIRE_CLASSIFICATION=1 STOP_TIMEOUT=900 STOP_MEM_MB=12288
  HIGH_RSS_MB=12288 scripts/generated_stage_self_build_hir_boundary_classifier.sh`
  exits 0 with
  `classification=self_build_hir_pending_target_lower_method_body_lowered_boundary`.
  Clean lower-method gates: enter, base ready, suffix done, early terminals
  done, scope ready, params collected, name ready, function created, self
  bound, params bound, auto-assign done, body setup, arena ready, and body loop
  start (`body_size=44`, `entry_boxes=0`). First bad gate:
  `ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_METHOD_BODY_LOWERED` exits 139 at
  about 4809 MB, without safe-wrapper memory or timeout kill. This supersedes
  the coarser after-instance-lower-method boundary and refutes lookup,
  call-arg recovery, materialization name, function creation, self/parameter
  binding, auto-assign, method arena, and entry-box setup as first bad
  transitions for this B5 target. Stop rule: do not add another generic
  `lower_method` body/`lower_expr` marker just because this gate moved. The next
  movement must either write a concrete owner-edge receipt for the body-lowering
  authority being migrated/refuted, or return to the SDD Current Execution Board
  and select an architecture slice. This remains red B5/s3b evidence, not a
  green bootstrap claim.

- 2026-07-03 UPDATE: the B5 pending target localizer now splits the queued
  `Adamas::Compiler::CLI#run$IO_IO` demand inside `lower_function_if_needed`.
  The diagnostic gates are default-off and target-filtered by
  `ADAMAS_PENDING_TARGET_FILTER`, with a short `PENDING_TARGET_ONLY=1` mode for
  the already-proven prefix. Fresh evidence: `crystal build src/adamas.cr -o
  tmp/adamas_b5_target_localizer_stage1 --error-trace` exits 0;
  `scripts/build_bootstrap_stages.sh --out tmp/bootstrap_b5_target_localizer
  --stages 2 --timeout 900 --mem 12288` builds and smokes `cv2_s1` and
  `cv2_s2` clean (`cv2_s2` wall 243.53s, peak RSS about 3362 MB);
  `PENDING_TARGET_ONLY=1 STAGE1_COMPILER=tmp/bootstrap_b5_target_localizer/cv2_s2
  REQUIRE_CLASSIFICATION=1 STOP_TIMEOUT=900 STOP_MEM_MB=12288
  HIGH_RSS_MB=12288 scripts/generated_stage_self_build_hir_boundary_classifier.sh`
  exits 0 with
  `classification=self_build_hir_pending_target_lower_func_after_instance_lower_method_boundary`;
  and `GENERATED_S2=tmp/bootstrap_b5_target_localizer/cv2_s2 REQUIRE_CLEAN=1
  scripts/generated_stage_llvm_entry_classifier.sh` reports
  `classification=clean_both_modes`. Clean target gates: lower-function enter,
  direct lookup done (`found=1, branch=direct`), resolved DefNode
  (`abstract=1`), call args ready, materialization ready
  (`wrapper=0, shape=0`), and the stop before the instance `lower_method`
  call (`owner=Adamas::Compiler::CLI`,
  `producer=instance_class_info_lower_method`,
  `reason=target_materialization`). First bad gate:
  `ADAMAS_STOP_AFTER_HIR_PENDING_TARGET_LOWER_FUNC_AFTER_INSTANCE_LOWER_METHOD`
  exits 139 at about 4806 MB, without safe-wrapper memory or timeout kill.
  Regression surface for the diagnostic slice remains green:
  `regression_tests/run_all_suites.sh tmp/adamas_b5_target_localizer_stage1 4`
  reports all suites passed (`152/152` full regressions and `36/36` combined).
  Therefore the next slice must localize inside
  `AstToHir#lower_method` for `Adamas::Compiler::CLI#run$IO_IO`, after
  `lower_function_if_needed` has selected the owner/materialized name and before
  it returns. Do not reopen lookup, call-arg recovery, materialization name,
  pending queue mechanics, old pending prefix gates, B4/L17-L22 LLVM,
  `NamedTuple` / `Tuple`, ambient maps, or `BlockOwner` from stale evidence.

- 2026-07-03 UPDATE: `process_pending_lower_functions` is now split by
  missing-sweep-owned pending subphase. New default-off context-filtered gates
  show the repeated lazy-RTA init and the first pending item/keep/lower gates
  are clean. Fresh evidence: `crystal build src/adamas.cr -o
  tmp/adamas_b5_pending_phase_stage1 --error-trace` exits 0;
  `scripts/build_bootstrap_stages.sh --out tmp/bootstrap_b5_pending_phase
  --stages 2 --timeout 900 --mem 12288` builds and smokes `cv2_s1` and
  `cv2_s2` clean (`cv2_s2` wall 240.92s, peak RSS about 3295 MB); and
  `STAGE1_COMPILER=tmp/bootstrap_b5_pending_phase/cv2_s2
  REQUIRE_CLASSIFICATION=1 STOP_TIMEOUT=900 STOP_MEM_MB=12288
  HIGH_RSS_MB=12288 scripts/generated_stage_self_build_hir_boundary_classifier.sh`
  exits 0 with `classification=self_build_hir_pending_pass_items_done_boundary`.
  Clean pending gates inside `missing_initial`: enter, lazy_rta, pass_start,
  first_item, first_keep_decision, first_lower_ready, and first_lower_done.
  First bad gate: `ADAMAS_STOP_AFTER_HIR_PENDING_PASS_ITEMS_DONE` exits 139 at
  about 4803 MB, without safe-wrapper memory kill. Its tail shows the item loop
  reached `idx=19` / `Adamas::Compiler::CLI#run$IO_IO` and crashed after
  `first_lower_ready`, before the corresponding `first_lower_done`. B4 remains
  clean: `GENERATED_S2=tmp/bootstrap_b5_pending_phase/cv2_s2 REQUIRE_CLEAN=1
  scripts/generated_stage_llvm_entry_classifier.sh` reports
  `classification=clean_both_modes`; combined regressions pass 36/36; full
  regressions pass 152/152. This supersedes
  `self_build_hir_missing_process_boundary`: the next slice must localize the
  `lower_function_if_needed` / `lower_method` path for the queued
  `Adamas::Compiler::CLI#run$IO_IO` demand from the initial missing-target
  sweep, not pending enter, lazy RTA, queue iteration, first RTA keep decision,
  first lowerable item, missing scan/uniq/queue, fun-main scan/lower,
  tracked signatures, MIR, LLVM, `NamedTuple` / `Tuple`, ambient maps, or
  `BlockOwner`.

- 2026-07-03 UPDATE: `lower_missing_call_targets` is now split by subphase.
  New default-off gates show the current first bad transition is not missing
  call scanning, uniquing, or queue insertion. The initial missing sweep finds
  and queues 28 missing targets, then crashes during the
  `process_pending_lower_functions` call owned by that sweep. Fresh evidence:
  `crystal build src/adamas.cr -o tmp/adamas_b5_missing_phase_stage1
  --error-trace` exits 0; `scripts/build_bootstrap_stages.sh --out
  tmp/bootstrap_b5_missing_phase --stages 2 --timeout 900 --mem 12288` builds
  and smokes `cv2_s1` and `cv2_s2` clean (`cv2_s2` wall 253.17s, peak RSS
  about 3249 MB); and `STAGE1_COMPILER=tmp/bootstrap_b5_missing_phase/cv2_s2
  REQUIRE_CLASSIFICATION=1 STOP_TIMEOUT=900 STOP_MEM_MB=12288
  HIGH_RSS_MB=12288 scripts/generated_stage_self_build_hir_boundary_classifier.sh`
  exits 0 with `classification=self_build_hir_missing_process_boundary`.
  Clean lower-missing gates: start, scan (`missing=28`), uniq (`missing=28`),
  and queue (`pending=28`). First bad gate:
  `ADAMAS_STOP_AFTER_HIR_MISSING_PROCESS` exits 139 at about 4804 MB, without
  safe-wrapper memory kill. B4 remains clean:
  `GENERATED_S2=tmp/bootstrap_b5_missing_phase/cv2_s2 REQUIRE_CLEAN=1
  scripts/generated_stage_llvm_entry_classifier.sh` reports
  `classification=clean_both_modes`; combined regressions pass 36/36; full
  regressions pass 152/152. This supersedes
  `self_build_hir_flush_missing_initial_boundary`: the next slice must localize
  the `process_pending_lower_functions` call made from the initial
  missing-target sweep, probably by pending-queue item or pending-pass phase,
  not missing scan/uniq/queue, lazy RTA init, tracked signatures, fun-main
  scan/lower, RTA pruning, MIR, LLVM, `NamedTuple` / `Tuple`, ambient maps, or
  `BlockOwner`.

- 2026-07-03 UPDATE: B5 fun-main flush is now split by flush subphase. New
  default-off gates inside `AstToHir#flush_pending_functions` show the current
  first bad transition is the initial `lower_missing_call_targets` safety-net
  sweep reached from top-level `fun main` flush. Fresh evidence:
  `crystal build src/adamas.cr -o tmp/adamas_b5_flush_phase_stage1
  --error-trace` exits 0; `scripts/build_bootstrap_stages.sh --out
  tmp/bootstrap_b5_flush_phase --stages 2 --timeout 900 --mem 12288` builds and
  smokes `cv2_s1` and `cv2_s2` clean (`cv2_s2` wall 253.37s, peak RSS about
  2962 MB); and `STAGE1_COMPILER=tmp/bootstrap_b5_flush_phase/cv2_s2
  REQUIRE_CLASSIFICATION=1 STOP_TIMEOUT=900 STOP_MEM_MB=12288
  HIGH_RSS_MB=12288 scripts/generated_stage_self_build_hir_boundary_classifier.sh`
  exits 0 with `classification=self_build_hir_flush_missing_initial_boundary`.
  Clean gates before the crash: fun-main scan/lower, flush reachability seed,
  lazy RTA init, initial pending drain, and tracked signatures. First bad gate:
  `ADAMAS_STOP_AFTER_HIR_FLUSH_MISSING_INITIAL` exits 139 at about 4803 MB,
  without safe-wrapper memory kill. B4 remains clean:
  `GENERATED_S2=tmp/bootstrap_b5_flush_phase/cv2_s2 REQUIRE_CLEAN=1
  scripts/generated_stage_llvm_entry_classifier.sh` reports
  `classification=clean_both_modes`; combined regressions pass 36/36; full
  regressions pass 152/152. This supersedes the coarser
  `self_build_hir_fun_main_flush_boundary`: the next slice must localize the
  first bad transition inside `lower_missing_call_targets` itself, not
  reachability seeding, lazy RTA init, initial pending lowering, tracked
  signature emission, fun-main scan/lower, RTA pruning, MIR, LLVM,
  `NamedTuple` / `Tuple`, ambient maps, or `BlockOwner`.

- 2026-07-03 UPDATE: B5 pending-flush corridor split now names the first bad
  sub-boundary. The refined classifier gained fun-main scan/lower/flush and
  before-normal-flush gates. Fresh evidence: `crystal build src/adamas.cr -o
  tmp/adamas_b5_flush_split_stage1 --error-trace` exits 0;
  `scripts/build_bootstrap_stages.sh --out tmp/bootstrap_b5_flush_split
  --stages 2 --timeout 900 --mem 12288` builds and smokes `cv2_s1` and `cv2_s2`
  clean (`cv2_s2` wall 243.30s, peak RSS about 3346 MB); and
  `STAGE1_COMPILER=tmp/bootstrap_b5_flush_split/cv2_s2
  REQUIRE_CLASSIFICATION=1 STOP_TIMEOUT=900 STOP_MEM_MB=12288
  HIGH_RSS_MB=12288 scripts/generated_stage_self_build_hir_boundary_classifier.sh`
  exits 0 with `classification=self_build_hir_fun_main_flush_boundary`.
  Clean gates: `compile_entry` 7 MB, `parse` 1263 MB, `lower_main` 4738 MB,
  lower-main bookkeeping 4738 MB, `fun_main_scan` 4738 MB with
  `hir_fun_main_entry_status=taken`, and `fun_main_lower` 4740 MB. First bad
  gate: `ADAMAS_STOP_AFTER_HIR_FUN_MAIN_FLUSH` exits 139 at about 4802 MB,
  without safe-wrapper memory kill. This supersedes the previous
  `self_build_hir_flush_pending_boundary`: the next slice must localize
  `AstToHir#flush_pending_functions` on the top-level `fun main` path, not
  fun-main scanning, `lower_def(fun main)`, normal post-branch flush, RTA, MIR,
  LLVM finalization/helper, `NamedTuple` / `Tuple`, ambient maps, or
  `BlockOwner` from stale evidence.

- 2026-07-03 UPDATE: B5 refined HIR localizer now narrows the active `cv2_s2`
  self-build boundary. Diagnostic-only gates were added around the post
  `lower_main` HIR corridor, plus
  `scripts/generated_stage_self_build_hir_boundary_classifier.sh`. Fresh
  evidence: `crystal build src/adamas.cr -o tmp/adamas_b5_hir_gates_stage1
  --error-trace` exits 0; `scripts/build_bootstrap_stages.sh --out
  tmp/bootstrap_b5_hir_gates --stages 2 --timeout 900 --mem 12288` builds and
  smokes `cv2_s1` and `cv2_s2` clean (`cv2_s2` wall 252.39s, peak RSS about
  3363 MB); and `STAGE1_COMPILER=tmp/bootstrap_b5_hir_gates/cv2_s2
  REQUIRE_CLASSIFICATION=1 STOP_TIMEOUT=900 STOP_MEM_MB=12288
  HIGH_RSS_MB=12288 scripts/generated_stage_self_build_hir_boundary_classifier.sh`
  exits 0 with `classification=self_build_hir_flush_pending_boundary`.
  `compile_entry`, `parse`, `lower_main`, and lower-main bookkeeping stop gates
  are clean (`6`, `1263`, `4737`, and `4738` MB respectively); the first bad
  refined gate is `ADAMAS_STOP_AFTER_HIR_FLUSH_PENDING`, which exits 139 at
  about `4801` MB without safe-wrapper memory kill. This supersedes the coarse
  `self_build_hir_boundary` wording: the next slice must localize the
  post-`lower_main` pending-flush corridor (fun-main scan/lowering versus
  `flush_pending_functions`) before any behavior patch. Do not return to
  `lower_main` itself, RTA, MIR, LLVM finalization/helper, `NamedTuple` /
  `Tuple`, ambient maps, or `BlockOwner` from stale evidence.

- 2026-07-03 UPDATE: post-0k-ET bootstrap-ladder remeasurement makes the
  current distance to green explicit. `scripts/build_bootstrap_stages.sh --out
  tmp/bootstrap_l22_demand --stages 3 --timeout 900 --mem 12288` builds and
  smokes `cv2_s1` and `cv2_s2` clean (`cv2_s2` build wall about 255s, peak RSS
  about 3186 MB), but `cv2_s3` fails during build with exit 139 after
  `[STAGE2_DEBUG] pass3 after lower_main call` at about 4801 MB peak RSS.
  With the same `cv2_s2`,
  `STAGE1_COMPILER=tmp/bootstrap_l22_demand/cv2_s2 REQUIRE_CLASSIFICATION=1
  STOP_MEM_MB=12288 HIGH_RSS_MB=12288
  scripts/generated_stage_self_build_boundary_classifier.sh` exits 0 with
  `classification=self_build_hir_boundary`: parse is clean, while HIR/MIR stop
  gates both exit 139 after lower_main. This supersedes the generic "not green
  s2b/s3b" wording for the active board: B4/tiny produced-s2 LLVM entry is
  green, and B5/s3 self-build is the current frontier. The next slice must
  localize the `cv2_s2` self-build HIR/lower_main boundary before any new
  source behavior patch. Do not return to L17-L22 post-`to_s` LLVM-validity
  symptoms, runtime-helper declaration, Slice storage, `NamedTuple` / `Tuple`,
  ambient maps, or `BlockOwner` from stale evidence.

- 2026-07-03 UPDATE: Slice 0k-ET consumes the L22 runtime-helper
  demand/definition edge. The root was an authority split in LLVM emission:
  helper-call producers could redirect `GC_realloc` / bulk extern lowering to
  `@__adamas_gc_aware_realloc`, while the helper-definition epilogue only
  scanned the shared reachable function list and missed helper calls produced
  during worker emission. The production slice records a producer-owned
  `@gc_aware_realloc_helper_needed` demand, serializes it through the existing
  worker side-effect channel, merges it before the epilogue, and emits the
  helper when either the demand flag or the legacy shared-MIR scan requires it.
  It still preserves the GC-free negative: the helper is not emitted when no
  `GC_realloc` redirect is produced. Focused evidence with
  `tmp/adamas_l22_demand_stage1`: `crystal build src/adamas.cr -o
  tmp/adamas_l22_demand_stage1 --error-trace` exits 0;
  `regression_tests/gc_aware_realloc_gating_repro.sh
  tmp/adamas_l22_demand_stage1` exits 0; and
  `STAGE1_COMPILER=tmp/adamas_l22_demand_stage1
  scripts/generated_stage_gc_realloc_helper_report.sh` exits 0 with
  `selection_status=rejected`, `reason=undefined_gc_realloc_helper_error_missing`,
  `gc_realloc_helper_call_count=2`, and `gc_realloc_helper_define_count=1`.
  Broader bootstrap evidence: `KEEP_TMP=1
  STAGE1_COMPILER=tmp/adamas_l22_demand_stage1 REQUIRE_RAW_DUMP=1
  REQUIRE_CLASSIFICATION=1 scripts/generated_stage_finalize_to_s_classifier.sh`
  builds `adamas_s2`, compiles full-prelude `puts 42`, and the produced
  `normal_out` prints `42` under `scripts/run_safe.sh`; and
  `STAGE1_COMPILER=tmp/adamas_l22_demand_stage1
  GENERATED_S2=<kept>/adamas_s2 REQUIRE_CLEAN=1
  scripts/generated_stage_llvm_entry_classifier.sh` reports
  `classification=clean_both_modes`. Regression surface:
  `regression_tests/run_combined.sh tmp/adamas_l22_demand_stage1 4` reports
  36/36 and `regression_tests/run_all.sh tmp/adamas_l22_demand_stage1 4`
  reports 152/152. This is the first current-board evidence that produced
  `s2b` compiles a tiny full-prelude program in both default and workers=1
  modes; it is still not a complete green `s3b` / arbitrary-program bootstrap
  claim. The next movement must remeasure the bootstrap ladder or stage
  comparison gate before selecting another production frontier. Do not return
  to L17-L22 finalization/LLVM-validity symptoms, backend undefined-extern
  rescue, unconditional helper emission, tail declarations, Slice storage,
  `NamedTuple` / `Tuple`, ambient maps, or `BlockOwner` from stale evidence.

- 2026-07-03 UPDATE: Slice 0k-ES adds the focused L22 selector for the
  post-0k-ER runtime-helper declaration residual. New script:
  `scripts/generated_stage_gc_realloc_helper_report.sh`. It preserves the
  consumed L19/L20/L21 rows (`normal_string_header_size_global_shape=i32_12`,
  `raw_dump_classification=raw_dump_before_to_s_buffer_valid`,
  `normal_llc_type_mismatch=0`, raw Slice stack storage, and raw Slice zero
  sentinel storage) and selects only when generated `normal_out.ll` calls
  `@__adamas_gc_aware_realloc` while providing neither a declaration nor a
  definition for that helper. Fresh evidence with
  `tmp/adamas_l22_selector_stage1`: `bash -n
  scripts/generated_stage_gc_realloc_helper_report.sh` exits 0, and
  `STAGE1_COMPILER=tmp/adamas_l22_selector_stage1 REQUIRE_SELECTED=1
  scripts/generated_stage_gc_realloc_helper_report.sh` exits 0 with
  `classification=runtime_helper_gc_realloc_missing_declaration_frontier`,
  `selection_status=eligible_gc_realloc_helper_missing_declaration`,
  `gc_realloc_helper_call_count=2`, `gc_realloc_helper_define_count=0`,
  `gc_realloc_helper_declare_count=0`, `gc_realloc_decl_count=1`,
  `gc_base_decl_count=1`, and `gc_realloc_helper_error_matches_call=1`.
  This is diagnostic-only and still not green `s2b`/`s3b`. The next production
  slice must name and consume the runtime-helper demand/definition authority
  edge: the producer that emits calls to `__adamas_gc_aware_realloc` must agree
  with the epilogue/helper-definition producer without over-linking GC-free
  programs. Do not patch backend undefined externs, tail declarations,
  output ownership, scalar globals, function-return slots, Slice storage,
  `NamedTuple` / `Tuple`, ambient maps, or `BlockOwner` from this evidence.

- 2026-07-03 UPDATE: Slice 0k-ER consumes the L21 zero-struct/value-storage
  LLVM validity edge. The root was not a missing late `%Slice$LUInt8$R`
  typedef ledger: V2 value storage is consumed through byte-level GEPs and
  pointer carriers, but two producers still emitted named aggregate LLVM types
  that may be absent from the initial type-definition sweep. Stack `Alloc`
  now uses raw `[size x i8]` storage for concrete value types, and zero-filled
  struct sentinels now emit raw `[size x i8] zeroinitializer, align N` globals.
  Focused evidence with `tmp/adamas_l21_raw_storage_stage1`:
  `scripts/generated_stage_zero_struct_sentinel_report.sh` exits 0 with
  `selection_status=rejected`, `reason=invalid_null_constant_error_missing`,
  preserved `upstream_classification=post_to_s_frontier`,
  `normal_string_header_size_global_shape=i32_12`,
  `raw_dump_classification=raw_dump_before_to_s_buffer_valid`, and
  `normal_llc_type_mismatch=0`. The generated IR shape moved from
  `%r2 = alloca %Slice$LUInt8$R` and
  `@__zero.Slice$LUInt8$R = internal global %Slice$LUInt8$R zeroinitializer`
  to `%r2 = alloca [16 x i8]` and
  `@__zero.Slice$LUInt8$R = internal global [16 x i8] zeroinitializer, align 8`.
  Adjacent guards pass: `REQUIRE_OUTPUT_OWNERSHIP=1
  scripts/llvm_output_ownership_source_shape_guard.sh`, the three L19 P2
  guards, `regression_tests/run_combined.sh tmp/adamas_l21_raw_storage_stage1
  4` (36/36), and `regression_tests/run_all.sh
  tmp/adamas_l21_raw_storage_stage1 4` (152/152). This is still not green
  `s2b`/`s3b`: the generated-stage residual moved to an undefined runtime
  helper declaration, `@__adamas_gc_aware_realloc`. The next slice should add a
  focused selector for that runtime-helper declaration edge before changing
  helper emission or tail declarations.

- 2026-07-03 UPDATE: Slice 0k-EQ adds the focused L21 selector for the
  post-0k-EP zero-struct sentinel residual. New script:
  `scripts/generated_stage_zero_struct_sentinel_report.sh`. It preserves the
  consumed rows from L19 and L20 (`normal_string_header_size_global_shape=i32_12`,
  `raw_dump_classification=raw_dump_before_to_s_buffer_valid`, and
  `normal_llc_type_mismatch=0`) and selects only when `llc` reports
  `invalid type for null constant` on the exact declaration
  `@__zero.Slice$LUInt8$R = internal global %Slice$LUInt8$R zeroinitializer`.
  Focused evidence: `bash -n
  scripts/generated_stage_zero_struct_sentinel_report.sh`; a synthetic
  positive fixture selects
  `classification=zero_struct_sentinel_invalid_initializer_frontier`, while a
  stale `ptr_null` negative exits 9 with
  `reason=string_header_size_scalar_global_not_preserved`; and
  `STAGE1_COMPILER=tmp/adamas_l21_selector_stage1 REQUIRE_SELECTED=1
  scripts/generated_stage_zero_struct_sentinel_report.sh` exits 0 with
  `upstream_classification=post_to_s_frontier`,
  `normal_llc_type_mismatch=0`, `invalid_null_error_line=9136`,
  `zero_struct_decl_line_no=9136`, `zero_struct_error_matches_decl=1`, and
  `classification=zero_struct_sentinel_invalid_initializer_frontier`. This is
  diagnostic-only and still not green `s2b`/`s3b`. The next production slice
  must name the producer/consumer authority edge for zero-filled struct
  sentinel declaration/type availability before editing backend emission.

- 2026-07-03 UPDATE: Slice 0k-EP consumes the L20
  `FunctionReturnAvailability` / `LoweredFunctionReturnContract` edge. The
  first bad transition was not a missing emitted callee ABI row:
  `IO#gets_slow` already emitted `IO#read_char_with_bytesize` as `call ptr`,
  but cross-block slot preparation still trusted a stale prepass
  `@value_types` entry of `Void`, allocated `%r18.slot` as `i64`, and
  suppressed the result store. The production slice makes the defining
  instruction inside the current function available during hoisted slot
  preparation and prevents stale prepass `Void` from classifying a non-void
  MIR `Call` as resultless. Focused evidence with
  `tmp/adamas_l20_contract_stage1`: `scripts/generated_stage_return_contract_mismatch_report.sh`
  now exits 0 with `normal_llc_type_mismatch=0`,
  `upstream_classification=post_to_s_frontier`,
  `normal_string_header_size_global_shape=i32_12`, and
  `raw_dump_classification=raw_dump_before_to_s_buffer_valid`; generated IR
  now has `%r18.slot = alloca ptr`, `store ptr %r18, ptr %r18.slot`, and
  `%r18.fromslot.* = load ptr`. Adjacent guards pass:
  `REQUIRE_OUTPUT_OWNERSHIP=1 scripts/llvm_output_ownership_source_shape_guard.sh`,
  the three L19 p2 guards, `regression_tests/run_combined.sh
  tmp/adamas_l20_contract_stage1 4` (36/36), and
  `regression_tests/run_all.sh tmp/adamas_l20_contract_stage1 4` (152/152).
  This is still not green `s2b`/`s3b`: the residual moved to a new
  post-`to_s` LLVM validity edge,
  `@__zero.Slice$LUInt8$R = internal global %Slice$LUInt8$R zeroinitializer`,
  where `llc` reports `invalid type for null constant`. Do not return to
  function-return slots, output ownership, scalar globals, `NamedTuple` /
  `Tuple`, ambient maps, or `BlockOwner` unless fresh evidence regresses L20.

- 2026-07-03 UPDATE: Slice 0k-EO adds an executable selector for the
  post-0k-EN residual instead of relying on prose. New script:
  `scripts/generated_stage_return_contract_mismatch_report.sh`. It preserves
  the consumed L19 scalar-global gate and selects the next architecture edge
  only when the generated-stage classifier reports
  `post_to_s_llc_type_mismatch_frontier`,
  `normal_string_header_size_global_shape=i32_12`,
  `raw_dump_classification=raw_dump_before_to_s_buffer_valid`, and the current
  `llc` mismatch uses `%r18.fromslot.1` as `i64` where `ptr` is expected inside
  `IO#gets_slow` with `IO#read_char_with_bytesize` in the local IR window.
  Focused evidence: `bash -n
  scripts/generated_stage_return_contract_mismatch_report.sh`; a synthetic
  positive fixture reports
  `classification=function_return_contract_mismatch_frontier`, while a stale
  `ptr_null` negative exits 9 with
  `reason=string_header_size_scalar_global_not_preserved`; and
  `REQUIRE_SELECTED=1
  scripts/generated_stage_return_contract_mismatch_report.sh` exits 0 on
  current HEAD with `normal_llc_error_line=6123`,
  `bad_function_symbol=IO$Hgets_slow$$Char_Int32_Bool_String$CCBuilder`, and
  `callee_candidate=IO#read_char_with_bytesize`. This is still not green
  `s2b`/`s3b` and is not a backend slot fix. The next production slice should
  introduce or consume a function-return availability contract so body
  finalization, function type registration, HIR calls, MIR calls, and LLVM call
  emission agree before any consumer fallback hides the mismatch.

- 2026-07-03 UPDATE: Slice 0k-EN consumes the L19
  `String::HEADER_SIZE` classvar scalar-global producer edge. The root was two
  producer-side hazards that compounded only in the generated stage:
  unresolved `offsetof(String, @c)` constants could be sealed by source
  fallback before class layout was complete, and `MacroNumberValue.new(Int64)`
  used the broad numeric-union constructor, which self-hosted stage2 stored as
  `0` even when the caller-side value was `12`. The production slice queues
  direct `OffsetofNode` constants for pending re-evaluation before source
  fallback, shares one `macro_value_for_offsetof` evaluator between macro
  constants and runtime `lower_offsetof`, and adds exact scalar
  `MacroNumberValue` constructors while preserving the union fallback. Focused
  evidence:
  `crystal build src/adamas.cr -o tmp/adamas_l19_macro_number_stage1
  --error-trace` exits 0; `KEEP_TMP=1
  STAGE1_COMPILER=tmp/adamas_l19_macro_number_stage1 REQUIRE_RAW_DUMP=1
  REQUIRE_CLASSIFICATION=1 scripts/generated_stage_finalize_to_s_classifier.sh`
  exits 0 and reports `normal_string_header_size_global_shape=i32_12`,
  `normal_string_header_size_global_line=@String__classvar__HEADER_SIZE =
  global i32 12`, `raw_dump_classification=raw_dump_before_to_s_buffer_valid`,
  and `classification=post_to_s_llc_type_mismatch_frontier`. Adjacent guards
  pass: `regression_tests/p2_constant_globals_no_prelude.sh
  tmp/adamas_l19_macro_number_stage1`,
  `regression_tests/p2_prescan_complex_constants_frontier.sh
  tmp/adamas_l19_macro_number_stage1`, and
  `regression_tests/p2_macro_number_parsed_literals_no_prelude.sh
  tmp/adamas_l19_macro_number_stage1`; `regression_tests/run_combined.sh
  tmp/adamas_l19_macro_number_stage1 4` reports 36/36; and
  `regression_tests/run_all.sh tmp/adamas_l19_macro_number_stage1 4` reports
  152/152. This is a moved frontier, not green `s2b`/`s3b`: the next residual is
  still post-`to_s` LLVM validity, now with `String::HEADER_SIZE` proven
  scalar-correct and `llc` failing at `%r18.fromslot.1` (`i64` defined, `ptr`
  expected). Do not return to constant global, source fallback, or
  `MacroNumberValue` constructors for this frontier unless fresh evidence
  decays the `i32_12` row.

- 2026-07-03 UPDATE: Slice 0k-EM is a diagnostic-only split of the
  post-0k-EL residual. `scripts/generated_stage_finalize_to_s_classifier.sh`
  now inspects the generated normal `.ll` and separates
  `post_to_s_classvar_scalar_global_frontier` from the broader
  `post_to_s_llc_type_mismatch_frontier`. Focused evidence before cleanup used
  this generated compiler:
  `GENERATED_S2=tmp/generated-stage-finalize-to-s.bVJp2w/adamas_s2
  REQUIRE_RAW_DUMP=1 REQUIRE_CLASSIFICATION=1
  scripts/generated_stage_finalize_to_s_classifier.sh` exits 0 and reports
  `classification=post_to_s_classvar_scalar_global_frontier`,
  `normal_finalize_to_s_done_rows=1`,
  `raw_dump_classification=raw_dump_before_to_s_buffer_valid`,
  `normal_string_header_size_global_shape=ptr_null`,
  the global line `@String__classvar__HEADER_SIZE = global ptr null`, and an
  LLVM type mismatch at `normal_out.ll:5799:17`
  (`%binop7.left_ext` defined as `i64`, expected `i32`). This refines L19:
  the next production movement must pin the producer of the
  `String::HEADER_SIZE` classvar scalar global type/value contract
  (constant recording, `offsetof` macro value, MIR global registration, or
  undefined-global fallback) before touching arithmetic emission, `llc`
  mismatch consumers, output ownership, finalization, generic `IO::Memory`,
  tail, metadata, DWARF, type-name, `NamedTuple`/`Tuple`, ambient maps, or
  `BlockOwner`.

- 2026-07-03 UPDATE: Slice 0k-EL consumes the 0k-EJ/0k-EK output-restore
  edge with a minimal `LLVMOutputOwnershipContract` production slice. The
  backend now owns primary/current output identity through the contract and
  routes metadata, function-block, parent/worker, merge, and rescue restore
  output transitions through explicit helpers instead of direct local
  `saved_output = @output` / `@output = saved_output` restore authority. Strict
  source-shape guard is green:
  `REQUIRE_OUTPUT_OWNERSHIP=1 scripts/llvm_output_ownership_source_shape_guard.sh`
  reports `output_ownership_shape=output_ownership_contract_consumed_by_parallel_restore`,
  `parallel_saved_output_snapshot_count=0`,
  `parallel_direct_saved_output_restore_count=0`, and
  `parallel_output_ownership_reference_count=3`. Fresh generated-stage evidence
  with `tmp/adamas_output_owner_stage1`:
  `STAGE1_COMPILER=tmp/adamas_output_owner_stage1 REQUIRE_RAW_DUMP=1
  REQUIRE_CLASSIFICATION=1 scripts/generated_stage_finalize_to_s_classifier.sh`
  exits 0 with `classification=post_to_s_frontier`,
  `normal_finalize_to_s_done_rows=1`,
  `normal_parallel_rescue_current_pos_before_restore=147519`,
  `normal_parallel_rescue_saved_output_pos=147519`,
  `normal_parallel_rescue_restored_output_pos=147519`, and
  `raw_dump_classification=raw_dump_before_to_s_buffer_valid`. This is not green
  `s2b`/`s3b`: the residual has moved after final output stringification to
  generated LLVM IR validity / post-`to_s` handling. The next production movement
  must split that post-`to_s` residual; do not return to output ownership,
  finalization, generic `IO::Memory`, tail, metadata, DWARF, type-name,
  `NamedTuple`/`Tuple`, ambient maps, or `BlockOwner` from stale L18 evidence.

- 2026-07-03 UPDATE: Slice 0k-EK adds the pre-code
  `OutputOwnershipContract` gate required before touching the 0k-EJ rescue
  restore edge. New executable source-shape guard:
  `scripts/llvm_output_ownership_source_shape_guard.sh`. Current source reports
  `output_ownership_shape=legacy_ambient_output_restore`, with
  `parallel_saved_output_snapshot_count=1`,
  `parallel_direct_saved_output_restore_count=3`, and
  `parallel_output_ownership_reference_count=0`. Strict mode is intentionally
  red:
  `REQUIRE_OUTPUT_OWNERSHIP=1 scripts/llvm_output_ownership_source_shape_guard.sh`
  exits 1. The next production code slice must make this strict guard green and
  then rerun the 0k-EJ generated-stage classifier. If strict source shape turns
  green but the classifier still selects
  `select_parallel_rescue_saved_output_binding_frontier`, the slice is
  architecture theater and must be reworked or reverted.

- 2026-07-03 UPDATE: Slice 0k-EJ refutes 0k-EI finalization-null as the first
  bad transition and moves the active L18 edge earlier, into
  `emit_functions_parallel` rescue fallback output restore. The classifier now
  logs default-off `parallel_rescue_before_output_restore` and
  `parallel_rescue_after_output_restore` rows. Fresh evidence with
  `tmp/adamas_0kej_stage1`:
  `STAGE1_COMPILER=tmp/adamas_0kej_stage1 REQUIRE_RAW_DUMP=1
  REQUIRE_CLASSIFICATION=1 scripts/generated_stage_finalize_to_s_classifier.sh`
  reports `classification=select_parallel_rescue_saved_output_binding_frontier`,
  with `normal_parallel_rescue_current_pos_before_restore=147447`,
  `normal_parallel_rescue_saved_output_present=1`,
  `normal_parallel_rescue_saved_output_pos=0`, and
  `normal_parallel_rescue_restored_output_pos=0`. Therefore the produced
  compiler still has a populated current `@output` immediately before rescue
  restore, but the rescue-local `saved_output` binding points at an empty output
  object; restoring it zeroes the final output, making the later
  `@output`/finalization-null rows a proxy. The next production movement must
  target an `OutputOwnershipContract` / scoped output-restore owner edge around
  `LLVMIRGenerator.@output`, parallel parent/worker temp outputs, and fallback
  restore. Do not patch finalization, `IO::Memory#bytesize`, generic
  `IO::Memory`/`String`, fd/raw output, tail, metadata, DWARF, type-name,
  worker count, `NamedTuple`/`Tuple`, ambient maps, or `BlockOwner` from this
  evidence; also do not force `ADAMAS_LLVM_WORKERS=1` as a fix without an
  owner-edge receipt.

- 2026-07-03 UPDATE: Slice 0k-EI refines the 0k-EH `bytesize` claim with a
  pre-cast receiver ownership split. The same default-off raw final-buffer gate
  now logs `@output.object_id`, raw header checkpoints, cast receiver
  `object_id`, registry-backed `@bytesize` offset lookup, raw ivar load, and
  getter entry. Fresh evidence with `tmp/adamas_l18_output_stage1`:
  `regression_tests/io_memory_final_materialization_repro.sh` remains green;
  `REQUIRE_RAW_DUMP=1 REQUIRE_CLASSIFICATION=1
  scripts/generated_stage_finalize_to_s_classifier.sh` preserves
  `classification=select_finalize_to_s_stringification_frontier` but now
  reports `raw_dump_classification=select_finalize_raw_dump_output_null_frontier`.
  The raw run logs `finalize_raw_dump_output_object_id_done` and
  `finalize_raw_dump_output_null` before any output raw-header, cast receiver,
  field-offset, raw-bytesize, or getter checkpoint. Therefore the 0k-EH
  `IO::Memory#bytesize` edge is refuted as the first boundary. The current
  L18 residual is `LLVMFinalOutputMaterialization` output receiver lifetime:
  why the produced compiler's `LLVMIRGenerator.@output` reference is already
  null at finalization. Do not patch `IO::Memory#bytesize`, final-output field
  offsets/layout, `as(IO::Memory)`, generic `IO::Memory`/`String`, fd/raw
  output, tail, metadata, DWARF, type-name, `NamedTuple`/`Tuple`, ambient maps,
  or `BlockOwner` from this evidence. The next source movement must split the
  producer of the null `@output` state: constructor/init ownership vs field
  overwrite vs generated-stage instance/ivar load.

- 2026-07-03 UPDATE: Slice 0k-EH narrows L18 again with a default-off raw
  final-buffer micro-split. `ADAMAS_DUMP_LLVM_FINAL_BUFFER_BEFORE_TO_S=<path>`
  now drives `scripts/generated_stage_finalize_to_s_classifier.sh` through
  cast/env/bytesize/buffer/write checkpoints and reports a raw-dump
  classification. Fresh evidence with `tmp/adamas_l18_rawdump_stage1`:
  `regression_tests/io_memory_final_materialization_repro.sh` remains green;
  `REQUIRE_RAW_DUMP=1 REQUIRE_CLASSIFICATION=1
  scripts/generated_stage_finalize_to_s_classifier.sh` preserves
  `classification=select_finalize_to_s_stringification_frontier` and reports
  `raw_dump_classification=select_finalize_raw_dump_bytesize_frontier`. The
  raw run reaches `finalize_raw_dump_env_lookup_done`,
  `finalize_raw_dump_cast_done`, and `finalize_raw_dump_enter`, then exits 139
  before `finalize_raw_dump_bytesize_done`. Therefore the next root movement is
  not fd output, raw buffer write, generic `String.new(buffer, bytesize)`, or
  generic user-runtime `IO::Memory#to_s`; it must split the produced compiler's
  final `IO::Memory` object field read / receiver validity at `bytesize`.

- 2026-07-03 UPDATE: L18 negative control after the refuted fd-output bypass.
  The `generate_to_fd` / `finalize_to_fd` WIP was removed; changing normal
  output ownership is not the active SDD route. New focused guard:
  `regression_tests/io_memory_final_materialization_repro.sh <compiler>`.
  Fresh evidence with `tmp/adamas_l18_iomem_stage1` reports
  `io_memory_final_materialization_repro_ok` for both tiny and resize-heavy
  (~2MB) `IO::Memory#to_s`, `IO::Memory#to_slice`, `String.new(slice)`, and
  `String.new(buffer, bytesize)` paths. A fresh L18 classifier using the same
  stage1 still reports `classification=select_finalize_to_s_stringification_frontier`
  with normal produced-s2 exit 139 at `finalize_to_s_enter`, 150/150 functions
  emitted, and stop-before-to-s clean. Therefore the next source movement is
  still `LLVMFinalOutputMaterialization`, but it must split final output
  buffer shape/context (produced compiler, large final buffer, ownership /
  finalization path) rather than patch generic user-runtime `IO::Memory` or
  resurrect fd/external-sink output.

- 2026-07-03 UPDATE: Slice 0k-EF classifies the L17 finalization boundary with
  a default-off stop gate and a focused script:
  `scripts/generated_stage_finalize_to_s_classifier.sh`. The new env gate
  `ADAMAS_STOP_BEFORE_LLVM_FINALIZE_TO_S=1` logs
  `llvm.generate_phase=finalize_to_s_stop_before` and exits before
  `IO::Memory#to_s`. Fresh classifier evidence reports
  `classification=select_finalize_to_s_stringification_frontier`: the normal
  produced-s2 full-prelude `puts 42` run exits 139 after
  `finalize_to_s_enter` with `finalize_to_s_done_rows=0`; the stop-before run
  exits 0 with `finalize_to_s_stop_before_rows=1`. Both runs emit 150/150
  sequential functions and reach `tail_done`, `metadata_done`,
  `type_name_table_done`, and `dwarf_done`. This is still not green
  `s2b`/`s3b`; the next production movement must target the
  `LLVMFinalOutputMaterialization` / in-memory stringification owner edge, not
  tail, metadata, DWARF, type-name, worker policy, `NamedTuple`/`Tuple`,
  ambient maps, or `BlockOwner`.

- 2026-07-03 UPDATE: Slice 0k-EE consumes the active function-emission
  attempt edge with a source-equivalent LLVM phi emission control-flow rewrite.
  In `emit_phi`, the bool and int mismatched-incoming loops no longer use an
  early `next` after `phi_incoming_ref`; they use an explicit `if/else` so the
  self-hosted compiler does not re-enter the same incoming loop shape. This is
  not a per-method `system_write` patch: the same reusable `PhiEmission`
  subowner covers the old #87 int phi and the next #92 bool phi. Focused
  generated-stage evidence with `tmp/adamas_0kee_stage1` and
  `tmp/adamas_0kee_s2`: `puts 42` no longer memory-kills in
  late function emission. It emits all planned sequential functions (149 in the
  fresh 0k-EE gate), reaches
  `llvm.generate_phase=finalize_to_s_enter`, and exits 139 with peak RSS about
  1.25 GB. The old #87 `system_write` and #92 `gets_slow` function-emission
  cliffs are consumed; the new frontier is post-function-emission finalization,
  not green `s2b`/`s3b`. Verification: clean stage1 build passes; combined
  suite passes `36/36`; the original suite run timed out under a 900s wrapper
  after 139 PASS results, the 13 remaining tests were run individually with
  12 PASS and `test_rescue_nested` red, and an isolated HEAD baseline confirms
  `test_rescue_nested` was already exit 139. Do not claim full-suite green from
  this slice; next work must classify the `finalize_to_s_enter` exit 139
  boundary before tail/output/string-buffer fixes.

- 2026-07-03 UPDATE: Slice 0k-ED consumes the 0k-EC ambiguity with an
  executable stop-before-active-function discriminator. New debug-only gate:
  `ADAMAS_STOP_BEFORE_LLVM_FUNCTION_INDEX=<n>`; new classifier:
  `scripts/generated_stage_function_emission_attempt_classifier.sh`. With
  `tmp/adamas_l15_stop_stage1`, `STOP_INDEX=87`, and
  `REQUIRE_CLASSIFICATION=1`, the classifier builds generated `s2`, stops both
  default and workers=1 produced compilers immediately before function #87, and
  reports `classification=select_active_function_attempt_edge`. Both stop
  probes are clean (`default_workers_peak_rss_mb=1180`,
  `workers1_peak_rss_mb=1183`, no memory kill, exit 0) and both last outcome
  rows are `status=stop_before`, `index=87`, function
  `__vdispatch__IO::FileDescriptor#system_write$Slice(UInt8)$T122`. The
  gate-off mode selector still reports
  `classification=select_default_late_llvm_resource_lane` with final outcome
  `status=started`, `index=87`; full suites pass `152/152 + 36/36`; static
  semantic/codepath guards remain green. This refutes pre-#87 retained
  output/resource state as the first owner for the current L15 edge. It does
  not fix memory and does not license patching `system_write` by name; the next
  slice must split inside function #87 emission or prove a reusable emission
  subowner behind that function.

- 2026-07-02 UPDATE: Slice 0k-EC extends the 0k-EB L15 owner fact with
  in-flight function-emission attempts. `emit_functions_sequential` now logs a
  default-off `llvm.function_emission_outcome` row with `status=started`
  before each function emission attempt, while preserving the existing
  `emitted` and `index_error` completion rows. This consumes the ambiguity in
  0k-EB: the last completed function was not necessarily the active resource
  edge at kill time. Evidence with `tmp/adamas_l15_attempt_stage1`:
  `scripts/generated_stage_mode_resource_lane_classifier.sh` preserves
  `classification=select_default_late_llvm_resource_lane`, keeps HIR/MIR stop
  gates clean in both modes, reports
  `transaction.default_function_emission_outcome_rows=173`,
  `transaction.workers1_function_emission_outcome_rows=173`, and selects last
  outcome `status=started`, `index=87`, function
  `__vdispatch__IO::FileDescriptor#system_write$Slice(UInt8)$T122`. Full
  suites pass `152/152 + 36/36`; static semantic/codepath guards remain green.
  This is still not a memory fix and not green `s2b`/`s3b`. It narrows the next
  L15 discriminator to the active emission of function #87 versus pre-existing
  output/resource/side-effect retention, and it explicitly does not license a
  per-method `system_write` patch by name.

- 2026-07-02 UPDATE: Slice 0k-EB implements the first L15 late
  LLVM/function-emission owner fact instead of adding another RSS selector.
  `src/compiler/mir/llvm_backend.cr` now has `LLVMFunctionEmissionOutcome` and,
  under `ADAMAS_GSETX_FUNCTION_EMISSION_OUTCOMES=1`, sequential function
  emission logs `llvm.function_emission_outcome` rows with function identity,
  index/total, output delta, emitted/called/undefined deltas, and status.
  `scripts/generated_stage_execution_transaction_report.sh` enables and
  consumes those rows; `scripts/generated_stage_mode_resource_lane_classifier.sh`
  passes them through. Focused evidence with `tmp/adamas_l15_outcome_stage1`:
  `REQUIRE_JOINED=1 REQUIRE_FUNCTION_EMISSION_SPLIT=1
  REQUIRE_FUNCTION_EMISSION_OUTCOMES=1
  scripts/generated_stage_execution_transaction_report.sh` reports
  `runtime.function_emission_outcome_rows=172`,
  `default/workers1_function_emission_outcome_rows=86/86`, last completed
  outcome index `86`, function
  `__vdispatch__IO::FileDescriptor#unbuffered_write$Slice(UInt8)$T121`.
  The broader mode selector still reports
  `classification=select_default_late_llvm_resource_lane` and preserves
  L15/L16. Full suites pass `152/152 + 36/36`. This is not a memory fix and not
  green `s2b`/`s3b`; the next L15 slice should use outcome rows to decide
  whether a function, output-growth, side-effect-growth, or retention edge is
  root-sized. Do not patch that last function by name without a new owner-edge
  falsifier.

- 2026-07-02 UPDATE: architecture acceleration checkpoint after 0k-DZ. The
  current docs/control risk is not lack of documentation; it is report churn
  that does not produce the next production receipt. The next code movement
  must either (a) write and consume a focused `PhaseAuthority` /
  `GeneratedStageExecution` receipt for the L15 default late
  LLVM/function-emission resource edge, preserving the L16 self-build guard and
  consumed workers=1 CopyPropagation controls, or (b) explicitly retire/refute
  an older report surface with a protecting falsifier. Phase 1/1b static
  censuses remain guards and planning inputs, not delete evidence. Do not start
  broad file splitting, `NamedTuple`/`Tuple`, ambient-map, `BlockOwner`,
  backend-rescue, memory-budget, worker-policy, or cleanup-by-grep work from
  this checkpoint. Each next slice must pass the mini-Quadrum preflight:
  claim, hardest falsifier, owner edge, and DoD before edits.

- 2026-07-02 UPDATE: fresh post-0k-DY hostile revalidation preserves `L15`
  but adds a self-build guard for generated-s2 build variance. A first strict
  mode-selector run with a freshly built `tmp/adamas_l15_stage1` failed before
  produced-s2 stop gates (`classification=mode_resource_classifier_build_failed`,
  `nested.classification=s2_build_fails`) after `pass3 after lower_main call`
  and deferred allocator flush. That failure is NOT promoted to a new frontier:
  a direct full self-build with a fresh `tmp/adamas_l16_stage1` succeeds under
  the same 4GB cap (`scripts/run_safe.sh tmp/adamas_l16_stage1 600 4096
  src/adamas.cr -o tmp/l16_full_s2` -> exit 0, peak RSS 3396 MB), and the new
  `scripts/generated_stage_self_build_boundary_classifier.sh` reports
  `classification=self_build_after_mir_boundary` with stop gates clean
  (`compile_entry=4` MB, `parse=330` MB, `HIR=1722` MB, `MIR=2328` MB).
  Rerunning the mode selector with `GENERATED_S2=tmp/l16_full_s2` re-establishes
  `classification=select_default_late_llvm_resource_lane` with clean produced-s2
  HIR/MIR stop gates in both modes, joined transaction rows, and
  `default_mode_boundary=workers1_mode_boundary=reached_function_emission`.
  Therefore the active production frontier remains the default late
  LLVM/function-emission lane, but future L15 rechecks must distinguish
  generated-s2 self-build variance from produced-s2 lane evidence.

- 2026-07-02 UPDATE: Slice 0k-DY CONSUMES the selected 0k-DX
  `CopyPropagationPass#compute_dominance_info` resource lane. Production
  change: `CopyPropagationPass` now uses exact lazy dominance queries for
  cross-block replacement checks instead of building a full dominator tree /
  interval table for each non-local CP run. `crystal build src/adamas.cr -o
  tmp/adamas_lazy_dom_stage1 --error-trace` passes. The old strict dominator
  classifier now decays in the intended direction:
  `STAGE1_COMPILER=tmp/adamas_lazy_dom_stage1 REQUIRE_CLASSIFICATION=1
  REQUIRE_DOMINATOR=1 TAIL_LINES=30
  scripts/generated_stage_workers1_copyprop_dominator_classifier.sh` reports
  `classification=workers1_copyprop_dominator_classifier_build_failed` only
  because the nested pass lane decayed: `subphase.classification=workers1_mir_subphase_clean`,
  `subphase.s2_mir_opt_peak_rss_mb=1177`, and
  `subphase.s2_mir_opt_memory_kill=0`. The broader mode selector confirms the
  new residual:
  `STAGE1_COMPILER=tmp/adamas_lazy_dom_stage1 STAGE2_BUILD_TIMEOUT=600
  REQUIRE_CLASSIFICATION=1 REQUIRE_LANE_SELECTION=1 TAIL_LINES=30
  scripts/generated_stage_mode_resource_lane_classifier.sh` reports clean HIR
  and MIR stop-gates in both modes (`s2_default_mir_peak_rss_mb=1173`,
  `s2_workers1_mir_peak_rss_mb=1177`) and selects
  `classification=select_default_late_llvm_resource_lane` with joined
  transaction residual `default_mode_boundary=reached_function_emission`,
  `workers1_mode_boundary=reached_function_emission`, and both modes still
  memory-killed after lower_main. Full stage1 suites pass:
  `regression_tests/run_all_suites.sh tmp/adamas_lazy_dom_stage1 4` -> `152/152`
  original and `36/36` combined. This is not green `s2b`/`s3b`; it moves the
  active resource frontier from workers=1 MIR CopyPropagation dominance to the
  default late LLVM/function-emission lane. Next production work must re-enter
  the board through that residual, not through CP, `NamedTuple`/`Tuple`,
  ambient maps, `BlockOwner`, backend rescue, worker forcing, or memory budget.

- 2026-07-02 UPDATE: post-0k-DX local-only CopyPropagation fail-closed
  preflight is REFUTED. A candidate production edit that returned without
  applying any dominance-dependent replacements avoided the old
  `compute_dominance_info` path but made the generated `s2` crash before the
  current MIR-optimization frontier: rerunning
  `STAGE1_COMPILER=tmp/adamas_cp_local_stage1 REQUIRE_CLASSIFICATION=1
  TAIL_LINES=30 scripts/generated_stage_workers1_copyprop_phase_classifier.sh`
  ended in `classification=workers1_copyprop_phase_classifier_build_failed`;
  the nested subphase classifier reported `classification=workers1_hir_resource_boundary`,
  `nested.classification=pre_llvm_entry_failure`, `s2_hir_rc=139`,
  `s2_mir_opt_rc=139`, and low RSS (`306` MB, no memory kill). The edit was
  reverted. Therefore the next production receipt must not "fix" 0k-DX by
  disabling all cross-block/dominance-dependent CP. It must provide a
  memory-safe dominance construction/query strategy or a narrower replacement
  policy with a generated-stage guard that does not regress to pre-LLVM-entry
  exit 139.

- 2026-07-02 UPDATE: post-0k-DX local-safe-subset CopyPropagation preflight is
  also REFUTED. A narrower candidate kept only replacements whose source,
  target, and uses were same-block/order-safe, while dropping the
  dominance-needed subset. It still regressed generated `s2` before the current
  MIR-optimization frontier:
  `STAGE1_COMPILER=tmp/adamas_cp_filter_stage1 REQUIRE_CLASSIFICATION=1
  TAIL_LINES=30 scripts/generated_stage_workers1_copyprop_phase_classifier.sh`
  ended in `classification=workers1_copyprop_phase_classifier_build_failed`;
  nested evidence reported `classification=workers1_hir_resource_boundary`,
  `nested.classification=pre_llvm_entry_failure`, `s2_hir_rc=139`,
  `s2_mir_opt_rc=139`, and low RSS (`306` MB, no memory kill). The edit was
  reverted. Therefore the next production receipt should not drop the
  dominance-needed subset as a bootstrap fix. It must make dominance
  construction/query itself memory-safe, or produce a stronger proof that a
  specific dominance-dependent replacement class can be omitted without
  regressing generated-stage entry.

- 2026-07-02 UPDATE: Slice 0k-DX splits the selected workers=1
  `CopyPropagationPass#apply_build_dominators` lane by inner substep. New
  debug-only cutoff: `ADAMAS_CP_DOM_THROUGH_STEP=<step>`; new executable
  classifier:
  `scripts/generated_stage_workers1_copyprop_dominator_classifier.sh`. Fresh
  `STAGE1_COMPILER=tmp/adamas_copyprop_dom_stage1 REQUIRE_CLASSIFICATION=1
  REQUIRE_DOMINATOR=1 TAIL_LINES=30` evidence first re-confirms 0k-DW
  (`phase.classification=select_workers1_copyprop_apply_build_dominators_resource_lane`,
  full `apply_build_dominators` peak `4329` MB, memory-kill), then selects
  `classification=select_workers1_copyprop_dom_compute_dominance_info_resource_lane`.
  Inner controls are clean for `build_def_maps` (`1175` MB) and `skip_check`
  (`1174` MB), while `compute_dominance_info` memory-kills at `4364` MB
  (`memory_kill_kb=4467872`). Therefore the next production resource receipt
  must consume or refute `compute_dominance_info` itself: dominance construction
  frequency, scope, representation, or replacement-demand policy. Do not patch
  `build_def_maps`, the skip predicate, affected-block collection, rewrite
  blocks, earlier MIR passes, worker policy, memory budgets, `NamedTuple` /
  `Tuple`, ambient maps, or `BlockOwner` from this evidence. Do not add another
  cascaded selector unless this compute-dominance result decays or directly
  names a production fix-form.

- 2026-07-02 UPDATE: Slice 0k-DW splits the selected workers=1
  `CopyPropagationPass` lane by phase-level OS-RSS cutoff. New debug-only
  cutoff: `ADAMAS_CP_THROUGH_PHASE=<phase>`; new executable classifier:
  `scripts/generated_stage_workers1_copyprop_phase_classifier.sh`. Fresh
  `REQUIRE_CLASSIFICATION=1 REQUIRE_PHASE=1` evidence first re-confirms 0k-DV
  (`pass.classification=select_workers1_mir_opt_copy_propagation_resource_lane`,
  copy-propagation memory-kill `4345` MB), then selects
  `classification=select_workers1_copyprop_apply_build_dominators_resource_lane`.
  Controls are clean for `run_collect_state` (`1173` MB),
  `run_find_replacements` (`1174` MB), and
  `apply_collect_affected_blocks` (`1175` MB); `run_apply_replacements` is
  broad-high (`4264` MB), but the first inner high is
  `apply_build_dominators` (`4237` MB), with later apply phases still high.
  Therefore the next production resource receipt must target the
  `apply_build_dominators` corridor (`build_def_maps`,
  `can_skip_dominators_for_local_replacements?`, or `compute_dominance_info`)
  before any rewrite, affected-block-set, or generic CopyPropagation patch.
  Preserve the earlier clean controls and default-mode residual; do not add
  another cascaded selector unless this phase result decays.

- 2026-07-02 UPDATE: Slice 0k-DV splits the selected workers=1 MIR
  optimization lane by pass-level OS-RSS cutoff. New debug-only cutoff:
  `ADAMAS_MIR_OPT_THROUGH_PASS=<pass>`; new executable classifier:
  `scripts/generated_stage_workers1_mir_opt_pass_classifier.sh`. Fresh
  `REQUIRE_CLASSIFICATION=1 REQUIRE_PASS=1` evidence first re-confirms 0k-DU
  (`subphase.classification=select_workers1_mir_optimization_resource_lane`,
  stage1 control `334` MB, produced-s2 MIR bodies `1173` MB, produced-s2 MIR
  opt memory-kill `4334` MB), then selects
  `classification=select_workers1_mir_opt_copy_propagation_resource_lane`.
  Pass cutoff controls are clean through `rc_elision` (`1174`/`1175`/`1174`
  MB for constant folding, local CSE, RC elision), while `copy_propagation`
  memory-kills at `4218` MB and later cutoffs remain high. Therefore the next
  production resource receipt must target `CopyPropagationPass` state/resource
  growth first, not generic optimizer work. Do not add another pass selector
  unless it refutes this result, and do not patch earlier MIR passes, HIR/MIR
  lowering, default LLVM emission, worker policy, memory budgets, backend
  rescue, `NamedTuple`/`Tuple`, ambient maps, or `BlockOwner` from this
  evidence.

- 2026-07-02 UPDATE: Slice 0k-DU splits the selected workers=1 HIR-to-MIR
  resource lane by MIR subphase using OS-RSS stop gates. New debug-only gates:
  `ADAMAS_STOP_AFTER_MIR_TYPE_REGISTRATION`,
  `ADAMAS_STOP_AFTER_MIR_PREPARE`, `ADAMAS_STOP_AFTER_MIR_BODIES`, and
  `ADAMAS_STOP_AFTER_MIR_OPT`; new executable classifier:
  `scripts/generated_stage_workers1_mir_subphase_classifier.sh`. Fresh
  `REQUIRE_CLASSIFICATION=1 REQUIRE_SUBPHASE=1` evidence reports
  `classification=select_workers1_mir_optimization_resource_lane`: stage1
  workers=1 MIR control is clean (`345` MB); produced-s2 workers=1 HIR/type
  registration/prepare/bodies stop gates are clean (`1167`/`1170`/`1170`/`1172`
  MB); produced-s2 workers=1 `MIR_OPT` memory-kills at `4149` MB and full MIR
  stop-gate memory-kills at `4408` MB. Therefore the next production resource
  receipt must target workers=1 MIR optimization resource growth first and
  preserve HIR/body-lowering as clean controls plus default late LLVM/function
  emission as residual. Do not patch HIR lowering, MIR type registration,
  function-stub prepare, body lowering, default function emission, worker
  policy, memory budgets, backend rescue, `NamedTuple`/`Tuple`, ambient maps,
  or `BlockOwner` from this evidence.

- 2026-07-02 UPDATE: Slice 0k-DT selects the mode-local resource lane with
  OS-RSS stop-gate evidence. New executable classifier:
  `scripts/generated_stage_mode_resource_lane_classifier.sh`. Fresh
  `REQUIRE_CLASSIFICATION=1 REQUIRE_LANE_SELECTION=1` evidence reports
  `classification=select_workers1_hir_to_mir_resource_lane`: stage1
  workers=1 MIR stop-gate is clean (`343` MB), produced-s2 HIR stop-gates are
  clean in both modes (`default=1168` MB, `workers1=1167` MB), produced-s2
  default MIR stop-gate is clean (`1172` MB), but produced-s2 workers=1 MIR
  stop-gate memory-kills at `4105` MB (`memory_kill=1`). The joined
  transaction report still records the default residual as
  `reached_function_emission` with 13 function-emission rows and the workers=1
  residual as `after_hir_final_before_mir_final`, both memory-killed. Therefore
  the next production resource receipt must target the workers=1 HIR-to-MIR
  resource growth lane first and preserve default-mode late LLVM/function
  emission as a residual. Do not patch default sequential function emission,
  worker policy, memory budgets, startup/parse/HIR retention, backend rescue,
  `NamedTuple`/`Tuple`, ambient maps, or `BlockOwner` from this evidence.

- 2026-07-02 UPDATE: Slice 0k-DS resolves the startup/process-baseline problem
  card required by 0k-DR. New executable classifier:
  `scripts/generated_stage_startup_resource_baseline_classifier.sh`, using the
  debug-only `ADAMAS_STOP_AFTER_COMPILE_ENTRY` gate plus existing parse/HIR/MIR
  stop gates and `/usr/bin/time -l` OS RSS evidence. Fresh
  `REQUIRE_CLASSIFICATION=1` evidence reports
  `classification=llvm_or_later_resource_boundary`:
  `stage1_compile_entry_peak_rss_mb=4`, `s2_compile_entry_peak_rss_mb=6`,
  `s2_parse_peak_rss_mb=305`, `s2_hir_peak_rss_mb=1168`,
  `s2_mir_peak_rss_mb=1171`, while the nested full generated-stage classifier
  remains `nested.classification=llvm_entry_failure_after_lower_main` with both
  default and workers=1 memory-killed after lower_main. Therefore 0k-DR's high
  compile-entry GC `non_gc` is telemetry/accounting noise for owner selection,
  not actual startup RSS. Do not patch startup/parse/HIR/MIR retention or add
  another GC memory selector. If resource pressure remains the active target,
  the next receipt must select a late LLVM/function-emission or mode-local
  resource owner edge using OS RSS evidence.

- 2026-07-02 UPDATE: Slice 0k-DR consumes the L9 pre-HIR split and terminates
  the no-more-selector-chain gate for the default-lane memory surface.
  `REQUIRE_SPLIT=1 scripts/generated_stage_pre_hir_memory_split_classifier.sh`
  reports `classification=pre_hir_pressure_compile_entry`,
  `terminal_status=terminal`, `default_first_phase=cli.compile_entry`,
  `default_first_high_owner=cli.compile`,
  `default_first_high_non_gc=4323300568`,
  `default_max_phase=cli.compile_entry`, and
  `default_last_phase=llvm.sequential_start`; stage1 workers=1 control remains
  clean (`stage1_control_rc=0`, `stage1_control_run_rc=0`, stdout `42`,
  `stage1_memory_rows=35`, `stage1_max_non_gc=0`). Therefore the earlier
  `pre_function_pressure_hir_owned` row was late-row aliasing, not a HIR owner
  edge. Do not add another pre-HIR pipeline memory selector. If resource
  pressure remains the target, write a startup/process-baseline problem card;
  otherwise return to the SDD Current Execution Board and select a behavior or
  state authority edge.

- 2026-07-02 UPDATE: Slice 0k-DQ adds default-off `memory.phase` rows and
  executable owner selector
  `scripts/generated_stage_pre_function_memory_owner_classifier.sh`. Fresh
  `REQUIRE_OWNER=1` evidence with the current produced s2 reports
  `classification=pre_function_pressure_hir_owned`: the first high produced-s2
  non-GC row is already `default_first_high_phase=cli.hir_final`,
  `default_first_high_owner=cli.hir`, `default_first_high_non_gc=4314198280`,
  and `default_last_phase=llvm.sequential_start` remains at the same non-GC
  level. Stage1 workers=1 control compiles/runs the same source with stdout
  `42`, `stage1_memory_rows=19`, and `stage1_max_non_gc=0`. Therefore the
  default-lane owner moved earlier than LLVM setup/session/function emission.
  This note is now superseded by 0k-DR above: the admitted L9 pre-HIR split
  returned a compile-entry lane refutation, not a HIR owner receipt. Do not
  patch LLVM output, function
  plan/session, metadata, workers, memory budget, materialization,
  `NamedTuple`/`Tuple`, ambient maps, or `BlockOwner` from this evidence.

- 2026-07-02 UPDATE: Slice 0k-DP adds executable discriminator
  `scripts/generated_stage_function_emission_memory_discriminator.sh` for the
  default-mode function-emission resource lane. Fresh
  `REQUIRE_CURRENT=1` evidence preserves the current transaction boundary
  (`report.default_mode_boundary=reached_function_emission`,
  `report.workers1_mode_boundary=after_hir_final_before_mir_final`,
  `report.default_memory_kill=1`, `last_index=80/150`) but classifies the
  memory shape as `function_emission_preexisting_non_gc_pressure`. Produced s2
  default-worker snapshots show `default_first_non_gc=4353564448` already at
  `idx=11/150`, unchanged at the last snapshot, while text/state counters remain
  small (`default_first_emit_raw_out=157628`,
  `default_last_emit_raw_out=239160`, `default_first_func_state=7220`,
  `default_last_func_state=18452`). The stage1 workers=1 control compiles/runs
  the same source with `stage1_first_non_gc=0`, `stage1_last_non_gc=0`,
  `stage1_snapshot_rows=314`, and stdout `42`. Therefore the next default-lane
  selector must move earlier than output sink or incremental function text
  growth: classify the owner of pre-existing produced-stage non-GC pressure
  present before/at function emission. Workers=1 remains the separate
  `after_hir_final_before_mir_final` residual.

- 2026-07-02 UPDATE: Slice 0k-DO selects the default-mode function-emission
  sink boundary as the next `PhaseAuthority` / `GeneratedStageExecution`
  receipt, then adds executable falsifier
  `scripts/generated_stage_external_sink_preflight.sh`. It copies `src/`,
  injects an env-gated `llvm_gen.generate(file_io)` path only into the temp
  copy, builds both temp stage1 and temp generated s2 from that copy, and cleans
  temp artifacts by default. Fresh `REQUIRE_REFUTED=1` evidence reports
  `host_compile_rc=0`, `host_run_rc=0`, `host_stdout=42`,
  `host_ll_size>0`, `s2_build_rc=0`, and
  `classification=external_sink_preflight_refuted_empty_ir`. The
  generated-stage part reports
  `report.default_mode_boundary=after_output_start_before_llvm_generate`,
  `report.join_status=phase_local_only`,
  `report.default_llvm_generate_phase_rows=0`,
  `report.default_memory_kill=0`,
  `report.output_commit_record=binary_compile_rc:1`,
  `default_workers_ll_size=0`, and `default_workers_missing_main=1`. Therefore
  external sink is not an admitted resource fix; the next default-lane slice
  must either own/falsify produced-stage external-sink entrypoint emission, or
  choose a different function-emission resource edge. The workers=1 lane remains
  the named `after_hir_final_before_mir_final` residual.

- 2026-07-02 UPDATE: the 0k-DM workers=1 observability gap is now a named
  per-mode transaction boundary rather than an ambiguous missing-row symptom.
  `scripts/generated_stage_execution_transaction_report.sh` adds
  `REQUIRE_WORKER_MODE_BOUNDARY=1`, mode-local stage row counts, and
  `resource.default_mode_boundary` / `resource.workers1_mode_boundary`.
  Fresh evidence:
  `STAGE1_COMPILER=/tmp/adamas_worker_boundary_stage1 TAIL_LINES=30 REQUIRE_JOINED=1 REQUIRE_POST_CU_RESOURCE=1 REQUIRE_RESOURCE_PHASE_SPLIT=1 REQUIRE_FUNCTION_EMISSION_SPLIT=1 REQUIRE_WORKER_MODE_BOUNDARY=1 scripts/generated_stage_execution_transaction_report.sh`
  exits 0 with `resource.default_mode_boundary=reached_function_emission`,
  `resource.workers1_mode_boundary=after_hir_final_before_mir_final`,
  `runtime.default_mir_final_rows=1`, `runtime.workers1_mir_final_rows=0`,
  `runtime.default_llvm_generate_phase_rows=2`,
  `runtime.workers1_llvm_generate_phase_rows=0`,
  `runtime.default_function_emission_phase_rows=13`, and
  `runtime.workers1_function_emission_phase_rows=0`. This closes the L8
  ambiguity: default worker mode reaches LLVM function emission and dies during
  fallback sequential function emission, while workers=1 dies earlier after HIR
  finalization and before MIR finalization. The next production slice must pick
  one of those two transaction-owned resource lanes explicitly and preserve the
  other as a residual; it must not present a default-mode fix as both-mode
  bootstrap progress.

- 2026-07-02 UPDATE: the 0k-DL function-emission corridor is now split one
  level deeper. `LLVMIRGenerator` records default-off
  `llvm.function_emission_phase` rows for dispatch, sequential progress,
  parallel planning/fork/wait/merge, and fallback, and the transaction report
  adds `REQUIRE_FUNCTION_EMISSION_SPLIT=1`. Fresh evidence:
  `STAGE1_COMPILER=/tmp/adamas_function_phase_stage1 TAIL_LINES=30 REQUIRE_JOINED=1 REQUIRE_POST_CU_RESOURCE=1 REQUIRE_RESOURCE_PHASE_SPLIT=1 REQUIRE_FUNCTION_EMISSION_SPLIT=1 scripts/generated_stage_execution_transaction_report.sh`
  exits 0 with `final_classification=abort_resource_after_lower_main`,
  `resource.function_emission_split=during_sequential_function_emit`,
  `resource.function_emission_last_phase=sequential_progress`,
  `resource.function_emission_last_index=80`,
  `resource.function_emission_last_total=150`,
  `resource.function_emission_mode_join_status=default_only`,
  `runtime.default_function_emission_phase_rows=13`, and
  `runtime.workers1_function_emission_phase_rows=0`. This means the default
  worker mode reaches the known parallel rand fallback and then dies during
  sequential function emission; workers=1 still reports after-`lower_main`
  memory kill via classifier logs but does not join function-emission runtime
  rows. The next slice must either make that workers=1 observability gap
  root-sized or select a transaction-owned default-mode sequential emission
  edge; worker policy, memory budgets, output behavior, tail stubs, metadata,
  rand fallback, and backend semantic changes remain rejected.

- 2026-07-02 UPDATE: post-0k-DK resource corridor is now split by default-off
  LLVM generate phase rows. `LLVMIRGenerator#generate` records
  `llvm.generate_phase` rows under the existing `GSETX` transaction, and
  `scripts/generated_stage_execution_transaction_report.sh` adds
  `REQUIRE_RESOURCE_PHASE_SPLIT=1`. Fresh evidence:
  `STAGE1_COMPILER=/tmp/adamas_phase_stage1 TAIL_LINES=30 REQUIRE_JOINED=1 REQUIRE_POST_CU_RESOURCE=1 REQUIRE_RESOURCE_PHASE_SPLIT=1 scripts/generated_stage_execution_transaction_report.sh`
  exits 0 with `final_classification=abort_resource_after_lower_main`,
  `resource.llvm_generate_last_phase=function_emission_start`,
  `resource.llvm_generate_phase_split=during_function_emission`,
  `resource.llvm_generate_last_out_pos=147350`,
  `runtime.llvm_generate_phase_rows=2`, and
  `output.commit_record=llvm_ir_started_without_commit:file`. This refutes
  tail/stub/metadata/type-name/DWARF/final `IO::Memory#to_s` as the first
  observed boundary for the current resource residual. The next production
  slice, if any, must name a transaction-owned function-emission edge
  (`emit_functions_parallel`/sequential function chunking, worker/parent output
  buffering, or function-plan memory growth) before changing worker policy,
  memory budgets, output behavior, tail stubs, rand fallback, or backend
  semantics.

- 2026-07-02 UPDATE: post-0k-CU generated-stage transaction remeasurement now
  has an executable classifier gate instead of a vague RSS tail. The updated
  `scripts/generated_stage_execution_transaction_report.sh` recognizes
  `b4.classification=llvm_entry_failure_after_lower_main` with joined runtime
  rows and resource kills as `final_classification=abort_resource_after_lower_main`.
  Fresh evidence:
  `STAGE1_COMPILER=/tmp/adamas_postcu_stage1 TAIL_LINES=30 REQUIRE_JOINED=1 REQUIRE_POST_CU_RESOURCE=1 scripts/generated_stage_execution_transaction_report.sh`
  exits 0 with `join_status=joined`, `resource.default_memory_kill=1`,
  `resource.workers1_memory_kill=1`, `resource.workers1_exit139=0`,
  `output.commit_record=llvm_ir_started_without_commit:file`, and
  `tail.semantic_vs_input_split=tail_not_reached_after_output_start`. This still
  rejects behavior admission: the next production slice must name a
  `PhaseAuthority` / `GeneratedStageExecution` owner edge for the
  post-`lower_main` resource corridor before changing memory budgets, worker
  policy, rand fallback, output behavior, tail stubs, or backend emission.

- 2026-07-02 UPDATE: implemented Slice 0k-CU, the assigned-tail
  `BlockCallReturnContract` behavior slice admitted by the Current Execution
  Board. The HIR wrapper materialization path now records a return contract only
  for untyped block helpers proven to be assigned-tail yield-passthrough
  (`result = yield; ...; result`) and only for non-nil/non-void block-return
  callsites; ordinary untyped block helpers remain un-specialized by return
  shape. New focused guard:
  `regression_tests/block_call_return_contract_assigned_tail_no_prelude.sh`.
  Fresh evidence: `crystal build src/adamas.cr -o /tmp/adamas_0kcu_stage1
  --error-trace` succeeded; the focused guard passed;
  `REQUIRE_CURRENT_CU_CONTRACT=1 scripts/hir_block_return_shape_census.sh`
  reports `classification=current_0k_cu_block_call_return_contract_applied`,
  `candidate_multi_shape_keys=207`,
  `candidate_additional_return_shape_bodies=224`,
  `assigned_tail_multi_shape_keys=0`,
  `timed_cp_phase_keys=5`,
  `timed_cp_phase_nil_value_coexist_keys=0`,
  `timed_cp_phase_assigned_tail_passthrough_keys=1`, and
  `timed_cp_phase_set_return_keys=1`. The generated-stage gate moved past the
  old O1 `affected_block_ids` / `Set(UInt32)#includes?` frontier:
  `STAGE1_COMPILER=/tmp/adamas_0kcu_stage1 REQUIRE_CURRENT_O1=1
  scripts/mir_optimization_container_frontier_classifier.sh` exits at the
  expected "not current O1" boundary with
  `b4_classification=llvm_entry_failure_after_lower_main` and
  `workers1_exit139=0`. A kept B4 classifier run shows both default and
  workers=1 modes reach `pass3 after lower_main call` and then RSS-kill around
  4.3-4.5GB; default still has the parallel `Invalid bound for rand: 0`
  fallback. Full regression suites pass `152/152 + 36/36`. This is a frontier
  move, not green `s2b`/`s3b`; the breakglass lane is consumed and the next
  movement must return to the Current Execution Board rather than continue from
  the new memory/resource symptom.

- 2026-07-02 UPDATE: implemented the Slice 0k-DH materialization scope-entry
  contract. The instance materialization path now applies the target
  type-param map and namespace override as an explicit scope-entry block owned by
  the existing `CallMaterializationTransaction` / `SemanticStateScope` boundary,
  instead of hiding that edge inside nested helper blocks. The temp-source
  classifier was updated to instrument that explicit shape. Fresh evidence from
  `STAGE1_COMPILER=/tmp/adamas_scope_entry_stage1 REQUIRE_REACHED=1 SAMPLES=8 scripts/generated_stage_lower_method_terminal_classifier.sh`
  reports `completion_classifier_classification=reached_tx_and_emit`,
  `method_call_rows=266`, `precall_rows=1330`, `method_entry_rows=356`,
  `method_name_rows=310`, `method_exit_rows=666`, `residual_rows=3`,
  `terminal_cause_kinds=1`, `terminal_groups=2`, and
  `selected_cause=lower_method_terminal_abstract_method` with `selected_rows=3`
  / `classification=eligible_lower_method_terminal_edge`. The previous six-row
  `lower_method_terminal_no_exact_after_tx_no_call` bucket is gone; residual rows
  now traverse `after_tx -> inside_type_params -> inside_namespace ->
  before_arity -> after_arity -> [MAT_METHOD_CALL]` and terminate as abstract
  methods. This completes the focused 0k-DH DoD but does not claim green
  `s2b`/`s3b`. The next movement must return to the Current Execution Board and
  remeasure the bootstrap pressure gate before selecting another owner edge.

- 2026-07-02 UPDATE: post-0k-DI remeasurement re-admits the B4/O1
  `bootstrap-emergency-with-ledger` lane as the next production slice, but only
  through the existing 0k-CU `BlockCallReturnContract` receipt. Fresh
  `REQUIRE_CURRENT_CP_BROAD=1 scripts/hir_block_return_shape_census.sh` still
  reports the broad rejected space (`candidate_multi_shape_keys=208`,
  `candidate_additional_return_shape_bodies=228`) and the root-sized
  assigned-tail discriminator (`assigned_tail_multi_shape_keys=1`,
  `assigned_tail_additional_return_shape_bodies=4`,
  `timed_cp_phase_assigned_tail_passthrough_keys=1`). The admitted source edit
  must make only assigned-tail yield-passthrough block wrappers return-shape
  dependent, keep nil/non-returning timed phases and ordinary iterator/scope
  helpers un-specialized, and run the O1/B4 gates before any bootstrap claim.

- 2026-07-02 UPDATE: added Slice 0k-DH, a compact pre-code receipt in
  `docs/compiler_architecture_sdd.md` for the `after_tx -> inside_type_params`
  boundary selected by 0k-DG. The selected old authority edge is now explicit:
  after `CallMaterializationTransaction` logging, body-lowering scope entry is
  still implicit in nested block helpers (`with_isolated_type_param_map` /
  `with_namespace_override_or_clear`). The admitted next production movement is
  a `contract-owner-migration` that makes existing
  `CallMaterializationTransaction` plus `SemanticStateScope` own that
  scope-entry contract, preserving generated-stage `[MAT_EMIT]` reachability
  and the abstract-method controls. If that cannot remove or root-size the
  `after_tx_no_call` class, this `MaterializationTransaction` row must return
  to the Current Execution Board instead of spawning another generic pre-call
  marker.

- 2026-07-02 UPDATE: refined the classifier as Slice 0k-DG with temp-only
  `[MAT_PRECALL]` checkpoints around the exact pre-call region between
  transaction logging and `lower_method`: `after_tx`, `inside_type_params`,
  `inside_namespace`, `before_arity`, and `after_arity`. Fresh evidence from
  `REQUIRE_REACHED=1 SAMPLES=8 scripts/generated_stage_lower_method_terminal_classifier.sh`
  still reaches backend emission and reports `method_call_rows=242`,
  `precall_rows=1628`, `method_entry_rows=338`, `method_name_rows=285`,
  `method_exit_rows=623`, `residual_rows=14`, `terminal_cause_kinds=4`,
  `terminal_groups=12`, and `terminal_root_sized_groups=12`. The selected broad
  bucket is now `lower_method_terminal_no_exact_after_tx_no_call` (6 rows).
  Samples for `Array(String)#<<`, `Slice(UInt8)#+`, `Atomic(Bool)#get`,
  `Slice(UInt8)#to_unsafe`, `Slice(UInt8)#index`, and `Slice(UInt8)#[]` show
  repeated `after_tx` rows but no `inside_type_params`, while abstract controls
  such as `IO#read` and `String::Builder#write` traverse
  `after_tx -> inside_type_params -> inside_namespace -> before_arity ->
  after_arity` and join to call rows. This refutes namespace override and arity
  repair as the first boundary for the selected six rows and makes the
  remaining gap the scoped type-param/block-yield boundary immediately after
  transaction logging. No behavior patch is admitted. The next movement must
  stop adding local pre-call markers unless it names that owner edge directly:
  write a pre-code receipt for a `MaterializationTransaction` /
  scoped-type-param-isolation or block-yield contract, or refute this
  materialization row and return to the Current Execution Board.

- 2026-07-02 UPDATE: refined the classifier again as Slice 0k-DF with a
  temp-only `[MAT_METHOD_CALL]` probe at the `instance_class_info_lower_method`
  call site. Fresh evidence from
  `REQUIRE_REACHED=1 SAMPLES=8 scripts/generated_stage_lower_method_terminal_classifier.sh`
  still reaches backend emission and reports `method_call_rows=242`,
  `method_entry_rows=338`, `method_name_rows=285`, `method_exit_rows=623`,
  `residual_rows=14`, `terminal_cause_kinds=4`, `terminal_groups=12`, and
  `terminal_root_sized_groups=12`. The broad bucket is now
  `lower_method_terminal_no_exact_no_call` (6 rows): every sampled row has
  `call_body_rows=0` and `call_requested_rows=0`, while abstract controls such
  as `IO#read` and `String::Builder#write` have matching call rows. This proves
  the coarse producer path can log `[MAT_TX]` and `[MAT_DONE]` as
  `instance_class_info_lower_method` without reaching the actual `lower_method`
  call for those six exact symbols. No behavior patch is admitted. The next
  movement must split the gap between transaction logging and the
  `lower_method` call: type-param isolation, namespace override, arity fallback,
  or another pre-call control edge.

- 2026-07-02 UPDATE: refined Slice 0k-DD with the 0k-DE no-exact splitter.
  `scripts/generated_stage_lower_method_terminal_classifier.sh` now logs
  temp-only `[MAT_METHOD_ENTRY]`, `[MAT_METHOD_NAME]`, and final
  `completed_method` rows in the copied source, so `created_hir_function` is
  no longer treated as a terminal completion. Fresh evidence from
  `REQUIRE_REACHED=1 SAMPLES=8 scripts/generated_stage_lower_method_terminal_classifier.sh`
  reports `completion_classifier_classification=reached_tx_and_emit`,
  `method_entry_rows=338`, `method_name_rows=285`, `method_exit_rows=623`,
  `residual_rows=14`, `terminal_cause_kinds=4`, `terminal_groups=12`, and
  `terminal_root_sized_groups=12`. Buckets are
  `lower_method_terminal_no_exact_no_entry` (6 rows),
  `lower_method_terminal_abstract_method` (4 rows),
  `lower_method_terminal_no_exact_matching_full_name_without_exit` (3 rows),
  and `lower_method_terminal_completed_method` (1 row). This refutes the
  earlier proxy framing that `created_hir_function` was a terminal state and
  proves the broadest remaining class is exact/base lower_method non-entry, not
  just terminal-join ambiguity. No behavior patch is admitted. The next
  movement must split `no_exact_no_entry` by actual lower_method call input,
  selected DefNode/source owner, and requested/target/body symbol relation.

- 2026-07-02 UPDATE: added Slice 0k-DD, the temp-source `lower_method`
  terminal classifier required by 0k-DC. New script:
  `scripts/generated_stage_lower_method_terminal_classifier.sh`. It copies
  `src/`, injects default-off `[MAT_METHOD_EXIT]` probes only into the
  temporary `ast_to_hir.cr`, uses current stage1 to compile that temp source
  into a generated probe `s2`, then runs the existing created-body completion
  classifier with `GENERATED_S2=<probe>`. Tracked production compiler source is
  not edited and no `lower_method` signature/ABI trace object is introduced.
  Fresh evidence from
  `REQUIRE_REACHED=1 SAMPLES=8 scripts/generated_stage_lower_method_terminal_classifier.sh`
  reports `completion_classifier_classification=reached_tx_and_emit`,
  `method_exit_rows=338`, `residual_rows=14`, `terminal_cause_kinds=3`,
  `terminal_groups=9`, and `terminal_root_sized_groups=9`. The current
  terminal buckets are `lower_method_terminal_no_exact_method_exit` (9 rows),
  `lower_method_terminal_abstract_method` (4 rows), and
  `lower_method_terminal_created_hir_function` (1 row). The classifier result
  is `rejected_mixed_lower_method_terminals`, so no behavior patch is admitted.
  The next movement must choose one of these terminal classes, preferably the
  broad `no_exact_method_exit` class, and split it by self-host-safe source
  identity / resolved DefNode / full-name derivation. Do not patch sampled
  Array/Slice/Atomic/IO/String::Builder/Int32 methods directly, and do not
  reintroduce production `lower_method` trace-object plumbing.

- 2026-07-02 UPDATE: added Slice 0k-DC, the producer-path split required by
  0k-DB while keeping `[MAT_DONE]` as the authority. `[MAT_DONE]` now records
  `producer_path`, `created_symbol_relation`, and capped `created_symbols`;
  `scripts/generated_stage_created_body_visibility_classifier.sh` classifies
  those fields. Fresh evidence from
  `STAGE1_COMPILER=/tmp/adamas_producer_path_stage1 SAMPLES=8 scripts/generated_stage_created_body_visibility_classifier.sh`
  reports `classifier_classification=reached_tx_and_emit`,
  `mat_tx_rows=717`, `mat_done_rows=787`, `mat_emit_rows=173`,
  `created_body_missing_completion_rows=14`,
  `completion_cause_kinds=1`,
  `selected_cause=attempt_lowering_returned_no_hir_function__producer_instance_class_info_lower_method__created_none`,
  `selected_rows=14`, `classification=rejected_completion_class_too_wide`,
  9 root-sized groups, and zero malformed/unjoined rows. This refutes the
  outer materialization branch as the discriminator: every residual enters the
  instance/class-info `lower_method` path and creates no HIR function at all.
  A deeper optional `lower_method` trace object was also preflight-refuted:
  produced-stage runs regressed to `tx_only_no_emit` with `mat_emit_rows=0`,
  so it was reverted. The next movement must split this exact
  `instance_class_info_lower_method` / `created_none` class using a
  self-host-safe producer observation, most likely via a temp-source classifier
  or another generated-stage-safe field, and must stop again if the class stays
  broad. Do not add a `lower_method` trace object, backend rescue, forwarder,
  sampled method patch, broad rendering policy, ambient-map policy, or
  `BlockOwner` rollback.

- 2026-07-02 UPDATE: added Slice 0k-DB, the terminal-status refinement of the
  post-lowering completion fact from 0k-DA. The implementation deliberately
  keeps the new terminal evidence inside the existing default-off `[MAT_DONE]`
  row (`status`, `reason`, `created_function_count`) and updates
  `scripts/generated_stage_created_body_visibility_classifier.sh` to classify
  those fields. Fresh evidence from
  `STAGE1_COMPILER=/tmp/adamas_mat_done_terminal_stage1 SAMPLES=8 scripts/generated_stage_created_body_visibility_classifier.sh`
  reports `classifier_classification=reached_tx_and_emit`,
  `mat_tx_rows=735`, `mat_done_rows=805`, `mat_emit_rows=173`,
  `created_body_missing_completion_rows=14`,
  `completion_cause_kinds=1`,
  `selected_cause=attempt_lowering_returned_no_hir_function`,
  `selected_rows=14`, `classification=rejected_completion_class_too_wide`,
  9 completion groups, and no malformed/unjoined rows. This preserves the
  generated-stage backend path while proving the residual terminal class is
  still broad. A separate `MaterializationAttemptResult` storage/log surface
  and a HIR-to-MIR consumer ledger were explicitly refuted during preflight:
  generated-stage runs stopped before backend emission with `mat_emit_rows=0`
  / tx-only evidence. The next movement must not add another consumer/result
  layer by inertia. It must split `attempt_lowering_returned_no_hir_function`
  at the producer boundary that returns from lowering without registering the
  exact materialized HIR function, or return to the Current Execution Board if
  that class cannot be narrowed.

- 2026-07-02 UPDATE: added Slice 0k-DA, the executable post-lowering
  completion fact required by 0k-CZ. `src/compiler/hir/ast_to_hir.cr` now emits
  default-off `[MAT_DONE]` rows under `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER`
  after a materialization attempt finishes, and
  `scripts/generated_stage_created_body_visibility_classifier.sh` consumes
  `[MAT_TX]` + `[MAT_DONE]` + `[MAT_EMIT]` as a completion classifier. Fresh
  evidence from
  `STAGE1_COMPILER=/tmp/adamas_mat_done_stage1 SAMPLES=8 scripts/generated_stage_created_body_visibility_classifier.sh`
  reports `classifier_classification=reached_tx_and_emit`,
  `mat_tx_rows=724`, `mat_done_rows=794`,
  `created_body_missing_completion_rows=14`,
  `completion_cause_kinds=1`,
  `selected_cause=lowering_completed_without_hir_function`,
  `selected_rows=14`, `classification=rejected_completion_class_too_wide`,
  9 completion groups, `missing_completion_rows=0`, and no malformed or
  unjoined ledger rows. This refutes the weakest 0k-CZ possibility
  (`missing_completion_fact`) and confirms the residual is post-lowering, but
  it is still broad and not a behavior license. The next movement must not add
  another report-only layer; it must introduce a behavior-neutral
  `MaterializationAttemptResult` / terminal-status owner for the lowering
  attempt, so the broad `lowering_completed_without_hir_function` class can be
  split by named terminal reason before any consumer or behavior patch.

- 2026-07-02 UPDATE: added Slice 0k-CZ, a docs-only hostile
  correction to the 0k-CY interpretation. Fresh source inspection shows the
  0k-CY `[MAT_TX]` body visibility facts are recorded after
  `@function_lowering_states[materialized_name] = InProgress` but before
  `lower_method(...)` creates or completes the body, and the `ensure` block
  updates/deletes the state only after lowering completes. Therefore
  `state_in_progress_without_hir_function` is a pre-lowering visibility fact,
  not a proven root cause. 0k-CY remains valid only as a refutation of
  `materialization_action=created_body` as body-present evidence. The active
  next executable slice remains read-only/behavior-neutral, but it must now be
  a post-lowering `FunctionAvailabilityContract` completion ledger: join
  `[MAT_TX]` / `[MAT_EMIT]` with a completion fact emitted after the
  materialization attempt finishes, then classify whether the body is absent
  after completion, present in HIR but missing in MIR/backend visibility, or
  only unobserved because completion facts are missing. Stop if the selected
  class remains broad. Do not patch backend lookup/emission, undefined externs,
  forwarders, requested-name policy, sampled methods, `NamedTuple`/`Tuple`
  rendering, ambient-map policy, or `BlockOwner`.

- 2026-07-02 UPDATE: added Slice 0k-CY, extending the self-applying
  materialization ledger and adding
  `scripts/generated_stage_created_body_visibility_classifier.sh`. Fresh
  current-source stage1 evidence:
  `crystal build src/adamas.cr -o /tmp/adamas_visibility_ledger_stage1 --error-trace`
  succeeded, and
  `STAGE1_COMPILER=/tmp/adamas_visibility_ledger_stage1 SAMPLES=8 scripts/generated_stage_created_body_visibility_classifier.sh`
  reports `classifier_classification=reached_tx_and_emit`,
  `created_body_missing_visibility_rows=14`, `visibility_cause_kinds=1`,
  `selected_cause=state_in_progress_without_hir_function`, `selected_rows=14`,
  `classification=rejected_visibility_class_too_wide`, 9 visibility groups,
  and `missing_visibility_field_rows=0`. This corrects the 0k-CX
  interpretation: `materialization_action=created_body` is only an in-progress
  lowering-state label for this residual, not proof that a HIR body exists.
  Residual samples report `body_function_present=0`, `body_has_body=0`,
  `body_state=in_progress`, and backend `lookup/module/plan/emitted` visibility
  all zero. The next executable slice must be read-only and split why exact
  `body_symbol` rows can have `function_state=InProgress` while
  `@module.has_function?=false`: state set before `create_function`, symbol-key
  mismatch, early return/reentrant defer, or another named state transition.
  Stop if the selected class stays broad; do not patch backend lookup/emission
  or sampled methods.

- 2026-07-02 UPDATE: added Slice 0k-CX and
  `scripts/generated_stage_exact_body_availability_classifier.sh`, a read-only
  exact-body lifecycle classifier for the 0k-CW residual. Fresh current-source
  stage1 evidence:
  `crystal build src/adamas.cr -o /tmp/adamas_exact_body_classifier_stage1 --error-trace`
  succeeded, and
  `STAGE1_COMPILER=/tmp/adamas_exact_body_classifier_stage1 SAMPLES=8 scripts/generated_stage_exact_body_availability_classifier.sh`
  reports `classifier_classification=reached_tx_and_emit`,
  `residual_exact_missing_body_rows=14`,
  `residual_body_lifecycle_cause_kinds=1`,
  `selected_cause=created_body_backend_missing`, `selected_rows=14`,
  `classification=rejected_body_lifecycle_class_too_wide`, and 9 lifecycle
  groups. The result refutes "HIR materializer never created the bodies" for
  this residual: self-applying `[MAT_TX]` rows already record
  `materialization_action=created_body`. The class is still broad, so no
  behavior patch is admitted. The next executable slice must split
  `created_body_backend_missing` by the next self-applying boundary: HIR body
  still present after materialization, HIR/RTA prune before MIR, MIR function
  missing, backend lookup/emitted-set miss, or legitimate extern/runtime helper.
  Stop if that class remains broad; do not patch sampled
  Array/Slice/IO/Atomic/String::Builder/Int32 methods directly.

- 2026-07-02 UPDATE: added Slice 0k-CW, the architecture-burn-down owner-spine
  selection required by 0k-CV. Fresh source-shape evidence rejects reselection
  of already-promoted seams:
  `SOURCE_SHAPE_ONLY=1 scripts/semantic_state_scope_admission_report.sh`
  reports `state_model_redesign_complete=1`,
  `scripts/materialization_symbol_binding_admission_report.sh` reports
  `already_promoted_shadow`, and
  `scripts/call_materialization_transaction_admission_report.sh` reports the
  main transaction seam `already_promoted_shadow`. Fresh generated-stage
  transaction evidence from
  `scripts/generated_stage_transaction_edge_selection_report.sh` reports
  `post_consumer_state=selected_consumed_by_contract_consumer`,
  `contract_mismatch_rows=0`, `residual_exact_missing_body_rows=14`,
  `residual_exact_missing_body_groups=9`, and
  `residual_selection_status=rejected_exact_missing_body_ambiguous`. The
  selected next architecture lane is therefore `MaterializationTransaction` /
  exact body availability, not B4 crash-stack pursuit and not the paused 0k-CU
  helper WIP. The next executable slice should be read-only: add or extend a
  `FunctionAvailabilityContract` / exact-missing-body classifier that splits
  those all-equal missing-body rows by producer cause (HIR body absent, HIR body
  present but not lowered to MIR, MIR function absent, backend emitted-set miss,
  or legitimate extern/runtime helper). Stop if the class stays broad or
  ambiguous; do not patch Array/Slice/IO/Atomic/String::Builder/Int32 samples
  directly.

- 2026-07-02 UPDATE: added Slice 0k-CV, an architecture-pause checkpoint after
  reviewing and removing the unfinished local 0k-CU `ast_to_hir.cr` WIP. The
  WIP was not completion evidence: it started adding a HIR
  `BlockCallReturnContract` helper but had not threaded the callsite
  `block_return_name` fact through the materialization callsites, had not run
  generated-stage evidence, and had not satisfied the 0k-CU architecture DoD.
  Production source is paused again. The breakglass B4/O1 lane remains
  documented but is no longer the automatic next movement and must not resume
  from uncommitted helper code by inertia. The active next movement is
  architecture burn-down: select one durable owner spine plus one
  producer-to-consumer authority edge, retire or refute a stale report surface,
  or promote a missing contract falsifier from
  `docs/specs/05-falsifier-matrix.md`. A fresh crash-stack classifier,
  classifier-only patch, local helper around the current failing value, or
  source-shape-only green row is not a valid next step unless a new receipt
  proves how it moves the actual path to green `s2b`/`s3b`.

- 2026-07-02 UPDATE: added Slice 0k-CU, the pre-code `SliceReceipt` required
  by 0k-CT for the only currently admitted breakglass production lane. Fresh
  baseline evidence still matches the assumptions:
  `REQUIRE_CURRENT_CP_BROAD=1 scripts/hir_block_return_shape_census.sh`
  reports the broad rejected shape scope (`candidate_multi_shape_keys=208`,
  `candidate_nil_value_coexist_keys=206`,
  `candidate_additional_return_shape_bodies=228`) and the root-sized
  assigned-tail discriminator (`assigned_tail_multi_shape_keys=1`,
  `assigned_tail_additional_return_shape_bodies=4`,
  `timed_cp_phase_assigned_tail_passthrough_keys=1`). Fresh
  `REQUIRE_CURRENT_O1=1 scripts/mir_optimization_container_frontier_classifier.sh`
  preserves B4/O1 pressure with
  `b4_classification=current_0k_bn_frontier`,
  `classification=current_0k_ck_mir_cp_container_frontier`, and
  `bad_container_candidate=affected_block_ids`. The next source movement, if
  taken, is CAUTION-tier and must implement the full HIR
  `BlockCallReturnContract` receipt for assigned-tail yield-passthrough helpers:
  classify the helper, key/materialize wrappers by non-nil block-return shape
  only inside that contract, keep nil/non-returning and ordinary iterator/scope
  helpers as negative controls, and run generated-stage evidence. If the slice
  widens, fails, or lands, return to the Current Execution Board before
  selecting any new crash-stack classifier or local fix.

- 2026-07-02 UPDATE: added Slice 0k-CT, a docs-only active-board compression
  checkpoint after hostile review of the post-0k-CS route. Production compiler
  source remains paused. The SDD now has an operator-facing
  `Current Execution Board` that must be cited before any non-doc source slice.
  The 0k-CR assigned-tail passthrough + return-shape wrapper-materialization
  slice remains allowed only as `breakglass bootstrap-emergency-with-ledger`,
  and only after a pre-code `SliceReceipt` names the old authority edge, owner
  fact, producers, consumers, measured-red baseline, generated-stage gate,
  negative controls, rejected shortcuts, and residual boundary. If that receipt
  cannot stay root-sized, the next movement is architecture burn-down: select a
  durable owner spine, retire/refute a stale report surface, or promote a
  missing contract falsifier. A new crash-stack classifier or local fix is not
  a valid next step from 0k-CT alone.

- 2026-07-02 UPDATE: added Slice 0k-CS, a docs-only architecture-board
  consolidation after hostile review of the post-0k-CR route. It does not
  retract 0k-CR, but it prevents the B4/O1 emergency lane from becoming the
  default development loop. One paired behavior slice remains admitted as
  `bootstrap-emergency-with-ledger`: assigned-tail yield-passthrough
  classification plus return-shape-specific wrapper materialization for the
  narrowed helper set. After that slice, or if it widens beyond the root-sized
  assigned-tail class, production code must return to the Active Architecture
  Board before selecting any new crash-stack classifier or local fix. The next
  non-emergency movement must select a durable owner spine, retire/refute a
  stale report surface, or promote a missing contract falsifier from
  `docs/specs/05-falsifier-matrix.md`.

- 2026-07-02 UPDATE: implemented Slice 0k-CR by extending
  `scripts/hir_block_return_shape_census.sh` with an assigned-tail
  yield-passthrough discriminator (`result = yield; ...; result`). Strict
  current evidence from
  `REQUIRE_CURRENT_CP_BROAD=1 scripts/hir_block_return_shape_census.sh` still
  reports the broad 0k-CQ classification for naive `contains_yield` scope, but
  adds root-sized discriminator rows:
  `assigned_tail_multi_shape_keys=1`,
  `assigned_tail_nil_value_coexist_keys=1`,
  `assigned_tail_additional_return_shape_bodies=4`, and
  `timed_cp_phase_assigned_tail_passthrough_keys=1`. This admits a future
  behavior slice only as a paired owner-contract migration: classify
  assigned-tail yield passthrough and use that fact to materialize
  return-shape-specific wrappers for the narrowed helper set. A
  classification-only patch remains rejected if the wrapper body can still be
  lowered with `yield : Void`.

- 2026-07-02 UPDATE: implemented Slice 0k-CQ, the read-only return-shape census
  required by 0k-CP. New script:
  `scripts/hir_block_return_shape_census.sh`. It copies `src/` to `tmp`,
  injects probes only into the temporary `ast_to_hir.cr`, builds a temporary
  probe compiler, runs it under `scripts/run_safe.sh`, and removes all temp
  artifacts unless `KEEP_TMP=1`. Current evidence:
  `classification=current_0k_cp_hir_block_return_shape_broad`,
  `candidate_multi_shape_keys=208`,
  `candidate_nil_value_coexist_keys=206`, and
  `candidate_additional_return_shape_bodies=228`. The current
  `timed_cp_phase$String_block` row is still present and observes nil plus
  `Int32` / `Set(UInt32)` / `Nil | DominanceInfo` /
  `Hash(UInt32, Int32)` shapes, but it is not unique enough to admit naive
  block-return-shape specialization for all untyped `&` helpers. This refutes
  the broad 0k-CP fix shape and keeps production source movement paused. The
  next admitted movement is another read-only discriminator: classify true
  return-demanded yield-passthrough helpers (`result = yield; ...; result`,
  tail yield, or equivalent) versus ordinary iteration/scope helpers that
  merely observe varied block returns while ignoring them as method return.

- 2026-07-02 UPDATE: added Slice 0k-CP, a docs-only pre-code design gate after
  0k-CO. Production compiler edits remain paused. The selected direction is a
  HIR-owned `BlockCallReturnContract` / block-call materialization shape: for
  untyped `&` helpers that can return `yield`, the callsite block-return fact
  must become part of the wrapper identity instead of a late ambient fallback
  on one shared wrapper name. This is not a behavior fix and not green
  `s2b`/`s3b`. The immediate next admitted movement is a read-only
  return-shape census that counts shared wrappers with multiple observed
  block-return shapes, distinguishes nil/non-returning callsites from
  value-returning callsites, and proves whether `(callee shape, arg shape,
  block-return shape)` specialization is root-sized enough for a bounded
  production slice. Still rejected: CopyPropagation null guards,
  `timed_cp_phase` annotation/inlining/deletion, MIR/LLVM/backend block-return
  rescue, Set/Hash rescue, output/resource/tail/worker fixes, broad
  normalization, and `BlockOwner` rollback.

- 2026-07-02 UPDATE: implemented Slice 0k-CO, the read-only HIR producer-order
  classifier selected by 0k-CN. New script:
  `scripts/mir_timed_phase_hir_producer_order_classifier.sh`. It copies `src/`
  to `tmp`, injects probes only into the temporary copy, builds a temporary
  probe compiler, runs it under `scripts/run_safe.sh`, and removes all temp
  artifacts unless `KEEP_TMP=1`. Strict mode
  `REQUIRE_CURRENT_CO=1 scripts/mir_timed_phase_hir_producer_order_classifier.sh`
  reports
  `classification=current_0k_co_hir_timed_phase_shared_wrapper_order_frontier`.
  Current evidence: `first_fallback_nil_line=108`,
  `first_set_record_line=117`, `early_void_before_set=1`,
  `set_recorded_later=1`, and `set_yield_return_not_classified=1`. The first
  materialization of the shared `timed_cp_phase$String_block` wrapper happens
  at an earlier callsite whose block return is `nil`; `infer_yield_fallback`
  sees `block_ret=nil`, `candidate=Void`, and returns `nil`, so `lower_yield`
  emits `yield : Void`. The later `apply_collect_affected_blocks` callsite
  correctly discovers and records `block_return=Set(UInt32)`, but the same
  shared wrapper is already void-yielded and `yield_return_function_for_block_call?`
  reports `result=0`. This is still not a fix and not green `s2b`/`s3b`; the
  next admitted movement is a pre-code fix design for callsite block-return
  specialization / wrapper materialization ownership, not a local
  CopyPropagation or backend rescue.

- 2026-07-02 UPDATE: implemented Slice 0k-CN, the read-only
  compiler-source seam classifier required by 0k-CM. New script:
  `scripts/mir_timed_phase_source_seam_classifier.sh`. Strict mode
  `REQUIRE_CURRENT_CN=1 scripts/mir_timed_phase_source_seam_classifier.sh`
  reports `classification=current_0k_cn_hir_timed_phase_source_seam`.
  Current evidence: `timed_wrapper_return_type=2698`,
  `wrapper_yield_void=1`, `collect_proc_return_type=1268`,
  `collect_block_builds_set=1`, `collect_block_proc_returns_set=1`,
  `apply_collect_call_type=2698`, `affected_block_ids_local_type=2698`,
  `apply_collect_result_nil_void=1`, and
  `call_differs_from_collect_proc=1`. This localizes the current
  `timed_cp_phase("apply_collect_affected_blocks")` return loss before
  HIR->MIR and LLVM backend handling: HIR already has a collect block proc
  returning `Set(UInt32)`, while the `timed_cp_phase$String_block` wrapper
  yields `Void` and the call/local are typed `Nil|Void`. This is still not a
  fix and not green `s2b`/`s3b`; the next admitted movement is a read-only
  HIR producer pin distinguishing `block_return_name` recording,
  `yield_return_function_for_block_call?`, `record_block_return_type_for_call`,
  and `infer_yield_return_type` fallback for untyped `&` helpers. Still
  rejected: production CopyPropagation guards, `timed_cp_phase` inlining or
  tactical return annotation, backend block-return rescue, Set/Hash rescue,
  and `BlockOwner` rollback.

- 2026-07-02 UPDATE: implemented Slice 0k-CM, the executable read-only
  producer-localization classifier after 0k-CL. New script:
  `scripts/mir_timed_phase_return_frontier_classifier.sh`. Strict mode
  `REQUIRE_CURRENT_CM=1 scripts/mir_timed_phase_return_frontier_classifier.sh`
  reuses the O1 classifier and reports
  `classification=current_0k_cm_timed_cp_phase_block_return_frontier`.
  Current evidence: `o1_classification=current_0k_ck_mir_cp_container_frontier`,
  `can_skip_affected_block_ids_x3_zero=1`, `timed_calls_block=1`,
  `timed_zeroes_after_block=1`, `timed_enabled_branch_returns_zero=1`,
  `apply_collect_uses_timed_phase=1`,
  `apply_collect_result_is_nil_void=1`, `collect_block_builds_set=1`, and
  `collect_block_returns_set_slot=1`. This refutes the Set/Hash constructor
  and `Set#includes?` body as first-bad for this frontier: the collect block
  builds and returns a `Set(UInt32)`, but produced `s2b` materializes
  `CopyPropagationPass#timed_cp_phase(String, &)` as a `String_block` wrapper
  that returns null/void instead of the block result. This is still not a fix
  and not green `s2b`/`s3b`; the next read-only question is the compiler-source
  seam that turns a bare `&` / `yield` helper into a void-return block wrapper.
  Still rejected: directly inlining or deleting `timed_cp_phase`, adding an
  explicit tactical return type without naming the lowering seam, `CopyPropagation`
  null guards, backend block-return rescue, backend Set/Hash rescue, and
  `BlockOwner` rollback.

- 2026-07-02 UPDATE: implemented Slice 0k-CL, the executable read-only O1
  classifier selected by 0k-CK. New script:
  `scripts/mir_optimization_container_frontier_classifier.sh`. Strict mode
  `REQUIRE_CURRENT_O1=1 scripts/mir_optimization_container_frontier_classifier.sh`
  reuses the B4 classifier, runs the workers=1 produced `s2b` path under
  `lldb`, and reports `classification=current_0k_ck_mir_cp_container_frontier`.
  Current evidence: `b4_classification=current_0k_bn_frontier`,
  `workers1_after_lower_main=1`, `workers1_exit139=1`,
  `has_set_uint32_includes=1`, `has_copyprop_affected=1`,
  `has_copyprop_can_skip=1`, `has_optimize_with_potential=1`,
  `register_x0_zero=1`, `register_x8_zero=1`, `set_load_from_x8=1`,
  `affected_method_includes_count=1`,
  `bad_container_state=set_receiver_base_register_null`, and
  `bad_container_candidate=affected_block_ids`. This is still not a fix and
  not green `s2b`/`s3b`; it narrows the next read-only question to the
  producer of the null `affected_block_ids` set returned by
  `apply_replacements`' `apply_collect_affected_blocks` timed block. Still
  rejected: direct `CopyPropagation` null guards, backend Set/Hash rescue,
  worker/resource/output/tail behavior, broad namespace/container
  normalization, physical extraction, and `BlockOwner` rollback.

- 2026-07-02 UPDATE: added Slice 0k-CK, a docs-only post-0k-CJ
  architecture pause after fresh B4 root-localization. Production compiler
  edits remain paused. Fresh
  `KEEP_TMP=1 STAGE1_COMPILER=bin/adamas TAIL_LINES=120
  REQUIRE_CURRENT_FRONTIER=1 scripts/generated_stage_llvm_entry_classifier.sh`
  preserves the current B4 shape (`default_workers` rand/RSS and
  `ADAMAS_LLVM_WORKERS=1` exit 139 after `pass3 after lower_main call`), but a
  fresh `lldb` workers=1 backtrace stops in `Set(UInt32)#includes?`, called by
  `Adamas::MIR::CopyPropagationPass#affected_blocks_use_only_local_replacements?`
  during `Function#optimize_with_potential`; registers show `x0=0` and `x8=0`
  at the `Set#includes?` null load. This lowers `BootstrapPotential` by
  decreasing plausible owner-spine ambiguity: the next root-sized question is
  not another `GeneratedStageExecutionOutcome`, worker/resource/output/tail, or
  LLVM emission edge. The admitted next movement is a read-only
  `MIROptimizationInvariant` / compiler-runtime-container root classifier that
  distinguishes malformed CopyPropagation local-replacement state from
  self-hosted `Set`/`Hash` constructor or namespace-initialization failure.
  Still rejected: direct `CopyPropagation` guard patches, backend Set/Hash
  rescue, LLVM worker/resource/output/tail behavior, memory-budget acceptance,
  broad container/namespace normalization, physical extraction, and
  `BlockOwner` rollback.

- 2026-07-02 UPDATE: implemented Slice 0k-CJ, the behavior-neutral
  `GeneratedStageExecutionOutcome` output-row checkpoint selected by 0k-CH and
  bounded by 0k-CI. `src/compiler/cli.cr` now owns one
  `GeneratedStageExecutionOutcome` per produced-compiler output corridor and
  serializes `output.llvm_ir_start`, `output.llvm_ir_written`, and
  `output.binary_compile_result` through outcome helper methods instead of
  direct scattered CLI row writes. New guard:
  `scripts/generated_stage_outcome_source_shape_guard.sh`; strict mode reports
  `source_shape=outcome_serializes_output_commit_rows` and zero direct output
  rows outside helpers. Verification kept the intended state: `crystal build`
  passes; `LLVMEmissionSession` guard passes; G6 `BlockOwner` guard reports
  `body_present_rows=7`, `real_defs=1`, `stub_defs=0`; B4/L6 joined report
  still reports `b4.classification=current_0k_bn_frontier`,
  `final_classification=abort_resource`, `join_status=joined`, and
  `admission_status=rejected_no_root_sized_consumer`; full regression suites
  pass `152/152 + 36/36`. This checkpoint only decreases
  `BootstrapPotential`'s last component, so the next source movement is still
  barred unless it decreases B4/L6 phase, owner-spine ambiguity, or live proxy
  surfaces, or declares an explicit `bootstrap-emergency-with-ledger` behavior
  slice.

- 2026-07-02 UPDATE: added Slice 0k-CI, a docs-only
  anti-proxy bootstrap-potential gate after hostile review of the repeated
  behavior-neutral owner/guard pattern. Production compiler edits remain paused
  except for resolving the already-selected 0k-CH
  `cli.output_commit_record` implementation candidate as a checkpoint or
  reverting it. Before any later source movement, write
  `BootstrapPotential = (B4/L6 phase, plausible owner-spine count, live
  proxy-surface count, unmigrated authority-edge count)` and name which
  component decreases. Reducing only the last component while B4/L6,
  owner-spine ambiguity, and live proxy surfaces stay unchanged is now
  bookkeeping, not bootstrap progress. The next movement after the current
  candidate must be SDD redesign, owner-spine refutation, direct root
  localization, or an explicitly bounded `bootstrap-emergency-with-ledger`
  behavior slice; not another automatic behavior-neutral
  `GeneratedStageExecution` edge.

- 2026-07-02 UPDATE: added Slice 0k-CH, the docs-only
  `GeneratedStageExecutionOutcome` pre-code plan requested by 0k-CG. Production
  compiler edits remain paused. The selected B4/L6 edge is now
  `cli.output_commit_record`: `src/compiler/cli.cr` currently emits
  `output.llvm_ir_start`, `output.llvm_ir_written`, and
  `output.binary_compile_result` rows directly, while
  `scripts/generated_stage_execution_transaction_report.sh` reconstructs
  `output.commit_record` and final classification from those phase-local rows.
  The next admitted source slice is a behavior-neutral
  `contract-owner-migration`: introduce a code-owned
  `GeneratedStageExecutionOutcome` helper/record with one produced-compiler
  invocation lifetime, make the CLI output row producer serialize from it, keep
  existing `GSETX` row format and B4/L6 measured-red state, and add a
  source-shape guard proving the direct scattered row writes are no longer the
  authority. Still rejected: worker/resource/tail/backend behavior, output
  semantics, side-effect semantics, memory-budget acceptance, materialization,
  parser behavior, broad `NamedTuple`/`Tuple` rendering, global ambient-map
  changes, physical extraction, and `BlockOwner` rollback.

- 2026-07-02 UPDATE: added Slice 0k-CG, a docs-only
  `GeneratedStageExecution` planning reset after the G6 availability guard.
  Production compiler edits remain paused. The phrase "select a root-sized
  consumer edge" is now constrained: the next movement may not be another
  selector/report that chooses among worker, resource, output, tail, backend, or
  crash-marker symptoms. It must first write a pre-code
  `GeneratedStageExecutionOutcome` / phase-outcome authority plan under
  `PhaseAuthority`: selected B4/L6 row, `contract-owner-migration` tranche, old
  authority edge, owner fact/service and lifetime, producer/consumer inventory,
  measured-red baseline, focused DoD, generated-stage gate, and residual
  boundary. If no root-sized code-owned edge can be named, stop and refute this
  boundary or route to another owner spine. Still rejected: worker forcing,
  memory-limit acceptance, output/tail/backend fixes, side-effect semantic
  changes, materialization behavior, parser behavior, broad `NamedTuple`/`Tuple`
  rendering, global ambient-map changes, physical extraction, and `BlockOwner`
  rollback.

- 2026-07-02 UPDATE: added Slice 0k-CF, an executable G6
  `MaterializationTransaction` availability guard:
  `scripts/block_owner_materialization_transaction_availability_report.sh
  bin/adamas` reports `tx_rows=1`, `joined_emit_rows=7`,
  `body_present_rows=7`, `real_defs=1`, and `stub_defs=0`. The older G6
  repro also passes. This proves the current `Hash(UInt64, BlockOwner)#[]=`
  lane is transaction-joined and body-present for the current stage1 compiler;
  it does not claim green `s2b`/`s3b`. Fresh pressure gates still report
  `b4.classification=current_0k_bn_frontier`, `join_status=joined`, and
  `admission_status=rejected_no_root_sized_consumer`. Next work therefore moves
  back to `GeneratedStageExecution` root-sized consumer selection, not another
  G6/materialization behavior patch unless the new guard regresses. Slice 0k-CG
  above tightens that route: selection must first become a pre-code
  phase-outcome owner-edge plan, not another standalone report.

- 2026-07-02 UPDATE: added Slice 0k-CE, the G6 pre-code
  `MaterializationTransaction` plan. Production source is still paused. The
  plan pins the actual setter producer path (`lower_assign` index target ->
  `resolve_method_call(..., "[]=")` -> `remember_callsite_arg_types` ->
  `lower_function_if_needed` -> `Call.with_receiver`), the materialization
  binding path (`materialized_name` body checks plus `CallMaterializationTransaction`
  override/body/call symbols), the HIR transaction contract keyed by call
  symbol, and the MIR/backend consumers that attach contract facts to
  `Call`/`ExternCall` and later decide body visibility. The next code slice is
  therefore not "make the grep green"; it must add a transaction-owned
  availability proof for the demanded `Hash(UInt64, BlockOwner)#[]=` setter
  before changing emitted behavior. Stop if the candidate set is broad, if the
  demand is not transaction-bound, or if the only proposed fix is backend
  rescue/forwarding, requested-name forcing, broad `NamedTuple`/`Tuple`
  rendering, global ambient-map policy change, parser work, or `BlockOwner`
  rollback.

- 2026-07-02 UPDATE: added Slice 0k-CD, a docs-only hostile review checkpoint
  that pauses production code before the G6 implementation. G6 remains the
  selected `MaterializationTransaction` lane, but the next movement is now a
  pre-code plan gate, not an `ast_to_hir.cr` patch. That gate must name the old
  authority edge, the owner record or consumer, the invariant that connects
  index-assignment demand to selected semantic identity to materialized body to
  HIR/MIR/backend body presence, and the negative controls that reject backend
  undefined-extern rescue, forwarders, requested-name forcing, broad
  `NamedTuple`/`Tuple` rendering, global ambient-map policy changes, parser
  changes, and `BlockOwner` rollback. Only after that plan exists may a code
  slice start from `regression_tests/block_owner_index_assign_materialization_repro.sh`.
  Green G6 alone will not be accepted as green `s2b`/`s3b` or as architecture
  progress unless the producer-to-consumer materialization invariant is proven.

- 2026-07-02 UPDATE: added Slice 0k-CC, a docs-only owner-spine
  consolidation that executes the 0k-CB reset. Active rows are now classified
  instead of selected from the latest crash stack: B4 and L6 stay
  `PhaseAuthority` guard-only pressure, H7/H8 stay `SemanticIdentity`
  pre-s2-clean residuals, and G6 is the next admitted implementation lane under
  `MaterializationTransaction`. The selected next code slice must start from
  `regression_tests/block_owner_index_assign_materialization_repro.sh` and keep
  `BlockOwner` as the owner carrier. It must fix or shadow the
  producer-to-consumer authority edge that proves `Hash(UInt64, BlockOwner)#[]=`
  has a real materialized body under the call-visible identity. It must not
  patch backend undefined externs, add forwarders, normalize
  `NamedTuple`/`Tuple`, globally change ambient maps, change parser behavior,
  or treat B4/L6 joined resource rows as behavior admission.

- 2026-07-02 UPDATE: added Slice 0k-CB, a docs-only architecture reset after
  hostile review of the post-0k-CA route. Production compiler behavior remains
  frozen. The joined transaction report is still the active B4 pressure gate,
  but a selector over joined rows is now guard-only unless it chooses a durable
  owner-spine decision, not merely the next local LLVM symptom. In particular,
  `final_classification=abort_resource`,
  `tail_not_reached_after_output_start`, and
  `llvm_ir_started_without_commit:file` are not sufficient to admit
  `ResourceEvidence`, worker, tail, output, memory-budget, backend-forwarder,
  parser, ambient-map, `NamedTuple`/`Tuple`, or `BlockOwner` changes. The next
  movement is an owner-spine consolidation slice: classify active work under
  `SemanticIdentity`, `MaterializationTransaction`, or
  `PhaseAuthority`/`GeneratedStageExecution`, retire or stale-mark symptom
  lanes that no longer move bootstrap, and select implementation only when a
  producer-to-consumer authority edge is named with a falsifier. This is still
  not green `s2b` or `s3b`; it prevents the joined report from becoming the
  next proxy metric.

- 2026-07-02 UPDATE: implemented Slice 0k-CA, the default-off runtime
  transaction-row follow-up selected by 0k-BZ. `scripts/generated_stage_llvm_entry_classifier.sh`
  now passes `GSETX_TRANSACTION_ID` / `GSETX_LEDGER` into only the produced-s2
  smoke runs, tagging them as `default_workers` and `workers1`. The compiler
  writes runtime rows only when `ADAMAS_GSETX_ID` and `ADAMAS_GSETX_LEDGER` are
  present: HIR module identity, MIR module identity, `LLVMEmissionSession` id
  and function plan, side-effect runtime counts, tail semantic-vs-input rows,
  and output commit/start rows. `scripts/generated_stage_execution_transaction_report.sh`
  now joins those rows under one transaction id. Fresh evidence:
  `STAGE1_COMPILER=bin/adamas REQUIRE_CURRENT_FRONTIER=1 REQUIRE_JOINED=1
  scripts/generated_stage_execution_transaction_report.sh` preserves
  `b4.classification=current_0k_bn_frontier`, but now reports
  `join_status=joined`, `final_classification=abort_resource`, runtime HIR/MIR
  ids, runtime session id, side-effect counts, `tail_not_reached_after_output_start`,
  and `output.commit_record=llvm_ir_started_without_commit:file`. Negative
  evidence: `STAGE1_COMPILER=bin/adamas GENERATED_S2=bin/adamas
  REQUIRE_ADMIT_BEHAVIOR=1 scripts/generated_stage_execution_transaction_report.sh`
  still exits 9 with `admission_status=rejected_no_root_sized_consumer`. This
  is still not green `s2b` or `s3b`; it only moves the active gate from
  unjoined evidence to joined abort evidence. The next slice must select exactly
  one root-sized transaction-owned old authority edge or refute
  `GeneratedStageExecution`; broad behavior fixes remain rejected.

- 2026-07-02 UPDATE: added Slice 0k-BZ, a docs-only hostile
  Quadrumvirate checkpoint after reviewing the 0k-BY path for tail-chasing.
  Production compiler behavior remains frozen. The next executable slice is
  still the 0k-BY missing-row follow-up, but it is now narrowed: it may add only
  default-off runtime transaction rows needed to move
  `scripts/generated_stage_execution_transaction_report.sh` from
  `phase_local_only` toward `joined`. It must not change worker behavior, tail
  stubs, side-effect semantics, output behavior, resource limits, backend
  forwarders, `NamedTuple`/`Tuple` rendering, ambient-map policy, parser
  behavior, or `BlockOwner`. Success is not "more rows exist"; success is one
  of: `joined` plus exactly one root-sized transaction-owned old authority edge,
  `joined` plus explicit refutation of the `GeneratedStageExecution` boundary,
  or a named stop because a required runtime row cannot be produced without a
  semantic behavior change. If the joined report is broad or ambiguous, the
  next slice must be a selector/falsifier, not a behavior patch.

- 2026-07-02 UPDATE: implemented Slice 0k-BY, the first executable
  `GeneratedStageExecutionTransaction` report. New script:
  `scripts/generated_stage_execution_transaction_report.sh`. It wraps the B4
  generated-stage LLVM-entry classifier, joins that output with the
  `LLVMEmissionSession` source-shape guard, and emits one transaction row set
  for the produced-compiler invocation. Current evidence with
  `STAGE1_COMPILER=bin/adamas REQUIRE_CURRENT_FRONTIER=1` prints exactly one
  `transaction_id`, preserves `b4.classification=current_0k_bn_frontier`, and
  reports `final_classification=abort_unjoined_evidence`,
  `join_status=phase_local_only`, and
  `admission_status=rejected_unjoined_evidence`. Negative guard:
  `REQUIRE_JOINED=1` exits 9 even when `GENERATED_S2=bin/adamas` compiles the
  tiny source cleanly, proving clean local compile output is not behavior
  admission without runtime transaction rows. This is still not green `s2b` or
  `s3b`; it names the next missing authority edge. The next admitted code slice
  is default-off runtime transaction-row production for HIR/MIR module identity,
  `LLVMEmissionSession` id, side-effect row counts, tail semantic-vs-input
  split, and output commit record. Behavior fixes remain rejected until the
  report reaches joined evidence and selects a root-sized transaction-owned
  consumer.

- 2026-07-02 UPDATE: added Slice 0k-BX, a docs-only
  `GeneratedStageExecutionTransaction` checkpoint after 0k-BW. Production
  compiler edits are paused again. The previous three `LLVMEmissionSession`
  ownership migrations are useful, but B4 stayed at
  `classification=current_0k_bn_frontier`; therefore "consume the next local
  session edge" is now rejected as the default move. The next executable slice
  must be a generated-stage transaction report/guard, not a behavior patch:
  one transaction row must join compiler invocation setup, function plan,
  worker/fallback policy, side-effect contract, tail declaration/stub inputs,
  output ownership, resource evidence, and B4 commit/abort classification for
  the same produced-compiler run. If that report cannot link the rows or only
  restates local session fields, stop before production code. If it links rows
  and selects a root-sized old authority edge, a later code slice may consume
  that transaction-owned edge in behavior-neutral mode. Still rejected:
  `TailDeclarationPlan`, `OutputOwnership`, `ResourceEvidence`, worker policy,
  side-effect semantics, backend stub rescue, memory-budget acceptance, or
  `ADAMAS_LLVM_WORKERS=1` as a fix without the transaction checkpoint.

- 2026-07-02 UPDATE: implemented Slice 0k-BW, the behavior-neutral
  `SideEffectMergeContract` consumer migration. `LLVMEmissionSession` now owns
  the worker side-effect row vocabulary, `emit_functions_parallel` receives the
  session, worker `.se` writing delegates to
  `write_worker_side_effects_with_contract`, and parent side-effect merging
  delegates to `merge_worker_side_effects_with_contract`. The `.se` file format,
  duplicate/malformed-row policy, undefined extern recording, called/emitted
  function set handling, debug-file registration, worker fallback behavior,
  tail declarations/stubs, output ownership, resource acceptance, and
  `BlockOwner` are unchanged. Verification: prepatch B4 was
  `classification=current_0k_bn_frontier`; prepatch side-effect guard was red
  with writer tags `10` and merge tags `9`; postpatch
  `REQUIRE_SESSION=1 REQUIRE_WORKER_PLAN=1 REQUIRE_SIDE_EFFECT_CONTRACT=1
  scripts/llvm_emission_session_source_shape_guard.sh` reports
  `side_effect_contract_shape=session_consumes_side_effect_merge_contract`,
  writer/merge call counts `1/1`, and inline raw writer/merge tags `0/0`;
  `crystal build src/adamas.cr -o bin/adamas --error-trace`, H6-core, B3, and
  static-call LLVM guards pass. Postpatch B4 remains exactly
  `classification=current_0k_bn_frontier` with the same default-worker
  rand+RSS split and workers=1 exit 139. Per 0k-BV, all convergence-vector rows
  were preserved unchanged, so the next movement is NOT another
  `LLVMEmissionSession` edge hoist (`TailDeclarationPlan`, `OutputOwnership`,
  or `ResourceEvidence`) by default; write a higher-level
  `GeneratedStageExecution` transaction checkpoint before the next production
  compiler edit.

- 2026-07-02 UPDATE: added Slice 0k-BV, a docs/guard convergence checkpoint
  before any production compiler edits. Hostile review found that
  `LLVMEmissionSession` edge-consumption can itself become a proxy metric:
  0k-BR and 0k-BS moved real authority edges but B4 remained at the same
  `current_0k_bn_frontier`. The selected `SideEffectMergeContract` route is
  retained, but implementation is now the future 0k-BW slice. 0k-BW must carry
  a convergence vector, not just source-shape success: B4 before/after, default
  worker vs `ADAMAS_LLVM_WORKERS=1` split, side-effect writer/merge source
  shape, tail-input vs semantic-failure classification, output/resource
  evidence boundary, and post-edge routing. If 0k-BW leaves B4 and every vector
  row unchanged, the next movement is a higher-level
  `GeneratedStageExecution` transaction redesign checkpoint, not another
  `LLVMEmissionSession` edge hoist. The side-effect source-shape guard now
  exists and is intentionally red on current source:
  `REQUIRE_SESSION=1 REQUIRE_WORKER_PLAN=1 REQUIRE_SIDE_EFFECT_CONTRACT=1
  scripts/llvm_emission_session_source_shape_guard.sh` reports
  `side_effect_contract_shape=legacy_parallel_side_effect_merge`,
  `parallel_raw_side_effect_writer_tags=10`, and
  `parallel_raw_side_effect_merge_tags=9`, then exits non-zero. No compiler
  production behavior changed.

- 2026-07-01 UPDATE: added Slice 0k-BU, a docs-only
  `SideEffectMergeContract` implementation plan selected from the 0k-BT
  vertical-contract checkpoint. Production compiler edits remain paused until the
  plan's prepatch red guard exists. The selected old authority edge is
  `parallel-side-effect-file-merge`: worker code writes raw `.se` rows directly
  in `emit_functions_parallel`, the parent parses raw tags in the same method,
  and tail emitters later consume mutable backend fields as if the merge were
  semantically authoritative. The next code slice must move the writer/parent
  merge consumer to a session-owned side-effect contract, not merely add tag
  getters. Required guard shape:
  `REQUIRE_SESSION=1 REQUIRE_WORKER_PLAN=1 REQUIRE_SIDE_EFFECT_CONTRACT=1
  scripts/llvm_emission_session_source_shape_guard.sh` must be red before patch
  and green only when `emit_functions_parallel` delegates side-effect writing and
  merging through the contract. B4 must be run before and after; unchanged
  `classification=current_0k_bn_frontier` is acceptable only for this
  behavior-neutral migration.

- 2026-07-01 UPDATE: added Slice 0k-BT, a docs-only architecture checkpoint after
  hostile review of the post-0k-BS path. Production compiler edits are paused
  again. A local side-effect-tag owner WIP was saved in git stash
  (`wip: llvm emission side-effect tag owner micro-slice before architecture
  checkpoint`) and is not completion evidence. The WIP moved only the worker
  `.se` tag vocabulary (`STR`, `ZSG`, `EXT`, etc.) toward
  `LLVMEmissionSession`; hostile review classifies that as too thin to count as
  the next architecture slice by itself. The next code movement on
  `GeneratedStageExecution` must be a vertical `SideEffectMergeContract` /
  `TailDeclarationPlan` / `OutputOwnership` / `ResourceEvidence` contract slice,
  or a docs-only redirect that refutes `LLVMEmissionSession` as the active owner
  boundary. A field-only, tag-only, getter-only, or report-only session change is
  rejected unless it moves a downstream consumer away from mutable backend
  fields/ad-hoc worker files/tail fallback and preserves or narrows B4 evidence.

- 2026-07-01 UPDATE: implemented Slice 0k-BS, the second behavior-neutral
  `LLVMEmissionSession` owner migration. The existing guard
  `scripts/llvm_emission_session_source_shape_guard.sh` now has
  `REQUIRE_WORKER_PLAN=1` and proves that `LLVMIRGenerator#generate` consumes
  effective worker count through the session instead of computing
  `parallel_llvm_workers` and the debug-info sequential override inline. The
  slice consumes `worker-policy-inline` only: requested worker count, effective
  worker count, and a compact sequential reason code are now session facts.
  `emit_functions_parallel`, its fallback-to-sequential behavior,
  side-effect merging, tail stubs, output ownership, resource acceptance, and
  `BlockOwner` are unchanged. Adversary result: a separate
  `LLVMEmissionWorkerPlan` class made B4 fail during stage1->s2 build under the
  4096MB gate, so the committed shape stores worker-plan scalars inside
  `LLVMEmissionSession`. Fresh B4 returns to
  `classification=current_0k_bn_frontier`; this is still not a green
  `s2b`/`s3b` claim.

- 2026-07-01 UPDATE: implemented Slice 0k-BR, the first behavior-neutral
  `LLVMEmissionSession` owner migration. New guard:
  `scripts/llvm_emission_session_source_shape_guard.sh`. The slice consumes
  the `function-list-inline` authority edge only: `LLVMIRGenerator#generate`
  now obtains `functions_to_emit` through an explicit
  `LLVMEmissionSession` / `LLVMEmissionFunctionPlan` owner object instead of
  keeping reachability, unresolved-pattern skip propagation, return-type
  precompute, and mangled-name dedup as inline locals in `generate`. Worker
  policy, parallel fallback, side-effect merging, tail undefined externs,
  missing-body stubs, output-file ownership, resource acceptance, and
  `BlockOwner` are unchanged. Adversary result: a first implementation using
  Crystal `record` macros was rejected because produced `s2b` changed B4 to
  `STUB CALLED: Adamas::MIR::LLVMEmissionFunctionPlan#functions_to_emit`; the
  committed shape uses explicit private classes/methods and B4 returns to
  `classification=current_0k_bn_frontier`. This is not a green `s2b`/`s3b`
  claim; it only installs the first owner boundary and guard.

- 2026-07-01 UPDATE: added Slice 0k-BQ, a docs-only
  `LLVMEmissionSession` owner-contract design under the 0k-BP
  `PhaseAuthority` freeze. Source inventory pins the current legacy authority
  edges: CLI step 5 creates/configures `LLVMIRGenerator`, assigns HIR extern
  maps and constant initializers, and owns `.ll` file output; the backend
  chooses the final function list, unresolved-pattern skip set, return-type
  precompute, mangled-name dedup set, worker count, sequential/parallel path,
  worker side-effect merge, tail undefined-extern declarations, missing-body
  stubs, and memory snapshots through mutable fields and locals. The next code
  slice is now admitted only as behavior-neutral `contract-owner-migration`:
  introduce one `LLVMEmissionSession` session/plan record that captures setup
  facts, function plan, worker plan, side-effect merge contract, tail plan,
  output ownership, resource evidence, and generated-stage gate linkage. It
  must add a source-shape guard proving at least one old authority edge is
  consumed by the session record. It must not change emitted LLVM semantics,
  worker defaults, fallback behavior, undefined externs, missing-body stubs,
  output-file behavior, or `BlockOwner` in the first implementation slice.

- 2026-07-01 UPDATE: added Slice 0k-BP, a docs-only architecture freeze after
  hostile review of the post-0k-BO decision. Production compiler fixes from
  the B4 crash stack are paused. `scripts/generated_stage_llvm_entry_classifier.sh`
  remains the active measured-red/future-green pressure gate, but it is not a
  license to patch LLVM workers, memory limits, backend fallback, output
  buffers, or direct segfault symptoms. The next movement must first define a
  `PhaseAuthority` / `GeneratedStageExecution` owner contract: which facts are
  semantic across stage1/s2b/s3b, which are phase-local, which are owned by a
  single `LLVMEmissionSession`, and which are debug/probe-only. A classifier
  extension is admitted only if it answers one of those owner questions
  (function-list identity, worker/fallback policy, side-effect table merge,
  output-buffer lifetime, resource-budget accounting, or generated-stage
  evidence). A behavior slice is admitted only after that owner contract names
  the old authority edge being replaced, shadowed, or refuted. This slice
  changes planning only; it does not make `s2b`/`s3b` green and does not weaken
  B4.

- 2026-07-01 UPDATE: implemented Slice 0k-BO, the executable B4
  generated-stage LLVM-entry classifier. New script:
  `scripts/generated_stage_llvm_entry_classifier.sh`. It builds or accepts a
  stage1 compiler, builds or accepts a produced `s2b`, then compiles a
  full-prelude tiny source with the produced compiler in two modes: default
  LLVM workers and `ADAMAS_LLVM_WORKERS=1`. It prints machine-readable
  evidence rows and has two explicit gates: `REQUIRE_CURRENT_FRONTIER=1` for
  the current measured-red 0k-BN boundary, and `REQUIRE_CLEAN=1` for the future
  green bootstrap gate. Fresh evidence:
  `REQUIRE_CURRENT_FRONTIER=1 scripts/generated_stage_llvm_entry_classifier.sh`
  exits 0 with `classification=current_0k_bn_frontier`, `stage1_build_rc=0`,
  `s2_build_rc=0`, `default_workers_parallel_rand=1`,
  `default_workers_memory_kill=1`, `workers1_parallel_rand=0`, and
  `workers1_exit139=1` after `pass3 after lower_main call`. This remains
  behavior-neutral: it does not patch LLVM workers, raise memory as acceptance,
  force worker count, or make `s2b` green. The next production movement must
  extend or consume this classifier to name the first bad owner boundary inside
  `LLVMEmissionSession`.

- 2026-07-01 UPDATE: added Slice 0k-BN, a docs-only generated-stage
  LLVM-entry checkpoint after the 0k-BM owner-fact slice. Production code is
  paused again. Fresh post-0k-BM evidence shows the next `s2b`/`s3b` movement
  must not be selected from stale guard order alone: a fresh stage1 builds a
  produced `s2b`, but that produced compiler compiling a full-prelude
  `puts 42`/hello source does not reach a clean binary. With default LLVM
  workers, the produced compiler reports
  `parallel emission failed: Invalid bound for rand: 0`, falls back to
  sequential emission, and is killed by `scripts/run_safe.sh` at the 4096MB
  RSS limit. With `ADAMAS_LLVM_WORKERS=1`, the parallel-rand path disappears
  but the same produced compiler still exits 139 immediately after
  `pass3 after lower_main call`. This falsifies treating the parallel worker
  failure as the sole root and also falsifies picking H7 parser or H8 runtime
  `.class` work as the next bootstrap-moving implementation merely because
  those guards are red. The next admitted movement is a generated-stage
  `LLVMEmissionSession` / LLVM-entry classification slice: name the first
  bad boundary between MIR setup, function emission scheduling, worker/fallback
  policy, side-effect tables, output buffers, and backend memory/resource
  ownership before any behavior patch. Do not patch `emit_functions_parallel`,
  raise memory limits, force `ADAMAS_LLVM_WORKERS=1`, or resume
  `fused_parallel_requested` cleanup as a bootstrap fix from this evidence
  alone.

- 2026-07-01 UPDATE: implemented Slice 0k-BM, the H6-core
  `TypeValue` / `RuntimeTypeIdentity` owner-fact migration admitted by 0k-BL.
  The slice adds a HIR-owned `RuntimeTypeIdentity` fact keyed by `ValueId`,
  with semantic `TypeRef`, display name, origin, and runtime stringification
  policy; producers now cover `lower_typeof` (including multi-arg union
  construction), runtime `.class`, explicit type literals, and type-literal
  name/string queries; consumers now cover string interpolation, direct
  `puts`/`print`, `<<`, general call-argument conversion, and local/copy
  propagation. Fresh clean-HEAD baselines reproduced H6-core and B3
  measured-red and H7 measured-red. Fresh patched evidence:
  `type_value_core_runtime_identity_contract.sh`, B3
  `original_vs_stage_semantic_oracle_contract.sh`, and H4
  `p2_type_literal_name_query_no_stub.sh` pass strict; the explicit-type-literal
  adversary `test_byteformat_decode_u32.cr` passes after gating string
  materialization by `runtime_stringification_required`; full
  `run_all_suites.sh /tmp/adamas_0kbl_typevalue 4` passes `152/152 + 36/36`.
  H7 remains measured-red under
  `ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH=1`. New residual guard:
  `regression_tests/type_value_dynamic_union_class_residual.sh <compiler>`,
  measured-red with `ADAMAS_EXPECT_DYNAMIC_UNION_CLASS_MISMATCH=1`, proves the
  remaining H8 edge case: runtime `.class` on dynamic `Int32 | String` prints
  static union display where original Crystal prints the concrete runtime
  class. Do not claim full old H6, green `s2b`, or green `s3b` from this
  slice.

- 2026-07-01 UPDATE: added Slice 0k-BL, a docs-only architecture
  execution-ladder checkpoint after pausing production edits. The uncommitted
  TypeValue / RuntimeTypeIdentity owner-fact WIP was quarantined in git stash
  (`wip: typevalue runtime identity owner fact before architecture plan`) and
  is not completion evidence. The next production slice must now pass the
  ladder in `docs/compiler_architecture_sdd.md`: select one active-board row
  and tranche, name the old authority edge, name the owner fact/service,
  enumerate producers and consumers, rerun the measured-red baseline before
  patching, prove the old edge is no longer sole authority, state generated
  stage relevance, and record residual red boundaries. For TypeValue
  specifically, resuming the WIP is admitted only as H6-core
  `contract-owner-migration`; it must rebaseline H6-core/B3, fix or explicitly
  scope multi-argument `typeof`, list remaining `dot_class_literal?` /
  `type_literal?` consumers as compatibility-only or authoritative, and keep
  the H7 command-call parser guard separate. No compiler behavior changed in
  this checkpoint.

- 2026-07-01 UPDATE: added Slice 0k-BK, a docs-only architecture pause
  checkpoint after hostile review of the repeated local-fix pattern. Production
  code remains paused. The next implementation may proceed only if it declares
  one tranche and stays inside it: currently the only admitted behavior tranche
  is H6-core `contract-owner-migration` for a HIR-owned
  `TypeValue` / `RuntimeTypeIdentity` fact. A backend forwarder, target
  keepalive, materialization rescue, global ambient-map policy change,
  parser-precedence loop, `NamedTuple`/`Tuple` rendering patch, or `BlockOwner`
  rollback is not an admitted shortcut. If a future code slice needs any of
  those surfaces, stop before editing and write a new SDD slice that names the
  authority edge, falsifier, root-size budget, and residual boundary. No
  compiler behavior changed in this checkpoint.

- 2026-07-01 UPDATE: added Slice 0k-BJ, a docs-only TypeValue
  owner-fact implementation gate. Production code remains paused until the next
  slice can name the `TypeValue` / `RuntimeTypeIdentity` owner fact, its
  producers, its consumers, the old authority edges it retires or shadows, and
  the residual command-call frontend row. The admitted code route is still
  `contract-owner-migration`, but a green H6-core result is not acceptable if it
  comes from a string-only `lower_typeof` patch, interpolation/direct-output
  special-case, backend stringification, `dot_class_literal?`-only authority, or
  another local side map. The next code slice must route direct output,
  interpolation, call-argument conversion, type-literal name/string queries, and
  local/copy propagation through the HIR-owned fact, while keeping parser,
  generic materialization, `BlockOwner`, requested-name policy, ambient-map
  policy, backend stubs/forwarders, and broad `NamedTuple`/`Tuple` behavior out
  of scope. No compiler behavior changed in this checkpoint.

- 2026-07-01 UPDATE: implemented Slice 0k-BI, the H6 split required by the
  0k-BH pause gate. New guard:
  `regression_tests/type_value_core_runtime_identity_contract.sh <compiler>`.
  It compares original Crystal and the stage compiler on direct/interpolated
  `typeof(1)`, direct/interpolated `1.class`, local nilable `.class`,
  parenthesized nilable `.class`, and type-literal `.name/.to_s/inspect`,
  deliberately excluding the parser-confounded no-parens
  `puts (true ? 1 : nil).class` row. Fresh evidence with current `bin/adamas`:
  strict mode exits 1; with `ADAMAS_EXPECT_TYPEVALUE_CORE_MISMATCH=1`, it exits
  0 after the stage binary prints blank `typeof` rows and exits 139 at
  `DIRECT_CLASS`. The existing
  `regression_tests/command_call_member_access_preservation_contract.sh`
  remains the separate measured-red frontend guard. Next admitted production
  route is back to `contract-owner-migration`: introduce the smallest
  HIR-owned `TypeValue` / `RuntimeTypeIdentity` fact that makes the new core
  guard strict-green while keeping the command-call parser guard out of scope.
  Do not claim the full old H6 guard green until the separate command-call
  frontend guard is also resolved.

- 2026-07-01 UPDATE: added Slice 0k-BH, a docs-only Architecture Pause Gate
  after the 0k-BG command-call parser guard and a reverted local parser WIP.
  The WIP widened `LParen` handling in the no-parens command-call parser path
  and added a tight postfix hook, but it was not completed or verified and was
  removed before this checkpoint. Production code is paused again. The next
  code movement must explicitly choose one of two routes before editing:
  (1) a single bounded `semantic-service-extraction` parser-frontier closure
  attempt that makes
  `regression_tests/command_call_member_access_preservation_contract.sh`
  strict-green while preserving targeted parser specs; or (2) split H6 into a
  TypeValue-core guard plus a measured-red command-call frontend guard, then
  resume the TypeValue owner-fact migration. If the parser attempt needs a
  second implementation loop, regresses adjacent parser specs, or broadens into
  generic command-call precedence work, stop, revert/quarantine the WIP, and
  return to the split-H6 / TypeValue-owner route. No TypeValue, `BlockOwner`,
  generic materialization, requested-name, ambient-map, backend stub/forwarder,
  or broad `NamedTuple`/`Tuple` behavior is admitted by this checkpoint.

- 2026-07-01 UPDATE: implemented Slice 0k-BG, the frontend command-call
  member-access preservation falsifier. New guard:
  `regression_tests/command_call_member_access_preservation_contract.sh`.
  It is strict by default and measured-red with
  `ADAMAS_EXPECT_COMMAND_CALL_MEMBER_MISMATCH=1`. Current evidence: strict mode
  exits 1 because `puts (true ? 1 : nil).class` parses as a root
  `MemberAccessNode` on the command-call result instead of a command `CallNode`
  whose argument is `.class`; measured-red mode exits 0. Controls in the same
  guard require `puts((true ? 1 : nil).class)`, `x.class`, and bare
  `puts (true ? 1 : nil)` to keep their expected shapes. This closes the
  missing parser-frontier falsifier from 0k-BF; no compiler behavior changed
  and TypeValue production remains paused until this frontend boundary is
  fixed or H6 is split into TypeValue-core plus frontend-command guards.

- 2026-07-01 UPDATE: added Slice 0k-BF, a docs-only failed-preflight
  checkpoint for the attempted `contract-owner-migration` TypeValue code
  slice. A reverted local owner-fact patch made B3 and H4 green, but strict H6
  still failed on direct `puts (true ? 1 : nil).class` while
  `puts((true ? 1 : nil).class)`, `x.class`, and interpolation passed. The
  first new boundary is therefore not another TypeValue consumer edge: Adamas
  command-call parsing/lowering preserves the argument as a `TernaryNode` and
  loses the `.class` suffix for this syntax. Do not green H6 by adding a
  source-text direct-puts workaround. The next admitted movement is to
  classify that frontend command-call preservation gap as its own
  `semantic-service-extraction` / parser-frontier slice, or to split H6 into a
  TypeValue core guard plus a separate measured-red frontend guard before any
  production fix.

- 2026-07-01 UPDATE: added Slice 0k-BE, a docs-only architecture
  tranche selector / tail-chasing stop after the TypeValue implementation
  receipt. Production code is paused again until the next code slice states
  its tranche before editing: `contract-owner-migration`,
  `semantic-service-extraction`, `cleanup/delete`, or
  `bootstrap-emergency-with-ledger`. TypeValue remains an admitted candidate,
  but only as `contract-owner-migration`: it must retire or shadow the named
  H6 authority edges through one owner fact, not become another local output
  patch. A future G3 generic-key migration is the fallback if TypeValue cannot
  stay inside H6 or if the implementation needs generic materialization,
  `BlockOwner`, requested-name policy, ambient maps, backend stubs/forwarders,
  or broad `NamedTuple`/`Tuple` rendering. This slice changes planning only;
  no compiler behavior changed and no green `s2b`/`s3b` claim is made.

- 2026-07-01 UPDATE: added Slice 0k-BD, a docs-only TypeValue implementation
  receipt before production code. This is the pause requested after the H6
  measured-red guard: the next code slice is admitted only if it introduces one
  HIR-owned `TypeValue` / `RuntimeTypeIdentity` fact and migrates the
  H6-reached consumers to that fact. The old authority edges are now explicit:
  `typeof(...)`'s nil placeholder, runtime `.class` type-literal construction,
  dot-class side maps, direct-output conversion, interpolation conversion, and
  type-literal name/string query lowering. The slice must not touch generic
  materialization, `BlockOwner`, requested-name policy, ambient maps, backend
  stubs/forwarders, or broad `NamedTuple`/`Tuple` rendering. If implementation
  requires consumers outside the H6 guard or mixes in those surfaces, stop at
  classification and return to the G3 semantic-key migration lane. This is
  planning/frontier control only; no compiler behavior changed and no green
  `s2b`/`s3b` claim is made.

- 2026-07-01 UPDATE: implemented Slice 0k-BC, the H6 TypeValue
  runtime-identity falsifier. New guard:
  `regression_tests/type_value_runtime_identity_contract.sh <compiler>`.
  It compares original Crystal and the supplied stage compiler through
  `scripts/run_safe.sh` on direct and interpolated `typeof(1)`, runtime
  `1.class`, nilable `(true ? 1 : nil).class`, and type-literal `.name` /
  `.to_s` / `inspect`. The guard is strict by default; use
  `ADAMAS_EXPECT_TYPEVALUE_MISMATCH=1` only to assert the known measured-red
  frontier. Fresh measured-red evidence is stronger than a plain stdout diff:
  the stage binary prints blank direct/interpolated `typeof` rows and then
  exits 139 at the direct `.class` row. This closes the H6 missing-falsifier
  hole but does not add the HIR-owned `TypeValue` / `RuntimeTypeIdentity` fact,
  does not fix B3, and does not prove green `s2b`/`s3b`. Next aligned
  production work is the TypeValue owner-fact implementation/migration for the
  reached consumers.

- 2026-07-01 UPDATE: added Slice 0k-BB, a docs-only hostile
  self-review checkpoint after the measured-red B3 oracle. The B3 failure is
  now classified as a `TypeValue` / `RuntimeTypeIdentity` frontier, not as a
  standalone `lower_typeof` output bug. Current implementation has split
  authority edges: `typeof(...)` lowers to a nil placeholder, runtime `.class`
  creates a nil type-literal pointer, type-literal name queries use a separate
  path, and string interpolation has its own dot-class special-case. The next
  admitted production slice must first extend the falsifier/contract to cover
  direct and interpolated `typeof`, runtime `.class`, nilable `.class`, and
  type-literal `.name` / `.to_s` / `inspect`, then introduce one HIR-owned
  type-visible value fact consumed by those paths. Do not patch `lower_typeof`
  as a string-only fix, add interpolation/direct-output special cases, use
  backend stubs, change generic materialization, change `BlockOwner`, or claim
  green `s2b`/`s3b` from B3 alone.

- 2026-07-01 UPDATE: implemented Slice 0k-BA, the B3 original-vs-stage semantic
  oracle slice. New guard:
  `regression_tests/original_vs_stage_semantic_oracle_contract.sh <compiler>`.
  The script builds and runs the same source with original Crystal and the
  supplied stage compiler through `scripts/run_safe.sh`, then compares explicit
  semantic lines: `TYPE=`, `CONST=`, and `UNION=`. This is currently
  measured-red: current stage preserves `CONST=7`, but emits blank `TYPE=` and
  `UNION=` where original Crystal emits `Int32`. Use
  `ADAMAS_EXPECT_ORIGINAL_STAGE_MISMATCH=1` only to assert the known frontier.
  Strict mode remains the acceptance gate. This closes the missing B3 oracle
  but does not fix the type-visible semantic mismatch and does not prove green
  `s2b`/`s3b`.

- 2026-07-01 UPDATE: implemented Slice 0k-AZ, the second contract burn-down
  slice after the 0k-AX pivot. G3 in `docs/specs/05-falsifier-matrix.md` now
  has an executable guard:
  `regression_tests/generic_identity_key_contract.sh`. The slice adds
  `GenericTemplateKey` and `GenericInstanceKey` under
  `src/compiler/semantic/identity/` and proves generic template/instance
  equality and hashing are keyed by owner, source `DefIdentity`, declared type
  parameters, specialization argument identities, and lexical owner rather than
  display/rendered names. This is a contract object plus falsifier only; it
  does not migrate generic materialization/registration call sites and does not
  prove green `s2b`/`s3b`. Next contract-first priority is B3 original-vs-stage
  semantic oracle coverage unless the next slice explicitly replaces a named
  old generic-identity authority edge with these keys.

- 2026-07-01 UPDATE: implemented Slice 0k-AY, the first contract burn-down
  slice after the 0k-AX pivot. H5 in `docs/specs/05-falsifier-matrix.md` now
  has an executable guard:
  `regression_tests/hir_function_body_presence_contract.sh`. The guard runs a
  focused spec that proves `HIR::Module#create_function` registers a function
  without making `has_function_with_body?` true, proves instruction and real
  terminator evidence do make it true, and proves HIR->MIR preserves a bodyless
  registered function as an empty `MIR::Unreachable` stub while a real body
  lowers to `MIR::Return`. This closes the missing H5 falsifier only; it does
  not change compiler behavior and does not prove green `s2b`/`s3b`. Next
  contract-first priority remains G3: generic template/instance semantic keys
  versus rendered-name identity.

- 2026-07-01 UPDATE: added Slice 0k-AX, a docs-only contract-first
  architecture pivot after 0k-AW. The next work must not be selected by the
  latest generated-stage crash stack. Before another behavior fix, pick one
  missing or weak compiler contract and either add its falsifier or replace a
  named authority edge with an owned fact. Priority order:
  1. function-body presence vs undefined/bodyless stubs
     (`docs/specs/05-falsifier-matrix.md` H5);
  2. generic template/instance semantic keys vs rendered-name identity (`G3`);
  3. original-vs-stage semantic oracle coverage for future language-behavior
     changes (`B3`).
  A slice that only adds a report, moves a crash frontier, or makes a source
  metric greener is rejected unless it also removes/refutes an older report
  surface or closes one of these falsifier holes. `s2b`/`s3b` remain the goal,
  but crash progress is now a downstream acceptance signal, not the work
  selector.

- 2026-07-01 UPDATE: implemented Slice 0k-AW, the behavior-neutral shared
  keep-requested-name state model admitted by 0k-AV. The paired frontend
  `lower_function_if_needed.callsite_args` and `.suffix_types` consumers now
  construct a `KeepRequestedNameDecision` record and read its `emitted_result`
  instead of recomputing the keep-requested-name expression inline. Emitted
  behavior remains legacy/parity; this is not a requested-name policy flip and
  not a green `s2b`/`s3b` claim. The source-shape gate now reports both
  consumers as `shared_keep_requested_name_model` with
  `state_model_redesign_complete=1`; the negative no-repeat gate
  `REQUIRE_SELECTED=1` still exits `9`, proving no single consumer was silently
  reselected. Added successor guard
  `regression_tests/block_owner_index_assign_materialization_repro.sh` for the
  current `Hash(UInt64, BlockOwner)#[]=` owner-cache carrier; the retired
  `NamedTuple` guard must stay retired. Next work should not chase the next
  crash frontier directly. Move the architecture track to contract-first SDD
  hardening: close missing falsifiers for semantic identity, function-body
  presence, and generic instance/template keys before admitting more behavior
  fixes.

- 2026-07-01 UPDATE: retired stale regression
  `regression_tests/hash_named_tuple_index_assign_materialization_repro.sh`.
  The script searched self-IR for the obsolete
  `Hash(UInt64, NamedTuple)#[]=` owner-cache shape, but the admitted carrier is
  now `Hash(UInt64, BlockOwner)`. Keeping the script produced false red
  evidence (`no Hash(UInt64, NamedTuple)#[]= materialization found`) after the
  `BlockOwner` migration. Future 0k-AV implementation must add a successor
  guard for the current `BlockOwner` carrier before using owner-cache
  materialization as DoD.

- 2026-07-01 UPDATE: added Slice 0k-AV, a docs-only hostile self-review
  checkpoint after the 0k-AU source selector. The selector correctly refused to
  choose between `lower_function_if_needed.callsite_args` and
  `lower_function_if_needed.suffix_types`, but an uncommitted helper WIP showed
  the next risk: turning the required state-model redesign into another
  source-shape proxy. That WIP was reverted before this checkpoint. The next
  admitted production slice may introduce a shared keep-requested-name state
  model only if it first states the owned fact, legacy edge, emitted-behavior
  parity rule, stale-regression audit, and generated-stage guard. It must not
  claim bootstrap progress from `state_model_redesign_complete=1` alone.
  Because the retired `hash_named_tuple_index_assign_materialization_repro.sh`
  no longer matches the `BlockOwner` carrier, add a successor guard before
  using owner-cache materialization as DoD. Do not add backend forwarders,
  target keepalive, requested-name forcing,
  `NamedTuple`/`Tuple` rendering changes, global ambient-map policy changes, or
  `BlockOwner` rollback.

- 2026-07-01 UPDATE: implemented Slice 0k-AU, a source-shape-only no-repeat mode
  in `scripts/semantic_state_scope_admission_report.sh`. `SOURCE_SHAPE_ONLY=1`
  now enumerates live direct
  `state_scope_consumer_def_has_untyped_regular_param?` callers without running
  a compiler. Result: `prefer_callsite_specialization` and
  `lower_function_if_needed.override` are already promoted; `lower_call.remangle`
  is backend-adjacent; the two remaining frontend direct consumers are
  `lower_function_if_needed.callsite_args` and
  `lower_function_if_needed.suffix_types`. Because both remain direct,
  unpromoted frontend candidates, the selector reports
  `frontend_candidate_count=2`, `selected_count=0`, and
  `state_model_redesign_required=1`; `SOURCE_SHAPE_ONLY=1 REQUIRE_SELECTED=1`
  exits `9`. Next aligned architecture step is therefore a state-model redesign
  checkpoint for shared `lower_function_if_needed` keep-requested-name state, or
  a stronger falsifier that collapses those two candidates to exactly one
  root-sized edge. Do not choose either consumer by source order or convenience.

- 2026-07-01 UPDATE: added Slice 0k-AT, an architecture pivot checkpoint after
  the cleanup lane produced only negative cleanup facts. The active bootstrap
  lane is now a no-repeat `SemanticStateScope` selection gate, not another
  cleanup classification and not the already promoted
  `lower_function_if_needed.override` seam. The next code slice must enumerate
  remaining direct `state_scope_consumer_def_has_untyped_regular_param?`
  consumers, reject already-promoted and backend-adjacent seams, and select at
  most one unpromoted root-sized consumer before any behavior-neutral owner
  decision is implemented. If no such consumer exists, move up to a state-model
  redesign checkpoint. Do not add backend forwarders, target keepalive,
  requested-name forcing, `NamedTuple`/`Tuple` rendering changes, global
  ambient-map policy changes, another cleanup classification, or `BlockOwner`
  rollback.

- 2026-07-01 UPDATE: added Slice 0k-AS, a focused
  `CodePathStatus` cleanup classification for
  `fused_parallel_requested`. The cleanup-entry report now supports
  `SELECTED_CLEANUP_PATH=fused_parallel_requested` and classifies it as
  `experimental_live`, with `default_status=not_taken`,
  `enabled_status=taken`, and `action=keep_experimental_live`.
  `REQUIRE_DELETE_READY=1` still fails with
  `inventory_status=no_delete_ready_candidate`. Decision: the fused parallel
  MIR path is not delete-ready from current evidence; do not delete it. The
  next cleanup slice must choose a different `not_taken_unproven` path or
  define a stricter delete-ready class.

- 2026-07-01 UPDATE: added Slice 0k-AR, fail-closed runtime
  inventory mode for the `CodePathStatus` cleanup-entry report. With
  `LIST_RUNTIME_PATHS=1`, a fresh stage1 no-prelude compile reports
  `inventory_rows=26`, `inventory_paths=26`, `inventory_malformed=0`,
  `inventory_delete_ready_rows=0`, and
  `inventory_status=no_delete_ready_candidate`. Negative control:
  `LIST_RUNTIME_PATHS=1 REQUIRE_DELETE_READY=1` exits 9. Decision: no
  cleanup/delete behavior change is admitted yet. Inventory `not_taken` rows
  are `not_taken_unproven`, not deletion targets. The next cleanup slice must
  pick one such path and add a protecting falsifier, or define a stricter
  `eligible_delete_ready_candidate` class before deleting code.
  `scripts/codepath_status_runtime_report.sh` now also creates repo-local
  `tmp/` before `mktemp`.

- 2026-07-01 UPDATE: ran the post-0k-AP cleanup-entry preflight
  on a freshly built stage1 compiler. Both currently supported cleanup paths
  remain classify-only: `SELECTED_CLEANUP_PATH=identity_dry_run` and
  `SELECTED_CLEANUP_PATH=phase0_metrics` each reported `default_rc=0`,
  `enabled_rc=0`, `default_status=not_taken`, `enabled_status=taken`, and
  `status=debug_only`. Decision: neither path is `delete_ready`; do not delete
  either CLI metrics path from the existing cleanup report. The next
  cleanup/delete slice must select a different named path or first extend the
  cleanup selector to enumerate a root-sized candidate with a protecting
  falsifier.

- 2026-07-01 UPDATE: added Slice 0k-AP, report-surface
  consolidation after the ambiguous 0k-AO residual. The active SDD now treats
  architecture reports as a status registry, not as a menu of competing next
  steps. `generated_stage_transaction_edge_selection_report.sh` is the
  `active-stop-gate`; `generated_stage_transaction_spine_classifier.sh` is only
  supporting; previously promoted source-shape reports for
  `CallMaterializationTransaction`, `MaterializationSymbolBinding`,
  `MethodNameCodec`, `InvocationContext`, and `SemanticStateScope` are guards,
  not new selectors; `codepath_status_cleanup_selection_report.sh` is the only
  current cleanup/delete entry point and now creates repo-local `tmp/` before
  `mktemp`; older census/ledger reports are historical unless a future SDD
  slice explicitly reactivates one with a
  decision question, root-size budget, negative control, and old authority
  edge. Decision: the default next executable slice should be `cleanup/delete`
  through `CodePathStatus`, or a stronger correctness-selection discriminator
  that selects exactly one authority edge. Do not add another standalone
  report, do not patch residual sample paths, and do not treat old green
  source-shape gates as green `s2b`/`s3b` evidence.

- 2026-07-01 UPDATE: implemented Slice 0k-AO,
  post-0k-AM exact-contract residual selector inside the existing generated
  stage transaction edge selection script. The script now creates repo-local
  `tmp/` before `mktemp`, reports `MAX_RESIDUAL_ROWS`, and classifies
  `call_materialization.exact_contract.extern_missing_body` rows by phase,
  branch, emitted owner, required contract, symbol relation, and identity
  status. Synthetic ledger checks covered eligible, ambiguous, too-wide, and
  no-residual states. Fresh generated-stage evidence reports
  `classifier_classification=reached_tx_and_emit`,
  `post_consumer_state=selected_consumed_by_contract_consumer`,
  `contract_mismatch_rows=0`, `other_missing_body_rows=14`,
  `residual_exact_missing_body_rows=14`,
  `residual_exact_missing_body_groups=9`,
  `residual_exact_missing_body_root_sized_groups=9`, and
  `residual_selection_status=rejected_exact_missing_body_ambiguous`.
  `REQUIRE_RESIDUAL_SELECTED=1` fails with exit 9 on the same log. Decision:
  the immediate exact-contract residual is ambiguous, not a selected next
  behavior edge. Do not patch any sample path (`Array#<<`, `Slice#[]`,
  `IO#read`, `Atomic#get`, `StaticArray`, `String::Builder`, `Int32`) from this
  report. Next slice must either add a stronger discriminator that selects one
  old authority edge, or switch to `consolidation` / `cleanup/delete` under the
  0k-AN covenant.

- 2026-07-01 UPDATE: added Slice 0k-AN, docs-only
  architecture pacing covenant after 0k-AM. The purpose is to stop the next
  step from turning into selector/report tail-chasing. A future slice must
  choose exactly one lane before production edits:
  `correctness-selection`, `consumer-migration`, `cleanup/delete`, or
  `consolidation`. New selectors are admitted only with a decision question,
  root-size budget, negative control, and named old authority edge. Broad
  results, including the current `other_missing_body_rows=14`, stop at
  classification and do not authorize behavior changes. Consumer migration is
  admitted only after a selected root-sized edge has an owned fact and a DoD
  proving that a legacy consumer reads that fact in shadow/parity mode or that
  the old edge is refuted. Cleanup requires `CodePathStatus` and a protecting
  falsifier. Consolidation must retire, merge, or mark stale an older
  report/gate or historical next-step paragraph; otherwise it is just another
  report slice. No two consecutive report-only slices are allowed unless the
  second one removes or refutes a previous report surface. This is not a
  behavior fix and not a green `s2b`/`s3b` claim.

- 2026-07-01 UPDATE: implemented Slice 0k-AM,
  behavior-neutral `CallMaterializationTransaction` contract consumer for the
  selected 0k-AJ transaction/emission edge. HIR now stores
  `MaterializationTransactionContract` facts by transaction id; HIR-to-MIR
  attaches `MaterializationContractFacts` to transaction-bound `Call` and
  `ExternCall`; backend `[MAT_EMIT]` rows print those contract fields
  mechanically; optimizer call replacement preserves both transaction id and
  contract metadata. No emitted call target, body materialization, backend
  forwarder, requested-name policy, target keepalive policy, ambient-map policy,
  `NamedTuple`/`Tuple` rendering, or `BlockOwner` carrier changed. Fresh
  generated-stage evidence with a fresh stage1 reports
  `classifier_classification=reached_tx_and_emit`, `mat_tx_rows=735`,
  `mat_emit_rows=173`, `transaction_bound_emit_rows=68`,
  `candidate_selected_rows=0`, `contract_consumer_rows=2`,
  `candidate_contract_consumer_rows=2`, `contract_mismatch_rows=0`,
  `selection_status=eligible_contract_consumer_state`, and
  `post_consumer_state=selected_consumed_by_contract_consumer`. Full suites pass
  `152/152 + 36/36`. The 0k-AJ selected edge is now consumed, not a behavior
  fix target. Next admitted slice: select the next reached transaction/emission
  edge, likely by splitting the broad exact-contract missing-body residual
  (`other_missing_body_rows=14`) into a root-sized class before any behavior
  change. Do not add backend forwarders, keep target bodies alive, force
  requested names, normalize `NamedTuple`/`Tuple`, globally change ambient-map
  policy, patch the segfault directly, or roll back `BlockOwner`.

- 2026-07-01 UPDATE: implemented Slice 0k-AL,
  executable post-consumer state gate for the generated-stage transaction edge
  selector. `scripts/generated_stage_transaction_edge_selection_report.sh` now
  prints `post_consumer_state` and supports
  `REQUIRE_POST_CONSUMER_STATE=<state>` so the old 0k-AJ selected edge can be
  classified as `selected_not_consumed`,
  `selected_consumed_by_contract_consumer`, or `selected_refuted_or_stale`
  after a future consumer migration. Synthetic ledger checks covered all three
  states. Fresh generated-stage evidence with a fresh stage1 reports
  `classifier_classification=reached_tx_and_emit`, `mat_tx_rows=591`,
  `mat_emit_rows=69`, `transaction_bound_emit_rows=29`,
  `candidate_selected_rows=4`, `candidate_selected_distinct_txs=3`,
  `contract_consumer_rows=0`, `candidate_contract_consumer_rows=0`,
  `contract_mismatch_rows=0`,
  `selection_status=eligible_reached_transaction_emission_edge`, and
  `post_consumer_state=selected_not_consumed`. Next admitted production slice:
  implement the behavior-neutral `CallMaterializationTransaction` contract
  consumer for the selected edge and prove
  `REQUIRE_POST_CONSUMER_STATE=selected_consumed_by_contract_consumer` with
  zero contract mismatches. Do not add backend forwarders, keep target bodies
  alive, force requested names, normalize `NamedTuple`/`Tuple`, globally change
  ambient-map policy, patch the segfault directly, or roll back `BlockOwner`.

- 2026-07-01 UPDATE: added Slice 0k-AK, docs-only architecture
  stop/checkpoint after the 0k-AJ reached-edge selector. An uncommitted
  behavior-neutral shadow-consumer WIP that propagated
  `CallMaterializationTransaction` contract facts into MIR call/extern-call
  instructions and backend `[MAT_EMIT]` rows was intentionally removed before
  commit. It was directionally aligned with Phase 2b, but it changed the old
  selector's meaning before the SDD defined the post-consumer success states.
  Decision: the next production slice must first refresh the
  `CallMaterializationTransaction` row's DoD and explicitly classify the old
  selected edge as `selected_not_consumed`,
  `selected_consumed_by_contract_consumer`, or `selected_refuted_or_stale`.
  Do not make `REQUIRE_SELECTED=1` green by redefining rows after the fact; do
  not add backend forwarders, keep target bodies alive, force requested names,
  normalize `NamedTuple`/`Tuple`, globally change ambient-map policy, patch the
  segfault directly, or roll back `BlockOwner`.

- 2026-07-01 UPDATE: implemented Slice 0k-AJ,
  generated-stage transaction/emission edge selection gate. New script:
  `scripts/generated_stage_transaction_edge_selection_report.sh`. It consumes
  either an existing classifier `LOG_FILE` or a fresh
  `scripts/generated_stage_transaction_spine_classifier.sh` run, joins
  transaction-bound `[MAT_EMIT]` rows back to `[MAT_TX]` transaction metadata,
  and selects exactly the reached contract class
  `call_materialization.wrapper_or_call_remap.extern_missing_body`:
  `required_contract=wrapper_or_call_remap`,
  `symbol_relation=body_eq_target_call_eq_requested`,
  `identity_status=rejected_mismatch`, backend `kind=extern`, and
  `body_present=0`. Measured fresh generated-stage result:
  `classifier_classification=reached_tx_and_emit`, `mat_tx_rows=604`,
  `mat_emit_rows=69`, `transaction_bound_emit_rows=29`,
  `candidate_selected_rows=4`, `candidate_selected_distinct_txs=3`,
  `candidate_selected_owner_kinds=2`, `candidate_selected_branch_kinds=1`,
  `source_shape=eligible_reached_edge`, and
  `selection_status=eligible_reached_transaction_emission_edge`. The gate is
  fail-closed: lowering `MAX_SELECTED_ROWS` to `3` rejects the same log as
  `selected_edge_too_wide`. Next admitted production slice: a behavior-neutral
  shadow/parity consumer for this selected transaction contract edge, proving
  how `CallMaterializationTransaction.required_contract`, `body_symbol`, and
  `call_symbol_hint` should own the old backend extern-emission-from-call-hint
  authority. Do not implement backend forwarders, keep target bodies alive,
  force requested names, normalize `NamedTuple`/`Tuple`, globally change
  ambient-map policy, or patch the segfault directly from this gate.

- 2026-07-01 UPDATE: implemented Slice 0k-AI,
  generated-stage transaction-spine classifier. New script:
  `scripts/generated_stage_transaction_spine_classifier.sh`. It builds a fresh
  stage1 compiler unless `STAGE1_COMPILER` is provided, builds a fresh
  generated s2 through `scripts/run_safe.sh` unless `GENERATED_S2` is provided,
  compiles a full-prelude `puts 42` source with
  `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1`, and classifies transaction-spine
  reachability as `reached_tx_and_emit`, `tx_only_no_emit`, `no_tx_rows`,
  `s2_build_fails`, or `stage1_build_fails`. Measured result on fresh current
  source: `s2_build_rc=0`, `compiler_rc=139`, `mat_id_rows=615`,
  `mat_tx_rows=615`, `mat_emit_rows=69`,
  `transaction_bound_mat_emit_rows=29`, `stub_rows=0`, and
  `classification=reached_tx_and_emit`. Decision: the current generated-stage
  full-prelude frontier does reach the `CallMaterializationTransaction` spine
  and transaction-bound emitted-call rows before the segfault. Next admitted
  production slice: select a reached transaction/emission edge with a red/green
  source-shape gate, then migrate exactly one selected reached edge in
  shadow/parity mode if the gate is root-sized. Do not patch the segfault,
  add backend forwarders, force requested names, keep target bodies alive,
  normalize `NamedTuple`/`Tuple`, change ambient-map policy globally, roll back
  `BlockOwner`, or continue generic residual-edge reduction without naming the
  reached edge.

- 2026-07-01 UPDATE: implemented Slice 0k-AH,
  `CallMaterializationTransaction` instance-symbol consumer promotion in
  shadow/parity mode. The selected `lower_function_if_needed` instance-method
  override, keepalive, and diagnostic materialization-symbol consumers now read
  from `CallMaterializationTransaction` fields instead of direct
  `MaterializationSymbolBinding` field reads. `CallMaterializationTransaction`
  now carries `override_symbol : String?` so the body-lowering override can
  preserve the previous nil-vs-string semantics. `MaterializationSymbolBinding`
  remains a parity input inside transaction construction, not the downstream
  authority for the selected consumer group. The 0k-AH gate is green:
  `REQUIRE_PROMOTED=1
  scripts/call_materialization_transaction_consumer_selection_report.sh`
  reports `preferred_source_shape=already_promoted_shadow`,
  `transaction_field_read_count=6`, and
  `selected_binding_consumer_count=0`. The broader transaction gate remains
  green with `symbol_binding_field_read_count=0`,
  `transaction_field_read_count=6`, and `residual_legacy_edge_count=20`; the
  older symbol-binding gate now accepts the forward transaction path with
  `binding_transaction_count=3`. Verification: fresh stage1 build to
  `/private/tmp/adamas_0kah_stage1`; transaction-consumer, transaction,
  symbol-binding, InvocationContext, MethodNameCodec, semantic census, and
  CodePathStatus gates run; `scripts/materialization_identity_ledger_smoke.sh`
  and `scripts/materialization_transaction_report.sh` run; full suites pass
  `152/152 + 36/36`; fresh stage1 builds fresh generated s2; generated s2
  compiles and runs a no-prelude `x = 1; puts x` smoke. This is not a compiler
  behavior fix and not green full-prelude `s2b`/`s3b` evidence. Next work:
  select the next transaction consumer with a red/green source-shape gate, or
  run generated-stage classification only if it answers the transaction-spine
  yes/no question. Consider whether future transaction broadening needs a
  cheaper owner-core/debug-payload split before more default-path fields are
  added. Do not add backend forwarders, force requested names, keep target
  bodies alive, normalize `NamedTuple`/`Tuple`, change ambient-map policy
  globally, or roll back `BlockOwner`.

- 2026-07-01 UPDATE: added Slice 0k-AG,
  `CallMaterializationTransaction` transaction-consumer stop-rule and
  next-edge selection gate. New script:
  `scripts/call_materialization_transaction_consumer_selection_report.sh`.
  It selects `lower_function_if_needed.instance_symbol_consumers` as the next
  transaction edge because the instance branch already constructs
  `CallMaterializationTransaction` records but still lets selected consumers
  bypass them through `MaterializationSymbolBinding` fields. Current measured
  red signal: `preferred_source_shape=legacy_instance_symbol_consumers`,
  `transaction_constructor_count=3`, `transaction_field_read_count=0`,
  `instance_override_binding_count=2`, `keepalive_binding_count=3`,
  `regmat_binding_count=1`, and `selected_binding_consumer_count=6`.
  `REQUIRE_PROMOTED=1
  scripts/call_materialization_transaction_consumer_selection_report.sh`
  intentionally exits 9 until the selected override, keepalive, and diagnostic
  materialization-symbol consumers read from `CallMaterializationTransaction`
  fields in shadow/parity mode. This is a docs/tool selection slice only; it is
  not a compiler behavior fix and not green `s2b`/`s3b` evidence. Next code
  slice: migrate exactly this selected consumer group to transaction fields
  while preserving emitted behavior. Do not run generated-stage crash
  classification unless it answers a transaction-spine yes/no question; do not
  add backend forwarders, force requested names, keep target bodies alive,
  normalize `NamedTuple`/`Tuple`, change ambient-map policy globally, or roll
  back `BlockOwner`.

- 2026-07-01 UPDATE: implemented Slice 0k-AF,
  `CallMaterializationTransaction` ledger-consumer promotion in shadow/parity
  mode. `src/compiler/hir/ast_to_hir.cr` now has a
  `CallMaterializationTransaction` owner record and
  `call_materialization_transaction(...)` helper carrying request name parts,
  requested/target/body/call symbols, selected definition and owner, state
  scope, target map, call arg shape, ABI shape, wrapper/forwarder contract, and
  rejection reason for the materialization identity/state-scope ledger path.
  The three old split-argument `log_materialization_identity_ledger(...)` calls
  are gone; `log_call_materialization_transaction_ledger(transaction)` reads the
  record instead. The 0k-AF gate is green:
  `REQUIRE_PROMOTED=1
  scripts/call_materialization_transaction_admission_report.sh` reports
  `preferred_source_shape=already_promoted_shadow`,
  `transaction_type_count=3`, `transaction_helper_count=3`,
  `legacy_ledger_call_count=0`, `transaction_ledger_call_count=3`,
  `ledger_transaction_field_read_count=4`, and
  `residual_legacy_edge_count=26`. The older
  `MaterializationSymbolBinding` gate was updated to accept this forward
  migration path and reports `binding_transaction_count=3`. This preserves
  emitted behavior and is not a green `s2b`/`s3b` claim. Verification: fresh
  stage1 build to `/private/tmp/adamas_0kaf_stage1`; transaction,
  symbol-binding, InvocationContext, MethodNameCodec, semantic census, and
  CodePathStatus gates run; `scripts/materialization_identity_ledger_smoke.sh`
  and `scripts/materialization_transaction_report.sh` run; full suites pass
  `152/152 + 36/36`. Next work: either select another transaction consumer with
  a red/green source-shape gate, or run generated-stage classification only if
  it answers the transaction-spine yes/no question under one transaction id. Do
  not flip requested/target/body symbols, add backend forwarders, force
  requested names, keep target bodies alive, normalize `NamedTuple`/`Tuple`,
  change ambient-map policy globally, or roll back `BlockOwner`.

- 2026-07-01 UPDATE: implemented Slice 0k-AE,
  `CallMaterializationTransaction` source-shape admission gate. New script:
  `scripts/call_materialization_transaction_admission_report.sh`. It selects
  `lower_function_if_needed.call_materialization_transaction` and currently
  reports `preferred_source_shape=legacy_split_transaction_edge`,
  `selection_status=eligible_transaction_spine_owner`,
  `transaction_type_count=0`, `transaction_helper_count=0`,
  `split_state_key_count=1`, `split_target_count=1`,
  `ambient_state_scope_consumer_count=1`, `legacy_ledger_call_count=3`,
  `direct_type_param_scope_count=5`, `direct_body_lowering_count=12`,
  `symbol_binding_field_read_count=24`, and `transaction_field_read_count=0`.
  `REQUIRE_PROMOTED=1
  scripts/call_materialization_transaction_admission_report.sh` intentionally
  exits 9 until a future shadow/parity owner record removes the selected seam's
  direct split-transaction authority. This is not a compiler behavior fix and
  not `s2b`/`s3b` progress by itself. Next code slice: implement a
  behavior-neutral `CallMaterializationTransaction` record/helper for exactly
  this selected seam while preserving emitted behavior, then make one selected
  consumer read that record. Do not add another transaction report, generated
  crash probe, backend forwarder, requested-name force, target keepalive,
  `NamedTuple`/`Tuple` normalization, global ambient-map predicate change, or
  `BlockOwner` rollback.

- 2026-07-01 UPDATE: paused production-code and generated-stage crash pursuit
  after the 0k-AC `InvocationContext` seam. Slice 0k-AD is now a docs-only
  architecture selection checkpoint: the next correctness axis is the vertical
  `CallMaterializationTransaction` spine, not another seam chosen from the
  latest generated-stage stack. The owned fact must join request name parts,
  requested symbol, selected definition, state scope, target symbol,
  materialization key/body symbol, emitted call symbol, callsite arg types,
  target type-param map, ABI shape, and wrapper/forwarder status. Next
  executable work is Slice 0k-AE: add a red/green source-shape admission gate
  for exactly one legacy consumer that still obtains those facts from split
  locals, rendered strings, or ambient maps instead of from one owner record.
  Do not run another generated-stage diagnostic unless it answers a named
  transaction-spine yes/no question; do not implement backend forwarders,
  requested-name forcing, target keepalive, `NamedTuple`/`Tuple` rendering
  normalization, global ambient-map predicate changes, or any `BlockOwner`
  rollback from this checkpoint.

- 2026-07-01 UPDATE: implemented Slice 0k-AC,
  `InvocationContext` shadow/parity promotion. The selected
  `lower_super.previous_def.invocation_context` seam now has an
  `InvocationContext` owner fact carrying current owner class, method name,
  class-vs-instance bit, super-source module, function name, and legacy
  forwardable argument ids. `lower_super` and `lower_previous_def` consume this
  owner fact instead of directly reading `@current_class`, `@current_method`,
  `@current_method_is_class`, `@current_super_source_module`, or
  `current_method_forward_arg_ids(ctx)`. `REQUIRE_PROMOTED=1
  scripts/invocation_context_admission_report.sh` is green with all selected
  direct ambient counts at zero. Verification: fresh stage1 builds;
  InvocationContext, MaterializationSymbolBinding, MethodNameCodec, semantic
  census, and CodePathStatus gates run; full suites pass `152/152 + 36/36`.
  This is not a super/previous-def behavior fix and not a green `s2b`/`s3b`
  claim. Next work must either run a fresh generated-stage owner-boundary
  classification after this shadow migration or select another active-board row
  with a red/green gate; do not add another context ledger, patch `lower_super`,
  reset inline-yield stacks, or treat the green source-shape gate as bootstrap
  completion.

- 2026-07-01 UPDATE: implemented the executable Slice 0k-AB source-shape gate
  for the `InvocationContext / InlineYieldFrame` boundary. New script:
  `scripts/invocation_context_admission_report.sh`. It selects
  `lower_super.previous_def.invocation_context` and currently reports
  `preferred_source_shape=legacy_ambient_context_edge`,
  `selection_status=eligible_invocation_context_owner`,
  `ambient_owner_method_count=4`, `ambient_kind_count=2`,
  `ambient_super_source_count=9`, `direct_forward_policy_count=2`, and
  `invocation_helper_count=0`. `REQUIRE_PROMOTED=1
  scripts/invocation_context_admission_report.sh` intentionally exits 9 until a
  future shadow/parity helper removes the selected seam's direct ambient
  authority. This is not a compiler behavior fix and not `s2b`/`s3b` progress by
  itself. Next code slice: implement the helper so `lower_super` /
  `lower_previous_def` consume explicit invocation-frame owner facts while
  returning legacy behavior.

- 2026-07-01 UPDATE: paused the post-0k-Z `lower_super` / inline-yield
  diagnostic direction before it became another report ladder. A local
  `SUPER_CTX`-style env ledger WIP was classified as non-admitted
  report-surface growth and removed: it did not first name the decision
  question, source-shape gate, owner fact, or cleanup rule required by
  `docs/compiler_architecture_sdd.md`. The next admitted movement is docs Slice
  0k-AA: design the `InvocationContext / InlineYieldFrame` boundary and then add
  a red/green source-shape gate, not a direct `lower_super` guard. Future code
  must prove one selected consumer seam stops treating ambient invocation state
  (`@current_class`, `@current_method`, class-vs-instance state, source module,
  inline-yield/proc/block frame stacks, and current function params) as its only
  authority before any behavior change. Do not re-add `ADAMAS_SUPER_CALL_CONTEXT`
  style logging, patch super argument forwarding, reset inline-yield state, or
  claim `s2b`/`s3b` progress from this docs-only checkpoint.

- 2026-07-01 UPDATE: implemented Slice 0k-Z,
  `MaterializationSymbolBinding` shadow/parity promotion. The selected
  `lower_function_if_needed.symbol_binding` seam now owns requested, target,
  materialization state key, body, call-symbol hint, override symbol, and
  override reason in one record. The old inline materialized-name and override
  branches are gone from `lower_function_if_needed_impl`; keepalive and
  materialization-ledger consumers read binding fields instead of recomputing
  split locals. `REQUIRE_PROMOTED=1
  scripts/materialization_symbol_binding_admission_report.sh` is green.
  Verification: fresh stage1 builds; source-shape, MethodNameCodec,
  materialization transaction, materialization promotion-selection, semantic
  census, and CodePathStatus census gates run; full suites pass `152/152 +
  36/36`; fresh stage1 builds fresh s2; generated s2 no-prelude smoke compiles
  and runs `x = 1` with output `1`. Residual boundary: generated s2
  full-prelude smoke still exits 139 after `pass3 after lower_main call`, so
  this is not a green `s2b`/`s3b` claim. Next work must classify that residual
  with fresh generated-stage evidence or choose another active-board owner
  seam; do not jump to backend rescue / keepalive / remangle / tuple-rendering
  patches.

- 2026-07-01 UPDATE: added the red/green source-shape gate for the selected
  Slice 0k-X implementation seam:
  `scripts/materialization_symbol_binding_admission_report.sh`. Current source
  reports `source_shape=legacy_split_edge` and
  `selection_status=eligible_symbol_binding_owner`; `REQUIRE_PROMOTED=1`
  intentionally exits nonzero until the future `MaterializationSymbolBinding`
  helper is consumed by downstream keepalive/ledger symbol users. The next
  production code slice must turn this exact gate green through authority
  migration, not by adding another report, backend rescue, target keepalive
  patch, remangle patch, `NamedTuple`/`Tuple` rendering change, ambient-map
  policy change, or `BlockOwner` rollback.

- 2026-07-01 UPDATE: selected the next implementation receipt without editing
  compiler behavior. Slice 0k-X chooses
  `MaterializationIdentity / lower_function_if_needed.symbol_binding` as the
  next code unit. The old edge is the split inline logic that independently
  computes `materialized_name`, `override`, keepalive target, and
  materialization call-symbol hints. The future owned fact is a
  `MaterializationSymbolBinding`-style helper/record carrying requested,
  target, materialized body, override/call hint, state-scope, target-map,
  call-arg, ABI, and keepalive facts in one place while returning legacy
  behavior. The next production code slice must first add a red/green
  source-shape gate for that seam and stop if it only adds another report.
  Acceptance is stronger than "record exists": downstream consumers must read
  body/call/keepalive symbols from the binding record, while legacy branches
  may remain only inside the helper as parity or implementation details.

- 2026-07-01 UPDATE: paused production-code and report-surface work after the
  `MethodNameCodec` 0k-V shadow helper. A local
  `scripts/method_name_codec_promotion_report.sh` scratch was classified as
  stale/non-admitted and removed because it only wrapped the existing
  `ADAMAS_METHOD_NAME_CODEC_PROMOTION_LEDGER=1` rows without naming the SDD
  decision it would unblock or reducing another authority edge. Current work
  remains governed by `docs/compiler_architecture_sdd.md`: the next slice must
  present a concrete implementation receipt (`old_edge`, `owned_fact`,
  `decision_question`, red/green gate, generated-stage boundary, cleanup rule)
  before production code or a new committed report is admitted. Do not claim
  s2b/s3b progress from this docs-only pause.

- 2026-07-01 UPDATE: switch the active path from unbounded bootstrap
  symptom-fixing to implementation of the architecture SDD. A parse-path
  identity WIP showed useful evidence (`s2` loaded 138 raw paths that
  canonicalize to 75 files; stage1 loaded 75/75, and the WIP reduced generated
  s2 registration to `modules=224`, `classes=146`), but it did not pass the
  bootstrap DoD: fresh s2 still timed out after `pass3 after lower_main call`.
  That evidence is now classified as a `NameResolution/file identity` boundary
  signal, not a shipped fix. Current work must follow
  `docs/compiler_architecture_sdd.md`: Phase 0b transition gate, Phase 1
  semantic decision census, Phase 1b dead-code/workaround census, then dynamic
  owner ledgers before further behavior-changing fixes. First executable slice:
  `scripts/semantic_decision_census.sh` (read-only static owner-map input).

- 2026-07-01 UPDATE: first dynamic owner ledger slice landed locally after the
  static census gate. `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1` now emits
  `[MAT_ID]` rows at the `lower_function_if_needed_impl` materialization seam,
  including requested symbol, target symbol, materialization state key,
  body symbol, call-symbol hint, override reason, lookup branch, ambient
  type-param map, target map, and call arg types. Verification:
  `crystal build src/adamas.cr -o /private/tmp/adamas_matid_stage1
  --error-trace`; `scripts/materialization_identity_ledger_smoke.sh
  /private/tmp/adamas_matid_stage1`; `regression_tests/run_all_suites.sh
  /private/tmp/adamas_matid_stage1 4` passes `152/152 + 36/36`. This is
  behavior-neutral instrumentation only; next behavior-changing bootstrap fix
  must first use this ledger (or a sibling owner ledger) to classify the active
  mismatch.

- 2026-07-01 UPDATE: the active frontier was reclassified before another
  behavior fix. A fresh stage1 built a fresh s2, and s2->s3 with
  `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1` produced zero `[MAT_ID]` rows
  because the generated compiler hit the 4GB safe-wrapper cap during
  parse/register (`top-level collection done defs=80 classes=124 modules=271`,
  last `module register idx=201/271`). That means the materialization seam is
  not yet reached. Added `scripts/parse_path_identity_probe.sh` as a
  behavior-neutral NameResolution/file-identity gate. Verification:
  `bash -n scripts/parse_path_identity_probe.sh`; with the same fresh stage1,
  the probe reports `raw=75 canonical=75` and `PASS parse_path_identity`; with
  fresh generated s2, the probe intentionally fails with
  `DUPLICATE_PATH_IDENTITY raw=138 canonical=75` and prints duplicate raw
  aliases for files such as `frontend/ast.cr`, `frontend/span.cr`, and
  `frontend/string_pool.cr`. Next behavior-changing work must make this gate
  green for generated s2 or refute file identity as the active boundary with
  newer evidence.

- 2026-07-01 UPDATE: fixed the generated-s2 parse path identity boundary.
  `parse_file_recursive` now runs every loaded source path through a dedicated
  `source_file_identity_key` that collapses lexical `.` / `..` path segments
  before using it as the `loaded_files` key, and require fallback checks compare
  through the same key. This is deliberately scoped to loaded source-file
  identity; it does not change `path_join`, overload resolution,
  materialization, or backend lowering. Verification:
  `crystal build src/adamas.cr -o /private/tmp/adamas_pathid_stage1
  --error-trace`; `scripts/parse_path_identity_probe.sh
  /private/tmp/adamas_pathid_stage1` reports `raw=75 canonical=75`; fresh
  stage1 builds fresh s2; `scripts/parse_path_identity_probe.sh
  /private/tmp/adamas_pathid_s2` now reports `raw=75 canonical=75`;
  `regression_tests/run_all_suites.sh /private/tmp/adamas_pathid_stage1 4`
  passes `152/152 + 36/36`; generated s2 compiles and runs a no-prelude
  `x = 1` smoke. Residual frontier: generated s2 full-prelude `x = 1` still
  exits 139 after allocator flush / LLVM emission fallback, and generated
  s2->s3 with the materialization ledger now reaches 11 `[MAT_ID]` rows before
  crashing in `NodeSlot#node <- AstArena#[] <- AstToHir#lower_call` while
  draining missing call targets. Do not claim green s2/s3.

- 2026-07-01 UPDATE: paused before another `lower_call` behavior patch and
  added an architecture gate for the residual `NodeSlot#node <- AstArena#[]`
  frontier. The next slice is `AstNodeIdentity / ArenaOwnership`: an `ExprId`
  index is not a global node identity, and `expr_id.index < arena.size` is only
  a containment heuristic. Added `scripts/arena_ownership_census.sh` and wired
  the main semantic census to report arena-owner surfaces. Added the
  env-gated dynamic lower-call arena ledger
  (`ADAMAS_LOWER_CALL_ARENA_LEDGER=1`) plus
  `scripts/lower_call_arena_ledger_smoke.sh` to prove the ledger channel on a
  no-prelude call without generated compiler artifacts. Next behavior-changing
  `lower_call` work must first run that ledger on the failing generated-s2
  callsite: current arena, preferred/call arena, resolved owner, `ExprId`, and
  raw-read site, without dereferencing the crashing node slot. If that row
  shows stale/corrupt `ExprId` or `NodeSlot` producer corruption instead of
  arena drift, patch the producer, not the `lower_call` consumer. Fresh
  ledger evidence from generated s2->s3 produced `475` `[LC_ARENA]` rows and
  `11` `[MAT_ID]` rows before the residual `EXIT 139`; the last lower-call
  row before the crash was `Adamas::Compiler::CLI#run$IO_IO`
  `before.member_object_read`, with current, preferred, and heuristic owner
  all pointing at the same `src/compiler/cli.cr` arena and all reporting
  `*_has=1`. This does not prove the root, but it refutes a simple
  current-arena-drift explanation for that last observed edge and raises the
  priority of an explicit `AstNodeRef`/`ArenaOwnership` facade over another
  broad `arena_for_expr?` consumer patch.

- 2026-07-01 UPDATE: added the first behavior-neutral `AstNodeRef`
  shadow facade for the ArenaOwnership slice. `AstNodeRef` is deliberately a
  reference type because generated-stage binaries have already shown fragile
  copies of structs carrying `ArenaLike` unions. The lower-call arena ledger now
  records explicit owner-scoped refs (`ref_origin`, `ref_path`, `ref_span`) in
  addition to current arena, preferred/ref arena, and heuristic owner arena.
  The facade is not consumed by lowering and raw `@arena[...]` reads are still
  untouched. Next behavior-changing AST-read work is still blocked: first add
  a parity/classification report that compares current arena, explicit
  `AstNodeRef` owner, and heuristic owner at each raw-read site; if they keep
  agreeing at the crash edge, move to `NodeSlot`/arena storage producer
  corruption instead of arena-selection fixes.

- 2026-07-01 UPDATE: added `scripts/lower_call_arena_parity_report.sh`, the
  read-only parity/classification gate for the `AstNodeRef` shadow facade. It
  runs with `ADAMAS_LOWER_CALL_ARENA_LEDGER=1`, accepts nonzero compiler exit
  as reportable data when ledger rows exist, and buckets each lower-call expr
  row into current/ref/heuristic owner agreement or divergence. Baseline
  no-prelude smoke reports `phase_rows=5`, `expr_rows=3`, and
  `agree_all_have=3`. Next generated-stage work must run this report on the
  s2->s3 crash corridor before any raw `@arena[...]` consumer is routed through
  `AstNodeRef`.

- 2026-07-01 UPDATE: ran the lower-call arena parity report on a fresh
  generated s2 compiling `src/adamas.cr` to s3. Fresh stage1 built fresh s2
  under `scripts/run_safe.sh` (`EXIT: 0` after ~178s). The s2->s3 parity report
  returned `compiler_rc=139`, `phase_rows=265`, `expr_rows=210`,
  `agree_all_have=210`, and zero current/ref/heuristic divergence buckets. The
  last expr row before the crash was `Adamas::Compiler::CLI#run$IO_IO`
  `before.member_object_read` with current arena, explicit `AstNodeRef` owner,
  and heuristic owner all equal to `src/compiler/cli.cr` and all `*_has=1`.
  This refutes arena-selection/current-arena drift as the root for the
  instrumented crash edge. Next work should instrument `NodeSlot`/arena storage
  producer/read integrity or find an uninstrumented raw read, not add another
  `lower_call` arena consumer patch.

- 2026-07-01 UPDATE: hardened the architecture stop-rule before further code
  changes. `docs/compiler_architecture_sdd.md` is now the active bootstrap
  control surface, not a post-bootstrap wish list.
  `docs/compiler_refactor_architecture_plan.md` is reference-only for
  near-term work and no longer
  recommends starting the current bootstrap objective with the LLVM writer.
  The next admitted implementation slice is
  `NodeSlotIntegrity / AstArenaStorage`: an env-gated, behavior-neutral ledger
  that reports arena owner, `ExprId`, slot initialization/presence, safe
  node-kind/span facts when available, and read site before the crashing
  `NodeSlot#node` dereference. Forbidden next moves: lower-call arena routing,
  broad arena scans, parser allocation rewrites, or behavior fixes that do not
  name the first bad transition.

- 2026-07-01 UPDATE: implemented the behavior-neutral
  `NodeSlotIntegrity / AstArenaStorage` ledger and report. `AstArena`,
  `VirtualArena`, and `PageArena` now expose debug-only node-address facts,
  and `ADAMAS_NODE_SLOT_LEDGER=1` emits `[NODE_SLOT]` rows at the existing
  lower-call raw-read trace points. `scripts/node_slot_integrity_report.sh`
  summarizes healthy/missing/out-of-range/null buckets and accepts nonzero
  compiler exit when rows exist. Verification: fresh stage1 builds; no-prelude
  report emits `rows=9 healthy_present=9`; default env-off no-prelude compile
  emits no `[NODE_SLOT]`; fresh stage1 builds fresh s2 (`EXIT: 0` after
  ~183s); fresh s2->s3 report returns `compiler_rc=139`, `rows=630`,
  `healthy_present=630`, and zero non-healthy buckets. The last crash-edge row
  remains `Adamas::Compiler::CLI#run$IO_IO before.member_object_read expr=2828`
  with `in_range=1`, `slot_present=1`, and `node_present=1`. This refutes
  missing/uninitialized slot and out-of-range `ExprId` for the instrumented
  edge. Next read-only slice should target node payload/vtable/deep-read
  integrity or the exact uninstrumented consumer after `NodeSlot#node`, not
  arena owner selection or slot existence.

- 2026-07-01 UPDATE: added the Phase 1b static `CodePathStatus` census entry
  point, `scripts/codepath_status_census.sh`. This is the architecture-side
  answer to codebase bloat and stale workaround risk: it groups debug/probe
  gates, bootstrap workaround comments, fallback/recovery paths, legacy naming
  shims, broad semantic scans, backend semantic leakage, and layout/ABI
  workaround candidates without classifying anything as live/dead/delete-ready.
  Cleanup remains blocked on a runtime census plus a protecting falsifier for
  each candidate path.

- 2026-07-01 UPDATE: paused the diagnostic ladder after the
  `NodeSlotIntegrity` slice instead of adding another unbounded payload probe.
  A local `ADAMAS_NODE_PAYLOAD_LEDGER` WIP was removed because it had no named
  SDD slice, no completed generated-stage evidence, and no cleanup rule. The
  payload/vtable/deep-read check remains an allowed future falsifier for the
  current crash corridor, but it is not the default next move. Current next
  architecture work: seal the `SemanticStateScope` / `MaterializationIdentity`
  transaction record enough that requested, selected, target, materialized, and
  emitted call symbols are one owned fact; then add a runtime
  `CodePathStatus` census before deleting stale workarounds or debug gates.
  Behavior-changing bootstrap fixes remain blocked unless they consume an
  existing owner ledger or add a surviving owner ledger/falsifier in the same
  logical change.

- 2026-07-01 UPDATE: added the behavior-neutral
  `MaterializationIdentityTransaction` pre-call ledger as Slice 0h of the
  architecture SDD. With `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER=1`, the
  materialization seam now emits structured `[MAT_TX]` rows alongside the
  existing `[MAT_ID]` rows and classifies requested/target/body/call-hint
  relations into `identity_status`, `symbol_relation`, and
  `required_contract`. `scripts/materialization_transaction_report.sh` is the
  executable report/falsifier: before this slice it fails with no `[MAT_TX]`
  rows; after the slice it reports `2513` rows on the focused stage1 repro,
  including `2504` exact rows and `9` rows requiring
  `wrapper_or_call_remap`, with `0` malformed rows. Full stage1 suites pass
  (`152/152` original + `36/36` combined). A fresh generated s2 build exits 0
  and the generated s2 can emit a no-prelude `[MAT_TX]` report with `1` exact
  row and `0` malformed rows. Residual boundary: this is a pre-call ledger
  using `call_symbol_hint`, not a backend-proven final emitted call symbol. The
  next architecture step is final-call linkage or a sibling emitted-call
  ledger, plus runtime `CodePathStatus`; do not treat this as a materialization
  forwarder fix or green `s2b`/`s3b` evidence.

- 2026-07-01 UPDATE: paused again before turning final-call linkage into the
  next diagnostic ladder. The active SDD now has Slice 0i: architecture pause
  and next-track selection. A stale uncommitted
  `scripts/emitted_call_linkage_report.sh` WIP was removed rather than carried
  forward, because a backend emitted-call report is admissible only as
  transaction-completeness evidence, not as a backend stub rescue or forwarder
  shortcut. Fresh static gates still run and show why ad hoc cleanup is unsafe:
  `scripts/semantic_decision_census.sh` reports broad owner surfaces
  (`SemanticStateScope`, `Materialization`, `CallResolution`, backend semantic
  leakage, debug/workaround gates), while `scripts/codepath_status_census.sh`
  reports broad env/debug, fallback/recovery, legacy/shim, broad-scan,
  backend-leakage, and layout/ABI candidate surfaces without classifying any
  path as live/dead/delete-ready. Current next work must explicitly choose one
  architecture track: runtime `CodePathStatus` if the goal is bloat/deletion,
  transaction-completeness if the goal is a call/materialization behavior fix,
  or a local falsifier only if fresh generated-stage evidence invalidates the
  current owner ledgers.

- 2026-07-01 UPDATE: implemented Slice 0j, the first runtime
  `CodePathStatus` ledger. `ADAMAS_CODEPATH_STATUS_LEDGER=1` now emits
  `[CODEPATH_STATUS]` rows from coarse CLI/compiler-driver branches, and
  `scripts/codepath_status_runtime_report.sh` fails closed when no rows are
  emitted. Verification on a fresh stage1: the focused no-prelude report
  produced `rows=26`, `malformed=0`, `taken=8`, `not_taken=18`; the default
  env-off no-prelude compile emitted no `[CODEPATH_STATUS]` rows; static
  semantic and CodePathStatus censuses still run; full stage1 suites passed
  (`152/152` original + `36/36` combined); a fresh generated s2 build exited
  `0`, and the generated s2 emitted the same focused report shape
  (`rows=26`, `malformed=0`). Boundary: this is runtime evidence for
  cleanup/bloat planning only. It does not mark any path `delete_ready`, does
  not alter compiler semantics, and does not make `s2b`/`s3b` green. Next
  correctness work remains the `SemanticStateScope` /
  `MaterializationIdentity` transaction-completeness path, not a backend
  forwarder or crash-stack patch.

- 2026-07-01 NEXT ARCHITECTURE SLICE: Slice 0k is design-only and names the
  next correctness track: complete the materialization transaction before any
  call/materialization behavior patch. The next implementation should upgrade
  `scripts/materialization_transaction_report.sh` or add a sibling emitted-call
  transaction report so one focused run can join requested symbol, selected
  definition, target symbol, created body symbol, emitted backend call symbol,
  state-scope authority, target map, callsite arg types, and ABI shape. It must
  classify each candidate as `exact`, `materialization_keepalive`,
  `wrapper_forwarder`, or `rejected_mismatch`. Forbidden moves remain:
  backend undefined-extern rescue as first discovery point, forced
  materialization to the requested name, global ambient-map ignore, or using
  `CodePathStatus` liveness as a substitute for semantic transaction identity.
  Hostile self-review hardened this direction: an emitted-call report is
  admissible only if it carries or joins a HIR-owned transaction identity.
  Backend rows may report the final callee and ABI shape, but the backend must
  not create, repair, or infer the semantic transaction from
  `@undefined_externs` / `@func_by_name`. The first code slice should be a
  default-off transaction-correlation channel with env-off behavior unchanged;
  if it needs broad live-target marking, source-level reconstruction in the
  backend, or backend-only stub discovery after HIR/MIR pruning, stop and pivot
  back to `SemanticStateScope` / `MaterializationRegistry`.

- 2026-07-01 UPDATE: paused behavior fixes and sharpened Slice 0k into a
  concrete preflight. The first implementation step is Slice 0k-A:
  transaction-correlation, not a forwarder. It must make the report red before
  green by requiring emitted-call correlation for HIR-owned `[MAT_TX]` rows,
  then add a default-off channel that carries a stable transaction id through
  HIR/MIR call lowering into backend mechanical `[MAT_EMIT]` facts. The gate is
  the joined transaction-bound subset only; broad backend call rows are
  diagnostics. Stop immediately if the implementation needs source-level
  reconstruction in `llvm_backend.cr`, broad live-target marking, or backend
  `@undefined_externs` as the first useful semantic signal.

- 2026-07-01 UPDATE: implemented Slice 0k-A as a behavior-neutral
  transaction-correlation channel. The report was made red first: a Slice
  0h-only compiler (`/private/tmp/adamas_txcorr_red`) failed with
  `FAIL: no [MAT_EMIT] materialization emitted-call rows emitted` while still
  producing `[MAT_TX]`. The code then added a stable `tx=` id to
  `MaterializationIdentityTransaction`, stored the HIR-owned
  call-symbol→transaction mapping on `HIR::Module`, carried optional
  `materialization_tx_id` through MIR `Call` / `ExternCall`, and made backend
  emission log only mechanical `[MAT_EMIT]` facts under the same ledger env.
  Focused stage1 report now shows `rows=2513`, `emit_rows=16995`,
  `transaction_bound_emit_rows=5332`, `joined_transactions=1349`, and
  `unjoined_emit_rows=0`; generated-s2 no-prelude report shows `rows=1`,
  `emit_rows=2`, `joined_transactions=1`, and `unjoined_emit_rows=0`.
  Env-off focused compile emits no materialization rows, and full stage1 suites
  pass `152/152 + 36/36`. This still is not a behavior fix and not green
  `s2b`/`s3b`: broad `[MAT_EMIT] tx=none` rows are diagnostic only, and the next
  behavior slice must consume a targeted joined transaction row or return to
  `SemanticStateScope` / `MaterializationRegistry` if selected-definition or
  state-authority evidence is still missing.

- 2026-07-01 UPDATE: implemented Slice 0k-B as default-off transaction owner
  fields. The report was made red first: a Slice 0k-A compiler
  (`/private/tmp/adamas_0kb_red`) still had joined `[MAT_TX]` / `[MAT_EMIT]`
  rows but failed the upgraded report with `owner_malformed=2513`. The code
  now emits `selected_def`, `state_scope`, `map_source`, and
  `materialization_action` on `[MAT_TX]` rows at the HIR materialization seam;
  backend `[MAT_EMIT]` remains mechanical. Focused stage1 report shows
  `rows=2513`, `emit_rows=16995`, `owner_malformed=0`,
  `joined_transactions=1349`, `unjoined_emit_rows=0`, `state_scope` buckets
  `callsite=871` / `target_materialization=1642`, and `map_source` buckets
  `callsite_arg_types=871`, `target_map=1165`,
  `ambient_snapshot_rejected=238`, `empty_map=239`. A generated-s2
  no-prelude report shows `rows=1`, `emit_rows=2`, `owner_malformed=0`,
  `joined_transactions=1`, and `unjoined_emit_rows=0`. Full suites pass
  `152/152 + 36/36`. This is still not a behavior fix and not green
  `s2b`/`s3b`: the next behavior slice must choose a targeted transaction row
  and run a would-change census before changing naming/materialization/backend
  behavior.

- 2026-07-01 UPDATE: paused behavior work again after the first full
  generated-s2 0k-B probe. A fresh stage1 built a fresh generated s2, but
  `scripts/materialization_transaction_report.sh` on generated s2 compiling
  full `src/adamas.cr` failed with
  `FAIL: no [MAT_EMIT] materialization emitted-call rows emitted` and
  `compiler_rc=139`. The run did emit HIR-side `[MAT_ID]` / `[MAT_TX]` rows
  through `Adamas::Compiler::CLI#run$IO_IO`, then crashed before backend
  emitted-call correlation. Interpretation: focused stage1 and generated-s2
  no-prelude transaction reports are green, but the full generated-stage
  frontier does not yet reach the emitted-call seam. Do not add another
  backend/forwarder/materialization behavior patch from this report. The next
  SDD slice must be a planning/owner-boundary slice: either make the full
  generated-stage seam reachability itself a named owner problem, or start the
  `SemanticStateScope` shadow facade that replaces ambient-map naming
  decisions with explicit authority records. `CodePathStatus` remains the
  cleanup track only.

- 2026-07-01 UPDATE: implemented the first behavior-neutral
  `SemanticStateScope` shadow ledger slice. A new
  `scripts/semantic_state_scope_report.sh` is red on pre-slice compilers with
  `FAIL: no [STATE_SCOPE] semantic state-scope rows emitted`. With
  `ADAMAS_SEMANTIC_STATE_SCOPE_LEDGER=1`, the HIR materialization seam now
  emits `[STATE_SCOPE]` rows containing transaction id, requested/target
  symbols, selected definition, explicit authority, map source,
  allowed/forbidden consumers, lifetime region, validation status, and ambient
  / target / callsite maps. The env is independent of
  `ADAMAS_MATERIALIZATION_IDENTITY_LEDGER`: state-scope reporting does not
  remember backend transaction ids or emit `[MAT_*]` rows unless the
  materialization ledger env is also enabled. Focused stage1 report shows
  `rows=2513`, `malformed=0`, `invalid_validation=0`, and
  `rejected_without_ambient=0`; default env-off focused compile emits no
  `[STATE_SCOPE]` / `[MAT_*]` rows. The existing materialization transaction
  report still passes on the same stage1 (`rows=2513`, `emit_rows=16995`,
  `owner_malformed=0`, `joined_transactions=1349`); full suites pass
  `152/152 + 36/36`; fresh stage1 builds fresh generated s2; generated-s2
  no-prelude state-scope report emits `rows=1`, `malformed=0`. This still is
  not a behavior fix and not green `s2b`/`s3b`. The next behavior slice remains
  blocked until a would-change census consumes an owner row, or until a
  full-stage seam-reachability slice names the owner boundary that prevents
  generated s2 from reaching `[MAT_EMIT]`.

- 2026-07-01 UPDATE: paused code fixes again after a fresh post-StateScope
  architecture review. The full generated-s2 state-scope corridor reaches the
  HIR materialization seam (`11` valid owned `[STATE_SCOPE]` rows) but still
  crashes before backend `[MAT_EMIT]`. lldb pins the crash to
  `NodeSlot#node <- AstArena#[] <- AstToHir#lower_call` while draining pending
  lower functions, and a fresh 8GB `NodeSlotIntegrity` report on the same
  corridor reports `rows=639`, `healthy_present=639`, and zero
  missing/out-of-range/null buckets. Interpretation: the next step is not a
  `lower_call` guard, arena scan, backend forwarder, requested-name
  materialization, global ambient-map change, or `NamedTuple`/`Tuple`
  normalization. The active next slice is Slice 0k-E in
  `docs/compiler_architecture_sdd.md`: an architecture migration contract that
  turns the existing ledgers into a concrete migration plan for
  `StateScope`, `MaterializationRegistry`, `AstNodeRef`, and `CodePathStatus`
  consumers. First executable follow-up should be a
  `StateScopeConsumerCensus` / shadow report over the known naming and
  materialization consumers (`def_has_untyped_regular_param?`,
  `raw_annotation_needs_callsite_specialization?`, type-param map helpers, and
  materialization override sites), with a would-change census before any
  behavior patch.

- 2026-07-01 UPDATE: hardened the next slice before implementation. Slice
  0k-F in `docs/compiler_architecture_sdd.md` now defines
  `StateScopeConsumerCensus` as a migration gate, not a diagnostic ladder. The
  future report must cover the known naming/materialization consumers
  (`prefer_callsite_specialization`, `lower_function_if_needed_impl`
  `callsite_args` / `suffix_types` / `override`, `lower_call` remangling, and
  the direct type-param predicates), and each reached consumer must emit a
  migration decision: `migrate_to_state_scope`,
  `migrate_to_materialization_registry`, `keep_legacy_shim`,
  `blocked_unknown`, or `rejected_ambient`. Any `diagnostic_only` or
  `blocked_unknown` row blocks behavior patches on that surface. This is
  docs-only; no compiler behavior changed. Next implementation remains the
  default-off report/ledger with red gate first, env-off behavior unchanged,
  focused stage1 evidence, existing static census gates, and no naming /
  materialization semantic change in the same commit.

- 2026-07-01 UPDATE: implemented Slice 0k-F as a behavior-neutral
  `StateScopeConsumerCensus` migration report. Red gate: a pre-slice compiler
  from `4d0965e2` fails the new report with
  `FAIL: no [STATE_SCOPE_CONSUMER] consumer rows emitted` while the focused
  compile itself exits `0`. Fresh stage1 report evidence:
  `rows=42224`, `malformed=0`, `invalid_authority=0`,
  `invalid_migration=0`, `invalid_validation=0`,
  `rejected_without_ambient=0`, with all required consumers present
  (`prefer_callsite_specialization`, `lower_function_if_needed_impl`
  `callsite_args` / `suffix_types` / `override`, `lower_call.remangle`, and
  direct predicate rows for `def_has_untyped_regular_param` /
  `raw_annotation_needs_callsite_specialization`). The report intentionally
  exposes blockers: `diagnostic_only=5935`, `keep_legacy_shim=5935`,
  `rejected_ambient=2767`, `migrate_to_state_scope=25978`, and
  `migrate_to_materialization_registry=7544`. The report now classifies every
  blocked row (`unclassified_blocked=0`) into
  `legacy_shim.concrete_typed_params=4481`,
  `legacy_shim.skipped_untyped_params=924`,
  `legacy_shim.no_regular_params=530`, and zero
  `legacy_shim.regular_untyped_param_review` rows, with bounded samples for
  each non-empty class. The skipped-untyped bucket contains splat,
  double-splat, or block untyped annotations; it is not evidence for a regular
  untyped-param predicate bug. Env-off focused compile emits no
  consumer rows and `basic_sanity` exits `0`; existing static
  `semantic_decision_census` / `codepath_status_census`, state-scope report,
  materialization transaction report, and focused split/proc reducers still
  pass; `regression_tests/run_combined.sh /private/tmp/adamas_ssc_stage1`
  passes `36/36`. A fresh generated s2 build exits `0`, but generated-s2 consumer report
  fails closed with `compiler_rc=139`, `rows=17`, and missing
  `callsite_args` / `suffix_types` consumers because the generated compiler
  crashes before those sites are reached. Next work is not a behavior patch on
  diagnostic rows: use the already-owned `migrate_to_state_scope`,
  `migrate_to_materialization_registry`, or `rejected_ambient` rows as the
  input to a bounded would-change census before changing any
  naming/materialization decision.

- 2026-07-01 UPDATE: upgraded the `StateScopeConsumerCensus` report with an
  owned-candidate / proposed owner-result preflight and immediately got a
  measured-red result that blocks naive behavior migration. The focused stage1
  report still exits `0` and remains malformed-clean
  (`owner_result_unknown=0`), but records `owned_candidate_rows=36289` and
  `owned_would_change=3779`. Owned class counts are
  `state_scope=25978`, `materialization_registry=7544`, and
  `ambient_rejected=2767`. The proposed owner-result probe is parity-clean for
  StateScope (`legacy_result_1=25978`) and ambient rejection
  (`legacy_result_0=2767`), but MaterializationRegistry is mixed:
  `legacy_result_1=3779` and `legacy_result_0=3765`. Interpretation: migration
  class alone is not a replacement rule, especially not
  `migrate_to_materialization_registry => false`. Next work must classify the
  MaterializationRegistry rows by consumer/decision/selected definition/target
  map/callsite shape before proposing a behavior patch. No naming,
  materialization, backend, AST, or StateScope behavior changed.

- 2026-07-01 UPDATE: attributed the mixed MaterializationRegistry owned rows
  instead of trying a behavior rule. The focused stage1 report still records
  `materialization_registry_rows=7544`, split as
  `legacy_result_1=3779` and `legacy_result_0=3765`. No single consumer owns
  the split: `def_has_untyped_regular_param` is `1775/1355`,
  `prefer_callsite_specialization` is `580/483`,
  `raw_annotation_needs_callsite_specialization` is `229/1055`,
  `lower_function_if_needed.override` is `566/496`, and
  `lower_call.remangle` is `629/376` for result 1/0 respectively. The strongest
  separator is selected-definition parameter class:
  `regular_untyped_params=3362/3`, `concrete_typed_params=2/2033`,
  `no_regular_params=4/572`, with mixed `short_type_params=273/895` and
  `skipped_untyped_params=138/262`. All rows have `target_map_present`; call
  arg shape remains mixed. Next SDD work: define a MaterializationRegistry
  contract for selected-definition parameter classes and their exceptions
  before any consumer/naming/materialization behavior patch.

- 2026-07-01 UPDATE: converted the post-0k-F tail-chase risk into Slice 0k-G
  in `docs/compiler_architecture_sdd.md`. This is a docs-only checkpoint, not
  a behavior fix. The active next implementation is now a behavior-neutral
  `MaterializationDecision` shadow record/report owned by
  `MaterializationRegistry`. It must carry requested symbol, selected
  definition, target symbol, state-scope authority, callsite arg types,
  target map, and ABI shape, and classify each row as `exact`,
  `callsite_specialized`, `target_materialized`, `wrapper_required`,
  `legacy_shim`, or `rejected_mismatch`. It must fail closed when required
  fields or owners are missing, and any later behavior consumer must run a
  bounded would-change census before changing naming, remangling, keepalive, or
  forwarder behavior. Rejected next moves remain direct patches to
  `def_has_untyped_regular_param?`, `raw_annotation_needs_callsite_specialization?`,
  materialization override, `lower_call` remangling, backend undefined-extern
  rescue, forced requested-name materialization, `NamedTuple`/`Tuple`
  display-string normalization, or rolling `BlockOwner` back to tuple or
  namedtuple metadata.

- 2026-07-01 UPDATE: implemented Slice 0k-G as a behavior-neutral
  `MaterializationDecision` shadow ledger/report. Red gate: after adding the
  report but before compiler instrumentation, `/private/tmp/adamas_matdec_red`
  failed with `FAIL: no [MAT_DECISION] materialization decision rows emitted`
  and `compiler_rc=0`. With `ADAMAS_MATERIALIZATION_DECISION_LEDGER=1`, the HIR
  naming/materialization consumer seam now emits `[MAT_DECISION]` rows only for
  `migrate_to_materialization_registry` candidates. Focused stage1 report:
  `rows=7544`, `malformed=0`, `invalid_decision=0`, `invalid_owner=0`,
  `invalid_reason=0`, `invalid_legacy_result=0`,
  `invalid_would_change=0`, `would_change_rows=0`,
  `legacy_shim_rows=891`, and `rejected_rows=0`; decision buckets are
  `exact=2311`, `callsite_specialized=2245`,
  `target_materialized=2097`, and `legacy_shim=891`. Existing
  `StateScopeConsumer`, `SemanticStateScope`, and materialization transaction
  reports still compose; env-off compile emits no `[MAT_DECISION]` rows and
  the tiny binary exits `0`; static semantic/codepath censuses run; full suites
  pass `152/152 + 36/36`. Fresh generated s2 builds, but the generated compiler
  still does not reach the focused `[MAT_DECISION]` seam before its existing
  crash (`compiler_rc=139`), and a tiny no-prelude source compiles with no rows
  because it does not reach MaterializationRegistry candidates. This remains a
  behavior-neutral architecture slice, not a materialization fix or green
  `s2b`/`s3b`. Next behavior work must choose an owned decision row and run a
  bounded would-change census; otherwise continue seam-reachability or cleanup
  architecture work.

- 2026-07-01 UPDATE: paused again after a hostile promotion review. Slice 0k-G
  is useful, but it is still a shadow ledger; adding a new ledger after every
  refuted local hypothesis is now classified as diagnostic tail-chasing unless
  the slice promotes an owner fact into a consumer seam, classifies an existing
  path through `CodePathStatus`, or refutes the current owner evidence with
  fresher generated-stage data. `docs/compiler_architecture_sdd.md` now has
  Slice 0k-H, the `MaterializationDecision` promotion gate. The next admitted
  implementation is behavior-neutral: expose the `MaterializationDecision`
  owner object/helper to exactly one naming/materialization consumer in
  shadow/parity mode, with legacy behavior unchanged and a bounded
  would-change census. Fresh focused generated-s2 recheck still does not
  justify a local crash fix: `materialization_decision_report` emits no
  `[MAT_DECISION]` rows and exits with `compiler_rc=139`; the same corridor's
  `NodeSlotIntegrity` report shows `rows=105 healthy_present=105` with zero
  bad buckets, and lower-call arena parity shows `expr_rows=35
  agree_all_have=35` with zero owner divergence. Forbidden next moves remain:
  lower-call/arena/slot consumer patches, backend undefined-extern rescue,
  target keepalive/forwarder, forced requested-name materialization, global
  ambient-map ignore, `NamedTuple`/`Tuple` display normalization, or rolling
  `BlockOwner` back to tuple/namedtuple metadata.

- 2026-07-01 UPDATE: stopped the first 0k-H implementation attempt before
  committing it. The attempted direction added a dedicated promotion report/env
  around a preferred consumer, but this repeated the planning mistake the SDD
  is trying to eliminate: it chose a promoted seam before proving that the
  consumer was the correct reached owner boundary for the focused report. The
  WIP was removed and the SDD now has Slice 0k-I:
  `Promotion target selection gate`. The next executable architecture step is
  not a promotion helper and not another crash probe. It is a report over
  existing `[STATE_SCOPE_CONSUMER]` / `[MAT_DECISION]` rows that selects at
  most one `eligible_promote_owner` consumer or explicitly routes the next
  slice to `CodePathStatus` cleanup. Any promotion helper, remangle change,
  backend reconciliation, target keepalive, requested-name materialization,
  global ambient-map change, `NamedTuple`/`Tuple` normalization, or
  `BlockOwner` rollback remains forbidden until that selection gate is green.

- 2026-07-01 UPDATE: implemented Slice 0k-I as a behavior-neutral promotion
  target selection report. `scripts/materialization_promotion_selection_report.sh`
  consumes existing `ADAMAS_MATERIALIZATION_DECISION_LEDGER=1` rows; it does
  not add compiler instrumentation, a new env ledger, backend hooks, or a
  behavior change. Red gate: before the report existed, the command failed with
  `FAIL: no materialization promotion selection report exists`. Focused stage1
  evidence: fresh `/private/tmp/adamas_0ki_stage1` report emits `rows=7544`,
  `malformed=0`, `invalid_owner=0`, `invalid_legacy_result=0`,
  `invalid_would_change=0`, `eligible_count=1`, and `selected_count=1`. The
  single eligible promotion consumer is `lower_function_if_needed.override`
  (`row_count=1062`, `would_change_rows=0`). Direct predicate consumers are
  rejected as requiring their own oracle, `lower_call.remangle` is rejected as
  backend-adjacent/too late for the first promotion, and `callsite_args` /
  `suffix_types` are unreached in the focused MaterializationRegistry row set.
  Existing `materialization_decision_report`, `state_scope_consumer_report`,
  `semantic_decision_census`, and `codepath_status_census` all remain green.
  Generated-stage residual remains explicit: fresh stage1 builds fresh s2
  (`EXIT: 0`), but generated s2 still crashes before `[MAT_DECISION]` on the
  focused full-prelude report (`compiler_rc=139`); residual mode records
  `generated_stage_status=not_reached_named_residual`. Next admitted
  implementation: a narrow shadow/parity promotion helper for
  `lower_function_if_needed.override` only, preserving legacy emitted behavior.

- 2026-07-01 UPDATE: paused the first 0k-J code attempt before implementation
  and converted it into a docs-only promotion-definition gate. The removed WIP
  added a `[MAT_PROMOTION]` report surface and partial
  `MaterializationDecisionRecord` refactor, but the selected override seam still
  called the old ambient predicate directly. That shape is now explicitly
  stale/non-admitted: 0k-J promotion must mean a consumption effect, not another
  diagnostic row. The next code slice may add a helper only if
  `lower_function_if_needed.override` obtains its parity/shadow input through
  the owned `MaterializationDecision` record, returns the legacy result for
  emitted behavior, and passes a source-shape gate proving that this seam no
  longer directly calls `state_scope_consumer_def_has_untyped_regular_param?`.
  Forbidden repeats remain backend reconciliation, target keepalive,
  requested-name materialization, remangle changes, global ambient-map changes,
  `NamedTuple`/`Tuple` display normalization, and rolling `BlockOwner` back to
  tuple/namedtuple metadata.

- 2026-07-01 UPDATE: added Slice 0k-K as an architecture pivot /
  anti-tail-chase gate before any 0k-J code helper. This is docs-only and
  records the current stop-rule from the owner review: the next code slice is
  admitted only if it has an authority-edge replacement receipt (`old_edge`,
  `owned_edge`, `legacy_parity`, `source_shape`, `report_shape`,
  `generated_stage_boundary`, and `cleanup_impact`). A helper that only prints
  `[MAT_PROMOTION]` rows, a crash probe that does not refute current owner
  evidence, or a cleanup pass without `CodePathStatus` runtime/falsifier
  evidence remains non-admitted. If the receipt cannot be made concrete, the
  next track must switch explicitly to `CodePathStatus` cleanup selection or a
  generated-stage reachability owner boundary. No compiler behavior changed and
  no green `s2b`/`s3b` claim is made.

- 2026-07-01 UPDATE: added Slice 0k-L as the concrete 0k-J implementation
  receipt. This is still docs-only. The admitted next code slice is now
  specific: at the `lower_function_if_needed.override` seam, replace the direct
  `state_scope_consumer_def_has_untyped_regular_param?` authority edge with a
  named shadow/parity helper that builds and consumes an owned
  `MaterializationDecisionRecord`, returns the legacy boolean for emitted
  behavior, and emits promotion rows only as evidence. The required next report
  is `scripts/materialization_override_promotion_report.sh`, red on a
  pre-slice compiler with no promoted rows and green only if the selected seam
  no longer calls the old predicate directly, rows are limited to
  `lower_function_if_needed.override`, owner fields are complete, and
  `emitted_result == legacy_result`. Do not change owner-result behavior,
  backend reconciliation, target keepalive, requested-name materialization,
  remangling, tuple rendering, global ambient-map rules, or `BlockOwner`.

- 2026-07-01 UPDATE: added Slice 0k-M as the architecture implementation pivot
  after the 0k-L receipt. The current rule is to close the 0k-L helper/report
  slice as behavior-neutral or revert it, then choose exactly one architecture
  lane before any further frontier work: `MaterializationDecision` owner
  extraction, `SemanticStateScope` facade, `NameResolution` / `MethodNameCodec`,
  `AstNodeRef` / `ArenaOwnership`, or runtime `CodePathStatus` cleanup. This is
  the active anti-tail-chase gate: a next slice must replace or shadow a named
  authority edge, classify/delete a path through `CodePathStatus`, or refute the
  current owner evidence. Do not resume generated-stage crash localization,
  backend stubs, forwarders, remangling, or materialization behavior changes
  until the chosen lane states its owner fact, source-shape guard, and
  falsifier.

- 2026-07-01 UPDATE: implemented the 0k-L helper/report slice as a
  behavior-neutral authority-edge shadow checkpoint. The override seam now
  calls `materialization_override_shadow_untyped_regular_param?`, which builds
  an owned `MaterializationDecisionRecord`, emits `[MAT_PROMOTION]` rows only
  under `ADAMAS_MATERIALIZATION_OVERRIDE_PROMOTION_LEDGER=1`, and returns the
  legacy boolean. Verification: red gate against `bin/adamas` fails with no
  promotion rows while compiler exit is `0`; fresh
  `/private/tmp/adamas_0km_stage1` green report emits `rows=1062`, only
  `lower_function_if_needed.override`, malformed/invalid counts `0`, and
  `emitted_mismatch=0`; materialization decision, promotion selection,
  state-scope consumer, semantic census, codepath census, and `git diff --check`
  gates all exit `0`; combined regression suite passes `36/36`; fresh stage1
  builds fresh generated s2 with `EXIT: 0`; generated s2 promotion report emits
  `rows=3` valid shadow-parity rows before the residual `compiler_rc=139`.
  Scope: no behavior change and no green `s2b`/`s3b` claim. Next work remains
  Slice 0k-M lane selection, not another crash-frontier fix.

- 2026-07-01 UPDATE: implemented Slice 0k-N as a no-repeat gate for the
  promotion-selection report. `scripts/materialization_promotion_selection_report.sh`
  now auto-detects the 0k-L promoted override seam from source shape and marks
  it `selection_status=already_promoted_shadow` instead of selecting it again.
  Verification: with `AUTO_DETECT_PROMOTED=0`, a fresh stage1 report preserves
  the old baseline (`lower_function_if_needed.override` remains
  `eligible_promote_owner`, `eligible_count=1`, `selected_count=1`); with
  default auto-detect, the report prints
  `promoted_consumers=lower_function_if_needed.override`,
  `selection_status=already_promoted_shadow`, `eligible_count=0`,
  `selected_count=0`, and `preferred_already_promoted=1`. Scope: report/gate
  only, no compiler behavior change and no green `s2b`/`s3b` claim. This means
  the focused post-0k-L MaterializationDecision lane has no second eligible
  consumer in the current report surface. Next implementation lane should be
  `SemanticStateScope` facade unless a fresh focused report names a different
  unpromoted MaterializationDecision consumer with complete owner fields.

- 2026-07-01 UPDATE: added Slice 0k-O as a docs-only
  `SemanticStateScope` admission gate before the next code slice. The prior
  "add a behavior-neutral scope snapshot" wording was too weak: it could admit
  another report/helper while leaving every ambient-state consumer on the old
  authority edge. The next `SemanticStateScope` code slice is now admitted only
  if it presents a concrete receipt for exactly one selected seam: `old_edge`,
  `owned_edge`, `legacy_parity`, `source_shape`, `report_shape`,
  `generated_stage_boundary`, and `cleanup_impact`. The preferred candidate is
  currently `prefer_callsite_specialization`, because it still directly reads
  `state_scope_consumer_def_has_untyped_regular_param?`, but this must be
  rechecked against the live `StateScopeConsumer` report before code. Rejected
  repeats remain: adding a report whose only effect is new rows, adding boolean
  modes to old predicates, global `@type_param_map` changes, migrating multiple
  consumers in one slice, backend stub/forwarder/keepalive work, remangling,
  requested-name materialization, `NamedTuple`/`Tuple` normalization, or rolling
  `BlockOwner` back to tuple/namedtuple metadata. If the receipt cannot be
  made root-sized, switch to runtime `CodePathStatus` cleanup selection rather
  than expanding diagnostics again. No compiler behavior changed and no green
  `s2b`/`s3b` claim is made.

- 2026-07-01 UPDATE: implemented Slice 0k-P as a behavior-neutral
  `SemanticStateScope` admission selection report. New script:
  `scripts/semantic_state_scope_admission_report.sh`. It consumes existing
  `ADAMAS_STATE_SCOPE_CONSUMER_LEDGER=1` rows and emits
  `[STATE_SCOPE_ADMISSION]` candidate rows; it does not add compiler
  instrumentation or change semantics. Fresh stage1 evidence:
  `crystal build src/adamas.cr -o /private/tmp/adamas_0kp_stage1 --error-trace`
  succeeds; default report selects exactly one candidate,
  `prefer_callsite_specialization`, with `preferred_source_shape=legacy_direct_edge`,
  `preferred_rows=3448`, migration buckets
  `migrate_to_state_scope=1256`, `migrate_to_materialization_registry=1063`,
  `rejected_ambient=269`, `keep_legacy_shim=860`, and
  `eligible_count=1` / `selected_count=1`. `REQUIRE_PROMOTED=1` is the red
  gate for the next code slice and currently exits `9` because the selected
  seam still calls the legacy helper directly (`already_promoted_count=0`).
  Scope: selection/report only; no `SemanticStateScopeSnapshot` implementation,
  no behavior change, no green `s2b`/`s3b` claim. Next code slice, if pursued,
  is a shadow/parity helper for `prefer_callsite_specialization` only; it must
  make `REQUIRE_PROMOTED=1` green and keep `emitted_result == legacy_result`.

- 2026-07-01 UPDATE: paused code after hostile self-review and added Slice
  0k-Q as a docs-only `SemanticStateScope` ownership contract. A local
  uncommitted `SemanticStateScopeSnapshot` / `[STATE_SCOPE_PROMOTION]` WIP was
  removed instead of committed because it risked wrapping
  `def_has_untyped_regular_param?` with more rows while leaving the old
  ambient predicate as the hidden authority. The future code slice is admitted
  only if it proves a real owner-contract for exactly
  `prefer_callsite_specialization`: old direct edge removed from the selected
  consumer, named owned record, separately computed owner result, legacy result
  used only for parity, `emitted_result == legacy_result`, no other consumer
  promoted, and existing state-scope/materialization/codepath reports still
  green. If that receipt cannot be made root-sized, switch to runtime
  `CodePathStatus` cleanup selection instead of adding another diagnostic
  ledger/helper. No compiler behavior changed and no green `s2b`/`s3b` claim is
  made.

- 2026-07-01 UPDATE: implemented Slice 0k-R, the first
  `SemanticStateScope` owner-consumption helper, in shadow/parity mode. The
  selected seam `prefer_callsite_specialization` now calls a named
  `SemanticStateScopeDecision` helper instead of calling the old
  `state_scope_consumer_def_has_untyped_regular_param?` edge directly. The
  helper evaluates `def_has_untyped_regular_param?` only as legacy parity,
  emits `[STATE_SCOPE_PROMOTION]` rows under
  `ADAMAS_SEMANTIC_STATE_SCOPE_PROMOTION_LEDGER=1`, records owner-result
  classes (`state_scope`, `materialization_registry`, `rejected_ambient`,
  `legacy_shim`), and returns the legacy result as emitted behavior.
  Verification: pre-slice red gate exited `9` with
  `preferred_source_shape=legacy_direct_edge`; fresh stage1 build succeeded;
  `REQUIRE_PROMOTED=1 scripts/semantic_state_scope_admission_report.sh
  /private/tmp/adamas_0kq2_stage1` exits `0` with
  `preferred_source_shape=already_promoted_shadow`, `promotion_rows=3448`,
  `promotion_non_preferred=0`, `promotion_malformed=0`,
  `promotion_invalid=0`, `promotion_emitted_mismatch=0`,
  `already_promoted_count=1`; owner-result buckets are
  `state_scope=1256`, `materialization_registry=1063`,
  `rejected_ambient=269`, `legacy_shim=860`; existing state-scope,
  materialization-selection, semantic-decision, and codepath-status reports
  still pass; env-off smoke emits no promotion rows and prints `1`;
  regression suites pass `152/152 + 36/36`; fresh generated s2 builds with
  `EXIT: 0` and compiles/runs a no-prelude `x = 1` smoke. Residual boundary:
  generated-s2 full-prelude `x = 1` still exits `139` after
  `pass3 after lower_main call`; no green `s2b`/`s3b` claim is made. Next work
  must not reselect `prefer_callsite_specialization`; choose a different
  root-sized state-scope consumer or switch to runtime `CodePathStatus`
  cleanup selection.

- 2026-07-01 UPDATE: implemented Slice 0k-S, the first runtime
  `CodePathStatus` cleanup selection report after the SemanticStateScope seam.
  New script: `scripts/codepath_status_cleanup_selection_report.sh`. It
  selects exactly one debug/probe path, `cli.metrics.identity_dry_run`, and
  classifies it as `debug_only` by running the compiler twice with
  `ADAMAS_CODEPATH_STATUS_LEDGER=1`: default run reports the selected path as
  `not_taken`, while `ADAMAS_IDENTITY_DRY_RUN=1` reports it as `taken`.
  Verification with fresh `/private/tmp/adamas_0ks_stage1`:
  `SELECTED_CLEANUP_PATH=identity_dry_run
  scripts/codepath_status_cleanup_selection_report.sh
  /private/tmp/adamas_0ks_stage1` exits `0` with default/enabled compiler
  rc `0`, selected rows `1/1`, default status `not_taken`, enabled status
  `taken`, category `cli.metrics`, owner `CLI`, and
  `[CODEPATH_CLEANUP_SELECTION] ... status=debug_only ...
  action=classify_only`. Existing `codepath_status_runtime_report` still
  reports `rows=26`, `malformed=0`, `taken=8`, `not_taken=18`; static
  codepath and semantic censuses still run; `bash -n` and `git diff --check`
  pass. Scope: classify-only, no deletion, no compiler behavior change, no
  green `s2b`/`s3b` claim. A later deletion/quarantine step requires
  `delete_ready` evidence and bootstrap guards.

- 2026-07-01 UPDATE: added Slice 0k-T, an active architecture execution board
  for the SDD. This is a control-plane checkpoint, not a compiler behavior
  change. The top of `docs/compiler_architecture_sdd.md` now says that the
  `Active Architecture Board` is the authoritative current decision surface,
  while older "Current next-slice decision after ..." paragraphs are historical
  ledger entries. The board buckets the live work into five owner boundaries:
  `SemanticStateScope`, `MaterializationIdentity` / `MaterializationRegistry`,
  `NameResolution` / `MethodNameCodec`, `AstNodeRef` / `ArenaOwnership`, and
  `CodePathStatus`. Next work must move exactly one board row by replacing or
  shadowing a named authority edge, producing runtime `CodePathStatus`
  classification for a named path, or refuting a row with fresher generated
  stage evidence. Default correctness lane after this checkpoint is
  `NameResolution` / `MethodNameCodec` plus `MaterializationIdentity`
  ownership, because the repeated high-cost frontiers are still symbol/owner
  identity failures. Cleanup remains admitted only as an explicit
  `CodePathStatus` slice with its own falsifier. No green `s2b`/`s3b` claim is
  made.

- 2026-07-01 UPDATE: implemented Slice 0k-U, the MethodNameCodec admission
  selection report. New script:
  `scripts/method_name_codec_admission_report.sh`. It selects one
  `NameResolution` / `MethodNameCodec` seam:
  `lower_function_if_needed.exact_lookup_keep_requested_name`. The old
  authority edge is the exact-lookup `keep_requested_name` branch that still
  uses rendered string checks for concrete suffix and arity wildcard
  (`name.includes?('$')`, `!name.includes?("$arity")`,
  `resolved_entry_name.includes?("$arity")`). The future owned edge is a
  shadow/parity helper named
  `method_name_codec_exact_lookup_keep_requested_name?`. Verification:
  `scripts/method_name_codec_admission_report.sh` exits `0` with
  `preferred_source_shape=legacy_string_edge`,
  `selection_status=eligible_codec_owner`,
  `exact_old_requested_suffix_count=1`, `exact_old_resolved_arity_count=1`,
  and `exact_helper_count=0`; `REQUIRE_PROMOTED=1
  scripts/method_name_codec_admission_report.sh` exits `9`, proving the future
  code slice has a red source-shape gate. Scope: source-shape/admission only,
  no compiler behavior change and no green `s2b`/`s3b` claim.

- 2026-07-01 UPDATE: implemented Slice 0k-V, the first MethodNameCodec
  consumer promotion in shadow/parity mode. The selected exact-lookup
  `keep_requested_name` branch now calls
  `method_name_codec_exact_lookup_keep_requested_name?` instead of directly
  deciding from rendered suffix/arity string checks inside
  `lower_function_if_needed_impl`. Default emitted behavior is unchanged: the
  helper preserves the legacy short-circuit result. A default-off
  `ADAMAS_METHOD_NAME_CODEC_PROMOTION_LEDGER=1` path computes a typed
  `MethodNameParts` owner-result and logs legacy/owner/emitted parity for the
  selected seam. Verification: `crystal build src/adamas.cr -o
  /private/tmp/adamas_method_codec_stage1 --error-trace` passes;
  `scripts/method_name_codec_admission_report.sh` reports
  `preferred_source_shape=already_promoted_shadow`,
  `selection_status=already_promoted_shadow`,
  `exact_old_requested_suffix_count=0`, `exact_old_resolved_arity_count=0`,
  and `exact_helper_count=2`; `REQUIRE_PROMOTED=1
  scripts/method_name_codec_admission_report.sh` exits `0`;
  `scripts/semantic_decision_census.sh` and
  `scripts/codepath_status_census.sh` still run; focused guards pass:
  `regression_tests/string_split_char_delimiter_repro.sh
  /private/tmp/adamas_method_codec_stage1`,
  `regression_tests/string_split_separator_materialization_collision_repro.sh
  /private/tmp/adamas_method_codec_stage1`,
  `regression_tests/string_split_default_nil_limit_repro.sh
  /private/tmp/adamas_method_codec_stage1`,
  `regression_tests/string_split_int32_nil_limit_collision_repro.sh
  /private/tmp/adamas_method_codec_stage1`,
  `regression_tests/class_arg_overload_dispatch_repro.sh
  /private/tmp/adamas_method_codec_stage1`, and
  `regression_tests/stage2_method_name_corruption_repro.sh
  /private/tmp/adamas_method_codec_stage1`; fresh stage1 builds fresh s2 under
  `scripts/run_safe.sh` (`EXIT: 0` after ~190s), and that generated s2 compiles
  and runs a no-prelude `x = 1` smoke through `scripts/run_safe.sh`. Scope:
  behavior-neutral consumer ownership only, no naming/materialization behavior flip, no
  `BlockOwner` rollback, and no green `s2b`/`s3b` claim. Next work must either
  run/extend this promotion ledger on a generated-stage corridor or explicitly
  choose the next active-board row; do not flip MethodNameCodec owner-result
  behavior from focused source-shape evidence alone.

- 2026-06-30 UPDATE: the
  `__adamas_string_eq <- __crystal_proc_1627 <-
  AstToHir#lower_generic_type_ref` s2->s3 SIGSEGV moved. The crashing Proc was
  the local `normalize_typeof_name : String -> String` lambda, but HIR probes
  showed the Proc receiver was correctly heap-backed and the bad argument was
  already a `Bool | String` local before the call. The first bad local binding
  came from `arg_name = br` under
  `@function_type_param_maps.dig?(..., "__block_return__")`: standalone
  falsifiers showed nested `Hash(String, Hash(String, String))#dig?` and the
  inner `[]?` path are unsafe under V2, while `has_key? + []` returns the
  expected `String`. Fix: introduce `function_type_param_map_value?` and route
  compiler `__block_return__` metadata lookups through `has_key? + []`, avoiding
  nested `Hash#dig?`/inner optional lookup in this self-host metadata path.
  Verification: fresh stage1 builds; new
  `regression_tests/function_type_param_map_safe_lookup_repro.sh` passes; full
  suites pass (`152/152` original + `36/36` combined); fresh fixed stage1 builds
  fresh s2; fixed s2->s3 no longer stops in
  `lower_generic_type_ref`/`__crystal_proc_1627` and now hits a later RSS
  frontier after `pass3 after lower_main call` (safe-wrapper kills at 4GB and
  8GB). Scope: this is a compiler metadata lookup hardening for
  `@function_type_param_maps`, not a global `Hash#dig?`/`Hash#[]?` fix and not a
  green s2->s3/s3b claim.

- 2026-06-30 UPDATE: the
  `Hash(Tuple(UInt32, UInt32), Nil)#entry_matches? <- Set#add <-
  AstToHir#lower_break` s2->s3 SIGSEGV moved. lldb on the crashing generated
  s2 showed the new lookup key was a valid tuple pointer, but the existing
  Hash entry stored the tuple key inline at offset 0 (`UInt32` fields in the
  entry body). The generated `entry_matches?` consumer nevertheless emitted
  `ldr x9, [entry]` and dereferenced that word as a tuple pointer. `set_entry`
  and `Hash::Entry#initialize` already copied the primitive tuple payload
  inline, so the first bad boundary was the read side: `FieldGet @key` from an
  inline-container receiver (`Hash::Entry`) treated a primitive tuple field as a
  pointer-carrier. Fix: when a primitive Tuple/NamedTuple field is read from an
  inline-container struct receiver, return the field address as a borrowed
  inline aggregate, matching the existing store/memcpy path. Verification:
  fresh stage1 builds; focused `Set(Tuple(UInt32, UInt32))` reducer still
  prints `true/true/2`; patched s2 disassembly for the same `entry_matches?`
  now directly reads `[entry]` and `[entry+4]` instead of dereferencing
  `[entry]` as a pointer; full suites pass (`152/152` original + `36/36`
  combined); fresh fixed stage1 builds fresh s2; fixed s2->s3 no longer stops
  in `Hash(Tuple(UInt32, UInt32), Nil)#entry_matches?` and now exits 139 in
  `__adamas_string_eq <- __crystal_proc_1627 <-
  AstToHir#lower_generic_type_ref`. This is an inline-container field-read ABI
  repair, not a green s2->s3/s3b claim.

- 2026-06-30 UPDATE: the
  `__adamas_string_eq <- __crystal_proc_653 <-
  LLVMIRGenerator#emit_extern_call` s2->s3 SIGSEGV moved. IR and lldb
  disassembly pinned `__crystal_proc_653` to the heap Proc body for
  `cast_fixed_arg` in `emit_extern_call`: the generated function expected
  five user parameters including two full `Nil | TypeRef` union arguments, but
  the indirect-call emission path unconditionally unwrapped every union
  argument as if the call were raw yield dispatch. That shifted the Proc ABI:
  `expected_type` was never passed in the expected register, and the first
  `expected_type == "void"` string comparison crashed. A standalone reducer
  with a heap Proc `(String, Wrap?, String, String, Wrap?)` returned `REF`
  before the fix because the second nilable argument was shifted into the
  later `String` slot. Fix: add an explicit `unwrap_union_args` mode to
  `MIR::IndirectCall`, keep the old unwrap-by-default behavior for raw yield
  callbacks, and make heap Proc dispatch preserve full union arguments.
  Verification: fresh stage1 builds; the new
  `regression_tests/proc_nilable_union_arg_indirect_call_repro.sh` passes and
  prints `VALUE`; full suites pass (`152/152` original + `36/36` combined);
  fresh fixed stage1 builds fresh s2; fixed s2->s3 no longer reaches
  `__crystal_proc_653` / `emit_extern_call` and now exits 139 after
  `pass3 after lower_main call` in
  `Hash(Tuple(UInt32, UInt32), Nil)#entry_matches? <- Set#add <-
  AstToHir#lower_break`. This is a bounded heap Proc indirect-call ABI repair,
  not a global Proc/yield ABI redesign and not a green s2->s3/s3b claim.

- 2026-06-30 UPDATE: the
  `MIR::TypeRef#hash <- Hash(MIR::TypeRef, String)#[]? <-
  LLVMTypeMapper#llvm_type <- LLVMIRGenerator#emit_string_interpolation`
  s2->s3 SIGSEGV moved. Pointer-safe probes showed the interpolation metadata
  itself was valid in the caller: the local `part_type.id` read succeeded, and
  the same value only became unsafe after crossing the helper boundary as
  `hint_type : TypeRef?` into `interpolation_i32_arg`. A tempting
  `LLVMTypeMapper` id-key cache change was refuted: it removed the hash call
  but then crashed directly on `type_ref.id` inside `llvm_type`, proving the
  bad edge was the helper argument transport, not the cache key. Fix: make
  `interpolation_i32_arg` accept scalar metadata (`hint_llvm_type : String?`
  and `signed : Bool`) instead of a nilable `TypeRef` wrapper; caller code still
  computes the LLVM type from the local `TypeRef` before the helper call.
  Verification: fresh stage1 builds; full suites pass (`152/152` original +
  `36/36` combined); fresh fixed stage1 builds fresh s2; fixed s2->s3 no
  longer reaches `MIR::TypeRef#hash`/`LLVMTypeMapper#llvm_type` and now exits
  139 in `__adamas_string_eq <- __crystal_proc_653 <-
  LLVMIRGenerator#emit_extern_call` during LLVM emission after allocator flush.
  This is a bounded interpolation-helper ABI repair, not a global `TypeRef`
  hash/value-round-trip fix and not a green s2->s3/s3b claim.

- 2026-06-30 UPDATE: the
  `AstToHir#missing_required_runtime_param_types? <-
  AstToHir#lower_method` s2->s3 `EXC_BREAKPOINT` moved. Fresh base stage1
  built fresh s2; base s2->s3 reproduced `EXIT 133`, and lldb stopped in
  `missing_required_runtime_param_types?`. A first marker before the
  `return true` branch did not print in generated s2, refuting that as the
  immediate edge. A wider primitive marker probe showed the last generated-s2
  line was the callback `loop` marker, with no `after skip`, pinning the
  producer to the yielded `each_param` callback skip line
  (`next if named_only_separator?(param) || param.is_block ||
  param.is_double_splat`) rather than corrupt `call_types` or the required-param
  check. Fix: rewrite only `missing_required_runtime_param_types?` as a plain
  indexed `while` scan using `param_at_or_nil`, with no yielded-block `next`,
  `break`, or `return`. Verification: fresh stage1 builds; full suites pass
  (`152/152` original + `36/36` combined); fresh fixed stage1 builds fresh s2;
  fixed s2 no longer hits `missing_required_runtime_param_types?`. Fixed s2->s3
  now reaches a later `EXIT 139` in
  `MIR::TypeRef#hash <- Hash(MIR::TypeRef, String)#[]? <-
  LLVMTypeMapper#llvm_type <- LLVMIRGenerator#emit_string_interpolation` during
  LLVM emission after allocator flush. Do not claim green s2->s3/s3b.

- 2026-06-30 UPDATE: the
  `AstToHir#static_truthy_value <-
  AstToHir#lower_short_circuit_condition <- AstToHir#lower_while` s2->s3
  SIGSEGV moved. Probe logs showed `ctx.value_for(value_id)` succeeded and
  the last failing case was a Bool `Literal`: `value.type.id=1`
  (`TypeRef::BOOL`), `is_literal=1`, and the probe printed after
  `value.value` returned before the crash. That pins the bad transition to the
  polymorphic `case bool_lit = value.value` over `LiteralValue`, not to
  `ctx.value_for`, `value.type`, or the payload load itself. This matches the
  existing `Literal` contract in `hir.cr`: Bool/number payloads are mirrored
  into primitive cache fields because V2 can corrupt the `@value` union tag,
  and `Literal#to_s` already uses `@int_value` for Bool. Fix: in
  `static_truthy_value`, evaluate Bool literals through `value.int_value != 0`
  instead of reading and case-dispatching on `value.value`. Verification:
  fresh stage1 builds; full suites pass (`152/152` original + `36/36`
  combined); fresh fixed stage1 builds fresh s2; fixed s2 no longer crashes in
  `static_truthy_value`. With a 20GB `run_safe` cap, fixed s2->s3 now exits
  133 in
  `AstToHir#missing_required_runtime_param_types? <- AstToHir#lower_method`.
  Do not claim green s2->s3/s3b.

- 2026-06-30 UPDATE: the
  `NodeSlot#node <- AstArena#[] <- AstToHir#stringify_type_expr <-
  AstToHir#lower_call` s2->s3 SIGSEGV moved. Boundary probes showed
  `stringify_type_expr` was not receiving a corrupt or unowned `ExprId`: the
  failing value was `ExprId 774`, the current arena had only `109` nodes,
  `@main_arenas` had `398` arenas, and `arena_for_expr?` resolved the same id
  to a known arena of size `775`. Root-shaped boundary was therefore
  `stringify_type_expr` reading through raw `@arena[expr_id]` instead of the
  existing arena-resolution path already used by `node_for_expr`. Fix:
  split `stringify_type_expr` into an arena-resolving wrapper plus
  `stringify_type_expr_in_current_arena`, and run the existing body under
  `with_arena(arena_for_expr?(expr_id))`; no nil/OOB consumer guard was added.
  Verification: fresh stage1 builds; full suites pass (`152/152` original +
  `36/36` combined); fresh fixed stage1 builds fresh s2; fixed s2 no longer
  crashes in `stringify_type_expr`. With a 20GB `run_safe` cap, fixed s2->s3
  now exits 139 in
  `AstToHir#static_truthy_value <- AstToHir#lower_short_circuit_condition <-
  AstToHir#lower_while` while draining missing call targets. Caveat: the same
  run can hit the 16GB `run_safe` memory cap before exposing that later stack.
  Do not claim green s2->s3/s3b.

- 2026-06-30 UPDATE: the
  `AstToHir#lower_enum_predicate <- AstToHir#lower_member_access <-
  AstToHir#lower_if` s2->s3 SIGSEGV moved. Boundary probes first separated
  the non-enum `Nil | String` path from the enum path, then pinned the failing
  enum predicate to `Path.to_kind$Path::Kind_Bool`: enum metadata was valid
  (`enum_key=Path::Kind`, `count=2`), `base=posix` and `target=posix` were
  valid, and the crash occurred before the `members.keys.find { ... }` match
  completed. Fix: replace that hot-path block `find` with an indexed scan over
  `members.keys`, preserving the same `underscore_lower(member) == target`
  predicate without yielding through a self-host-brittle block. Verification:
  fresh stage1 builds; full suites pass (`152/152` original + `36/36`
  combined); fresh fixed stage1 builds fresh s2; fixed s2 compiling
  `src/adamas.cr` no longer crashes in `lower_enum_predicate`. Residual
  frontier: fixed s2->s3 still exits 139 after `[STAGE2_DEBUG] pass3 after
  lower_main call`, now in
  `NodeSlot#node <- AstArena#[] <- AstToHir#stringify_type_expr <-
  AstToHir#lower_call`. Do not claim green s2->s3/s3b.

- 2026-06-30 UPDATE: the
  `NodeSlot#node <- AstArena#[] <- AstToHir#collect_assigned_vars_in_expr <-
  AstToHir#lower_block_to_block_id` s2->s3 SIGSEGV moved. Boundary probes
  showed this was not a `NodeSlot` storage root: the failing block body had
  expr `76`, and a valid cached block arena existed with `size=138` /
  `body_max=76`, but `lower_block_to_block_id` was entered with a current
  caller arena of `size=41`. The method then unconditionally overwrote
  `@block_node_arenas[node.object_id] = @arena`, clobbering the correct block
  arena before `collect_assigned_vars` read body expr `76` from arena `41`.
  Fix: choose the block arena at `lower_block_to_block_id` entry from
  existing cache / `resolve_arena_for_block` / caller fallback, store it with
  `store_block_arena`, lower the block with `@arena` set to that arena, and
  restore the caller arena in `ensure`. Verification: fresh stage1 builds;
  full suites pass (`152/152` original + `36/36` combined); fresh fixed stage1
  builds fresh s2; fixed s2 no longer crashes in `collect_assigned_vars`.
  Residual frontier: fixed s2->s3 still exits 139 after
  `[STAGE2_DEBUG] pass3 after lower_main call`, now in
  `AstToHir#lower_enum_predicate <- AstToHir#lower_member_access <-
  AstToHir#lower_if`. Do not claim green s2->s3/s3b.

- 2026-06-30 UPDATE: the `String#bytesize <-
  AstToHir#parse_method_name <- AstToHir#apply_default_args` s2->s3 SIGSEGV
  moved. lldb showed `parse_method_name` received `x0=0x10`. Targeted
  raw-pointer probes then showed the value was already corrupt in
  `lower_member_access` before `apply_default_args`: `resolve_method_call`
  returned a valid String (`pre_raw` high), `dollar=16`, and the local suffix
  strip `base_method_name[0, dollar]` produced `post_raw=16`. Root-shaped
  producer was therefore the compiler hot-path use of self-host-brittle
  `String#[](Int32, Int32)` for function-name suffix stripping, not
  `parse_method_name`, `apply_default_args`, or method resolution. Fix: replace
  that local slice with the existing `strip_type_suffix(...)` helper, which
  already uses `byte_slice`. Verification: fresh stage1 builds; full suites
  pass (`152/152` original + `36/36` combined); fresh fixed stage1 builds fresh
  s2; fixed s2 no longer crashes in `parse_method_name`. Residual frontier:
  under the normal 12GB `run_safe` cap fixed s2 reaches memory kill first; with
  a 16GB cap it reaches the next SIGSEGV in
  `NodeSlot#node <- AstArena#[] <- AstToHir#collect_assigned_vars_in_expr <-
  AstToHir#lower_block_to_block_id`. Do not claim green s2->s3/s3b.

- 2026-06-30 UPDATE: the
  `__crystal_block_proc_744 <- AstToHir#each_param <- lower_method`
  s2->s3 `EXC_BREAKPOINT` moved. Root-shaped producer was the untyped-param
  default inference branch in `lower_method`: it used `each_param(params) do`
  with a `break` from inside the yielded block when a param had no annotation
  and no default. Generated s2 traps on this non-local block control-flow
  shape. Fix: add `param_at_or_nil` and rewrite only that default-inference
  scan as an indexed `while` loop guarded by `all_defaulted`, preserving the
  previous early-stop semantics without a block `break`. Verification: fresh
  stage1 builds; full suites pass (`152/152` original + `36/36` combined);
  fresh fixed stage1 builds fresh s2; fixed s2 compiling `src/adamas.cr` no
  longer hits the `each_param` breakpoint. Residual frontier: fixed s2->s3
  now exits 139 after `[STAGE2_DEBUG] pass3 after lower_main call`; lldb stops
  in `String#bytesize <- AstToHir#parse_method_name <-
  AstToHir#apply_default_args <- AstToHir#lower_member_access`. Do not claim
  green s2->s3/s3b.

- 2026-06-30 UPDATE: the `AstToHir#lower_unless` s2->s3 SIGSEGV
  moved. A gated coercion probe showed the direct branch values were valid
  (`then=62`, `else=63` in the crashing case), but the tuple-destructured block
  parameters from `incoming.map do |(blk, val)|` read back corrupted
  (`blk={}` / blank `val`) immediately before `UnionWrap.new`. This matches
  the local invariant already documented in `lower_if`: use indexed tuple
  access to avoid V2 tuple destructuring issues. Fix: rewrite the
  two-branch `lower_unless` value merge to use indexed `incoming_blocks` /
  `incoming_values` arrays and a plain `while` loop, avoiding both the `map`
  destructuring and the later `coerced_incoming.each` destructuring.
  Verification: fresh stage1 builds; full suites pass (`152/152` original +
  `36/36` combined); fresh fixed stage1 builds fresh s2; fixed s2 compiling
  `src/adamas.cr` no longer segfaults in `lower_unless`. Residual frontier:
  fixed s2->s3 now exits 133 after `[STAGE2_DEBUG] pass3 after lower_main
  call`; lldb stops at `EXC_BREAKPOINT` in
  `__crystal_block_proc_744 <- AstToHir#each_param <- lower_method`. Do not
  claim green s2->s3/s3b.

- 2026-06-30 UPDATE: the `ExprId out of bounds: 260` s2->s3 frontier
  moved. Root was not `lower_main` packing and not an empty arena registry:
  a targeted `arena_for_expr?` probe showed `@main_arenas` had 177 candidate
  arenas that covered ExprId 260, and the original `@main_arenas.each` loop
  visited fitting candidates, but captured locals `best` / `best_size` still
  read back as `nil` / `Int32::MAX` after the block in generated s2. Fix:
  replace the `@inline_arenas.each` and `@main_arenas.each` fallback scans in
  `AstToHir#arena_for_expr?` with explicit `while` loops so the selected arena
  is assigned in the current frame. Verification: fresh stage1 builds; full
  suites pass (`152/152` original + `36/36` combined); fresh fixed stage1
  builds fresh s2; fixed s2 compiling `src/adamas.cr` no longer raises
  `ExprId out of bounds: 260`. Residual frontier: fixed s2->s3 now exits 139
  after `[STAGE2_DEBUG] pass3 after lower_main call`; lldb stops in
  `AstToHir#lower_unless` while lowering an inlined yield path. Do not claim
  green s2->s3/s3b.

- 2026-06-30 UPDATE: the `String#size <-
  scan_hir_function_for_live_types` s2->s3 SIGSEGV moved again. Two
  independent probes pinned the same producer family: after the earlier central
  receiver-call factory fix, s2 still constructed malformed HIR calls where a
  receiver `ValueId` became the `method_name` pointer. First source was
  `src/compiler/cli.cr:1003` (`options.optimize = 3`) with raw method pointer
  `97`; after the assignment call sites were migrated, the next source was
  `src/stdlib/file.cr:681` (`Path.new(*parts).to_s`) with raw method pointer
  `0`. Root class: self-hosted overload selection for the many overloaded
  `HIR::Call.new` constructors is not a safe boundary. Fix: add explicit
  no-receiver block/virtual factories and migrate production HIR call
  construction in `AstToHir` to the intent-named factories
  (`with_receiver*` / `without_receiver*`), leaving only the two intentional
  placeholder `Call.new(..., "")` sites. Verification: fresh stage1 builds;
  static grep finds no remaining production HIR `Call.new` construction in
  `ast_to_hir.cr`; independent Spark scout review found the same; full suites
  pass (`152/152` original + `36/36` combined); fresh fixed stage1 builds
  fresh s2; fixed s2 compiling `src/adamas.cr` no longer segfaults in
  `String#size <- scan_hir_function_for_live_types`. Residual frontier: fixed
  s2->s3 now exits 1 with `error: ExprId out of bounds: 260
  (arena=:67, current=:67, main_arenas=398, inline_arenas=0)` after
  `[STAGE2_DEBUG] pass3 after lower_main call`. Do not claim green s2->s3/s3b.

- 2026-06-30 UPDATE: the `AstToHir#apply_is_a_narrowing -> TypeRef#==`
  s2->s3 SIGSEGV moved. Root was not `type_ref_for_name` and not the
  narrowing consumer loop: probes showed `is_a_narrowing_targets` produced a
  valid `("parser", OptionParser TypeRef)` and the local array was valid, but
  returning `Array(Tuple(String, TypeRef))` across the recursive helper
  corrupted the carried entry before `apply_is_a_narrowing` consumed it.
  Standalone reducers confirmed the broader shape: recursive returns of
  tuple arrays carrying `String + small value` corrupt after return, while an
  `Array` of a reference carrier preserves the same data. Fix:
  `is_a_narrowing_targets` now returns `Array(IsANarrowingTarget)` instead of
  `Array(Tuple(String, TypeRef))`, and case-branch narrowing call sites use the
  same carrier. Guard:
  `regression_tests/hir_is_a_narrowing_target_carrier_guard.sh`. Verification:
  fresh stage1 builds; the new guard passes; full suites pass (`152/152`
  original + `36/36` combined); fresh fixed stage1 builds fresh s2. Residual
  frontier: fresh fixed s2 compiling `src/adamas.cr` still exits 139 after
  `[STAGE2_DEBUG] pass3 after lower_main call`, but lldb now stops in
  `String#size <- AstToHir#scan_hir_function_for_live_types`. Do not claim
  green s2->s3/s3b.

- 2026-06-30 UPDATE: the `AstToHir#lower_case <- lower_node`
  s2->s3 SIGSEGV moved. Root was a producer bug in the `Array#reduce`
  HIR intrinsic: `lower_array_reduce_dynamic` hardcoded the element and
  accumulator type to `Pointer`, which is valid for reference-like arrays but
  wrong for primitive arrays. `lower_case` builds `conds.reduce` over
  `Array(ValueId)` (`UInt32`), so generated s2 tried to pass a pointer-shaped
  reduce result as a `Branch` condition. Fix: `lower_array_reduce_dynamic`
  now resolves the element type through `array_element_type_for_value`, the
  same container helper used by sibling Array intrinsics; no `lower_case`
  consumer guard was added. Guard:
  `regression_tests/array_reduce_uint32_element_type_repro.sh` is red on the
  previous compiler with an llc pointer-vs-i32 type error and green on fixed
  stage1 with `plain=6`. Verification: fresh stage1 builds; the new reduce
  guard passes; manual `Array(UInt32)#map + #reduce` reducer passes; full
  suites pass (`152/152` original + `36/36` combined); fresh fixed stage1
  builds fresh s2. Residual frontier: fresh fixed s2 compiling
  `src/adamas.cr` still exits 139 after `[STAGE2_DEBUG] pass3 after
  lower_main call`, but lldb now stops in `AstToHir#lower_module_method` at a
  null receiver before `DefNode#return_type`. Do not claim green s2->s3/s3b.

- 2026-06-30 UPDATE: the `AstToHir#reorder_named_args <- lower_call`
  s2->s3 SIGSEGV moved. Root was a producer contract bug in the
  `Array#index(value)` HIR fast path: it returned concrete `Int32` with `-1`
  as a miss sentinel, while Crystal's `Indexable#index` contract is
  `Nil | Int32`. In generated s2, `param_call_names.index(arg_name)` in
  `reorder_named_args` therefore saw a miss as truthy `-1` and indexed the
  result array through the negative slot. Fix: `lower_array_index_dynamic`
  now returns a nilable union, wrapping the found index as `Int32` and the
  miss path as `nil`; no consumer guard was added. Guard:
  `regression_tests/array_index_nilable_contract_repro.sh` is red on the
  previous compiler with `miss_obj=IDX:-1` and green on fixed stage1 with
  `miss_obj=NIL`. Verification: fresh stage1 builds; the new contract guard
  passes; adjacent bootstrap guards
  `hir_inline_yield_param_bind_loop_guard.sh`,
  `hir_pack_splat_param_find_guard.sh`, and
  `stage2_contains_yield_deep_materialization_repro.sh` pass; full suites pass
  (`152/152` original + `36/36` combined); fresh fixed stage1 builds fresh s2.
  Residual frontier: fresh fixed s2 compiling `src/adamas.cr` still exits 139
  after `[STAGE2_DEBUG] pass3 after lower_main call`, but lldb now stops in
  `AstToHir#lower_case <- lower_node`, reached through nested inlined block
  bodies under `inline_yield_function`. Do not claim green s2->s3/s3b.

- 2026-06-29 UPDATE: the `inline_yield_function <-
  each_param_with_index` s2->s3 SIGSEGV moved. Producer-side probes refuted
  the first tempting explanation: `ParameterBuffer#to_a` stored valid high
  pointer slots in the returned `Array(Parameter)`; the low `unsafe_as` tokens
  seen in generated s2 were not raw array slots. lldb on the crashing s2 then
  showed the fault occurred inside the generated block callback for
  `each_param_with_index` before the probe body could print. Fix: bind
  `inline_yield_function` callee parameters with a direct `while` loop over
  the `params` array, preserving the existing `arg_idx` semantics and null-slot
  skip but avoiding the self-host-brittle block callback in this compiler
  chokepoint. Guard:
  `regression_tests/hir_inline_yield_param_bind_loop_guard.sh`. Verification:
  fresh stage1 builds; focused guards
  `hir_inline_yield_param_bind_loop_guard.sh`,
  `hir_pack_splat_param_find_guard.sh`, and
  `stage2_contains_yield_deep_materialization_repro.sh` pass; full suites pass
  (`152/152` original + `36/36` combined); fresh stage1 builds fresh s2.
  Residual frontier: fresh fixed s2 compiling `src/adamas.cr` no longer stops
  in `each_param_with_index`; lldb now stops in
  `AstToHir#reorder_named_args <- lower_call`, reached from the inlined body
  under `inline_yield_function`. Do not claim green s2->s3/s3b.

- 2026-06-29 UPDATE: the `contains_yield_deep?` s2->s3 abort-stub
  frontier moved. Root was not a backend undefined-extern problem and not a
  local `contains_yield_deep?` special case: `declared_type_match_score` could
  match a scalar argument against a union parameter, but it could not match a
  union argument whose variants are a subset of a wider union parameter. That
  made the registered `ArenaLike?` overload
  (`Nil | AstArena | PageArena | VirtualArena`) reject the non-nil ArenaLike
  call suffix (`AstArena | PageArena | VirtualArena`) unless older nilable
  callsite history happened to exist. Fix: if both declared and argument types
  are unions, accept the argument union when every argument variant matches at
  least one declared variant. Guard:
  `regression_tests/stage2_contains_yield_deep_materialization_repro.sh`.
  Verification: fresh stage1 builds; the focused guard passes; fresh stage1
  builds fresh s2; the generated s2 contains a real `contains_yield_deep?`
  symbol and no `STUB CALLED: ...contains_yield_deep` string; full suites pass
  (`152/152` original + `36/36` combined). Residual frontier: fresh fixed s2
  compiling `src/adamas.cr` no longer aborts on `contains_yield_deep?`, but
  exits 139 after `[STAGE2_DEBUG] pass3 after lower_main call`; lldb stops in
  `AstToHir#inline_yield_function <- each_param_with_index`. Do not claim
  green s2->s3/s3b.

- 2026-06-29 UPDATE: the `AstToHir#pack_splat_args_for_call` s2->s3
  SIGSEGV moved. Temporary probes on fresh fixed s2 pinned the crash to
  `Adamas::Compiler::LSP::ToolDispatch.resolve_server_path` lowering
  `File.join$Path | String_splat` with two `String` args. The first splat
  param scan, array slicing, and `splat_types=String,String` were readable; the
  bad transition was the later `params.find { |p| p.is_splat &&
  !p.is_double_splat }` callback before `splat_param` returned. This matches
  the existing self-host brittle-helper pattern for block-based metadata scans.
  Fix: replace only that compiler-critical `Array#find` call with an explicit
  `params.each` loop; splat semantics are unchanged. Guard:
  `regression_tests/hir_pack_splat_param_find_guard.sh`. Verification:
  fresh stage1 builds; focused guards
  `hir_call_receiver_factory_guard.sh`,
  `hir_pack_splat_param_find_guard.sh`,
  `p2_short_type_index_first_no_prelude.sh`, and
  `class_method_noarg_super_forward_repro.sh` pass; full suites pass
  (`152/152` original + `36/36` combined); fresh stage1 builds fresh s2.
  Residual frontier: fresh fixed s2 compiling `src/adamas.cr` no longer
  segfaults in `pack_splat_args_for_call`; it aborts with `STUB CALLED:
  Adamas::HIR::AstToHir#contains_yield_deep?$Array(ExprId)_AstArena|PageArena|VirtualArena`.
  Do not claim green s2->s3/s3b.

- 2026-06-29 UPDATE: the `String#size <-
  scan_hir_function_for_live_types` s2->s3 frontier moved. Read-only probes
  before the fix showed that `lower_call` resolved
  `src/adamas.cr:20:3` as `IO#puts$String` with receiver
  `IO::FileDescriptor`, `virtual=true`, and `ret=Nil`, but the constructed
  HIR `Call` at emit time had `method_name` as tiny pointer/value id `126`,
  no receiver, no args, and type `Symbol`. The bad value was therefore produced
  by the overloaded receiver `Call.new(...)` constructor path in central
  `lower_call`, not by RTA/live-type scanning. The fix adds named
  `HIR::Call.with_receiver*` factories and routes the receiver branch through
  them, leaving receiverless calls unchanged. Guard:
  `regression_tests/hir_call_receiver_factory_guard.sh`. Verification:
  fresh stage1 builds; focused guards
  `hir_call_receiver_factory_guard.sh`,
  `p2_short_type_index_first_no_prelude.sh`,
  `multi_ref_union_truthy_narrowing_repro.sh`, and
  `class_method_noarg_super_forward_repro.sh` pass; full suites pass
  (`152/152` original + `36/36` combined); fresh stage1 builds fresh s2.
  Residual frontier: fresh fixed s2 compiling `src/adamas.cr` no longer stops
  in `String#size <- scan_hir_function_for_live_types`; lldb now stops in
  `AstToHir#pack_splat_args_for_call <- lower_call` after
  `[STAGE2_DEBUG] pass3 after lower_main call`. Do not claim green s2->s3/s3b.

- 2026-06-29 UPDATE: the `s2 -> s3` frontier moved past
  `error: Index out of bounds` after `pass3 after lower_main call`. Root was
  not MIR/LLVM and not `Exception#backtrace?` itself: lldb on fresh s2 stopped
  at `__adamas_raise`, with the stack
  `lower_missing_call_targets -> process_pending_lower_functions ->
  lower_function_if_needed_impl -> lower_method -> lower_super ->
  Array(HIR::Parameter)#[](Range(Int32, Nil))`. `lower_super` and
  `previous_def` used `ctx.function.params[1..]` to forward implicit no-arg
  calls, assuming every lowered method has a synthetic `self` parameter. That
  is false for class/static/top-level wrappers; a no-arg `super` in that shape
  tried to slice an empty parameter array from index 1. Fix: forward current
  method args with `current_method_forward_arg_ids`, skipping the first
  parameter only when it is actually named `self`. Guard:
  `regression_tests/class_method_noarg_super_forward_repro.sh` is red on
  baseline `/tmp/adamas_try_noblock_stage1` with `Index out of bounds` and
  green on fixed stage1 and fixed s2. Fresh fixed s2 builds s3 cleanly
  (`/tmp/adamas_super_forward_s3`, exit 0). Residual frontier: generated s3 is
  not a usable compiler yet; compiling even `puts "hi"` exits 134 with
  `STUB CALLED: get$Q$$String`. Do not claim green s3/s3b.

- 2026-06-29 UPDATE: the `s2 -> s3` frontier moved past the
  `AstToHir#inline_try_with_block` SIGSEGV. Root was not `TypeRef` parameter
  passing: the crash came from `inline_try_core` taking a Crystal block callback
  with a scalar `ValueId` (`UInt32`) argument. In generated s2 code, the block
  callback path either reused closure cells allocated only on the non-union
  branch or treated the scalar callback argument as a pointer (`ldr w3, [x8]`
  with `x8=4`). Fix: inline the nilable `try` CFG separately for block and proc
  paths, and call `inline_try_block_body` / `inline_try_proc_body` directly
  instead of crossing the generated block-callback ABI. Guard:
  `regression_tests/stage2_inline_try_block_scalar_callback_repro.sh` is red on
  baseline `/tmp/adamas_537e13fc_s2` and green on fixed
  `/tmp/adamas_try_noblock_s2`. Fresh fixed `s2` also keeps
  `regression_tests/stage2_lower_field_get_full_prelude_frontier_repro.sh`
  green. Residual frontier: fixed `s2 -> s3` no longer exits 139 in
  `inline_try_with_block`, but now exits 1 with `error: Index out of bounds`
  after `pass3 after lower_main call`. Do not claim s3 green.

- 2026-06-29 UPDATE: the full-prelude s2 frontier moved again. Root for the
  `Random#rand_int(Int32)` undefined-extern was not a backend stub problem.
  The source `src/stdlib/random.cr` macro body contains `range.begin` /
  `range.end` inside a macro-for generated method signature/body. The parser's
  macro body scanner treated keyword tokens after dot as real `begin`/`end`
  block delimiters, leaving `block_depth=1`, consuming the outer `{% end %}`,
  and dropping the `MacroForNode` plus all later module members from the
  registered `Random` body. Fix: macro body scanning ignores keyword block
  effects after dot, and module macro-for include expansion is replayed for
  existing includers when a later module reopening is registered. Guards:
  `regression_tests/macro_body_keyword_member_after_dot_repro.sh`,
  `regression_tests/module_macro_for_include_private_helper_repro.sh`, and
  `regression_tests/stage2_lower_field_get_full_prelude_frontier_repro.sh`.
  Fresh `/tmp/adamas_random_rootfix` gets the full-prelude guard to
  `status=0`; `Random#rand_int` is no longer an accepted frontier.

- 2026-06-29 UPDATE: the previous full-prelude s2 frontier moved. Root for the
  `Time::Format#initialize(String, Location?)` crash was not backend ABI: the
  ivar annotation `@location : Location?` in `Time::Format` was registered
  before nested `Time::Location` was discoverable, leaving class ivar metadata
  as stale `Nil | Location` while the initializer parameter was
  `Nil | Time::Location`. The final ivar layout pass now canonicalizes
  owner-scoped simple union variants after all class names are known, so stale
  `Nil | Inner` becomes `Nil | Outer::Inner` for field storage. Guard:
  `regression_tests/nilable_forward_nested_class_ivar_repro.sh`. Fresh s2
  built from the fixed compiler gets past the old `lower_field_get`, old
  `Time::Location.local`, and old `Time::Format#initialize` frontiers; the
  downstream boundary at that checkpoint was `STUB CALLED:
  Random$Hrand_int$$Int32` (exit 134). That boundary is now superseded by the
  parser/module macro-for include slice above.

- 2026-06-28 UPDATE: the current `lower_field_get` crash has moved, but s2 is
  still not green. Fresh producer/consumer probes on clean HEAD showed the first
  crashing `FieldGet` is `String#bytesize @bytesize` (`id=1`, offset 4): HIR
  construction, `ctx.emit`, and `ctx.register_type` all preserve
  `TypeRef::INT32` (`id=4`) in both stage1 and s2, and the MIR side table
  `@hir_value_types[field.id]` also contains `id=4` in s2. The bad consumer
  transition was direct inherited `field.type` access inside
  `HIRToMIRLowering#lower_field_get`. The slice now uses the HIR value-type
  side table for `FieldGet` lowering and avoids the s2-brittle `Array#find`
  helper only in the compiler-critical MIR field-descriptor lookup. Fresh s2
  compiling full-prelude `puts "x"` no longer exits 139 in `lower_field_get`;
  it reaches the next boundary, `STUB CALLED: Time::Location.local` (exit 134).
  Guard: `regression_tests/stage2_lower_field_get_full_prelude_frontier_repro.sh`
  accepts only that moved frontier or a future clean compile, and fails if the
  old segfault returns. Do not claim `Array#find` or general HIR node storage is
  fixed by this slice.

- CURRENT STATUS: branch `work/s3-range-slice-frontier` is still not
  merge-ready, but the previous broad dirty batch has been cut down and several
  old full-prelude frontiers have moved. Fresh stage1 now builds fresh s2;
  generated s2 passes the focused escaped-interpolation parser guard, the
  full-prelude lower-field-get/Time/Random guard, the `Exception#backtrace?`
  inline-try scalar callback guard, the receiver-call factory guard, the splat
  param find guard, the `contains_yield_deep?` materialization guard, and the
  `Array#index(value)` nilable contract guard.
  Generated s2 compiling `src/adamas.cr` to s3 no longer exits in the old
  `inline_try_with_block`, `lower_super`, `String#size`, `pack_splat_args`, or
  `contains_yield_deep?` frontiers, and no longer stops in the
  `inline_yield_function` parameter-binding `each_param_with_index` callback or
  the downstream `reorder_named_args` negative-index crash.
  The active red evidence is now a fresh s2 SIGSEGV after `[STAGE2_DEBUG] pass3
  after lower_main call`, with lldb stopping in
  `AstToHir#lower_case <- lower_node`, reached from nested inlined yield
  body. Treat that as the active frontier; do not claim green s2->s3/s3b.
- 2026-06-29 NOTE: the first `get$Q$$String` probes found a real owner-loss
  boundary but no shippable fix yet. Earlier wording that blamed "after splat
  packing" is now stale: direct `full_method_name || ""` debug strings are not
  reliable evidence in this corridor. A later focused trace showed static
  receiver recognition is correct for `src/adamas.cr:13`:
  `Adamas::Compiler::BootstrapEnv.get?` is recognized as a path/static call,
  static lookup selects `Adamas::Compiler::BootstrapEnv.get?$String`, and M3F
  path refine also returns `Adamas::Compiler::BootstrapEnv.get?$String`; final
  lower-call consumption still collapses to bare `get?$String`. Refuted
  branches: pre-pack snapshot restore (no effect),
  `splat_pack_full_method_name` restore (registration-time segfault), broad
  `Path.method` recovery (over-fires to `ArrayLiteralNode.named` stub), scoped
  typed-entry/lib fallback (outer `get?` fixed but inner `BootstrapEnv.get?`
  lowering malformed to `Adamas::Compiler::BootstrapEnv.` with a
  `Pointer(UInt8)` argument), pre-base static-owner reconstruction (s2->s3
  segfaults in `register_function -> annotation_type_ref ->
  monomorphize_generic_class`), and M3E lookup-only static-owner correction
  (patched s2 builds, but s2->s3 segfaults before/after lower_main on repeated
  runs). A later `static_resolved_call_name` carrier attempt, recording the
  selected static/path resolver identity and feeding it back into `lookup_name`,
  fixed the cheap no-prelude `BootstrapEnv.get?("X")` IR reducer (qualified
  call/define, no bare `get$Q$$String` stub) but failed the real self-host
  falsifier: patched s2 compiling `src/adamas.cr` segfaulted early in
  class/module registration, with lldb stopping in
  `Array(TypeRef)#size -> Array(TypeRef)#equals? -> Module#intern_type ->
  AstToHir#type_ref_for_name_inner -> register_concrete_class`. Treat this as
  another refuted local carrier/consumer shape, not a shippable root fix. A
  follow-up path-refine checkpoint probe pinned a sharper self-host-only
  transition: generated s2 writes
  `full_method_name=Adamas::Compiler::BootstrapEnv.get?$String` at the
  PathNode refine entry, keeps it through the top-level-source/exact checks,
  then the third null guard
  `method_name = "" unless v2_string_readable?(method_name)` corrupts the
  neighboring local so `BASE_METHOD` reads `full_method_name=get?`. Later
  hostile rechecks refined this: generated-s2 standalone reducers prove that
  `v2_string_readable?`'s raw-pointer ingredients are themselves not reliable
  under produced code. Stage1 emits `ptrtoint ptr %str` / load-from-pointerof
  and exits with valid buckets; generated s2 emits `ret i64 0` for both
  `str.as(Void*).address` and `pointerof(str).as(UInt64*).value`, and also
  lowers the large `0x0000_7FFF_FFFF_FFFF` bound to `0` in the reduced bucket
  helper. However globally disabling `v2_string_readable?` is refuted too:
  the `BootstrapEnv.get?("X")` reducer then segfaults in
  `String#single_byte_optimizable? -> String#index(Char, Int32) ->
  strip_type_suffix_uncached`, showing other guard sites still protect real
  invalid strings. Unconditional third-guard removal fixed the cheap IR
  reducer (qualified call/define), but exposed a later s2->s3 crash in
  `String#bytesize -> String#ends_with?(Char) -> ensure_accessor_method`.
  Narrower skip attempts using `static_class_name && full_method_name`, a
  carried `path_static_refined` Bool, and a recomputed `PathNode` AST-shape
  Bool all failed under generated s2: the cheap reducer still emitted the
  bare `get$Q$$String` stub. Do not repeat local Bool/string carrier skips in
  this corridor. A narrower lexical-short-name variant
  (derive MemberAccess short names from source and bypass the third guard for
  static calls by assigning `method_name = lexical_method_name`) also failed
  under generated s2: the `BootstrapEnv.get?("X")` reducer still emitted the
  bare `get$Q$$String` stub, and
  `p2_stage2_static_call_named_llvm_no_prelude.sh` still failed. This confirms
  that simply refeeding the short method local at this point is too late or
  still tied to the same fragile local-slot corridor. A helper-level attempt to
  make `v2_string_readable?` `@[NoInline]` was also refuted: host gates stayed
  green and s2 built, but generated s2 still emitted the bare
  `get$Q$$String` stub for the `BootstrapEnv.get?("X")` reducer, and the
  static-call regression still failed. The owner collapse is therefore not
  fixed by changing only helper inlining. An external callsite map carrier
  (store the selected PathNode resolver entry under `node.object_id`, consume it
  as `lookup_name` before M3E) was also refuted: it fixed the
  `BootstrapEnv.get?("X")` reducer under generated s2 (qualified call/define,
  no bare `get$Q$$String` stub), but patched s2 compiling `src/adamas.cr` to s3
  regressed to a SIGSEGV after `lower_main` in
  `AstToHir#pack_splat_args_for_call -> lower_call`. Treat this as another
  bridge-carrier that improves the local oracle while destabilizing the real
  bootstrap path.
  Later explicit-return raw-pointer reducers refuted the broad "produced-code
  raw pointer/int literal lowering is the next root" wording: when the reducer
  preserves explicit returns, stage1-built and generated-s2-built binaries both
  return valid non-null pointer buckets. The earlier raw-pointer reducer mostly
  exposed an unfaithful implicit-final-expression shape, while
  `v2_string_readable?` itself uses explicit returns. The active next step is
  therefore not to patch raw pointer lowering or add another guard carrier. Use
  a read-only identity/registration ledger. The focused
  `Exception::CallStack.skip("x")` no-prelude guard shows the first bad layer in
  HIR: stage1 emits `call Exception::CallStack.skip$String` and a matching
  function body, while generated s2 emits `Class Exception::`, a dummy
  `Type(36)` literal, `call skip$String`, and no
  `Exception::CallStack.skip$String` body. Trace evidence shows
  `full_method_name` is already missing the `$String` suffix by
  `with_arena_done` in generated s2, and the splat-pack corridor further
  collapses the owner/name channel. Next probe: class/nested-method
  registration and selected-call identity ledger for `Exception::CallStack.skip`,
  not another consumer restore, Bool/string carrier, backend forwarder, or
  raw-pointer fix. The first registration probe now pins that direction further:
  stage1 registers the nested body on the current `AstArena` as
  `Exception::CallStack.skip$String`, while generated s2 sees the same nested
  body through a `VirtualArena` where the body member is a generic `Node`, fails
  `arena_fits_class_node?`, fails source reparse repair, and falls back to
  registering the method under `Exception::.skip$String`. Instrumented
  generated-s2 repair showed source and slice recovery are good (`class
  CallStack`, `roots=1`, `arena present=1`), but fetching the reparsed root via
  `AstArena#[]?` returns nil for a valid root (`expr=1`, `null=0`, `invalid=0`,
  `arena_size=2`). A narrow `[]?` -> strict `[]` patch inside
  `reparse_class_from_current_source` was refuted: patched stage1 passed the
  static-call guard and built fresh s2, but patched generated s2 still emitted
  bare `skip$String` with no owner-qualified body. Do not repeat that
  consumer-local repair tweak. Next probe must name whether the reparsed
  `AstArena` root/slot storage, `TypedNode?` materialization, or the outer
  `VirtualArena` node-body storage is the real producer.
  Two behavior attempts after that probe were refuted and reverted. First,
  changing `resolve_class_name_for_definition` to split qualified names with
  explicit `byte_slice` lengths moved one sub-boundary: generated s2 registered
  `Class Exception::CallStack` instead of `Class Exception::`, but the focused
  static-call guard still failed and HIR still emitted bare `call skip$String`
  with no owner-qualified body. Second, adding an exact typed PathNode target
  check before M3F path-refine fallback also failed under generated s2: the same
  bare `skip$String` HIR remained. Do not ship either as a standalone fix. The
  selected-name-to-BASE identity channel has now been root-fixed at the
  short-circuit lowering layer, not by another resolver carrier: a primitive
  generated-s2 trace pinned the first bad transition to
  `_post_fmn_ok = full_method_name.nil? || full_method_name == method_name`,
  where the RHS nilable narrowing of `full_method_name` leaked out of the value
  `||` expression and corrupted the later `full_method_name || ...` read. The
  fix scopes value-expression short-circuit RHS narrowing with the same
  restore-if-unchanged mechanism previously used for condition-context RHS
  narrowing. Guard:
  `regression_tests/short_circuit_value_narrowing_leak.cr` is red on the old
  shape with SIGSEGV in `String#bytesize` and green after the fix; the older
  `regression_tests/short_circuit_condition_narrowing_leak.cr` remains green;
  `regression_tests/run_all_suites.sh /tmp/adamas_value_narrow_fix_stage1 4`
  passed 152/152 original + 36/36 combined. Fresh fixed generated s2 now
  preserves the call identity through BASE:
  `lookup=Exception::CallStack.skip`, `mangled=Exception::CallStack.skip$String`,
  and HIR contains `call Exception::CallStack.skip$String`. Residual frontier:
  the body is still not materialized in generated-s2 HIR, and running the
  no-prelude binary aborts with
  `STUB CALLED: Exception$CCCallStack$Dskip$$String`. The next probe is
  nested static method body registration/materialization for the already-correct
  call symbol, not owner-loss, `v2_string_readable?`, raw-pointer lowering,
  exact-target rebinding, or another local resolver carrier.
- 2026-06-29 UPDATE: the nested static class-method body registration sibling
  is fixed. After the value short-circuit narrowing fix, generated s2 already
  lowered `Exception::CallStack.skip("x")` to the correct call symbol
  `Exception::CallStack.skip$String`, but registered the nested body as
  `Exception::.skip$String`; the generated binary then aborted in the backend
  stub for the correct call symbol. Root was mixed String indexing in
  `resolve_class_name_for_definition`: `rindex("::")` is consumed as a byte
  offset, but the leaf was sliced through the self-host-fragile range path.
  The fix uses byte slices for both owner and leaf. Guard:
  `regression_tests/nested_class_static_method_registration_repro.sh`. Fresh
  fixed s2 no-prelude HIR now contains both call and body under
  `Exception::CallStack.skip$String`, and the generated no-prelude binary exits
  0. Full stage1 suites pass (`152/152` originals + `36/36` combined). Residual
  frontier: fresh fixed s2 compiling `src/adamas.cr` still aborts before
  producing s3, now at
  `STUB CALLED: Adamas::HIR::AstToHir#try_resolve_simple_default(...)`. Treat
  that as the active frontier; do not claim green s2->s3/s3b.
- 2026-06-29 UPDATE: the `try_resolve_simple_default` stub frontier is fixed at
  the producer layer. Root was not resolver scoring or the helper's signature:
  truthy narrowing only unwrapped `Nil | T` when there was exactly one non-Nil
  variant. For all-reference unions with multiple non-Nil variants, such as
  `Nil | AstArena | PageArena | VirtualArena`, `lower_not_nil_intrinsic`
  returned the original nilable value. The allocator default loop then called
  `try_resolve_simple_default(default_node, default_arena, ivar.type)` with a
  still-nilable `default_arena`, so overload resolution missed the
  non-nil `ArenaLike` overload and emitted an abort stub into generated s2. The
  fix removes `Nil` for all-reference unions by emitting a typed pass-through
  `Copy` to the `union-minus-Nil` type; mixed/value unions remain conservative.
  Guard: `regression_tests/multi_ref_union_truthy_narrowing_repro.sh`, red on
  the previous stage1 (`CALL_LOOKUP_MISS func=accept`, runtime stub) and green
  after the fix (`RESULT=11`). Stage1 -> s2 trace now shows
  `try_resolve_simple_default` arg types as
  `Node, AstArena | PageArena | VirtualArena, TypeRef`, selected overload
  `$ArenaLike_TypeRef$arity3`, and HIR+MIR bodies present. Full stage1 suites
  pass (`152/152` originals + `36/36` combined). Residual frontier: fresh fixed
  s2 compiling `src/adamas.cr` now moves past the stub and stops later with
  `error: Empty enumerable`; do not claim green s2->s3/s3b.
- 2026-06-29 UPDATE: the `error: Empty enumerable` frontier is fixed as a
  guarded short-type-index lookup. Root was a direct `Set#first` in
  `resolve_short_type_in_namespace_chain`: generated s2 reached
  `Nil | Exception::CallStack` from `Exception#backtrace?`
  (`@callstack.try &.printable_backtrace`), found a singleton
  `@short_type_index["CallStack"]`, but that generated `Set` reported
  `size == 1` while yielding no first value, so `Set#first` raised
  `Enumerable::EmptyError`. The fix reuses the existing `safe_set_first?`
  guard for the final singleton candidate and fails closed to `nil` when the
  self-hosted `Set` is internally inconsistent. Guard:
  `regression_tests/p2_short_type_index_first_no_prelude.sh` now also forbids
  direct `Set#first` in this resolver. Full stage1 suites pass (`152/152`
  originals + `36/36` combined). Refuted: skipping short namespace resolution
  for all union owners overcorrected and made produced s2 crash immediately
  after `prelude exists`. Residual frontier: fresh fixed s2
  compiling `src/adamas.cr` moves past `Empty enumerable`, reaches
  `[STAGE2_DEBUG] pass3 after lower_main call`, then segfaults in
  `String#size <- scan_hir_function_for_live_types <- initialize_lazy_rta <-
  flush_pending_functions`; do not claim green s2->s3/s3b.
- HARD BOUNDARY: keep `BlockOwner`. Do not revert `@block_owner` back to
  `NamedTuple` or positional `Tuple`; that rollback re-enters an already
  observed materialization/key-shape trap.
- FIXED: `case x; when StructConstant` now uses Crystal's
  `condition === subject` semantics for non-primitive conditions instead of raw
  storage/pointer equality. The focused guard is
  `regression_tests/struct_constant_case_equality_repro.sh`; it is red on
  baseline `d623f52f` (`case=miss`) and green on the fixed compiler
  (`case=hit`). Primitive scalar case comparisons still use raw `Eq`.
- FRONTEND SLICE CLOSED: s2 previously parsed `String#dump_or_inspect_unquoted`
  incorrectly because the two-pass `lex_string` fast path treated escaped
  `\\\#{` as real interpolation and swallowed the rest of the class body.
  `lex_string` now uses one processed scanner for all string literals, and
  processed token slices are retained through `StringPool`. The existing
  parsed-class debug oracle is also stage2-safe in body-count mode. The new
  regression is intentionally parser/HIR-frontier scoped; it does not claim
  full s2 program compilation.
- STALE EVIDENCE: the previous `IO#<<$String` / `String`-as-`Unknown` /
  `TypeRef.new(15)` case-identity ledger described an earlier frontier before
  the escaped-interpolation parser fix. Do not continue from that row unless it
  is re-observed on the current tree.
- REQUIRED NEXT SLICE (read-only/default-off first): re-run the bootstrap gate
  from the new clean full-prelude baseline and localize the next observed
  `s2b`/`s3b` boundary. Do not continue patching `Random#rand_int`,
  `lower_field_get`, `Time::Location.local`, or `Time::Format#initialize` unless
  `regression_tests/stage2_lower_field_get_full_prelude_frontier_repro.sh`
  regresses or new evidence names a fresh boundary in those older slices.
- DEAD-CODE/BLOAT TRACK: classify backend fallback and repair paths touched by
  the current batch (`emit_dead_code_stub`, `lookup_module_function_for_extern`,
  `fixup_call_arg_types`, `emit_functions_parallel` bootstrap workarounds) using
  `CodePathStatus` before deleting or expanding them. Backend fixes that
  re-resolve source-level semantics are not architecture fixes unless a
  materialization boundary says they are the owner.
- MERGE RULE: merge to `main` only after the current batch is split into
  verified commits or replaced by smaller verified slices, and after fresh
  stage1, fresh s2, direct `puts "x"`, the escaped-interpolation regression,
  and the relevant stage2 regressions all pass under the declared compiler.

## 2026-06-27 — fixed block-shorthand Array index dispatch

- FIXED: `parsed.map(&.[0])` and `parsed.map(&.[i])` no longer lower the
  synthetic `__arg0.[](idx)` CallNode to `Array(T)#[](Range)` while passing an
  `Int32` index as the Range pointer. The bug surfaced in s3 while compiling
  `src/adamas.cr`: `AstToHir#try_unify_tuple_variant_names` used
  `parsed.map(&.[i]).uniq`, and the generated s2 called
  `Array(String)#[](Range)` with an integer index, crashing in `Range#begin`.
- Root: parser block shorthand expands `&.[idx]` into a CallNode, not an
  IndexNode. The existing IndexNode path already treated `Array#[](non-Range)`
  as direct element access, but the CallNode path went through overload
  resolution and selected the Range overload despite `arg_types=Int32`.
  Fix: in `lower_call`, for `Array`/`StaticArray` receivers, `[]`, one arg, and
  an argument that is not Range by AST or TypeRef, emit the same `IndexGet`
  element access as IndexNode lowering.
- Regression guard: `regression_tests/block_shorthand_array_index_repro.sh`
  covers literal shorthand, local-index shorthand, explicit block indexing, and
  direct Range slicing.
- Verified for this slice:
  `regression_tests/block_shorthand_array_index_repro.sh
  /tmp/adamas_array_shorthand_fix`;
  `regression_tests/stage2_indexable_range_materialization_repro.sh
  /tmp/adamas_array_shorthand_fix`;
  `regression_tests/arc_unionwrap_cross_block_owned_return_repro.sh
  /tmp/adamas_array_shorthand_fix`; and
  `regression_tests/run_all_suites.sh /tmp/adamas_array_shorthand_fix 4`
  passed originals 151/151 + combined 36/36.
- Bootstrap status: fixed stage1 builds s2 successfully:
  `scripts/run_safe.sh /tmp/adamas_array_shorthand_fix 900 12288
  src/adamas.cr -o /tmp/adamas_array_shorthand_s2` exits 0. Fresh s2 then gets
  past the previous `Range#begin`/`try_unify_tuple_variant_names` crash, but s3
  still fails with a separate `Bus error` in `Slice(UInt8).cmp` called from
  `Slice(Tuple(String, Int32)).merge_sort!` /
  `Array(Tuple(String, Int32))#sort!` inside
  `AstToHir#resolve_union_method_call`. Treat that as the next frontier; do not
  conflate it with Array Range slicing.

## 2026-06-27 — fixed sort comparator Proc carrier through s2

- FIXED: the post-Array-shorthand s2 no longer crashes in the
  `Array(Tuple(String, Int32))#sort!` / `Slice(UInt8).cmp(..., Proc)` corridor
  while compiling `src/adamas.cr` toward s3. The old crash was a double-carrier
  Proc bug: `Array#sort!(&block)` forwarded a materialized Proc object into
  `Slice#sort!(&block)`, which wrapped it again; `Slice(UInt8).cmp` then loaded
  the inner Proc object pointer as if it were a function pointer.
- Root slice: block-suffix calls now forward the raw callback carrier to callee
  block parameters. Raw callback materialization remains reserved for ordinary
  `Proc` / `Proc?` parameters, and the raw-proc coercion path now skips callee
  parameters that are real block parameters.
- Second boundary in the same corridor: once the carrier was correct,
  `Slice(UInt8).cmp(v1, v2, block)` still lowered `block.call(v1, v2)` as
  `void` because the comparator parameter is bare `Proc` and loses return
  shape. This slice recovers the stdlib comparator contract for
  `Slice(UInt8).cmp` as `Int32`; this is not a general erased-Proc return
  inference fix.
- Regression guard: `regression_tests/sort_by_tuple_key_runtime_repro.sh` now
  fails on crash/non-zero exit or wrong output and requires the sorted output
  `1,2,3`.
- Verified for this slice: `regression_tests/sort_by_tuple_key_runtime_repro.sh
  /tmp/adamas_block_proc_cmp_fix` passes; block-shorthand Array index,
  stage2 indexable Range materialization, and ARC UnionWrap cross-block guards
  pass; `regression_tests/run_all_suites.sh /tmp/adamas_block_proc_cmp_fix 4`
  passes originals 151/151 + combined 36/36; static LLVM IR shows
  `Array#sort!$block` forwarding raw `%block` to `Slice#sort!$block`,
  `Slice#sort!$block` materializing exactly one Proc for `merge_sort!`, and
  `Slice(UInt8).cmp(..., Proc)` calling the comparator as `i32` and returning
  that `i32`.
- Bootstrap status: fixed stage1 builds s2 successfully:
  `scripts/run_safe.sh /tmp/adamas_block_proc_cmp_fix 900 12288 src/adamas.cr
  -o /tmp/adamas_block_proc_s2` exits 0. Fresh s2 gets past the previous
  sort/comparator crash, then s2->s3 fails later with `SIGSEGV` in
  `AstToHir#inline_try_with_block` after `pass3 after lower_main call`.
  Disabling try inline changes the failure to
  `STUB CALLED: Adamas::HIR::AstToHir::class_name:String#empty?`, so the new
  frontier is not yet root-classified; do not conflate it with the closed
  sort/Proc carrier slice.

## 2026-06-27 — fixed enum-member generic inference for filled arrays

- FIXED: generated `s2b` no longer crashes the no-prelude smoke in
  `Adamas::HIR::EscapeAnalyzer#build_summary` after `lower_main`. The first bad
  producer was `EscapeSummary#initialize`: `Array.new(param_count,
  LifetimeTag::StackLocal)` inferred the generic owner as
  `Array(LifetimeTag::StackLocal)` instead of `Array(LifetimeTag)`. That
  singleton-member array materialized `initialize(Int32, LifetimeTag)` as a
  no-arg zeroing body, leaving `@buffer = null`; `build_summary` then wrote the
  first parameter lifetime into that null buffer.
- Root: `infer_type_name_from_node(PathNode)` treated enum member paths as type
  names when generic constructors inferred type arguments from AST nodes. Enum
  members are values of their declaring enum, so `SomeEnum::Member` now
  canonicalizes to `SomeEnum` when the path matches a registered enum member.
- Regression guard: `regression_tests/enum_member_array_new_repro.sh` covers
  `Array.new(size, Enum::Member)` and verifies the array is usable as
  `Array(Enum)`.
- Verified for this slice: `crystal build src/adamas.cr -o bin/adamas
  --error-trace`; `regression_tests/enum_member_array_new_repro.sh
  bin/adamas`; `regression_tests/array_filled_pointer_value_dup_repro.sh
  bin/adamas`; `regression_tests/hash_block_shape_default_proc_repro.sh
  bin/adamas`; `regression_tests/run_all_suites.sh bin/adamas 4` passed
  originals 151/151 + combined 36/36. ASAN bootstrap
  `scripts/bootstrap_chain.sh --stages 2 --out
  /tmp/adamas_bootstrap_enum_owner_fix --timeout 900 --mem 12288` builds s2 and
  both s2 plain and no-prelude smokes pass. Static IR check shows
  `EscapeSummary#initialize` now calls
  `Array(Adamas::HIR::LifetimeTag).new(Int32, LifetimeTag)`, whose initializer
  allocates/fills the buffer for non-zero size.
- CURRENT FRONTIER: one stage deeper, ASAN
  `scripts/bootstrap_chain.sh --stages 3 --out
  /tmp/adamas_bootstrap_enum_owner_fix_s3 --timeout 900 --mem 12288` gets
  through s1 and s2 (both smokes green), then fails the s3 build during module
  registration (`module register idx=151/268`) in
  `Adamas::Compiler::Frontend::ExprId#invalid?`. `ExprId` is a 4-byte struct,
  but generated `invalid?` has signature `(ptr %self)` and the crashing receiver
  is `0x000c00001102`, a non-null scalar-looking value. Treat this as the next
  by-value `ExprId`/struct-call ABI frontier; do not patch `invalid?` with a
  broader guard, because the immediate problem is an invalid call/receiver
  representation.

## 2026-06-22 — s2b phantom `Adamas::MIR::Hash` under-alloc: tactical fix landed; resolver bug A deferred

- FIXED (tactical, this branch): self-host `@value_def_block` backend crash
  (`emit_function` → `@value_def_block.clear` → `__bzero` @ `0x7fffffffffffffff`).
  Root: the debug reopens `class ::Hash(K,V)` / `struct ::Set(T)` /
  `class ::Array(T)` (adding `adamas_debug_structural_bytes`) were nested inside
  `module Adamas::MIR` in `llvm_backend.cr`; the absolute `::` is stripped at name
  extraction and the bare builtin base is re-qualified to a PHANTOM
  `Adamas::MIR::Hash` generic template (no ivars) → size-4 ClassInfo →
  `.new` under-allocates 12B while real `::Hash#initialize` writes ~56B →
  adjacent-heap stomp. Fix = moved the 3 reopens to top level (outside the
  module). Verified: 0 `Adamas::MIR::(Hash|Set|Array)` phantom symbols,
  `@value_def_block` now real `::Hash(UInt32,UInt64)` (64B, type_id 2045),
  `x=1` 5/5 EXIT 0, suites 148/148 + 36/36, `hash_dual_typeref_phantom_repro` PASS.
- DEFERRED — central resolver bug (A): an absolute `class ::X` reopen written
  *inside* a module must preserve the top-level base in definition registration.
  `definition_leaf_name_from_header_text` (ast_to_hir.cr:6686) drops the `::`;
  `qualified_nested_type_name` (:6977) and `resolve_class_name_for_definition`
  (:45225) then re-qualify the bare builtin base with the enclosing namespace.
  Needs a coordinated definition+reference fix; 5 narrow attempts failed (see
  memory `s2b_value_def_block_phantom_hash_underalloc`). NOT fixed here.
- NEW FRONTIER (surfaced by the fix, NOT a regression): s2b compiling a
  non-trivial program stack-overflows (SIGBUS) in the `Array(T)#join` super-chain
  recursion (`join → join_super_from_Enumerable → join_super_from_Indexable →
  join`), crashing in `String::Builder#initialize`. Separate super-chain family
  bug (cf. `super_chain_module_class_collision_fix`); do not bundle.

## Goal

Reach a clean bootstrap corridor:

`original -> stage1 -> s2b -> s3b -> s4b -> s5b`

with normalized HIR/MIR/LLVM semantic equivalence across stages.

Working policy:

- Prefer fast `--no-prelude` oracles.
- Use `s1 -> s2b` as the main integration gate.
- Run `s1 -> s5b` rarely, after `s1 -> s2b` is clean.

## 2026-06-26 — fixed s2b no-prelude interpolation helper materialization

- FIXED: fresh generated `s2b` no longer aborts the no-prelude interpolation
  smoke on `STUB CALLED:
  Adamas::MIR::LLVMIRGenerator#interpolation_i32_arg(String, UInt32, String,
  Int32, <large union>)`. The immediate boundary was the backend helper call
  sites: `part_type` is a compiler metadata value whose source contract is
  `Nil | MIR::TypeRef`, but V2 could record the callsite hint argument as a
  large value-domain union under self-hosting. Each call into
  `interpolation_i32_arg(..., hint_type : TypeRef?)` now asserts that boundary
  contract with `part_type.as(TypeRef?)`, so the requested helper symbol is
  materialized as `Nil | TypeRef` instead of as a live huge-union abort stub.
- Scope: this is a focused frontier fix, not a global cure for value-domain
  pollution around compiler metadata values. A local annotation on `part_type`
  was tested and did not change the self-hosted helper symbol; the residual
  root-family remains "why V2 admits value-domain unions for TypeRef metadata
  flow". Do not generalize this slice into a backend stub rescue.
- Regression guard: `regression_tests/p2_generated_stage2_no_prelude_interp.sh`
  now reports this exact `interpolation_i32_arg` stub separately when it
  regresses.
- Verified for this slice: `crystal build src/adamas.cr -o
  /tmp/adamas_interp_cast_out --error-trace`;
  `regression_tests/p2_generated_stage2_no_prelude_interp.sh
  /tmp/adamas_interp_cast_out`; `regression_tests/run_all_suites.sh
  /tmp/adamas_interp_cast_out 4` passed originals 151/151 + combined 36/36.
  Fresh `scripts/bootstrap_chain.sh --stages 2 --out
  /tmp/adamas_bootstrap_interp_cast_s2_current --timeout 900 --mem 12288`
  builds s2 and the s2 no-prelude smoke passes. Static IR check on
  `/tmp/adamas_bootstrap_interp_cast_s2_current/cv2_s2.ll` shows the real
  `interpolation_i32_arg(String, UInt32, String, Int32, Nil | TypeRef)` body
  and no old live huge-union stub.
- CURRENT FRONTIER: the same fresh bootstrap-chain run built s2 but its first
  full-prelude plain smoke hit a separate `EXIT 133` / `EXC_BREAKPOINT` in
  `libsystem_malloc`, with lldb showing
  `__adamas_file_read -> AstToHir#constant_source_text ->
  record_constant_definition` during module/class registration. A direct plain
  rerun can pass, but a repeated smoke reproduced the trap, so do not claim
  full `s1 -> s2b` green or attempt `s3b` until this full-prelude
  `constant_source_text`/file-read memory frontier is reduced.

## 2026-06-26 — fixed over-broad filled-array helper fast-path; next smoke frontier named

- FIXED: `Array.new(size, value)` no longer routes every non-Bool value through
  the Int32 filled-array helper. That helper hardcodes 4-byte element stride and
  the `Array(Int32)` runtime type id, so pointer-valued arrays such as
  `Array(String).new(2, "x")` received an 8-byte backing buffer for two pointer
  elements. A later `Array#dup` copied 16 bytes and ASAN reported a
  heap-buffer-overflow in `__adamas_ptr_copy`.
- Root: the HIR call fast-path in `ast_to_hir.cr` treated
  `Array.new(size, value)` as a generic filled-array constructor but selected
  only `__adamas_array_new_filled_bool` or `__adamas_array_new_filled_i32`.
  The helper contract was narrower than the call intercept. Fix: use the
  helpers only for their exact element types (`Bool`, `Int32`) and let all other
  element types use the normal `Array(T).new` materialization path.
- Regression guard: `regression_tests/array_filled_pointer_value_dup_repro.sh`
  compiles and runs `Array(String).new(2, "x").dup` under ASAN.
- Verified for this slice: `crystal build src/adamas.cr -o bin/adamas
  --error-trace`; `regression_tests/array_filled_pointer_value_dup_repro.sh
  bin/adamas`; focused `Array(Int32)`/`Array(Bool)`/`Array(String)` smoke;
  `regression_tests/run_all_suites.sh bin/adamas 4` passed originals 151/151 +
  combined 36/36.
- Bootstrap status: ASAN `scripts/bootstrap_chain.sh --stages 2 --out
  /tmp/adamas_bootstrap_plain_asan_arrayfix --timeout 900 --mem 12288` builds
  s2. The old `Array(HIR::TypeRef)#dup` heap-buffer-overflow is gone. Both s2
  plain and no-prelude smokes now stop at a new separate frontier:
  `Hash(Adamas::Compiler::Semantic::DefIdentity, Int32).new(Int32, Nil)`
  dereferences null (`READ` from zero page, exit 134). The prior
  `constant_source_text`/file-read frontier is therefore stale for this branch;
  do not keep debugging it without re-reproduction.
- CLOSED FOLLOW-UP (`bf67d667`): standalone `Hash(String, Int32).new(0)`,
  `Hash(String, Int32).new { ... }`, and `Hash(String, String).new("x")`
  default-provider reducers now compile and run. Root: generated allocator
  lookup could miss `Hash#initialize(block : Proc?, *, initial_capacity)` and
  raw block callbacks passed as Proc/Proc? arguments were not materialized as
  heap Proc objects. Fix: retry allocator initialize lookup with named-only
  compatibility after the positional miss, materialize raw callback values at
  Proc/Proc? call boundaries, and preserve raw callback carrier provenance for
  Proc-typed block-wrapper parameters. Regression guard:
  `regression_tests/hash_default_provider_proc_repro.sh`.
- Verified for this slice: `crystal build src/adamas.cr -o bin/adamas
  --error-trace`; `regression_tests/hash_default_provider_proc_repro.sh
  bin/adamas`; `regression_tests/array_filled_pointer_value_dup_repro.sh
  bin/adamas`; stateful closure Hash default-provider smoke; and
  `regression_tests/run_all_suites.sh bin/adamas 4` passed originals 151/151 +
  combined 36/36.
- CURRENT FRONTIER: ASAN
  `scripts/bootstrap_chain.sh --stages 2 --out
  /tmp/adamas_bootstrap_hash_default_fix --timeout 900 --mem 12288` now builds
  s2, but s2 plain/no-prelude smokes still fail in a sibling Hash constructor
  materialization case. In `cv2_s2.ll`,
  `Hash(Adamas::Compiler::Semantic::DefIdentity, Int32).new(Int32, Nil)` now
  correctly builds a heap Proc default provider, then calls
  `new$block$arity1` after loading `initial_capacity` from a null Nil pointer.
  The target `new$block$arity1` body was materialized with an `Int32`
  initial-capacity parameter and reused for the default-value path where
  `initial_capacity` is Nil. Treat this as an arity-only block-wrapper
  call-shape/materialization collision, not as the raw Proc/default-provider
  root fixed by `bf67d667`.

## 2026-06-26 — fixed tuple/hash bootstrap frontiers; next s2b frontier named

- FIXED: mixed tuple equality/hash and Hash tuple keys with nilable fields no
  longer miscompile under stage1 V2. Two root causes were removed:
  (1) mixed tuple element comparison/hash now lowers element-wise instead of
  routing scalar elements through String equality/hash shapes; (2) tuple
  container provenance is preserved through HIR -> MIR `IndexGet`, so Hash
  tuple keys are not read with Array `size/buffer` layout.
- FIXED: `Int32#remainder(Int64)` / `Crystal::Hasher.reduce_num(Int32)` no
  longer truncates the large Int64 modulus before `srem`; div/rem now evaluate
  in an operation width wide enough for both operands, then truncate to the MIR
  result width.
- Regression guards:
  `regression_tests/tuple_equality_hash_repro.sh`,
  `regression_tests/hash_tuple_key_nilable_field_repro.sh`,
  `regression_tests/int_remainder_mixed_width_repro.sh`, and
  `regression_tests/stage2_indexable_range_materialization_repro.sh`.
- Verified: `crystal build src/adamas.cr -o /tmp/adamas_commit_candidate
  --error-trace`; focused guards above; existing
  `hash_named_tuple_index_assign_materialization_repro.sh` (retired later after
  the `BlockOwner` carrier replaced the old NamedTuple owner cache);
  `regression_tests/run_all_suites.sh /tmp/adamas_commit_candidate 4` passed
  originals 151/151 + combined 36/36.
- PREVIOUS FRONTIER (closed by the section above): fresh
  `scripts/bootstrap_chain.sh --stages 2 --out
  /tmp/adamas_bootstrap_d48a73dc_s2 --timeout 900 --mem 12288` builds s2b and
  passes the plain smoke, but the generated s2b fails the no-prelude smoke with
  `STUB CALLED:
  Adamas::MIR::LLVMIRGenerator#interpolation_i32_arg(String, UInt32, String,
  Int32, <large union>)`. Do not attempt s3b until this
  `interpolation_i32_arg` materialization frontier is reduced.

## 2026-06-25 — fixed s2b full-prelude wildcard base-dir corruption

- FIXED: produced s2b no longer falls into `error: Unreachable` while resolving
  stdlib `indexable.cr`'s `require "./indexable/*"`. Root: `safe_dirname`
  still depended on `String#rindex('/')`; under self-hosting that call returned
  the final `.cr` byte position for `.../indexable.cr`, producing
  `.../src/stdlib/indexable.` as `base_dir`. The primary wildcard resolver then
  looked for `indexable./indexable`, returned nil, and the source fallback
  reached the stage2-broken `Dir.glob` path. Fix: split CLI paths with a
  byte-local reverse separator scan instead of `String#rindex(Char)`.
- Regression: `regression_tests/stage2_full_prelude_wildcard_require_repro.sh`
  is a focused s2b guard. It is red on the old s2b (`Warning: Could not resolve
  require './indexable/*'` / `error: Unreachable`) and green when
  `./indexable/*` resolves to `src/stdlib/indexable/mutable.cr`.
- NEW FRONTIER: the same full-prelude `puts 42` corridor now passes parsing and
  HIR setup, then aborts in `lower_main` with
  `STUB CALLED: Adamas::HIR::AstToHir#yield_return_function_for_block_call?...`.
  This is a separate materialization/demand frontier; do not bundle it with the
  path helper fix.

## 2026-06-26 — fixed s2b yield-return block-call nilable wrapper materialization

- FIXED: produced s2b no longer aborts in `lower_main` on
  `STUB CALLED: Adamas::HIR::AstToHir#yield_return_function_for_block_call?...`.
  Root: source registration only had the concrete first-argument overload
  (`mangled_name : String`), while the self-hosted call demand used
  `mangled_name : String?`. The materializer could not find a DefNode for the
  nilable wrapper and emitted an undefined-extern stub. Fix: add the explicit
  `String?` overload that fail-closes on nil and delegates to the concrete
  overload when present.
- Regression: `regression_tests/stage2_yield_return_block_call_materialization_repro.sh`
  is red on the post-dirname s2b and green once the nilable wrapper is
  materialized. It is intentionally focused: downstream full-prelude compilation
  may still fail after this frontier has moved.
- NEW FRONTIER: the same full-prelude `puts 42` corridor now reaches a later
  abort in `AstToHir#lower_block_to_proc(...)`. This is a separate
  block/proc materialization-demand frontier; do not bundle it with the
  yield-return wrapper fix.

## 2026-06-26 — fixed s2b lower_block_to_proc arena type materialization

- FIXED: produced s2b no longer aborts in `lower_main` on
  `STUB CALLED: Adamas::HIR::AstToHir#lower_block_to_proc...`. Root: the source
  helper signature requires `block_arena : Frontend::ArenaLike`, but self-hosted
  lowering inferred the local `block_arena_for_proc` at the three materialization
  callsites as wider unions such as `Nil | ArenaLike | String` or pointer-erased
  forms. Resolver saw the registered overload but rejected it as incompatible,
  then queued/stubbed the call-symbol. Fix: add explicit `ArenaLike` local
  annotations at the three `lower_block_to_proc` callsites. This preserves the
  runtime arena selection expression and only restores the declared helper
  contract for call-symbol materialization.
- Regression: `regression_tests/stage2_lower_block_to_proc_materialization_repro.sh`
  is red on the post-yield s2b (exact `lower_block_to_proc` stub) and green once
  the arena local is constrained. The guard is intentionally focused: it accepts
  the downstream full-prelude failure after the stub frontier moves.
- Verified: stage1 build; old-s2b red/new-s2b green focused guard; existing
  yield-return guard remains green; fresh s2b compiles and runs no-prelude
  `x = 1`; full stage1 suites pass 149/149 originals + 36/36 combined.
- NEW FRONTIER: full-prelude `puts 42` now passes `lower_main` and crashes later
  in MIR lowering: `HIRToMIRLowering#set_block_map` called from
  `mir_block_for` -> `resolve_pending_phis` -> `lower_function_body`. Treat this
  as a separate HIR->MIR block-map/phi frontier, not as a block/proc
  materialization bug.

## 2026-06-25 — fixed HIR RTA pruning of materialized target symbols

- FIXED: self-compiled compiler IR no longer emits the aborting
  `Hash(UInt64, NamedTuple(class_name:String?, method_name:String?, is_class:Bool))#[]=`
  undefined-extern stub. Root was not a backend-forwarder gap: `lower_function_if_needed`
  could materialize a body under the resolved target symbol while the call path
  still used a related requested symbol, and HIR RTA pruned the unreferenced
  target body before MIR. Fix: when materialization chooses the target symbol
  for a distinct requested name, mark that target as a materialization keepalive
  root in `HIR::Module.reachable_function_names`.
- Regression: `regression_tests/hash_named_tuple_index_assign_materialization_repro.sh`
  built self-IR through `run_safe` and failed on any matching abort stub. This
  guard was later retired after the owner cache moved from the old
  `Hash(UInt64, NamedTuple)#[]=` carrier to `Hash(UInt64, BlockOwner)`.
- Verified: stage1 build; focused Hash/NamedTuple self-IR regression; split
  materialization + `split(Char)` + short-circuit-narrowing guards; full suites
  149/149 originals + 36/36 combined. Fresh s2b builds and compiles a no-prelude
  `x = 1` smoke. The later `error: Unreachable` frontier is superseded by the
  path-helper fix above.

## Open Design Constraints

- Do not solve block/proc or generic-container demand bugs with fixed nesting
  depth caps. Real Crystal programs can contain deeply nested block, tuple,
  hash, array, proc, and iterator shapes. Guards may use focused negative
  patterns to catch known bad demand, but production fixes must preserve
  demanded deep shapes and remove only proven non-demand/root pollution.

## Deferred Designs

- **`@[Inline]` field-embedding annotation** — see
  `docs/inline_field_annotation_sdd.md`. Status DEFERRED after a hostile
  Quadrumvirate (2026-06-16): the idea is sound but mis-ordered. It must NOT
  precede (1) consolidation of the 3 layout oracles through `LayoutContract`
  and (2) the #4 repr-flip fix, because a per-field pointer-vs-inline override on
  un-consolidated oracles injects #4-class non-deterministic crashes. v1 scope
  = struct fields only (= opt-in, incremental step-4, Crystal-checkable);
  class-field embedding deferred behind an interior-ref leak check. Demand is
  narrow (~2-3% of compiler ivars; containers/primitives dominate and are out
  of scope) — measure access-frequency before investing.

- **"struct vs class on stack" / unified object model** — see
  `docs/class_on_stack_unified_model_review.md`. Status DEFERRED after a hostile
  Quadrumvirate (2026-06-16): discussion record, not a plan. "struct vs class =
  only copy semantics" is an oversimplification (identity/mutation/nil/dispatch
  derive from copy policy); "class on stack, LLVM SROA finishes it" is false —
  the `$Dnew` malloc is struct-gated (`hir_to_mir.cr:5800`/`:5854`), so a
  StackLocal class still mallocs; the unified model is premature while #4 is
  open and perf is unmeasured. Same blockers as `@[Inline]` (oracle
  consolidation + #4 fix) plus sound interprocedural escape + non-observable
  identity. NOT current work — current work is struct inlining (step-4).

## ABI-rework: layout-oracle consolidation

Goal: collapse the layout oracles onto the single `LayoutContract` so the #4
repr-flip family cannot live in their disagreements.

IMPORTANT refinement (2026-06-16): there are TWO distinct repr regimes, not one.
(a) **Field storage** — a struct as a class/struct FIELD: inline iff
`user_struct_inline?` = family OR `size > pointer_word`. (b) **Container element**
— a struct as Array/Slice ELEMENT: inline iff `inline_container_family?` ONLY; a
>8-byte plain user struct is still a POINTER element (inlining it corrupts
`Array(Parameter)`, llvm_backend.cr:2773). The two regimes share only the family
sub-predicate. So "route every oracle through one repr predicate" is WRONG — it
would inject divergence. Consolidate the shared piece (the family name-list) and
keep the two regimes distinct.

- **1c — MIR field-access readers (DONE, `66d6c015` 2026-06-16).** Routed
  `lower_field_get` (hir_to_mir.cr:2863) and `lower_field_store_to_ptr` (:3047)
  through `LayoutContract.user_struct_inline?`. Surfaced and fixed a latent
  pointer-word boundary divergence: HIR `user_struct_inline?` used `>= 8` while
  the MIR readers used `> 8`, so an exactly-8-byte struct value was INLINE per
  HIR but a POINTER CARRIER per MIR — masked only because both occupy one slot,
  but a step-4 repr-flip in waiting. Aligned the contract to `>` (matches the
  behavioural readers). Behaviour-neutral: LayoutProbe decision set byte-identical
  (565 decisions); guard `struct_pointer_word_boundary_repro.sh`; suite 159/159 +
  31/31. Per `[[abi_slot_conflict_metric_invalid]]` this is a correctness/clarity
  consolidation, NOT itself a #4 fix.
- **Demand (measured 2026-06-16).** step-4 target is a narrow tail: ~11 distinct
  small (<8B) value-struct field-slots (~5% of struct types); most struct fields
  are already ≥8B inline (215 distinct InlineBytes). Win concentrates in
  runtime-hot structs (Atomic, SpinLock, Timers, Arena::Index); access-frequency
  still unmeasured.
- **2a — LLVM container-element oracle (DONE, 2026-06-16).** Routed
  `inline_container_struct_type?` (llvm_backend.cr:2796) through
  `LayoutContract.inline_container_family?`, collapsing the duplicated family
  name-list (was also at layout_contract.cr:124) onto the single source.
  Behaviour-neutral (textually the same 3 prefixes under the same struct/size
  gate); via the container regime, NOT `user_struct_inline?`. Guard
  `struct_pointer_word_boundary_repro.sh`; suite 159/159 + 31/31.
- **1b — label unification (REFRAMED, not a neutral routing).** Routing the
  LayoutProbe container-element label through `LayoutContract.repr` is NOT
  behaviour-neutral: `repr` encodes FIELD semantics (`user_struct_inline?`,
  size>8 → InlineBytes) while the container-element probe uses CONTAINER
  semantics. Doing it as-is would make the label disagree with the actual
  storage. Needs a container-regime `repr` variant first, or leave the probe
  label site-local. LOW priority (diagnostic only).
- **mir_field_storage_size (REFRAMED, NOT a repr oracle).** hir_to_mir.cr:6383
  is a SIZE helper (returns bytes, returns `desc.size` for aggregates), used
  only in `trivial_struct_initializer_covers_all_storage?` where a wrong size is
  fail-safe (skips the trivial-init opt, no miscompile). It is NOT a #4 repr-flip
  source and should NOT be force-routed through the repr predicate (that would
  change small-struct field sizes 4→8 and toggle the opt). Leave as-is; document.
- **Next: step-4 flip.** With the field regime single-sourced (1c) and the
  container family list single-sourced (2a), the remaining work toward the perf
  win is the step-4 flip itself — make small (<8B) user-struct FIELDS inline at
  `user_struct_inline?` (the one flip point), gated/measured per the demand tail
  above. This is the Collapse move (remove the carrier box), CAUTION-tier; needs
  the #4 producer understood first.
  - **Scaffold shipped (gated OFF), `7abbfa08`.** `ADAMAS_INLINE_SMALL_STRUCTS`
    env gate read at COMPILE time via `LayoutContract.user_struct_inline?`;
    gate-OFF byte-identical to baseline (no rebuild needed to toggle).
  - **gate-ON full parity reached (2026-06-18).** Running the full matrix gate-ON
    vs the gate-OFF baseline surfaced exactly two non-routed readers, both fixed
    (each byte-neutral at the default gate-OFF):
    1. A struct-typed ivar whose default degrades to a scalar literal — e.g.
       `@__evloop_data : Arena::Index = INVALID_INDEX` collapsing to `literal 0`
       — crashed the inline-struct field store at startup (memcpy from a scalar
       register). Fix: `generate_allocator` (ast_to_hir.cr, both generators) now
       routes a struct ivar whose lowered default is NOT itself a struct value to
       a zero-struct `Allocate` (declared default still lost — separate documented
       gap). Guard `struct_ivar_module_default_inline_repro.sh`.
    2. A small (≤ pointer word) struct as a Tuple/NamedTuple element:
       `register_tuple_types` keeps it a pointer-word CARRIER, but
       `lower_field_get`/`lower_field_store_to_ptr` applied the step-4 FIELD flip
       → the carrier slot was misread as inline bytes (repr-flip). Fix: suppress
       only the step-4 small flip for a tuple receiver (`field_receiver_is_tuple?`
       in hir_to_mir.cr); large structs (> pointer word) inline in both regimes
       and are unchanged. Guard `tuple_small_struct_element_inline_repro.sh`
       (proven bad→good on pre/post-fix binaries).
    Result: gate-ON 131/131 + 36/36 + complex 17/19 == gate-OFF baseline (the 2
    complex fails are the pre-existing Array#find ёжики, present on both gates).
  - **Remaining: default-flip decision (owner call).** Flipping the shipped
    default to ON is CAUTION-tier (ABI change, also affects s3b). Gate it on a
    measured perf win over the runtime-hot small-struct tail
    (Atomic/SpinLock/Timers/Arena::Index) — measure first, then owner decision;
    then remove the env gate.

## Current Checkpoint

**2026-06-21 — gated fix: String#split nilable-limit monomorphization collision (Bug 2), gate `ADAMAS_BLOCK_SHAPE_SPECIALIZE` (`abi-struct-byvalue`).**
Per-shape block specialization: distinct `String#split$Char_Int32_Bool_block`(i32 limit) and
`Char_Nil_Bool_block`(ptr limit) instead of one collapsed `$Char$arity3_block`. Root of the
incomplete WIP was a 4th, emit-time block-target resolution site (`ast_to_hir.cr` ~78530) that
re-derived the arity name and overwrote the shape-keyed `mangled_method_name`; fixed by re-keying
its 3 branches through `shape_keyed_block_target` before `preserve_receiver_block_call_target`.
Gate DEFAULT OFF (fully inert; suites identical OFF/ON: originals 148/148, combined 36/36). Gated
reducer `string_split_int32_nil_limit_collision_repro.sh` (GATE=1 default) green: `int_limit=2
nil_limit=4`; IR has the two distinct defines, no `inttoptr 2->ptr`, no `load i32,ptr %limit`.
NOT default-on and NOT s2b-clean: gate-ON s2b now passes the Globber/String#split STARTUP crash
(gate-OFF still dies there) and reaches a SEPARATE deterministic backend crash —
`@value_def_block.clear` (Hash(UInt32,UInt64) @entries=-1) in `LLVMIRGenerator#emit_function`
during codegen. That is the next frontier (fresh session; localize crash frame + Hash state +
whether shape-block functions are the only HIR/MIR delta + minimal reducer). Bug 1 (single-Char
`split('/')` overload misdispatch, `string_split_default_nil_limit_repro`) remains separate/open.

**2026-06-20 — A′ BEHAVIOR: inline-value Array(C) storage ABI (gate `ADAMAS_INLINE_VALUE_ARRAY_STORAGE`) (`abi-struct-byvalue`).**
First slice where LLVM CONSUMES the A′ facts and changes the Array(C) ABI: a leaf-POD
value struct is stored INLINE in the Array buffer (stride C.size), read back as an
escape-safe heap-carrier copy, and the whole family (push/grow/realloc, [], delete_at/
shift/insert/concat, clear) uses the inline stride. Pure mechanical fact consumer:
emit_gep_dynamic reads `array_buffer_element_stride`; emit_store/load key off
`array_buffer_value`+`@inline_value_gep_value_slots`; emit_extern_call/emit_call rebuild
`logical_count*stride`; emit_array_get/set/new/literal read eligibility. Two sets
(strides vs value-slots) so pointer-arith geps never get heap-copy-load. 4 impl bugs
fixed: per-function ValueId set `.clear` (IO#gets_peek `switch i32` leak); array_new/
literal cap*8 under-alloc; **facts populated POST-MIR-opt** (the optimizer clones geps
and drops the durable props — cli.cr runs opt serially under the gate, populates, then
disables per-worker opt); clear-dest arith gep non-V3 element_type (broadened buffer-
gep marking). Surgical to_unsafe escape fix: exclude only COMPILER-SYNTHESIZED
dispatchers (`@synthetic_abstract_dispatchers`), so V3 is eligible but a user
`Box#to_unsafe{@a.to_unsafe}` stays caught. DoD: V3 genuinely flipped (ELIGIBLE,
stride-geps=19, 26 ivc_raw in Array(V3)#, delete_at ptr_move i32 12, behavior-identical
to legacy); wrapper-escape negative keeps WV ineligible; non-Array Pointer boxed;
gate-OFF byte-identical (broader suite 138/138 + 36/36, 0 fail); all 8 A′ reducers
green. v1 limit: positive target needs call-shaped Array usage (main-inlined-only
arr[i]/arr[i]= gives bv=0 → ineligible, fail-closed; v2 may add bv-from-ArrayGet/Set).
Reducers: inline_value_array_storage_behavior, inline_value_array_wrapper_escape_guard,
inline_value_nonarray_pointer_guard (re-pointable to behavior gate). NEXT: C (by-value
$Dnew/sret, stack-fast-path copy-on-load) and/or extend eligibility coverage.

**2026-06-20 — A′ facts extension: arith-gep stride + bulk logical_count (read-only) (`abi-struct-byvalue`).**
The behavior flip hit GPT's stop-signal (backend would have to re-derive provenance/
stride for the pointer-arith geps feeding `__adamas_ptr_move` — `getelementptr ptr`
stride-8 — and lacked a `logical_count` to rebuild byte counts). Partial behavior was
STASHED, facts extended instead (no backend oracle). New durable facts (gate
`ADAMAS_ARRAY_BULK_OP_FACTS`): `GetElementPtrDynamic#array_buffer_element_stride`
(set for EVERY @buffer-derived gep of an eligible C — value AND arith — via
`buffer_roots`); `ExternCall/Call#array_bulk_stride` + `#array_bulk_logical_count`
(ptr_move/copy count arg; memmove/memcpy/memset/malloc/realloc non-const Mul operand;
Pointer#clear/move_from count arg; no count → fail-closed Uncovered). All
eligibility-baked. Reducer: `Cov` ELIGIBLE with value+arith stride-geps + every
covered bulk op carrying logical_count (missing=0); strides only inside `Array(...)`
(outside=0); `Unc`/`Esc` get none; `Vec3#delete_at` arith geps now strided; gate-OFF
byte-identical; no `ivc_raw`. All 6 A′ reducers green. NEXT = resume the atomic
behavior flip (now a pure mechanical fact consumer), owner-gated, NOT started.

**2026-06-20 — A′ mini-AbiFacts: Array bulk-op coverage facts (read-only) (`abi-struct-byvalue`).**
Gate `ADAMAS_ARRAY_BULK_OP_FACTS`. The pre-behavior infra GPT/owner GO'd, built as a
durable typed-fact layer (aligns with the AbiFacts architecture note — minimal facts
for this slice, not a giant oracle). Typed facts in `mir.cr`: `ArrayBulkOpKind`,
`ArrayBulkCoverageReason`, `Type#inline_array_storage_eligible`,
`ExternCall#array_bulk_op`, `Call#array_bulk_op`. Pass in `hir_to_mir.cr` structurally
classifies every Array(C) @buffer bulk op (move/copy/clear/alloc/realloc) inside
monomorphic `Array(C)#` bodies via a precomputed `buffer_roots` set (strict, GPT-
constrained: @buffer-ivar Load; exact `Array(C)#to_unsafe`/`root_buffer` Call on an
Array(C) param; fresh strided malloc/realloc stored into self.@buffer). Eligibility =
`inline_value_safe(C) && no Heterogeneous/Uncovered op`. Reducer
`inline_array_storage_facts_probe.{cr,sh}`: `Cov` (push/[]/delete_at/shift/insert/
concat) → ELIGIBLE; `Unc` (adds dup/reverse → copy into fresh non-self buffer) →
ineligible `[…Uncovered]` (proves the refinement did NOT open a hole, fail-closed).
Read-only: gate-OFF IR byte-identical, no `ivc_raw`. NEXT = behavior commit per §3-§5
(now consumes both `array_buffer_value` + the bulk-op facts), owner-gated, NOT started.

**2026-06-20 — A′ behavior PREFLIGHT: design/DoD packet + non-Array guard (`abi-struct-byvalue`).**
`docs/inline_value_array_storage_behavior_plan.md` (PROPOSED, owner-gated) — the
design/DoD packet for the behavior slice that first makes LLVM read the A′ marks
(CAUTION/ABI). Incorporates GPT hardening: (1) ONE gate `ADAMAS_INLINE_VALUE_ARRAY_STORAGE`
that itself runs annotation (no two-env false-mark path); (2) Array-CONTEXT stride,
never a type-global `container_elem_storage_size_u64` flip (it is shared by
`Pointer(T)#bytesize`/StaticArray → would re-fire the refuted type-driven slice);
(3) atomic Array(C) family flip (alloc/realloc stride + store + copy-on-load +
memmove/delete_at/shift), not one GEP site; (4) copy-on-load v1 = heap carrier, no
stack fast path; (5) the reducer DoD + 48h pre-mortem. Preflight guard shipped:
`regression_tests/inline_value_nonarray_pointer_guard.{cr,sh}` — a leaf-POD struct
used only via `Pointer(Disc).value` (never in an Array) stays boxed: out=42, Disc
not-marked, array_buffer_value outside=0, 0 `ivc_raw` (the invariant the type-driven
slice violated). Packet revised per GPT review (4 blockers closed): memmove family
is MANDATORY not "if touched" (else first delete_at/shift = heap corruption);
buffer_ptr_arith uses an Array-context helper keyed on the monomorphic `Array(C)#`
body (not type-global) + fail-closed exclusion; the single behavior gate emits
`[IVANNOT]` so the guard's GATE re-point keeps mark evidence; copy-on-load reuses
the existing `[i64 INT64_MAX header][payload]` carrier (raw+8), not malloc(payload).
PREFLIGHT FINDING (measure-first, before any codegen): behavior is NOT one bounded
diff. The mutation family (delete_at/shift/insert/concat) memmoves via
`(@buffer+i).move_from` → `Pointer#bytesize(count)` = `count *
container_elem_storage_size_u64(T)` — type-global (llvm_backend.cr:13774/13807),
running inside shared `Pointer(T)#` bodies (NOT `Array(C)#`), so the durable
`array_buffer_value` mark (value Load/Store only) does not reach it. Inline stride
without mutation-family provenance = heap corruption on first delete_at/shift. This
fires GPT's stop-rule. NEXT = pre-authorized infra commit (§8): mutation-family
coverage marking (taint @buffer-derived Pointer(C) → mark memmove/arith sites,
read-only first, prove 0 outside Array) + executable fail-closed eligibility bit;
THEN the behavior flip. Behavior NOT started.

**2026-06-20 — A′ DURABLE annotation (infrastructure-only, NO behavior) (`abi-struct-byvalue`).**
Gate `ADAMAS_INLINE_VALUE_ANNOTATE`. Materializes the step-(c) safe-set IN MIR (not
STDERR): `populate_inline_value_safe_set` runs the SAME `{bv && !vd && !erased_flow}`
analysis (refactored into shared `compute_inline_value_safe_set(mark_provenance)`)
and persists two durable marks — `MIR::Type#inline_value_safe` (per-type eligible
flag) and `MIR::GetElementPtrDynamic#array_buffer_value` (per-site Array(C) @buffer
value-access provenance). `verify_inline_value_annotation` reads them back in a
separate pass. **NO lowering site reads either mark** ("same computation, durable
annotation, no behavior" — guards against silently re-deriving provenance by
type/name in LLVM = the refuted type-driven slice). Reducer
`regression_tests/inline_value_annotation_probe.sh` (reuses the step-(c) .cr):
Vec2 SAFE-MARKED, Vraw not-marked (value_derived → not eligible; doubles as the
behavior reducer's "unsafe types not eligible"), array_buffer_value marks inside
`Array(...)` bodies only (inside=10 outside=0), no `ivc_raw` in IR, gate ON vs OFF
IR byte-identical. NEXT (still owner-gated, NOT this step): behavior slice that
inline-stores ONLY at `array_buffer_value` sites whose elem is `inline_value_safe`.

**2026-06-20 — Step (c): read-only per-type inline-value SAFE-SET shipped (`abi-struct-byvalue`).**
`run_inline_value_safe_set_probe` (gate `ADAMAS_INLINE_VALUE_SAFE_SET_PROBE`).
v1 SAFE-SET = `{ C | bv && !vd && !erased_flow }`. The erased gate is FLOW-based
(does `Array(C)` / an upcast `Indexable/Enumerable(C)` actually flow into a
type-erased body) — it REPLACES the over-coarse variant signal (C ∈ the
program-wide `Indexable(T)#fetch` mega-union), which would WRONGLY exclude 3 types
incl. `Vec2`. KEY FINDING: this compiler monomorphizes ALL candidate-array access,
so `erased_flow` stays 0 — the durable reducer exercises `Vec2` via
push/each/[]/map AND the erasure-attempt forms (`Indexable(Vec2)` param, `.as` cast,
two-implementer abstract dispatch) and `Vec2` still classifies SAFE; the step-3 (c)
erased repr-mismatch hazard does NOT occur for candidate types; `erased_flow` is a
sound but dormant guard. Reducer `regression_tests/inline_value_safe_set_probe.{cr,sh}`:
one compile asserts `Vec2` SAFE (bv=1 vd=0 erased_flow=0, even under abstract
dispatch) + `Vraw` UNSAFE (value_derived access — raw `Pointer(Vraw)` read+write)
+ flow-based erased=0 + mega-union over-count + gate-neutral (IR diff=0). Read-only;
no codegen consumes the label. STEP-3 conditions: (a) DONE; (b) held; (c) DONE;
(d) negative reducer keeps 0 `ivc_raw`.
**Behavior slice (step 3) is owner-gated — NOT green-lit.**

**2026-06-20 — Step (a): leaf-storage-POD gate narrowed (`abi-struct-byvalue`).**
`leaf_storage_pod_struct?` no longer admits `k.pointer?` — a struct with a raw
pointer field (Pointer::Appender, Crystal::PointerLinkedList) is NOT
value-copy-safe (inline copy duplicates a live interior pointer), so it now
classifies as `ExistingLowering`. Classifier-only / read-only: no codegen
consumes the label on this base (`llvm_backend.cr` has no `ivc_raw`), gate ON vs
OFF IR byte-identical (normalized diff = 0). Reducer
`regression_tests/leaf_pod_struct_pointer_field_repro.{cr,sh}`: Vec2/Vec3 stay
InlineValueCopy, WithPtr (raw Pointer(Int32) field) → ExistingLowering. NEXT =
step (c) erased reconciliation / per-type safe-set (read-only first): the set of
types with a `buffer_value` store/read AND no erased/`value_derived` read path,
or explicit reconciliation for erased `Indexable(T)#fetch`. Behavior-slice only
after (c); invariant (b) held HARD — no global type-driven `Pointer(T)#<<`.

**2026-06-20 — A′ provenance marker: read-only proof shipped (`abi-struct-byvalue`).**
Step 2 of the A′ plan. `run_array_buffer_provenance_probe` (gate
`ADAMAS_ARRAY_BUFFER_PROVENANCE_PROBE`, default OFF, STDERR-only). Refines the
census "function-context" idea into a precise **buffer-base provenance** rule that
does NOT use the function name: a candidate `GetElementPtrDynamic` G (elem C, an
InlineValueCopy candidate) is in the A′ mark set (`buffer_value`) iff (1) `G.base`
= `Load(static GEP @buffer of a receiver typed `Array(C)`)` AND (2) G is the
address of a `Load`/`Store` of C. Four categories split the mark set from
look-alikes: `buffer_value` (mark) / `buffer_ptr_arith` (root_buffer / memmove
ptr arithmetic) / `value_derived` (raw `Pointer(C)[i]`, no @buffer chain) /
`neither` (resize realloc-ptr). **PROVEN:** on a probe mixing Array(Vec2) inline
access + a deliberate raw `Pointer(Vec2)[idx]` access, `buffer_value` lands ONLY
in `Array(C)#` bodies — **0 marks outside an Array body** — and the raw Pointer
access is `value_derived`, NOT marked. The `IO#gets_peek` `Pointer(C)#value`
blocker that sank the refuted type-driven slice is structurally excluded. Gate
ON vs OFF LLVM IR byte-identical (normalized diff = 0). Regression:
`regression_tests/array_buffer_provenance_marker_probe.{cr,sh}` (asserts the 0-
outside invariant + positive Array(Vec2) marks + negative Pointer(Vec2) not
marked + gate neutrality). Doc section: `docs/container_access_path_census.md`
"A′ provenance marker — read-only proof". STILL OPEN before step-3 behavior:
the 4 hard conditions below (leaf-gate narrowing; no global type-driven
`Pointer(T)#<<`; erased `Indexable(T)#fetch`/`Enumerable(T)` reconciliation OR
per-type safe-set — note an erased generic body's buffer GEP is `value_derived`
(self typed `Indexable(T)`, not `Array(C)`) so it would read inline-stored bytes
via the pointer-slot path unless reconciled; negative reducer stays 0 ivc_raw).
Step-3 order (owner+GPT, NOT a green light yet — behavior must CONSUME exactly
this provenance mark, not re-guess in LLVM by type/name): **(a) FIRST narrow the
leaf gate** — `leaf_storage_pod_struct?` still admits `k.pointer?`; raw-pointer-
field structs must go to `ExistingLowering`, with a reducer (Vec2/Vec3 →
InlineValueCopy, struct-with-raw-pointer-field → NOT InlineValueCopy). **(c) THEN
erased reconciliation / per-type safe-set** (else inline-store in `Array(C)#push`
+ pointer-slot read via erased `Indexable(T)#fetch` = repr mismatch).

**2026-06-20 — Container access-path census shipped (`abi-struct-byvalue`).**
Read-only diagnostic `run_container_access_census` (gate
`ADAMAS_CONTAINER_ACCESS_CENSUS`, default OFF; gate-OFF IR byte-identical after
normalizing non-det `@.stub_name_<hash>`). Buckets every InlineValueCopy-candidate
access by read|store × mechanism × provenance (recoverable / concrete_np / erased).
Full table: `docs/container_access_path_census.md`. Decisive finding: the real
Array element store/load is a raw `GetElementPtrDynamic`+Store/Load INSIDE the
monomorphic `Array(Concrete)#push`/`#unsafe_fetch` body (symmetric), NOT
ArrayGet/ArraySet and NOT the type-erased `Indexable#fetch` path (erased = 3.4%
reads, 0 for Vec2/Vec3 → the erased-read falsifier did NOT fire). 35 candidates
(Vec2/Vec3 + 33 stdlib value structs). **Decision (owner+GPT): A′ now, C later.**
A′ next slice = a **read-only provenance marker FIRST** (function-context +
buffer-base provenance: mark a raw GEP only if it addresses Array.@buffer, not any
`Pointer(T)` inside an `Array(...)#` body; prove 0 marks outside Array buffers),
THEN behavior (store/load by marker, heap-copy carrier on load). Hard conditions
before behavior: (a) restore leaf-gate narrowing — raw-pointer-field structs
(PointerLinkedList/Pointer::Appender) are NOT leaf-storage-POD; (b) no global
type-driven `Pointer(T)#<<`; (c) close erased reconciliation OR ship v1 per-type
safe-set (only types with no erased access in the lowered module); (d) reducer
must include a NEGATIVE (IO#gets_peek / `Pointer(Range/Hasher)#value` → 0 ivc_raw).

**2026-06-19 — ABI-rework + s2b GC fix MERGED to `main` and pushed.** Two
revertable merge commits on `main` (now `71b707ff`, == `origin/main`):
`d07b07d6` merges `abi-step4-inline-struct` (full ABI-rework series: LayoutContract
consolidation 1a/1c, gated-OFF step-4 small-struct inline flip
`ADAMAS_INLINE_SMALL_STRUCTS`, StaticArray by-value memcopy, SplatNode guard,
docs — all default-behavior-neutral), and `71b707ff` merges
`s2b-twoheap-gc-fix-D` (brought only `e635fbc4`, the GC two-heap redirect).
Post-merge verification: `bin/adamas` builds clean; suites **originals 131/131 +
combined 36/36, 0 fail** (count rebalanced vs old 158/31 by main's test-batching
commits); `gc_aware_realloc_gating_repro` PASS; all 4 new struct/ABI repros
(splat / struct_ivar_module_default / struct_pointer_word_boundary /
tuple_small_struct_element) PASS. No regressions from the merge.

**2026-06-19 — By-value struct ABI: Stage 0 census shipped (`abi-struct-byvalue`,
`19e72d7d`).** Read-only diagnostic (gate `ADAMAS_STRUCT_BYVALUE_CENSUS`, default
OFF): for every user-struct ctor call, classify result flow (field_store /
container / arg / return / local / mixed) + POD vs ref. Decision-grade finding:
the common `Particle.new(Vec2.new(...))` lands in `arg`, NOT `field_store`, so no
single bucket is "the flip set" — exact eligibility is for a later escape/inline
predicate. GPT round-2 hostile review confirmed (anchors re-verified vs live
code): (1) `arg` too coarse — needs sub-census; (2) inline-proof must exactly
match `lower_field_store_to_ptr`/`use_memcopy` incl. `suppress_step4_tuple`
(else stack-alloc + pointer-carrier store = UAF); (3) `type_needs_rc?` doesn't
recurse through struct fields + `struct_type_is_pod?` optimistic default → unfit
as flip gate; (4) shared escape walker trusts receiver-self as borrowed without
proving callee doesn't leak `self` — don't reuse blindly. NEXT (deferred per
owner, who chose merge-first): `arg` sub-census + a SEPARATE predicate
`param_value_is_consumed_only_by_inline_field_memcopy?` (definite recursive POD +
exact use_memcopy equivalence), rollout direct `field_store` first then exact
`arg_param_copy_field_only`. THEN Stage 1a flip (gated, default OFF, POD-only).

**2026-06-19 — Stage 0+ SHIPPED (`abi-struct-byvalue`, `b16bf758`): arg sub-census
+ by-value eligibility predicate.** Read-only/gated; suite 131/131 + 36/36; gate-OFF
compile behavior unchanged. New: `struct_type_is_recursive_pod?` (DEFINITE recursive
POD — recurses struct fields, rejects ref/array/union/proc/tuple/opaque, no optimistic
default; addresses finding 3), `classify_arg_param_consumption` +
`param_value_is_consumed_only_by_inline_field_memcopy?` (single-hop reason-coded:
rejects pointer-carrier store [finding 2], receiver call [finding 4], forwarding,
container, return), `field_store_site_is_inline?`, census splits. **Census (366 sites)
RESHAPES Stage 1a:** `arg` = 82 forwarded / 46 no_callee / **0 copy_field_only** — the
common `Particle.new(Vec2.new(..))` forwards through `.new`→`initialize`, so a one-hop
arg predicate flips NOTHING. `field_store` inline/carrier = 8/10 (step-4 OFF) → 17/1 (ON);
**flip_eligible = 6 (OFF) / 12 (ON)**, ALL from direct inline `field_store` (recursive-POD-
gated); coarse-POD over-count = 18 (confirms `struct_type_is_pod?` unfit). REVISED Stage 1a:
(1) flip direct inline `field_store` + recursive-POD FIRST (6/12 sites); (2) for `arg`,
add a one-hop `.new`→`initialize` forwarding trace OR flip at the forwarded callee — decide
after measuring `initialize`-side stores. NOT the whole arg bucket.

**2026-06-19 — Stage 1a brief WRITTEN (`c79446d4`, `docs/abi_byvalue_stage1a_brief.md`),
awaiting owner's GPT hostile review.** Verified ground truth: `Vec2$Dnew` mallocs 16B
(8B `i64` INT64_MAX GC/RC sentinel header at `ptr-8` + 8B payload, returns payload ptr);
the `-8` header is the rc_inc/rc_dec sentinel and structs are currently treated as STATIC
(never rc'd, leak to exit) → by-value PODs reaching an rc path are a no-op not a crash
(Darwin; glibc `malloc_usable_size(non-heap)` UB = hazard). **CRUX for review:** `T$Dnew`
return ABI is per-type-GLOBAL, so the per-site census (6/12) is a FLOOR — Stage 1a needs
Shape A (whole-type flip + new per-TYPE aggregation pass = Stage 0++) or Shape B (dual ABI
`T$Dnew$byval`). NEXT: adversary-verify GPT critique → pick Shape A/B → build per-type
aggregation + gated flip. Brief lists 7 hazards + DoD.

**2026-06-19 — GPT critique ADVERSARIALLY VERIFIED (brief §4a added).** GPT said A/B is a
false dichotomy because **Shape C** already exists (per-site stack promotion,
`lower_stack_local_struct_allocator_call` `hir_to_mir.cr:6163`, intercept `:3973`, ptr ABI
kept). Verified with 2 falsifiers (`--emit llvm-ir`, `ADAMAS_STACK_PROMO_TRACE=.new` — the
MIR name is `T.new$...`, `$Dnew` is backend-only mangling, so filtering "Dnew"=0 traces=false
negative). All GPT anchors CONFIRMED (6163/3973/3367/6320/llvm:294). **Falsifier 1**
(non-escaping local): `Particle.new`+`Vec2.new` PROMOTED, `alloca %Vec2`/`%Particle`, 0 malloc,
0 `$Dnew`, ptr sigs intact. **Falsifier 2** (escaping `arr << Particle.new(...)`): `Particle.new`
→ reject `ArgEscape` → heap `Particle$Dnew(24B)` + 2 inner `malloc64(16)` field-Vec2 slots; only
Vec2 temporaries promote. **VERDICT: Shape C real but VULNERABLE as the gap-closer** — the
~10×/~2× bench gap is escaping containerized Particles (`Array(Particle)`), which the lifetime
walker *correctly* rejects (outlive frame, cannot stack-promote). Shape C = verified no-op on the
bench. Real lever = container/escape VALUE ABI (Array stores inline struct values + sret/by-value
`$Dnew` for escaping PODs) = Shape A direction + per-type aggregation.

**3rd lever found + GPT anchors VERIFIED → PATH ORDER (revised).** Escaping `Particle$Dnew` does 3
mallocs: 1 Particle + 2 **dead default-init Vec2** per struct field — `alloc gc Type#911 size=8` +
memcopy into field, then `initialize` overwrites. Origin VERIFIED at `ast_to_hir.cr:29679` (regular)
+ `:30200` (overload): every struct-typed ivar with no usable default emits `Allocate(zero-struct)` +
`FieldSet` regardless of whether `initialize` fully sets it. MIR proof `/tmp/bench_mir_on.mir:65958/65961`
(both GPT anchors confirmed). PATH ORDER (was Shape-C-first; corrected per GPT): **(1) dead-default-init
elimination FIRST** (bounded slice, real perf signal, no Array-ABI change) — skip the zero-struct alloc
ONLY if `initialize` has a **dominating unconditional FieldSet** to that ivar before ANY read/escape;
REJECT on read-before-write (`log(@pos)`), self-escape-before-write (`register_self(self)`),
branch/return/raise before store, address-of self/field, union/fixup, non-POD/ref-owning field.
Gated default OFF + negative reducers + suite + s2b + bench malloc/RSS/time delta. **(2) container/escape
value ABI** later (the true final lever, too broad now: stride/return ABI/Array storage/self-host).
**(3) Shape C eligibility extension** optional cleanup (correctness-neutral, bench unchanged — proven).

**2026-06-19 — PATH ORDER step (1) dead-default-init elimination IMPLEMENTED + VERIFIED**
(branch `abi-struct-byvalue`). Gated
`ADAMAS_SKIP_DEAD_DEFAULT_INIT` (default OFF). New predicate
`initialize_unconditionally_sets_ivar?` (`ast_to_hir.cr`) scans ONLY initialize's
**entry block** (always-executes, straight-line — branches/returns/raises live in the
terminator or successor blocks, so any control flow auto-rejects): ACCEPT on a dominating
`FieldSet(self.@ivar, value!=self)` reached before any read/escape; REJECT on self-FieldGet,
Call/Yield carrying self, AddressOf/Cast of self, FieldSet storing self, or any unknown
instruction (whitelist). Wired into both zero-struct sites — regular `generate_allocator`
(init pre-lowered at the layout pre-lower) and `generate_allocator_overload` (lowers init
early via `lower_function_if_needed`, since it is otherwise lowered after the gate). Skipping
the `Allocate`+`FieldSet` is safe: the field memory already exists in the object `alloc`;
initialize overwrites it first. **DoD ALL MET:**
- Reducer `regression_tests/dead_default_init_elim_repro.sh`: gate OFF `Particle.new` = 2 dead
  Vec2 allocs, gate ON = 0; 3 negatives (read-before-write, self-escape, branch-partial) kept ≥1.
  Adversary trace confirmed negatives rejected by the **predicate** (`found=true skip=false`),
  not a trivial nil-func pass.
- Runtime correctness: single struct `pos=7,8 vel=9,10` and container sum identical ON vs OFF
  (the `Array(Particle)` sum also re-exposes the pre-existing container-aliasing bug = lever (i),
  untouched).
- Full suite gate OFF: ALL PASSED. Full suite gate ON: **131/131 + 36/36 ALL PASSED** (identical set).
- Bench (2M `Array(Particle)`): `Particle$Dnew` `__adamas_malloc64` **3→1** (−2/particle = −4M);
  whole-module malloc sites 6290→6275; peak RSS **150.3MB→85.95MB = −43% (−64MB ≈ predicted
  2·16B·2M)**; warm wall ~0.06s→~0.03s.
- s2b gate ON: **builds** (33.88MB, 18KB SMALLER than gate-OFF 33.90MB, 223s); behaves
  **identically** to gate-OFF s2b — both compile `x=1` cleanly (identical 88760B binary) and both
  SIGBUS (exit 138) on a struct program (= documented pre-existing GC two-heap crash, not fixed on
  this branch). NO regression from the gate.

Step (1) COMMITTED `8076254f` (`ast_to_hir.cr` + reducer + TODO).

**2026-06-19 — PATH ORDER step (2) prep: Stage 0++ per-type aggregation + enum refactor**
(`abi-struct-byvalue`, this commit; `hir_to_mir.cr` only). Two parts, ONE logical change:
- **Enum refactor (allocation-free classifiers):** the by-value classifiers
  (`classify_arg_param_consumption` is the hot-path one — runs per call site when the flip
  is enabled) now return ENUMS (`CtorFlow`/`ArgUse`/`RefinedBucket`/`ByvalTier`) instead of
  Strings — member compares, no per-site String garbage. Snake_case display labels derived
  ONLY at diagnostic print time (cold, gated census) via `#to_s.underscore`.
- **Stage 0++ (`run_struct_byvalue_type_aggregation`):** read-only/gated pass that folds
  per-SITE buckets into a per-TYPE verdict (`ByvalTier`), because `T$Dnew` is ONE function
  per type → its return ABI is per-type-GLOBAL. Prints `[BYVAL_TYPEAGG]` under
  `ADAMAS_STRUCT_BYVALUE_CENSUS`.
Claim scope (narrow, per GPT): **gate-OFF behavior-neutral** (census+typeagg output
byte-identical pre/post, suite 131/131 + 36/36, dead-default reducer green); gated census
diagnostics changed/extended (BYVAL_TYPEAGG now always prints under the census gate).
**Decision-grade finding:** Shape A (whole-type flip) is impractical as first step — `trivial`
tier (whole-type-flip-safe) is tiny + perf-irrelevant (Fiber::Context/Stack, CachedPowers::Power);
`Vec2` lands in `container` tier with MIXED flows (arg_forwarded=3 container=1 copy=1 return=1) →
a whole-type Vec2 flip must close container + arg-forward + return + copy ABIs at once (viral).
**Blocker found:** recursive-POD predicate has a nested-struct FALSE-NEGATIVE — `Pair{Vec2,Vec2}`
classifies `non_pod` (NOT a step-4 carrier artifact; `ADAMAS_INLINE_SMALL_STRUCTS=1` keeps it
non_pod). Root: struct-typed ivar's MIR field type_ref does not resolve back to the registered
struct in `struct_type_is_recursive_pod_mir?`.

**2026-06-19 — recursive-POD nested false-negative FIXED** (`abi-struct-byvalue`, this commit;
`hir_to_mir.cr` + new reducer). ROOT CAUSE (empirically pinned via a temp POD trace, then
reverted) was NOT a type_ref resolution miss (the earlier hypothesis above is WRONG):
`Pair{Vec2,Vec2}` resolves to `Struct/fields=2` fine. The bug: `struct_type_is_recursive_pod_mir?`
used `seen` as an ALL-VISITED set that was never popped, so `@a:Vec2` added Vec2's id and then
`@b:Vec2` (a SIBLING of the same POD type) hit the cycle guard and returned false → `Pair` wrongly
`non_pod`. FIX: `seen` is now the current DFS ANCESTOR-PATH set (id removed on the way back up) — a
real cycle is a type reachable from itself along the path, not the same POD used twice as siblings.
Also renamed `struct_type_is_recursive_pod?` → `struct_type_is_semantic_recursive_pod?` + doc note:
this is the SEMANTIC predicate (declared fields recursively bit-copyable; gates future value/container
ABI); a SEPARATE storage-aware predicate must gate memcpy/stack-promo on the current layout (else
lever-(i) container-aliasing UAF). DoD: reducer `recursive_pod_nested_sibling_repro.sh` (Vec2/Pair/
Quad=true, WithString=false); dead-default reducer green; suite 131/131 + 36/36; Stage 0++ rerun
(bench_struct_heap.cr) now classifies GC::Stats/Time::Instant/Pointer::Appender/DWARF::Register as
pod=true.

**2026-06-19 — ContainerElemRepr rename + stored-label PLUMBING SHIPPED** (`abi-struct-byvalue`; GPT
GO behavior-neutral plumbing-before-codegen). Hardens the scaffold per GPT round-2 before any lowering
change: (1) RENAME enum member `PointerSlot → ExistingLowering` — the fallback arm means "keep the
existing per-element lowering", NOT "the slot is a pointer" (primitives/wide-unions/primitive-tuples
are stored INLINE-by-value by the existing cascade `container_elem_storage_size_u64_impl`, so a literal
`when PointerSlot` would corrupt them); lowering sites must treat it as a passthrough. (2) STORE the
classification on `MIR::Type#container_elem_repr` (variant 1): classify ONCE during HIR→MIR via
`populate_container_elem_repr` (registry + HIR lib-set in scope, run late after sizes settle) and have
LLVM READ the stored label — LLVM has no `@hir_module.lib_structs`, and the lib reject is part of the
leaf-gate, so re-deriving in LLVM would lose lib-info and drift (Vec3 stride). Renamed compute
`container_elem_repr → classify_container_elem_repr`; census now READS the stored label. Still gated
`ADAMAS_INLINE_POD_CONTAINERS` (default OFF), behavior-NEUTRAL. DoD MET: reducer green
(Vec2/Vec3=InlineValueCopy, Pair/WithStr=ExistingLowering, families struct=InlineAddress, 410 unions
all ExistingLowering, gate OFF no [ELEM_REPR]); gate-OFF `--emit llvm-ir` BYTE-IDENTICAL to `ae479948`
(124 diff lines ALL non-det `stub_name` salts — prev-vs-prev same-binary AND cur-vs-prev both 124, 0
non-stub, normalized 0). NEXT (behavior-changing, ONE atomic gated slice, requires s2b): sizing for
InlineValueCopy + ALL store paths (emit_array_set, raw Array#<<:4453, Pointer(T)#<<:13837) + ALL load
paths (emit_array_get:25121, unsafe_fetch:4499) together; copy-on-load v1 = heap-copy ALWAYS through
the CURRENT carrier layout `[i64 header][payload]` via the strategy-aware allocator (llvm_backend.cr
:17708-17721; ARC=refcount 1, GC=INT64_MAX sentinel, return base+8 — NOT malloc(payload), else
rc_inc/rc_dec at ptr-8 corrupts); NO stack fast-path in v1. Reducers
copy-on-store/load/double-store/realloc-stride (12B Vec3) + s2b green.

**2026-06-19 — ContainerElemRepr classification SCAFFOLD SHIPPED** (`abi-struct-byvalue`; GPT GO
scaffold-only). First implementation slice of the storage brief, behavior-NEUTRAL: adds MIR
`ContainerElemRepr` enum (`PointerSlot | InlineAddress | InlineValueCopy`, mir.cr) + registry-backed
classifier `container_elem_repr` / `leaf_storage_pod_struct?` / `mir_struct_is_lib?` (hir_to_mir.cr) +
new gate `LayoutContract.inline_pod_containers?` (`ADAMAS_INLINE_POD_CONTAINERS`, default OFF). The
classifier is COMPUTED + LOGGED only (`[ELEM_REPR]` census under the gate); NO lowering site reads it
(container_elem_storage_size_u64 / emit_array_get / _set / Pointer(T)#<< / unsafe_fetch UNTOUCHED).
GATE = leaf-storage-POD (every field primitive/enum/raw-ptr, no nested struct/tuple/union/ref, ≤16,
non-union, non-lib), NOT semantic-POD. Family/leaf checks gated on `kind.struct?` (mirror
inline_container_struct_type? :2798) so a union named `Slice(..)|..` is NOT misread as a family.
DoD MET: reducer `container_elem_repr_scaffold_repro.sh` green (Vec2/Vec3=InlineValueCopy,
Pair/WithStr=PointerSlot, Slice/StaticArray/Hash::Entry struct=InlineAddress, 410 unions all
PointerSlot, gate OFF no [ELEM_REPR]); gate-OFF `--emit llvm-ir` BYTE-IDENTICAL to pre-step baseline
(only non-det `stub_name_<hash>` salt churn — 124 diff lines both base-vs-base AND base-vs-cur,
0 non-stub diffs, normalized identical); suite 131/131 + 36/36. s2b NOT required for scaffold (next
behavior-changing store/load commit). NEXT (behavior-changing): wire InlineValueCopy into the store
sites (Pointer(T)#<<:13837, raw Array#<<:4453, emit_array_new sizing) + copy-on-load
(emit_array_get:25121, unsafe_fetch:4499), gated, with copy-on-store/load/double-store/realloc-stride
(12B Vec3) reducers + s2b green.

**2026-06-19 — Option C: placement-fusion census axis SHIPPED** (`abi-struct-byvalue`;
`hir_to_mir.cr` +`run_struct_byvalue_fusion_census` + reducer `byvalue_fusion_site_census_repro.sh`).
Second, read-only census axis (gated `ADAMAS_STRUCT_BYVALUE_CENSUS`, behavior-neutral): counts
placement-CANDIDATE boxes = a user-struct ctor whose SOLE value use is a container write
(`classify_struct_ctor_flow == Container`), split semantic-POD (malloc 1→0 candidate) vs non-POD
(stays boxed). CANDIDATE axis, not proof: `container_write_call?` is method-name-based (#push/#<</
#[]=/#unsafe_put), so the count is an upper bound — each site still needs proving against the real
container storage ABI. KEY SIGNAL: prelude baseline = `removable_box_sites=4` (UInt128×3, DWARF
Attribute×1), `ineligible=1`, only `fresh_ctor=5` of `container_writes_total=1495`. So the isolated
`arr << T.new(...)` placement-fusion lever is RARE in self-host — fusion-first would barely move the
compiler. DoD: reducer green (Vec2=3, WithStr=1, named-local `arr << v` excluded); suite 131/131 +
36/36; gate-OFF byte-neutral. NEXT (per GPT, storage-first NOT fusion-first): scoped storage ABI
slice for `Array(LEAF-storage-POD struct ≤16B)` FIRST — brief
`docs/abi_byvalue_storage_slice_brief.md` (DESIGN checkpoint, GPT round-1 ROBUST). v1 = MIR
`ContainerElemRepr` enum (`PointerSlot | InlineAddress | InlineValueCopy`) + new gate
`ADAMAS_INLINE_POD_CONTAINERS` (default OFF, byte-identical) + copy-on-store + escape-aware
copy-on-load. GATE IS leaf-storage-POD (every field primitive/enum/raw-ptr, no nested
struct/tuple/union/ref, ≤16, non-union, non-lib), NOT semantic-POD: under step-4-OFF field ABI a
`Vec2` FIELD is a pointer carrier (`user_struct_inline?` = `size>8`), so `Pair{Vec2,Vec2}` payload =
two pointers → memcpy would copy pointers. semantic-POD is the FUTURE gate once field-inline (step-4)
lands. First impl PR must be NARROW: repr enum + gate + reducers (incl. 12B `Vec3` for the
`emit_array_new` >8 path), NO fusion, NO nested POD. Must-fix store/load sites: `emit_array_get:25121`
(copy-on-load gap), raw `Array#<<:4453` (store-ptr corrupts payload), `unsafe_fetch:4499`
(load-ptr returns interior). Placement fusion (`arr << T.new(...)`) lands later as a separate
sub-slice. Whole-type Shape A not practical as first step.

**2026-06-18 — #1 s2b startup crash FIXED (two-heap GC hazard, fix D).** Branch
`s2b-twoheap-gc-fix-D`, 7 edits all in `src/compiler/mir/llvm_backend.cr` (no
stdlib). The atomic byte-buffer allocator family is moved off the Boehm GC heap
onto libc so no live String/Builder/IO buffer survives only on a heap Boehm
cannot scan through libc containers (premature free -> `String#byte_at` SIGSEGV
at stage2 startup): `GC.malloc_atomic` -> `__adamas_malloc64` (libc calloc),
`GC.realloc` -> `__adamas_gc_aware_realloc` (GC_base-aware: Boehm blocks via
`GC_realloc`, libc blocks via libc realloc). Scanned `GC.malloc` (GMP, EventLoop
arena) stays on Boehm. The wrapper is emitted at the module epilogue only when a
reachable `ExternCall "GC_realloc"` exists (`gc_aware_realloc_needed?`) — the
same condition that links libgc, which fixes a link bug where GC-free programs
got `Undefined symbols: _GC_base, _GC_realloc`. Evidence: baseline pre-D s2b
SIGSEGVs on `x=1`; D-built s2b compiles `x=1` exit 0 ~1s, output links + runs
clean; regression suite 160/160 + 31/31; repro
`regression_tests/gc_aware_realloc_gating_repro.sh`. NEXT: E = ARC-owned String
(general-runtime reclamation; D's leak-to-exit semantics enable leak
measurement to inform E). Details in `LANDMARKS.md` (LM-S2B-TWOHEAP-FIX-D).

Latest bootstrap frontier (LM-624/625, 2026-05-23): produced `s2` builds
cleanly under the safe wrapper and passes focused no-prelude guards for
qualified nested module namespaces, `skip_file` require scanning, and
`typeof(Enumerable.element_type(...))` annotation normalization. The latest
hardening removed two generated-stage2 crash roots: `skip_file` macro
directive scanning no longer calls Regex-backed `String#sub` while recursively
loading requires, and fixed `element_type` prefix tables no longer use
`Array(String)#find`/`any?` block scans in HIR or semantic type-expression
resolution. LLVM emission also avoids a nilable `@current_func_params[i]?`
fetch in `current_func_param_index?`, which had allowed produced `s2` to
dispatch `Parameter#index` to an unrelated `#index` method after union
narrowing.

Boundary: full-prelude produced `puts 42` is still not clean. With
`/tmp/cv2_param_index_s2/cv2_s2`, the smoke reaches `lower_main: exprs=15` and
times out under a 360s safe wrapper at about 646MB RSS instead of crashing
during prelude parse, module/class registration, or `typeof(element_type)`
normalization. Treat the next root as a lower-main progress/time frontier, not
a parser-first bug. The non-fatal `CLI#file_sha256$String` MIR optimizer
arithmetic-overflow diagnostic remains during produced `s2` builds. Refuted:
adding readability guards inside normalizer helpers fixed a no-prelude reducer
but regressed full-prelude module registration; do not reapply that branch
blindly.

Container-layout side checkpoint (LM-626/LM-630, 2026-05-23): `Pointer(T)`
allocation, store/load arithmetic, realloc, clear, and copy/move helpers now
agree on the same container storage size for inline unions. This fixed
corruption in `Array(Pair | Nil)` and `Array(Pair | Int64)` where initial malloc
and shifted buffer compaction used 8-byte pointer slots while reads/writes used
24-byte inline union slots. The next tuple frontier was also fixed:
`Array(Tuple(Int64, Int64))#push` previously memcpy'd tuple bytes into
pointer-slot buffers while reads loaded each slot as `ptr`; tuple pointer-buffer
stores now persist a tuple copy and store the pointer. Release benchmark smoke
now matches original checksums for struct arrays, tuple arrays, class arrays,
nilable struct/class arrays, and mixed struct/int unions. Remaining performance
gap: tuple/class-heavy V2 cases still pay extra heap-pointer/allocation cost.

Pointer-copy stride checkpoint (LM-631, 2026-05-24): `Pointer(T)#copy_from`,
`copy_to`, `move_from`, and `move_to` now use the same V2 container element
storage size as Array buffers instead of logical `type_size(T)`. This fixed
`Array(ExprId)#dup` and `Array(tiny_struct)#dup`, where generated code copied
only 4 bytes per heap-struct pointer slot and truncated every other pointer.
Produced `s2` now emits `Array(ExprId)#dup` with `elem_size=8`, and the former
full-prelude require-scan segfault moves forward into module registration.

Stack-local struct constructor checkpoints (LM-661/662, 2026-05-24): generated
struct `.new` calls whose HIR result is `StackLocal` now lower directly to a
caller-local stack allocation. Trivial generated `initialize(@ivar, ...)`
bodies inline as direct field stores; non-trivial initializer bodies still use
the real `#initialize` call. Zero-fill is skipped only when the field-store
ranges exactly cover the struct storage, so padding bytes remain protected.
Escaping constructors still use the heap-backed generated allocator. The
no-prelude layout matrix keeps all checksums aligned with original Crystal and
improves the local/nested/yield struct hot-loop profile, but V2 still trails
original substantially.

Primitive tuple carrier checkpoint (LM-663, 2026-05-24): primitive/enum-only
tuples now use one inline container-slot ABI across `Pointer(Tuple(...))` and
`Array(Tuple(...))`. Allocation, indexed load/store, pointer add, realloc, and
LLVM Array get/set all agree on the MIR tuple byte size, while tuple carriers
containing refs, unions, or structs still use the legacy pointer-carrier path.
The no-prelude layout matrix now brings `pointer_tuple_stride` down to the
same V2 internal-tick class as the scalar baseline. Remaining structural
slowdowns are now concentrated in heap-backed struct pointer slots, nilable/mixed
union materialization, and optimizer parity.

Nested generic pointer-appender checkpoint (LM-652, 2026-05-24):
`Pointer::Appender(T).new(pointer)` now preserves its specialized nested
receiver through path receiver normalization and is no longer mistaken for the
primitive `Pointer(T).new(address)` shortcut in LLVM. The focused produced
binary oracle for `Pointer(UInt8)#appender` now initializes `@pointer`/`@start`,
pushes bytes, and reads the resulting slice successfully. Produced `s2` still
builds in about 154s with the existing non-fatal `CLI#file_sha256$String` MIR
optimizer overflow diagnostic; full-prelude produced-s2 `puts 42` still exits
139, now with trace output reaching later `Float` module registration.

String constructor safety checkpoint (LM-653, 2026-05-24): the
`String.new(UInt8*, Int32, Int32)` LLVM override now rejects non-positive,
null, and allocation-overflow byte counts before allocation or `memcpy`; the
UInt64 delegate now bounds-checks before truncation. This removes a verified
heap-corruption root where negative `bytesize` became a huge unsigned copy
length and could poison GC metadata with `[STAGE2_DEBUG]` bytes. Produced `s2`
still builds in about 154s, but full-prelude produced-s2 `puts 42` still exits
139; the current frontier has moved to class registration (`class register
idx=3/111` in the latest safe run), so continue with class-registration memory
and malformed byte-count source localization rather than treating this as a
complete s2b fix.

Built-in generic-base checkpoint (LM-654, 2026-05-24): contextual generic
resolution now preserves built-in generic bases such as `Array`, `Hash`,
`Tuple`, and `Pointer` instead of resolving plain `Array(T)` to sibling
compiler-internal names like `Crystal::MIR::Array(T)`. This fixes the generated
`Module#intern_type` bucket entry type (`Tuple(UInt8, Array(HIR::TypeRef),
HIR::TypeRef)`) and removes the produced-s2 no-prelude crash while interning
`Pointer(UInt8)`. Host guards for `Hash#to_a` block-return tuples and qualified
module namespaces pass, and produced-s2 passes the namespace no-prelude guard.
Boundary: full-prelude produced-s2 `puts 42` still exits 139 during early module
registration, so the next root remains full-prelude module-registration
state/memory, not generic-base tuple capture.

Nilable Proc union checkpoint (LM-655, 2026-05-24): HIR union construction now
preserves typed `Proc(...)` variants instead of canonicalizing them to bare
`Proc`, and proc shorthand argument normalization resolves `self` against the
concrete owner. This fixes the host HIR pollution where
`Hash(String, Crystal::HIR::ClassInfo)#[]` returned
`Crystal::HIR::ClassInfo | String` because `@block : (self, K -> V)?` lost its
proc signature and made `Proc#call` return `Void`/wrong fallback types. Host
guards for nilable proc unions, `Hash#to_a`, and qualified namespaces pass.
Produced `s2` still builds, and the full-prelude `puts 42` frontier now reaches
`fixup_inherited_ivars start` before a segfault; continue from that
memory/layout-sensitive fixup frontier, not from the erased-Proc return root.

Bare generic constructor checkpoint (LM-656, 2026-05-24): bare generic `.new`
inside generic methods now prefers the enclosing concrete generic return type
when the generic template base and arity match. This fixes the host-generated
HIR invariant break where `Array(String)#to_set : Set(String)` called
`Set(Array(String)).new$Array(String)` for stdlib `Set.new(self)`. The focused
no-prelude guard catches the same root with `Bag.new(self)` in a generic module,
and full host HIR now calls `Set(String).new$Array(String)`. Produced `s2`
still builds and passes the qualified namespace guard, but full-prelude
produced-s2 `puts 42` still fails in `fixup_inherited_ivars`; the fresh lldb
frontier is `Set(String)#each` called from
`invalidate_generated_allocator_state` / `invalidate_lowered_layout_functions`
during `align_all_class_ivars`. Continue there rather than revisiting
`Array(String)#to_set` or patching `.to_set`/`Set#hash` symptoms.

Nil-return block proc checkpoint (LM-657, 2026-05-24): raw block callback
materialization now honors callee `& : T ->` / `Proc(T, Nil)` contracts instead
of using the block body's incidental return type as the function-pointer ABI.
The no-prelude guard verifies that a block passed to `&block : String ->` can
return `Token.new` internally while the materialized `__crystal_block_proc`
still has return type `Nil` and explicitly returns nil. Full host HIR now shows
the previous `Set(String)#each` crash site in
`invalidate_generated_allocator_state` passing `Proc(String, Nil)` to
`Set(String)#each$block`, and produced `s2` reaches past
`fixup_inherited_ivars`. Current frontier: produced `s2` build now fails later
with `Worker 0: MIR opt error for Adamas::Compiler::CLI#file_sha256$String:
Arithmetic overflow`; continue there as the next root, not at allocator-state
Set iteration.

MIR constant-fold wrapping checkpoint (LM-658, 2026-05-24): integer constant
folding now uses wrapping add/sub/mul semantics for signed and unsigned MIR
integer ops, matching the LLVM integer instructions V2 emits. This fixes the
produced-s2 build failure where the optimizer evaluated the FNV-1a
`file_sha256` `UInt64` multiply with checked Crystal arithmetic and raised
`Arithmetic overflow`. The focused MIR optimizer spec covers the same FNV
offset/prime multiply. Produced `s2` now builds cleanly again. Current
frontier: produced-s2 full-prelude `puts 42` exits 139 during target compile,
with trace reaching `class register idx=3/92`; continue from class
registration state/memory, not MIR constant folding.

Module stripped-lookup checkpoint (LM-659, 2026-05-24): generic module stripped
name lookup is now maintained incrementally instead of rebuilding
`@module_defs_stripped_lookup` by iterating `@module_defs` during include
registration. This removes the produced-s2 full-prelude crash at
`String include Comparable(self)`, where the lazy cache rebuild/lookup corridor
returned an empty generic key and then crashed in `Hash(String, Array(...))`.
Nested module registration now bumps the module-def cache version as well.
Produced-s2 full-prelude `puts 42` now passes class registration,
constant registration, pass2 function registration, and inherited-ivar fixup,
then reaches `lower_main: exprs=12`; it is still not a clean compile and may
segfault or time out in the lower-main frontier. Continue from lower-main
demand/layout behavior, not from `String`/`Comparable` include registration.

LSP performance side checkpoint (LM-605, 2026-05-20): the background prelude
loader now has a single in-flight owner. Repeated foreground requests while
`@prelude_state` is still nil no longer spawn duplicate cache rebuilds. The
focused regression and full LSP suite are green. After LM-606, opt-in
`LSP_AST_CACHE=1` also reuses AST cache for unchanged foreground documents; keep
it opt-in until the existing ast-cache signature/completion deltas are resolved.
After LM-607, `LSP_AST_CACHE=1` composes with the prelude summary cache instead
of forcing a fallback full-prelude parse, and background prelude cache
hydration publishes rebuilt cache maps only after the cache state is complete.
After LM-608, warm project-cache foreground analysis no longer applies
project-cache `ExprId -> type` maps to freshly parsed opened documents, and
cached method summaries rehydrate parameter/overload metadata. The focused
project-cache semantic-fidelity regression is green for signature params,
member completion, and method definition routing against a no-cache baseline.
After LM-609, foreground definition requests no longer hard-fail solely because
background prelude hydration is still in flight; warm default and
`LSP_AST_CACHE=1` harness runs now keep `definition handle_completion` at 1
location.
After LM-610, warm project-cache foreground docs preserve filtered `require`
paths for on-demand semantic fallback without re-enabling eager background
dependency warming. After LM-611, the remaining first-hit bench-file default
no-AST-cache dependency-load cost was closed for the current harness:
`definition Lexer` stays around 0.5-1.2ms, `signature help Parser.new` stays
sub-millisecond to low-millisecond, and `completion parser.` stays around
9-12ms with source-backed private/protected method labels instead of collapsing
to the shallow 11-item cache summary or loading the dependency graph. After
LM-612, `LSP_AST_CACHE` is enabled by default with `LSP_AST_CACHE=0` and
config `ast_cache: false` opt-outs; warm default `server.cr` open is now about
150ms in the harness while the focused cache semantic-fidelity spec and full
LSP suite stay green. After LM-613, AST document symbols are collected lazily
on `textDocument/documentSymbol` instead of during `didOpen`; warm default
`server.cr` open is about 140ms in the harness, while document symbols remain
AST-backed when requested. After LM-614, foreground `didOpen`/`didChange`
preserve declaration indexes but stop eagerly building the child expression span
index; positional navigation falls back to the AST walk and the focused
regression keeps hover, definition, semantic tokens, and lazy document symbols
green. After LM-615, first full semantic-token requests avoid ignored trivia,
hash priority lookups, dedup allocation, and temporary String allocation during
name/member source-window searches; the warm harness now reports `server.cr`
semantic tokens around 122-126ms with server-side collection around 66ms and
JSON serialization around 14ms. After LM-616, the formatter stores only
non-whitespace tokens while preserving comments/newlines and uses direct
one-token lookahead; steady direct formatting of `server.cr` is about 68-70ms
instead of about 73ms. After LM-618, declaration-header hover bypasses the
generic foreground AST walk while keeping the foreground expression index lazy;
warm harness `hover handle_completion` now hits the method-declaration fast
path in about 1.5ms server-side and about 5.4ms client-side. After LM-619,
exact-text reopen restores recently closed document analysis and diagnostics
inside the same server process; the repeated harness `server.cr` open used by
the call-hierarchy scenario dropped from about 130-140ms to 13-31ms in the
measured runs. After LM-620, exact-text reopen also restores already-computed
semantic-token and formatting response JSON; a direct profile on `server.cr`
showed reopened formatting served at about 0ms, while reopened semantic tokens
avoid server collection/serialization and are then dominated by large-response
JSON parsing. After LM-621, the parser accepts nilable indexer postfix chains
such as `table[key]?.try { ... }` inside ternary true branches, removing the two
recoverable parser diagnostics from `src/compiler/hir/ast_to_hir.cr` that
blocked foreground AST-cache persistence. A stable-binary isolated LSP profile
created the AST cache on the first run and then loaded `ast_to_hir.cr` from it
on the second run, dropping measured first `didOpen` from about 2.5s to about
1.14s for that file. After LM-622, full semantic-token JSON responses for
large exact disk-backed documents persist across LSP processes behind a strict
compiler-fingerprint/mtime/size/text-match gate and a 64KB source-size floor.
The measured `ast_to_hir.cr` full-token request dropped from about 1028ms on
the first compute-and-save run to about 410ms on a fresh disk-cache-hit run in
the helper path; the remaining cost is dominated by handling/parsing the huge
JSON response. After LM-623, semantic-token full responses carry stable
`resultId`s and the server supports `textDocument/semanticTokens/full/delta`;
when a client already has the current result id, the repeated
`ast_to_hir.cr` request returns an empty 75-byte delta in about 0.9ms instead
of resending 1,276,950 encoded ints. After LM-624, the remaining first full
semantic-token request no longer pays the full frontend lexer cost for the
LSP-only lexical overlay. On `ast_to_hir.cr`, the lexer-oracle path measured
about 550.5ms collection / 314.1ms lexical, while the default byte scanner
measured about 315.1ms collection / 117.8ms lexical with the focused
semantic-token fixtures and full LSP suite green.
After LM-625, unchanged disk-backed foreground opens can use the loaded
project cache after AST-cache parsing instead of rerunning foreground
name-resolution on `didOpen`; full semantic analysis is materialized lazily
for precision features that need a current-AST identifier map. On
`ast_to_hir.cr`, a stable-binary isolated profile measured warm default
`didOpen` at about 548.0ms versus about 999.5ms with
`LSP_FAST_PROJECT_OPEN=0` on the same warm cache.
After LM-626, that same cached foreground-open path no longer queues a
redundant debounced `UnifiedProject.update_file` for unchanged text; warm
`ast_to_hir.cr` `didOpen` stayed about 529.3ms while shutdown dropped from the
old ~1.7s maintenance tail to about 12.8ms.
After LM-627, warm cached foreground opens for unchanged disk-backed files also
skip AST-cache deserialization on `didOpen`; the open stores project-cache
summaries in a lightweight empty-AST document state and materializes the AST,
or full foreground semantic analysis, only when the first request needs it.
On `ast_to_hir.cr`, an isolated safe-wrapper timing probe measured lazy cached
`didOpen` at about 280.8ms average versus about 1149.1ms with
`LSP_FAST_PROJECT_OPEN=0` on the same warm cache. Focused first-request guards
cover semantic tokens, signature help, prepare rename, document symbols, and
folding ranges after a lightweight open.
Refuted for the current one-file warm harness: project-cache load itself is not
the dominant `initialize` cost (`cache=~2.9ms`), and disabling project cache
pushes dependency analysis back into foreground `didOpen`; lazy-on-first
`ExprSpanIndex` makes first hover worse for the current one-file warm harness.
Remaining LSP latency and fidelity candidates are first precision-request
materialization when the cached open has no identifier map and JSON/client
handling for the first full semantic-token response before a client has a
current delta result id. After LM-628, the method-local member-completion gap
exposed by lightweight cached opens is closed for constructor assignments such
as `helper = Helper.new`: the constructor extractor now recognizes uppercase
identifier receivers while still rejecting lowercase `variable.new`.
After LM-629, unqualified method-call hover and definition no longer force
first foreground semantic materialization after a lazy cached open. On
`ast_to_hir.cr`, first hover/definition at
`class_name_from_node(member, source)` measured about 24-25ms and kept
`ast_loaded=false` / `identifiers=false`, instead of paying the earlier
~2.6-2.8s semantic materialization cost. Remaining LSP latency candidates are
now mostly request shapes that genuinely need identifier maps, member/qualified
call precision outside the text fast path, and first full semantic-token
response transport before a client has a current delta result id.
After LM-630, `adamas tool lsp` is available as a thin launcher for a
sibling `adamas_lsp` binary or `ADAMAS_LSP_SERVER`, and the VS Code
extension can be configured with `crystalv2.lsp.serverPath` plus
`crystalv2.lsp.serverArgs` while keeping the old default direct binary path.
After LM-631, cached lightweight opens also serve hover and definition for
constructor-assigned member calls such as `helper = Helper.new` followed by
`helper.value(2)` without foreground AST materialization, as long as the
receiver type resolves to a concrete source file.
After LM-632, the same constructor-assigned local receiver corridor also serves
member completion for `helper.` without foreground AST materialization when the
receiver type resolves to a concrete source file.
After LM-633, signature help for the same shape (`helper.value(`) also returns
the resolved method signature without foreground AST materialization.
After LM-634, cached lightweight opens also serve `textDocument/documentSymbol`
from persisted `SymbolSummary` rows without foreground AST materialization,
but only when the open buffer exactly matches the unchanged cached file.
After LM-635, the VS Code extension no longer hardcodes a repo-relative LSP
binary path: settings override discovery, configured paths must be executable,
and the default path is `crystal2 tool lsp` with fallbacks to `adamas` and
standalone `adamas_lsp`.
After LM-636, invalid project-cache entries no longer run through a background
startup reparse path. They are recorded as deferred foreground work, skipped by
background indexing, and cleared only after a successful foreground document
update. This removes the VS Code crash corridor where `bin/adamas_lsp`
could stack-overflow in the parser shortly after startup while reparsing an
invalid cached file.
After LM-637, hover on qualified paths and member accesses no longer loads the
dependency graph on the request path. On `src/adamas.cr`, the harness keeps
the `CLI`/`CLI.new`/`cli.run` hover corridor in the low-millisecond range and
the debug log shows no `Loading dependency` entries during hover. Definition
keeps the broader dependency-loading resolver.
After LM-638, the hover text fallback for unqualified method calls uses
call-site arity to choose between same-name overloads and source-backed
signature formatting preserves default parameter values. This fixes the
`Random::PCG32#new_seed` shape where hovering a two-argument call selected the
zero-argument overload.
After LM-639, the matching definition fast path also carries call-site arity
into source-text method location lookup and keys the method-location cache by
arity. On the real `pcg32.cr` stdio harness, the two-argument `new_seed(...)`
call now hovers as the parameterized overload and go-to-definition points at
that same overload instead of the zero-argument wrapper.
After LM-640, hover also recognizes bare zero-argument member calls whose method
name ends in `!`/`?`. The real `int.cr` `value.to_i8!` request now returns
`def to_i8! : Int8`; because that numeric conversion is generated, hover uses
a narrow synthetic signature rather than inventing a fake definition location.
After LM-641, definition for that generated conversion points at the real
primitive template in `primitives.cr`, and uppercase stdlib constants in macro
argument lists use a lexical source-text path. The real `int.cr`
`Number.expand_div [Float64], Float64` request now hovers as `struct Float64`
and defines to `float.cr`.
After LM-642, the `expand_div` call itself is covered too: no-parentheses
member calls with uppercase receivers resolve the receiver source and index
`macro` declarations, so hover returns
`macro expand_div(rhs_types, result_type)` and definition opens `number.cr`.
After LM-643, `Int#abs_unsigned`-style ternary branches are covered: `&-`
hovers as a wrapping primitive operator and `to_u8!` reaches the generated
conversion fallback even after a ternary `:`, with definitions anchored in
`primitives.cr`.
After LM-644, explicit `lib` receivers are covered by the source-text path:
`LibIntrinsics.popcount8(src)` now hovers as the `fun` declaration and defines
to the `fun` line instead of selecting the wrapper `def self.popcount8`.
After LM-645, `&-` definition responses include an explicit
`originSelectionRange` via `LocationLink`, so editors have the operator token
range needed for clickable-source decoration.
After LM-646, AST-owned unary/binary operators also emit semantic-token
`operator` ranges, and the disk semantic-token cache moved to v3 so unchanged
large stdlib files do not serve stale pre-operator-token JSON.
After LM-647, fully qualified uppercase receiver hover/definition stays
receiver-local: `Crystal::System::Time.instant` resolves to
`crystal/system/time.cr` and hovers as `def self.instant`, rather than falling
back to the nearby `def Time.instant` wrapper.
After LM-648, callable parameter hover preserves the source parameter
signature and parameter definition uses byte-offset-derived ranges instead of
trusting stale span columns. This fixes the `Comparable(T)#<` body hover on
`other` so it reports `other : T` and definition lands on the parameter name.
The VS Code language configuration also treats Crystal operator tokens such as
`&-` and `<=>` as word-pattern units, so the editor can decorate the same
operator span that the server already returns through hover, definition, and
semantic tokens.
After LM-649, DiamondDB's full `src/diamond_foundation.cr` open no longer
crashes the LSP server on scoped alias-head type names such as
`Plan::Replica`. The semantic resolver now transports through lexical alias
heads before resolving the rest of a `::` path, and an exact in-progress
type-name guard keeps true alias cycles from stack-overflowing.
After LM-650, semantic coloring now traverses `case`/`when` branches and the
fast lexical overlay recognizes the frontend's broader Crystal keyword set.
The exact DiamondDB SQL lexer slice now emits tokens for `private`, `loop`,
`.ord.to_u8`, `peek_byte_at`, receiverless `peek_byte`/`at_end?`, and
`!at_end? && peek_byte`; the semantic-token disk cache moved to v4 to avoid
stale large-file token JSON.

Spec-first bootstrap checkpoint (2026-05-08): `docs/specs/` now contains the
first executable contract slice for Crystal V2, modeled after the DiamondDB
spec-first workflow but scoped to compiler bootstrap rather than full language
standardization. The initial set defines the stage corridor, HIR name/type
literal invariants, generic-template registration policy, MIR call ABI, LLVM
emission rules, and a falsifier matrix. Use these specs as the default target
when fixing new frontiers: every meaningful root fix should either satisfy an
existing row in `docs/specs/05-falsifier-matrix.md` or add/update a row with a
small guard.

Self-hostile spec review checkpoint (2026-05-08): after LM-561, the spec layer
has explicit pressure for `[MISSING-FALSIFIER]` rows, a first original-vs-stage
semantic oracle rule, a concrete generic template key shape, a MIR static-call
shape guard brief, and `docs/specs/06-cli-output-contract.md` for the active
post-LLVM file-output/outer-rescue frontier. Do not treat `--emit llvm-ir`
success as evidence for normal binary output.
After LM-562, the CLI/output spec also contains the exact static-call reducer,
adjacent emit-vs-binary commands, and the required localization log points for
the next post-LLVM tail fix attempt.
After LM-563, the falsifier matrix no longer marks the full-prelude
generic/template `puts 42` frontier as the active `current` row; it is a
`pre-s2-clean` gate behind the no-prelude CLI/output tail.

Stage2 CLI output tail checkpoint (2026-05-08): after LM-564, produced `s2`
passes the no-prelude static-call reducer in both adjacent modes:
`--emit llvm-ir --no-link` and normal binary output. CLI/cache-tail closure:
binary mode now keeps LLVM IR generation in memory, writes the `.ll` file
through raw `LibC` fd IO outside `LLVMIRGenerator`, and the LLVM cache hash
path streams through raw `LibC.open/read/close` instead of `File.open`. The
last C2 root was not static-call lowering and not the backend output sink
alone: lldb showed the post-write crash entering
`compile_llvm_ir -> file_sha256 -> Dir.open` and calling `__adamas_raise`
with a nil exception object in produced `s2`. The deeper nil-exception/Dir.open
path remains a separate runtime/lowering risk, not solved by this CLI-tail fix.
New guard: `p2_stage2_cli_output_tail_no_prelude.sh`, passed on host and
produced `s2`. Boundary: this clears the active no-prelude CLI/output tail; the
full-prelude generic/template `puts 42` row remains the next `pre-s2-clean`
gate, not a solved smoke.

Bootstrap investigation process checkpoint (2026-05-08): after LM-565, the
process specs record the patterns learned from the C2 cycle. Missing trace
lines are not proof that a function was not entered; use lldb/breakpoints/IR
when practical. Small helpers in self-host critical paths require fresh
`s1 -> s2` evidence. Cursor/Grok/Spark output is candidate evidence only.
Cache/hash/filesystem tails are bootstrap runtime surface, not harmless
infrastructure. A gate-local root fix must name deeper subsystem roots that
remain open.

Stage2 nilable union-wrap codegen checkpoint (2026-05-15): after LM-566,
produced `s2` passes the focused no-prelude reducer `x : UInt32? = nil; if x;
1; else; 0; end` and the produced binary runs under `scripts/run_safe.sh`.
Root closure: ordered union descriptor registrations are carried into MIR, the
LLVM union-wrap path uses descriptor-backed scalar scans instead of
stage2-sensitive iterator/string reverse lookups, and union-derived temporary
names are sanitized with the existing local-name helper. New guard:
`p2_nilable_union_wrap_codegen_no_prelude.sh`, passed on host and produced
`s2`. Boundary: this does not clear full-prelude `puts 42`; produced `s2` still
times out under a 60s adversary check during early registration, and the broader
nilable short-circuit union-phi reducer remains open on produced `s2`. The
`s1 -> s2` build also still prints a non-fatal MIR optimizer overflow for
`Adamas::Compiler::CLI#file_sha256$String`.

Stage2 generic static type-param `new!` checkpoint (2026-05-19): after
LM-571, host lowering preserves include-derived concrete long type-param
bindings such as `EquivUint => UInt64` when they are real module type params,
and static calls requested on a concrete generic owner such as
`Direct(Int32, UInt64).f` reuse that requested-owner map instead of falling
back to the template owner `Direct(T, U)`. New guard:
`p2_generic_static_type_param_new_bang_no_prelude.sh`, passed on the host
compiler and rules out unresolved `U.new!` / `EquivUint.new!` stubs plus
void-returning lowered methods. Produced `s2` builds successfully and the
full-prelude `puts 42` smoke no longer stops at
`STUB CALLED: EquivUint$Dnew$BANG$$UInt64`; without the trace env it now stops
at `STUB CALLED: Indexable$LT$R$Hequals$Q$$Indexable_block`. Boundary: the new
no-prelude guard still cannot pass on produced `s2` because it hits that
separate `Indexable#equals?` block-stub frontier before IR emission. The
`ADAMAS_TRACE_CLASS_FRONTIER=1` diagnostic env perturbs the produced
full-prelude smoke into a pre-scan timeout, so prefer the untraced abort stub as
the next primary frontier unless the trace path is being debugged directly.

Stage2 included generic equality block checkpoint (2026-05-19): after LM-572,
host full-prelude lowering for `Array(Int32)#==` emits the concrete receiver
helper `Array(Int32)#equals?$Array(Int32)_block` instead of the generic
`Indexable(T)#equals?$Indexable_block` abort stub. New guard:
`p2_indexable_equals_block_receiver_rebase.sh`, passed on the host compiler.
Produced `s2` builds successfully under the standard 300s/4096MB `run_safe`
gate; the produced namespace guard still passes. A clean-vs-patched produced
comparison shows the old `Indexable#equals?` abort is gone: clean produced `s2`
aborts the static `new!` guard source at that stub, while patched produced `s2`
gets past it and exposes a later segfault. Boundary: a broad generic
included-module block rebase was refuted because it pushed the s2 build over the
4096MB cap. The accepted fix is equality-family scoped, not a general
block/proc closure. The current traced full-prelude `puts 42` frontier is now
`Crystal::SpinLock`, segfaulting after `concrete_after_pass0`.

Stage2 macro-included proc source-sink checkpoint (2026-05-19): after LM-573,
the produced `s2` no-prelude reducer for `macro included` no longer crashes in
`AstToHir#extra_sources_for_arena` through the `MacroExpander#reparse`
`source_sink` proc. Root closure: proc literal capture detection now recognizes
bare calls that require lexical `self` when they are not proc params or parent
locals, so `->(code) { store_extra_source(macro_arena, code) }` carries the
compiler receiver instead of passing null as `self`. New guard:
`p2_macro_included_proc_sink_self_capture_no_prelude.sh`, passed on host and
produced `s2`. A broader unconditional proc `self` capture was refuted because
it made produced `s2` crash during pass3 on unrelated no-prelude main programs;
keep the accepted fix tied to implicit receiver demand, not every proc literal.
Current full-prelude `puts 42` frontier moved past `Crystal::SpinLock` /
`Crystal::Once::Operation` source-sink crash. Untraced produced `s2` now
segfaults during module registration in
`Hash(String, MacroValue)#key_hash` from `assign_macro_iter_vars` /
`process_macro_for_in_module` / `record_constants_in_body`. With
`ADAMAS_TRACE_CLASS_FRONTIER=1`, the same smoke timed out in pre-scan under
the 60s gate, so the untraced lldb backtrace is the cleaner next anchor.

Stage2 module macro-for iter-var checkpoint (2026-05-19): after LM-574,
macro-for iter variable names inside HIR module/class/lib/enum handling are
read through `safe_slice_to_string` and validated as identifiers before they
are used as `Hash(String, MacroValue)` keys. Root closure: produced `s2` was
constructing corrupted `String` keys with raw `String.new(slice)` in
`process_macro_for_in_module`, then crashing in
`Hash(String, MacroValue)#key_hash` during `assign_macro_iter_vars`. New guard:
`p2_module_macro_for_iter_var_names_no_prelude.sh`, passed on host and
produced `s2`; the prior proc source-sink and namespace guards still pass on
produced `s2`. Produced `s2` also builds successfully under the standard
300s/4096MB gate. Boundary: this clears the focused module macro-for hash-key
crash, not full-prelude `puts 42`. The full-prelude smoke now reaches module
register idx=51/114 untraced; lldb did not reach the crash under the 90s safe
timeout. With the trace env it reaches File error nested classes before exiting
133. A source-backed macro-for iter-var fallback was refuted because it made the
`s1 -> s2` compiler build fail during pass3 with an `ExprId out of bounds`
diagnostic; do not reapply that branch blindly.

Stage2 single-var macro-for binding checkpoint (2026-05-19): after LM-575,
produced `s2` no longer crashes on one-variable module macro-for reducers such
as `{% for name in %w(alpha beta) %}` while binding the loop variable into
`Hash(String, MacroValue)`. Root closure: the one-variable fallback path in
`assign_macro_iter_vars` used a direct `vars[iter_vars[0]] = value` shape that
generated an unstable produced-s2 `Hash#[]=` call, while the indexed loop shape
used by pair/tuple binding was stable. The fix routes the one-variable case
through an indexed `each_with_index` loop without adding any visible macro
variables. The `p2_module_macro_for_iter_var_names_no_prelude.sh` guard now
covers single-var generated defs, pair-var generated defs, and single-var
nested struct output; it passed on host and produced `s2`. Produced `s2` builds
successfully under the standard 300s/4096MB gate. Boundary: full-prelude
`puts 42` no longer reaches the `Hash(String, MacroValue)#key_hash` stack under
the tested trace path; it now times out in pre-scan under 45s/120s gates.

Stage2 unbound type-param scan checkpoint (2026-05-19): after LM-576,
produced `s2` no longer crashes in `Regex::MatchData#byte_end` while checking
include-derived method annotations such as `Array(T)` for unbound type
parameters. Root closure: `unbound_type_params_from_type_name` used
`String#scan(Regex)`, and produced `s2` can crash in the Regex match-data path
during class/module registration. The replacement is a direct byte tokenizer
for capitalized identifier tokens, matching the existing bootstrap rule to
avoid Regex in hot self-hosted paths. New guard:
`p2_unbound_type_param_scan_no_regex_no_prelude.sh`, passed on host and
produced `s2`. Produced `s2` builds successfully under the standard
300s/4096MB gate. Boundary: full-prelude `puts 42` now completes module
registration and reaches class registration before exiting 133; lldb under the
60s safe gate did not capture that moved class-register frontier.

Stage2 static-call LLVM emission checkpoint (2026-05-08): after LM-559,
produced `s2` no-prelude LLVM IR for `Exception::CallStack.skip("x")` now emits
the named static callee
`Exception$CCCallStack$Dskip$$String` with a valid `void` return ABI, not
fallback `@func1` and not `call  @...`. Root closure: preserve forced static
class-method names in HIR recovery, lower exact static calls before treating
stale receiver values as runtime receivers, and use dense FunctionId lookup in
LLVM emission because self-hosted hash lookup can miss. New guard:
`p2_stage2_static_call_named_llvm_no_prelude.sh`, passed on host and produced
`s2` and validated by `llc` when available. Boundary: produced `s2`
no-prelude binary output for the reducer still exits 139 after LLVM finalizes
output, so the next root is the separate CLI/file-output tail or outer-rescue
frontier, not the static-call callee/ABI spelling.

Stage2 type-literal name-query checkpoint (2026-05-06): after LM-558, produced
`s2` LLVM no longer contains `Bool$Dto_s` / `Bool$Dname` abort stubs. Root
closure: type-literal receivers such as stdlib `Pointer(T)#to_s` using
`T.to_s`, and direct `Bool.to_s` / `Bool.name`, now lower to a compile-time
type-name string unless a real dot-method override exists on the owner/parent
chain. New guard: `p2_type_literal_name_query_no_stub.sh` now uses a
no-prelude `NameProbe` type-literal method body, so it checks the name-query
lowering invariant without mixing in full-prelude registration. Boundary: this
is a shape/root fix, not a clean full-prelude smoke. Produced `s2` full-prelude
`puts 42` still exits 139; with the refuted source-backed top-level
return-annotation experiment reverted, the current untraced frontier reaches
pass2 `register_functions idx=3/297` and crashes before the next clean phase
log. Do not reapply the top-level source-return hunk blindly; with the
type-literal fix it still regressed the smoke to an earlier class-registration
crash around `class register idx=51/104`.

Stage2 Char::Reader post-registration frontier (2026-05-06): after LM-557,
produced full-prelude `puts 42` got past the previous `Proc` class-body trap.
That checkpoint remains useful historical evidence for the semantic
check-only/source-provider corridor, but LM-558 is the fresher active frontier.

Stage2 nested-method annotation namespace checkpoint (2026-05-05): produced
`cv2_s2` no longer qualifies top-level/builtin method annotations inside
`Float::FastFloat` as fake nested types. Root shape: after the self-wrapper fix,
full-prelude trace showed `Float::FastFloat.to_f64?` and `to_f32?` signatures
with `raw=String resolved=Float::FastFloat::String` and `raw=Bool
resolved=Float::FastFloat::Bool`. `DEBUG_TYPE_EXISTS_TRACE` showed the
candidate existed through an enum table hit, so `qualify_method_annotation...`
trusted a registry fallback rather than the structural nested-type set. Root
fix: for unqualified top-level/builtin annotations, keep the top-level name
unless the active namespace chain structurally records that nested type. Evidence:
`/private/tmp/cv2_annot_structural` host build; `p2_qualified_module_namespace_no_prelude.sh`,
`p2_nested_module_registration_no_prelude.sh`,
`p2_self_nested_module_registration_frontier.sh`, and
`p2_full_prelude_generic_template_namespace_no_pollution.sh` pass on host;
`scripts/run_safe.sh /private/tmp/cv2_annot_structural 300 4096
src/adamas.cr -o /private/tmp/cv2_annot_structural_s2/cv2_s2` exits 0; and
`p2_full_prelude_generic_template_namespace_no_pollution.sh` passes on produced
`/private/tmp/cv2_annot_structural_s2/cv2_s2`. Boundary: produced full-prelude
`puts 42` still times out in class registration after `class register idx=3/104`,
so the next root is liveness/registration cost past the now-correct
`Float::FastFloat` signatures, not the `String`/`Bool` annotation pollution.

Stage2 self-nested module wrapper checkpoint (2026-05-05): generated `cv2_s2`
now passes the module-registration trap that followed the pre-scan fix. Root
shape: produced `s2` can represent a qualified reopen wrapper as a nested
`ModuleNode` whose canonical name is the current owner itself
(`Float::FastFloat -> Float::FastFloat`). Routing that node back through
ordinary nested-module registration recurses into the same canonical owner and
hits a Trace/BPT trap during full-prelude `puts 42`. Root fix: self-wrapper
module names are removed from nested-name visibility, recursive self module
registration is skipped, and direct nested types/aliases carried by that wrapper
are still registered under the owner so the `ParsedNumberStringT` namespace
guard stays intact. Evidence: `/private/tmp/cv2_self_nested_final` host build;
`p2_qualified_module_namespace_no_prelude.sh`,
`p2_nested_module_registration_no_prelude.sh`, and new
`p2_self_nested_module_registration_frontier.sh` pass on the host compiler;
`scripts/run_safe.sh /private/tmp/cv2_self_nested_final 300 4096
src/adamas.cr -o /private/tmp/cv2_self_nested_final_s2/cv2_s2` exits 0; and
`p2_qualified_module_namespace_no_prelude.sh` plus
`p2_self_nested_module_registration_frontier.sh` pass on the produced compiler.
Refuted variant: recursively flattening self-wrapper module bodies into the
owner was too broad and moved produced `s2` back to an early module-register
Trace/BPT trap. Boundary: produced full-prelude `puts 42` now passes module
registration under the frontier guard, but the wider clean `puts 42` compile is
not yet an `s2 -> s3` unlock; suspicious parameter types such as
`Float::FastFloat::String` / `Float::FastFloat::Bool` remain the next root
pattern to localize.

Stage2 pre-scan constant frontier checkpoint (2026-05-05): generated `cv2_s2`
passes CLI class/module constant pre-scan for full-prelude `puts 42`. Root fix:
pre-scan keeps complex RHS constants name-visible without performing
registration-time literal/type/deferred-init work, while scalar Number/Bool/Char
constants still get full metadata early enough for ivar defaults such as
`IO::DEFAULT_BUFFER_SIZE`. Evidence: `/private/tmp/cv2_prescan_final` host
build; `p2_macro_compare_versions_control_no_raw_sanitize.sh`,
`p2_qualified_module_namespace_no_prelude.sh`, and
`p2_prescan_complex_constants_frontier.sh` pass on both the host compiler and
produced `/private/tmp/cv2_prescan_final_s2/cv2_s2`; and s1 -> s2 build exits 0
under `scripts/run_safe.sh`. Refuted variants: all name-only pre-scan and
`TypeRef::VOID` placeholders in `@constant_types` both lead to invalid LLVM
`store ptr 32768`.

Stage2 source-backed initializer-parameter checkpoint (2026-05-01): class and
module registration now avoid another stale frontend-slice boundary when
capturing `initialize` params into ivars. `capture_initialize_params` reads
parameter names and type annotations from `name_span` / `type_span` through the
member/source arena before falling back to guarded slices, and its registration
callers now pass the relevant arena explicitly. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_param_source_candidate
--error-trace`; `regression_tests/p2_enum_class_setter_return_infer_no_prelude.sh
/tmp/cv2_param_source_candidate`;
`regression_tests/p2_nested_module_registration_no_prelude.sh
/tmp/cv2_param_source_candidate`;
`regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/tmp/cv2_param_source_candidate`;
`regression_tests/p2_visibility_private_accessor_no_prelude.sh
/tmp/cv2_param_source_candidate`; and `scripts/run_safe.sh
/tmp/cv2_param_source_candidate 300 4096 src/adamas.cr -o
/tmp/cv2_direct_param_source_candidate/cv2_s2`, which builds generated
`cv2_s2` in ~160s. Boundary: generated `cv2_s2` plain `puts 42` smoke still
segfaults during full-prelude module registration near
`Exception::CallStack` / `each_param(Array(Parameter), &block)`, so this is not
an `s2 -> s3` unlock yet.

Stage2 implicit-ivar param scan checkpoint (2026-05-01): generated `cv2_s2`
now advances past the previous `Exception::CallStack` implicit-ivar scan crash.
Root fix: the post-mixin implicit ivar discovery pass no longer scans every
method's parameter array looking for `param.is_instance_var`; it first checks
the source `def` header for an `@` parameter and only falls back to old
Parameter-field scanning if source is unavailable. Real `@param` names/types
are read from source-backed parameter spans. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_ivar_param_source_candidate
--error-trace`; existing p2 no-prelude guards; new
`regression_tests/p2_implicit_ivar_param_source_scan_no_prelude.sh
/tmp/cv2_ivar_param_source_candidate`; and `scripts/run_safe.sh
/tmp/cv2_ivar_param_source_candidate 300 4096 src/adamas.cr -o
/tmp/cv2_direct_ivar_param_source/cv2_s2`, which builds generated `cv2_s2` in
~161s. Boundary: generated `cv2_s2` plain `puts 42` smoke still segfaults, but
`DEBUG_REG_CONCRETE_PHASE=CallStack` now reaches `after_new_register`; lldb
shows the new frontier is a different `each_param` block inside
`register_nested_module_in_current_arena`.

Stage2 nested-module parameter checkpoint (2026-05-01): the
`register_nested_module_in_current_arena` PASS 2 class-method registration path
now resolves parameter annotations from source-backed `Parameter#type_span`
instead of direct `param.type_annotation` slices when a member arena is known.
Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_nested_module_params_candidate --error-trace`; the five p2 no-prelude
guards including `p2_implicit_ivar_param_source_scan_no_prelude.sh`; and
`scripts/run_safe.sh /tmp/cv2_nested_module_params_candidate 300 4096
src/adamas.cr -o /tmp/cv2_direct_nested_module_params/cv2_s2`, which
builds generated `cv2_s2` in ~155s. Boundary: generated `cv2_s2` still fails
plain full-prelude `puts 42`, but lldb no longer shows `each_param` /
`safe_slice_to_string`; the next frontier is
`infer_type_from_expr_inner -> infer_concrete_return_type_from_body` while
registering `Float::Float::Bigint`.

Stage2 initialize-return checkpoint (2026-05-01): class `initialize` methods
now keep the semantic `Void` contract in both registration and actual method
lowering. Root cause: registration was hardened first, but `lower_method` still
treated unannotated `initialize` like an ordinary implicit-return method, merged
the final body expression from Return terminators / `last_value`, and rewrote
HIR signatures such as `Box#initialize$Int32` to the body type (`Bool` in the
new no-prelude reducer). The fix makes `initialize` return `TypeRef::VOID`
before function creation, skips annotated/implicit return re-inference for
constructors, and emits a valueless implicit return terminator. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_initialize_void_candidate
--error-trace`; `regression_tests/p2_initialize_return_void_no_prelude.sh
/tmp/cv2_initialize_void_candidate`; the five existing p2 no-prelude guards;
and `scripts/run_safe.sh /tmp/cv2_initialize_void_candidate 300 4096
src/adamas.cr -o /tmp/cv2_direct_initialize_void/cv2_s2`, which builds
generated `cv2_s2` in ~162s. Boundary: generated `cv2_s2` plain full-prelude
`puts 42` smoke now reaches module registration and aborts on the next frontier,
`STUB CALLED:
Crystal$CCMIR$CCUnionDescriptor$Hinitialize$$String_Array$LCrystal$CCMIR$CCUnionVariantDescriptor$R_Int32_Int32`.
Do not treat this as an `s2 -> s3` unlock yet; next work should localize the
missing `UnionDescriptor#initialize` demanded symbol rather than changing
constructor semantics again.

Stage2 macro-expanded parameter source checkpoint (2026-05-01): the
`UnionDescriptor#initialize` abort was a stale source-recovery bug, not a
missing constructor feature. `MacroExpander#reparse` retains generated macro
output as an arena extra source but still reparses into the macro-definition
arena, so `parameter_name_string` / `parameter_type_annotation_string` could
slice `src/stdlib/macros.cr` or macro-body text instead of generated output.
The fix tries recent retained macro outputs for the same parameter span before
trusting the primary arena source, with bounded name/type candidate checks and
explicit `ArenaLike` narrowing at the helper callsite to avoid a generated-s2
nilable-helper abort stub. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_macro_param_source_candidate3 --error-trace`;
`regression_tests/p2_macro_extra_source_param_recovery_no_prelude.sh
/tmp/cv2_macro_param_source_candidate3`; existing p2 guards
`p2_initialize_return_void_no_prelude.sh`,
`p2_implicit_ivar_param_source_scan_no_prelude.sh`,
`p2_bootstrap_semantic_emit_oracle.sh`,
`p2_nested_module_registration_no_prelude.sh`,
`p2_enum_class_setter_return_infer_no_prelude.sh`, and
`p2_visibility_private_accessor_no_prelude.sh`; and
`scripts/run_safe.sh /tmp/cv2_macro_param_source_candidate3 300 4096
src/adamas.cr -o /tmp/cv2_direct_macro_param_source3/cv2_s2`, which builds
generated `cv2_s2` in ~153s. Boundary: generated `cv2_s2` plain full-prelude
`puts 42` no longer hits `UnionDescriptor#initialize` or the helper stub; the
new frontier is `[INFER_INDEX] method=unlock
self=Exception::Exception::CallStack obj= idxs=1` followed by a segfault during
module registration. Do not attempt `s3b+` until that frontier is reduced.

Stage2 no-prelude semantic-corpus checkpoint (2026-05-01): generated `cv2_s2`
now compiles and runs `regression_tests/bootstrap_semantic_corpus.cr
--no-prelude` after the HIR inline-yield/proc-literal corridor and the MIR/LLVM
backend state were hardened. Root fixes in this checkpoint: inline-yield stack
ivars are explicitly initialized because generated stage2 can miss inline
defaults; inline-yield callee arenas are resolved through a non-nil
`function_def_arena_or_current`; `function_namespace_override_for` uses fixed
arity overloads instead of a splat helper that stage2 materialized as an abort
stub; proc-literal capture name/type arrays are built with explicit loops and a
non-nil arena; unary `&expr` is treated as the parser block/proc-pass marker
instead of a runtime unary method call; MIR pre-scans avoid stdlib `map/each`
over `Array(Tuple(ValueId, ValueId))` phi/switch arrays; LLVM backend caches the
current function's canonical param name/type pairs while emitting the signature;
and pointer-return emission now passes through already-pointer values instead
of generating invalid `inttoptr ptr ... to ptr`. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_clean_candidate --error-trace`;
`scripts/run_safe.sh /tmp/cv2_clean_candidate 300 4096 src/adamas.cr -o
/tmp/cv2_s2_clean`; `scripts/run_safe.sh /tmp/cv2_s2_clean 30 2048
--no-prelude regression_tests/bootstrap_semantic_corpus.cr -o
/tmp/cv2_clean_corpus`; and `scripts/run_safe.sh /tmp/cv2_clean_corpus 5 512`.
Boundary: this is a focused no-prelude oracle, not a full `s2 -> s3` proof.
Next work should add more fast no-prelude oracles around inline yield, proc
literal block pass, phi/switch MIR pre-scans, and pointer-return coercion before
promoting to a wider bootstrap ladder.

Stage2 container/arena/backend checkpoint (2026-05-01): generated `cv2_s2`
now builds again after several root-cause fixes in the container storage and
mixed-union ownership corridor. Fixed evidence-backed issues: `Array(Slice(UInt8))`
registered its element from an early `Generic Slice(UInt8)` alias instead of
the later concrete `Struct Slice(UInt8)` descriptor; broad inline struct-array
storage corrupted pointer-shaped frontend structs such as `Array(Parameter)`;
mixed unions like `Array(Parameter) | ExprId` failed to transfer ownership of
reference payload variants, so parser-returned arrays could be `rc_dec`'d while
stored in the union; function-name suffix rewriting sent literal `$arity...`
through `String#sub` regex replacement; V2 heap `Slice(UInt8)` validation only
probed the first bytes before `String.new(slice)`; module arena validation used
the recursion depth cap as a hard mismatch and could trigger repeated source
reparse repair for deeply nested namespace modules; GEP dynamic index conversion
could emit self-referential SSA names in no-prelude interpolation. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_gep_selfref_candidate
--error-trace`; `regression_tests/p2_array_struct_unsafe_fetch_return_no_prelude.sh
/tmp/cv2_gep_selfref_candidate`; `regression_tests/p2_pending_budget_no_prelude.sh
/tmp/cv2_gep_selfref_candidate`; `scripts/run_safe.sh
/tmp/cv2_gep_selfref_candidate 30 1024
regression_tests/combined/test_no_prelude_interpolation.cr --no-prelude -o
/tmp/cv2_gep_selfref_interp_bin`; `scripts/run_safe.sh
/tmp/cv2_gep_selfref_candidate 120 4096
regression_tests/complex/test_array_map_select_chain.cr -o
/tmp/cv2_gep_selfref_plain_smoke`; and
`BOOTSTRAP_STAGE_OUT=/tmp/cv2_bs_s2_post_7d99340f BOOTSTRAP_CHAIN_STAGES=2
BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
scripts/build_bootstrap_stages.sh --stages 2 --out /tmp/cv2_bs_s2_post_7d99340f`,
which builds generated `cv2_s2` in ~219s and now passes `smoke no-prelude`.
Boundaries: `s2` plain smoke still segfaults during nested module registration;
the latest lldb trace on `/tmp/cv2_bs_s2_post_7d99340f/cv2_s2` shows stack
overflow in `GC_clear_stack_inner`, reached through repeated
`with_reparsed_module_from_current_source -> register_nested_module` recursion
while parsing a generic type annotation in a nested module. Stochastic stage2 build OOBs
with ASCII-like ExprId payloads (`[S2_`, `shad`) were observed in wrapper runs
but not reproduced under direct `run_safe` with `DEBUG_EXPR_OOB=1`; treat them
as suspected memory corruption, not verified root cause yet.

Stage2 source-backed extern registration checkpoint (2026-04-30): generated
`cv2_s2` now advances past the LibC registration abort stubs for
`extract_alias_name_value_from_source`, `register_extern_fun_from_source`, and
`resolve_extern_fun_signature_from_source`. The root was a helper ABI mismatch,
not a missing LibC case: source-backed extern helpers threaded `ArenaLike`
through generated-stage2 calls even though all local callers used the current
`@arena`, and the signature resolver mixed lib and top-level contexts through
`lib_name : String?`. Generated stage2 then emitted concrete `$String...` calls
while lowering materialized only broader `$Nil | String...` targets. The fix
adds the alias/extern source helper family to exact-demand, removes redundant
`ArenaLike` parameters from the local source extern helpers, and splits lib
extern signature resolution (`String` lib name) from top-level `fun`
resolution (no lib-name parameter). Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_source_extern_split_candidate
--error-trace`; `regression_tests/p2_source_extern_signature_no_prelude.sh
/tmp/cv2_source_extern_split_candidate`; and
`BOOTSTRAP_STAGE_OUT=/tmp/cv2_bs_s2_source_extern_split
BOOTSTRAP_CHAIN_STAGES=2 BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
scripts/build_bootstrap_stages.sh --stages 2 --out
/tmp/cv2_bs_s2_source_extern_split`, which builds generated `cv2_s2` and keeps
`smoke no-prelude: ok`. Boundary: full-prelude `s2` smoke is still not clean;
the next exposed frontier is
`Hash(String, Hash(UInt32, Crystal::HIR::Value))#to_unsafe` during LibC
registration. Also keep the broader requested-symbol-wrapper issue open:
when a concrete call symbol resolves to a wider typed overload, lowering may
still need to materialize a requested-name wrapper instead of only the wider
target.

Stage2 bounded String-search checkpoint (2026-04-30): the generated `cv2_s2`
`private class Hidden` no-prelude reducer no longer dies in
`lookup_function_def_for_call -> String#includes?` because the LLVM backend
now emits bounded `memcmp` loops for `String#includes?(String)` and
`String#index(String, offset)` instead of passing Crystal's length-delimited,
non-NUL-terminated payloads to libc `strstr`. The helpers also fail closed on
null operands so the self-hosted compiler does not crash before exposing the
real next frontier. Evidence so far: `crystal build src/adamas.cr -o
/private/tmp/cv2_string_nullsafe_candidate --error-trace`;
`regression_tests/p2_string_bounded_search_runtime_repro.sh
/private/tmp/cv2_string_nullsafe_candidate`;
`regression_tests/p2_visibility_modifier_semantics_no_prelude.sh
/private/tmp/cv2_string_nullsafe_candidate`; and
`scripts/run_safe.sh /private/tmp/cv2_string_nullsafe_candidate 300 4096
src/adamas.cr -o /private/tmp/cv2_s2_string_nullsafe`, which builds the
next generated compiler. Boundary: this is not a full nilable/short-circuit
codegen fix. Two `lower_call` hot paths now use explicit local narrowing for
`full_method_name`, but the broader self-hosted nilable guard issue remains
open. Generated `cv2_s2` now advances the simple `String#includes?("$$block")`
and `private class Hidden` no-prelude reducers from String segfaults to
existing Hash-stub aborts (`Hash#each` and
`Hash(String, Array(Tuple(String, Crystal::MIR::Function)))#<<$String`).
Treat those Hash stubs as the next root-cause frontier before attempting
`s2 -> s3`.

Stage2 self-host visibility/arena frontier update (2026-04-30): the
`private DIGITS_DOWNCASE` failure is no longer a visibility allowlist problem.
The parser now recognizes uppercase identifier assignment through a concrete
`IdentifierNode` path and ASCII byte check, and deferred constant
initializers now store an arena-stable `ExprId`+arena record instead of a raw
`Int32` index. Generated `cv2_s2` now compiles the no-prelude reducer
`private VALUE = 1; VALUE` and registers it as a constant. The next exposed
family is self-host exact-signature drift around arena helpers: generated
calls may be `Nil | AstArena | PageArena | VirtualArena` while the intended
helper contract is `Frontend::ArenaLike`. Several reparsing/class-registration
helpers now normalize nilable arenas explicitly and avoid `map/find` block
helpers on reparsed roots. Evidence so far: `crystal build
src/adamas.cr -o /private/tmp/cv2_cast_candidate --error-trace`;
`regression_tests/p2_visibility_modifier_semantics_no_prelude.sh
/private/tmp/cv2_cast_candidate`;
`regression_tests/p2_visibility_private_accessor_no_prelude.sh
/private/tmp/cv2_cast_candidate`;
`regression_tests/p2_splat_default_args_no_prelude.sh
/private/tmp/cv2_cast_candidate`; and
`regression_tests/p2_visibility_private_const_module_no_prelude.sh
/private/tmp/cv2_cast_candidate`; plus the same
`p2_visibility_private_const_module_no_prelude.sh` run against generated
`/private/tmp/cv2_bs_s2_cast/cv2_s2`; and
`BOOTSTRAP_STAGE_OUT=/private/tmp/cv2_bs_s2_cast
BOOTSTRAP_CHAIN_STAGES=2 BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
scripts/build_bootstrap_stages.sh --stages 2 --out
/private/tmp/cv2_bs_s2_cast`, which builds generated `cv2_s2` and keeps
`smoke no-prelude: ok`. Boundary: generated `cv2_s2` now passes no-prelude
`private module M; end` and `private VALUE = 1`, but
`private class Hidden; def value; 1; end; end; Hidden.new.value` has advanced
past registration stubs and now segfaults in `lower_main` through
`lookup_function_def_for_call -> String#includes?`. Full-prelude `s2` smoke
still segfaults at `top-level collection walk start`; do not claim full
visibility-class support until the generated no-prelude `private class` reducer
is green.

Stage2 full-prelude frontier update (2026-04-30): three root fixes are ready
as the next green commit, but full-prelude `s2` smoke is still not clean.
First, default-argument expansion now preserves the actual named-argument
signal and returns the concrete overload selected before defaults; splat packing
uses that selected overload instead of re-resolving the generic base after
scalar defaults. This removes bad scalar wrappers such as `Dir.glob$String` and
`Dir.glob$String_File::MatchOptions_Bool`. Second, MIR now indexes Proc carrier
provenance across class variables, so raw C function-pointer callbacks returned
by extern calls and stored in class vars (for example GC push-root callback
hooks) are not later called as heap Proc objects. Third, `private/protected
abstract def` now preserves visibility in the parser instead of wrapping the
abstract modifier and losing the method visibility. Evidence so far:
`crystal build src/adamas.cr -o /private/tmp/cv2_commit_candidate
--error-trace`; `regression_tests/p2_splat_default_args_no_prelude.sh
/private/tmp/cv2_commit_candidate`;
`regression_tests/p2_selfhost_stage2_shape_guard.sh
/private/tmp/cv2_commit_candidate`; `regression_tests/p1_mixed_proc_block_yield_carrier.sh
/private/tmp/cv2_commit_candidate`; and
`regression_tests/p2_visibility_modifier_semantics_no_prelude.sh
/private/tmp/cv2_commit_candidate`. Boundary: generated `s2` now moves past the
old `Dir.glob` MIR shape and GC raw-callback SIGBUS, then fails in full-prelude
smoke on `private DIGITS_DOWNCASE = ...` from `src/stdlib/int.cr`. A hostile
diagnostic showed generated `s2` parses uppercase assignments as ordinary
identifier assignments; treating them as constants exposes a deeper deferred
constant/lower_main frontier. Do not paper over this with a broad visibility
allowlist; fix the parser/constant-lowering root.

Stage2 no-prelude LLVM smoke checkpoint (2026-04-29): generated `s2b` now
passes the no-prelude interpolation smoke. Three backend roots were fixed in
sequence. First, MIR stack `Alloc` slots were emitted by the entry alloca
prepass and then re-hoisted from buffered block IR; the block-IR splitter now
skips alloca names already emitted by the entry prepass. Second, derived LLVM
temporary names used `name.lstrip('%')`, which can produce invalid digit-leading
names such as `%0.conv1`; string interpolation now uses a local-name helper
that strips one leading `%` and prefixes numeric bases. Third, generated s2
discovered string constants during function emission but lost them before tail
constant emission through Hash-backed bookkeeping; string constants now use
parallel arrays as the authoritative ordered table, with the Hash retained only
as a cache. Evidence: `crystal build src/adamas.cr -o
/private/tmp/cv2_string_table_arrays --error-trace`;
`regression_tests/p2_no_prelude_unique_alloca_names.sh
/private/tmp/cv2_string_table_arrays`;
`regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/private/tmp/cv2_string_table_arrays`;
`regression_tests/p2_pending_budget_no_prelude.sh
/private/tmp/cv2_string_table_arrays`; and
`BOOTSTRAP_STAGE_OUT=/private/tmp/cv2_bs_s2_string_table_arrays
BOOTSTRAP_CHAIN_STAGES=2 BOOTSTRAP_TIMEOUT_SEC=300 BOOTSTRAP_MEM_MB=4096
scripts/build_bootstrap_stages.sh --stages 2 --out
/private/tmp/cv2_bs_s2_string_table_arrays`, which builds `cv2_s2` in ~235s
and reports `smoke no-prelude: ok`. Boundary: full-prelude stage2 smoke still
fails with SIGBUS immediately after `prelude exists`; that is the next
bootstrap frontier.

Proc#call backend-boundary checkpoint (2026-04-29): HIR intentionally emits
`Proc#call` as a plain `Call` so MIR can lower heap Proc dispatch through
`call_heap_proc`, but `lower_missing_call_targets` was also treating that name
as source demand. This was a wrong boundary even in a tiny no-prelude reducer:
`p = ->(x : Int32) { x + 1 }; p.call(41)` left `Proc#call` in the HIR and
also queued it as a missing source function. `Proc#call`, `Proc#call$...`, and
`Proc#call(...)` are now classified with the other backend-owned HIR call
names. Evidence: `crystal build src/adamas.cr -o
/private/tmp/cv2_proc_call_boundary --error-trace`;
`regression_tests/p2_proc_call_backend_boundary_no_prelude.sh
/private/tmp/cv2_proc_call_boundary`;
`regression_tests/p2_backend_intrinsic_boundary_no_prelude.sh
/private/tmp/cv2_proc_call_boundary`;
`regression_tests/p2_pending_budget_no_prelude.sh
/private/tmp/cv2_proc_call_boundary`; and
`regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/private/tmp/cv2_proc_call_boundary`. Boundary: this is not the remaining
full-source fanout root. A fresh `STOP_AFTER_HIR` profile on `src/adamas.cr`
still reports `lower_missing: 615 -> 35892 (+35277) in 166338.1ms`; the next
root-cause corridor remains supply-driven `Hash` / `Array` / `Hash::Entry`
materialization, not `Proc#call`.

Visibility modifier semantics checkpoint (2026-04-29): top-level collection
and HIR member unwrapping now validate `VisibilityModifierNode` before
discarding the wrapper. This aligns the non-accessor declaration cases with
Crystal's top-level visitor for the covered forms: `private` type/constant/macro
wrappers remain valid, `protected` type/constant/macro wrappers now fail with
the original-style diagnostics, and invalid non-call expressions such as
`private 1` no longer compile silently. Evidence: `crystal build
src/adamas.cr -o /private/tmp/cv2_visibility_modifier_semantics
--error-trace`; `regression_tests/p2_visibility_modifier_semantics_no_prelude.sh
/private/tmp/cv2_visibility_modifier_semantics`;
`regression_tests/p2_visibility_private_accessor_no_prelude.sh
/private/tmp/cv2_visibility_modifier_semantics`;
`regression_tests/p2_visibility_protected_namespace_no_prelude.sh
/private/tmp/cv2_visibility_modifier_semantics`; `crystal spec
spec/parser/parser_visibility_spec.cr --error-trace`;
`regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/private/tmp/cv2_visibility_modifier_semantics`; and
`regression_tests/p2_named_tuple_annotation_keys_no_prelude.sh
/private/tmp/cv2_visibility_modifier_semantics`. Boundary: visibility-wrapped
`CallNode` remains allowed as a macro-call escape hatch (`private record`,
typed macro calls) until v2 has a reliable expanded/unexpanded macro-call
marker equivalent to original Crystal's MainVisitor check.

Union annotation + protected namespace checkpoint (2026-04-29): stage2
`STOP_AFTER_HIR` now gets past the former
`debug_cli_root_block_state(...AstArena...)` stub/miss and the subsequent
`protected method 'entries_size' called for Hash(...)` failure. The root fixes
are: registration resolves annotations in the method owner's namespace
(`Frontend::ArenaLike` inside `CLI` resolves to the frontend alias), union
descriptors keep their union-shaped mangled names instead of collapsing through
`resolve_type_alias_chain`, union alias strings are resolved structurally per
variant, union cache hits reject stale non-union descriptors, and protected
visibility now mirrors Crystal's `has_protected_access_to?` rule by allowing
same top namespace/nested types such as `Hash::KeyIterator -> Hash` without
whitelisting `entries_size`. Evidence: `crystal build src/adamas.cr -o
/private/tmp/cv2_protected_namespace --error-trace`;
`regression_tests/p2_visibility_protected_namespace_no_prelude.sh
/private/tmp/cv2_protected_namespace`;
`regression_tests/p2_visibility_private_accessor_no_prelude.sh
/private/tmp/cv2_protected_namespace`; `ADAMAS_STOP_AFTER_HIR=1
ADAMAS_PHASE_STATS=1 scripts/run_safe.sh /private/tmp/cv2_protected_namespace
180 4096 src/adamas.cr -o /private/tmp/cv2_protected_namespace_s2` exits 0
after ~145s. Boundary: this unblocks HIR completion but does not solve the
remaining `lower_missing` fanout (`615 -> 35882`, ~159s), which is the next
demand-driven root-cause corridor.

Visibility accessor checkpoint (2026-04-29): parser/HIR now preserve
`private`/`protected` on accessor macros instead of dropping the modifier at
`private getter` / `protected property` parse time. Accessor nodes carry
visibility through LSP AST cache, generated accessor registrations mirror it
into HIR method metadata, and both normal call lowering and property-style
member access reject explicit non-self calls to private accessors. Evidence:
`crystal spec spec/parser/parser_visibility_spec.cr --error-trace`,
`crystal build src/adamas.cr -o /private/tmp/cv2_visibility --error-trace`,
`regression_tests/p2_visibility_private_accessor_no_prelude.sh
/private/tmp/cv2_visibility`, and `bash -n
regression_tests/p2_visibility_private_accessor_no_prelude.sh`. Boundary:
broader top-level visibility semantics for constants/types/macros are not yet
fully aligned with original Crystal's top-level visitor.

LLVM value-lookup iterator checkpoint (2026-04-29): after removing the
debug-cache tuple key, generated `cv2_s2` reached LLVM emission for the
no-prelude smoke and crashed inside `LLVMIRGenerator#value_ref(UInt32)` from
`emit_extern_call`. The first bounded attempt only replaced
`@current_func_params.any? { |p| p.index == id }`, which moved the crash into
`find_def_inst` at `block.instructions.find { |inst| inst.id == id }`. The
root pattern is the same: this backend materialization path does not need
closure/Enumerable helpers, and generated stage2 is still fragile around block
iterator helpers in this hot lookup corridor. The fix uses direct while loops
for both parameter-index lookup and definition lookup. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_value_ref_def_loop --error-trace`;
`p2_bootstrap_semantic_emit_oracle.sh`, `p2_pending_budget_no_prelude.sh`,
`p2_universal_helper_fanout_no_prelude.sh`, and `p1_ir_shape_check.sh` pass
with `/tmp/cv2_value_ref_def_loop`; canonical `s1 -> s2` still builds `cv2_s2`
in about 229s. Boundary: generated `cv2_s2` smoke still fails, but ASLR-enabled
LLDB now stops later in `File.new_internal -> File.open -> CLI#file_sha256`,
not in `LLVMIRGenerator#value_ref` or `find_def_inst`.

Debug line-scope cache checkpoint (2026-04-29): the generated `cv2_s2`
no-prelude smoke no longer crashes in `__adamas_string_eq` through
`Hash(Tuple(String, Int32), UInt32)#fetch ->
HIRToMIRLowering#hir_innermost_scope_for_source_line`. The root was a
compiler-internal MIR debug cache using `{loc.path, loc.line}` tuple keys in
self-hosted stage2, where tuple-key Hash lookup can hand invalid String fields
to `Tuple#==`. The fix changes the cache to `Hash(String, Hash(Int32, UInt32))`
and reinitializes the per-function scope caches instead of mutating them with
`clear`, preserving the local stage2 invariant already used for other lowering
maps. Evidence: `crystal build src/adamas.cr -o /tmp/cv2_scope_cache_nested
--error-trace`; `p2_class_method_nested_yield_block_param_no_prelude.sh`,
`p2_loop_block_proc_capture_no_prelude.sh`,
`p2_bootstrap_semantic_emit_oracle.sh`, and `p2_pending_budget_no_prelude.sh`
all pass with `/tmp/cv2_scope_cache_nested`; canonical `s1 -> s2` still builds
`cv2_s2` in about 227s. Boundary: generated `cv2_s2` smoke still fails, but
LLDB now stops later in `Crystal::MIR::LLVMIRGenerator#value_ref(UInt32)` from
`emit_extern_call`, not in the old debug-cache `string_eq` path.

Class-method nested-yield block-param checkpoint (2026-04-29): the current
root after the loop-capture fix was not `Pointer#read` itself. `File.open`'s
lowered HIR already creates a concrete `File` and yields it, but the AST-level
`block_param_types_for_call -> infer_yield_param_types_from_body` path inferred
the callsite block using the caller's `@current_class` whenever the callee was
a class method with no instance receiver. For bodies shaped like
`File.open { open_internal { |file| yield file } }`, the nested
`open_internal` block-param inference therefore lost the callee owner context
and the outer user block proc kept `file` as `Pointer`. The fix uses the callee
owner recovered from the function name (`owner_override`) as `self_type_name`
before falling back to `@current_class`. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_yield_owner_fix --error-trace`,
the focused `File.open` HIR reducer now emits `%file : File` and
`File#read(Slice(UInt8))` both inline and in `__crystal_block_proc_0`,
`regression_tests/p2_class_method_nested_yield_block_param_no_prelude.sh
/tmp/cv2_yield_owner_fix` guards the no-prelude class-method nested-yield
shape, and canonical `s1 -> s2` still builds `cv2_s2` in about 230s. Generated
`cv2_s2.ll` now contains `__crystal_block_proc_720 -> File#read(Slice(UInt8))`,
not `Pointer#read`. New frontier: generated `cv2_s2` smoke no-prelude segfaults
after `lower_main: exprs=5`; LLDB shows `EXC_BAD_ACCESS` in
`__adamas_string_eq` called from
`Tuple(String, Int32)#== -> Hash(Tuple(String, Int32), UInt32)#fetch ->
HIRToMIRLowering#hir_innermost_scope_for_source_line ->
propagate_debug_local_bindings -> lower_function_body`. This is a debug-scope
hash/string equality crash, separate from the now-resolved `File.open` block
param precision bug.

Loop block-proc capture checkpoint (2026-04-29): generated stage2 still builds
successfully, and the previous `file_sha256` smoke abort no longer resolves
`file.read(buffer)` to the unrelated
`Hash(String, Array(Tuple(String, Crystal::MIR::Function)))#read(Slice(UInt8))`.
Two root invariants were missing. First, `collect_proc_body_ident_walk` and
`detect_written_captures_walk` did not traverse `LoopNode` and several related
control-flow/container nodes, so a block body shaped as `loop do ... end` could
report `refs=` / `captures=` even when it read and wrote outer locals such as
`buffer` and `hash`. Second, `lower_block_to_block_id` defaulted untyped block
params from `VOID` to `POINTER`, but `lower_block_to_proc` kept the same
untyped param as `VOID`, so a standalone block proc could erase its runtime
receiver parameter even though the inline block view had a pointer-shaped
param. The fix expands the capture walkers and keeps standalone block-proc
param defaulting in parity with inline block lowering. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_loop_capture_walk3 --error-trace`,
`regression_tests/p2_loop_block_proc_capture_no_prelude.sh
/tmp/cv2_loop_capture_walk3`,
`regression_tests/p2_abstract_getter_vdispatch_no_prelude.sh
/tmp/cv2_loop_capture_walk3`,
`regression_tests/p2_bootstrap_semantic_emit_oracle.sh
/tmp/cv2_loop_capture_walk3`, and canonical `s1 -> s2` building `cv2_s2` in
about 215s under the 300s/4GB gate. New frontier: generated `cv2_s2`
no-prelude smoke aborts at `STUB CALLED: Pointer$Hread$$Slice$LUInt8$R` from
`__crystal_block_proc_720 -> File.open -> CLI#file_sha256`; this is now a more
precise block parameter type problem (the proc param is pointer-shaped, but not
yet resolved to the concrete `File`/`IO::FileDescriptor` read implementation).

Abstract generated-getter vdispatch checkpoint (2026-04-29): generated stage2
still builds successfully, and the previous smoke abort at
`STUB CALLED: Adamas$CCCompiler$CCFrontend$CCNode$Hspan` is resolved. The
root was not `Node#span` itself: concrete getter/property accessors such as
`LiteralNode#span` are registered in `@function_types` but have no `DefNode`
until generated on demand. `lower_function_if_needed_impl` previously ran
inherited lookup first, so an exact concrete request could resolve back to the
abstract parent `Node#span`, leaving `maybe_generate_accessor_for_name` no
chance to materialize the concrete accessor. The fix preempts inherited lookup
only for registered generated-accessor requests with no `DefNode`, then emits
the real concrete getter body. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_abstract_getter_fix --error-trace`,
`regression_tests/p2_abstract_getter_vdispatch_no_prelude.sh
/tmp/cv2_abstract_getter_fix`,
`regression_tests/abstract_class_method_dispatch_synth.sh
/tmp/cv2_abstract_getter_fix`, `regression_tests/complex/test_vdispatch_struct_return.cr`
compiled and run through `scripts/run_safe.sh`, the fast p2 bootstrap semantic
oracles, and canonical `s1 -> s2` building `cv2_s2` under the 300s/4GB gate.
New frontier: generated `cv2_s2` smoke no-prelude now reaches LLVM emission
and aborts later at
`STUB CALLED: Hash$LString$C$_Array$LTuple$LString$C$_Crystal$CCMIR$CCFunction$R$R$R$Hread$$Slice$LUInt8$R`
from `Adamas::Compiler::CLI#file_sha256 -> compile_llvm_ir`.

Call-argument known-emitted-type checkpoint (2026-04-29): generated stage2
now builds successfully. The immediate `llc` frontier after the return-type
force-lower fix was an invalid call-argument adaptation:
`%eq_ptr_to_fp.* = ptrtoint ptr %r685 to i64` even though `%r685` had already
been emitted as `double`. The root was that the call formatter trusted an old
`find_def_inst(a).type == ptr` hint after `value_ref(a)` had produced an SSA
value with a newer `@emitted_value_types` entry. The fix preserves the packed
scalar decode path, but only when the known emitted SSA type is actually `ptr`
or when there is no emitted-type fact and the older definition type is still
the only available evidence. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_arg_fp_known_type --error-trace`, fast p1/p2 guards, and canonical
`BOOTSTRAP_CHAIN_STAGES=2 ... scripts/build_bootstrap_stages.sh --stages 2`
all passed through the previous LLVM verifier/llc error. The new current
frontier after this checkpoint was generated `s2` smoke aborting immediately
in parser setup with `STUB CALLED: Adamas$CCCompiler$CCFrontend$CCNode$Hspan`;
that follow-up is resolved by the abstract generated-getter vdispatch
checkpoint above.

Return-type force-lower checkpoint (2026-04-29): call lowering now force-lowers
pending call targets only when the current return type is still `VOID`, a
union that needs exact variant shape, or an unresolved generic placeholder. The
root was that `lower_call` / `lower_member_access` refreshed every pending
target before freezing the call instruction type, even when the call already
had a concrete non-union return type. During self-hosting that bypassed lazy
RTA and recursively materialized thousands of concrete helper bodies from
`force_pending_call_targets_for_return_type`. A too-aggressive first guard
skipped union returns as well and broke the stage1 full-prelude `puts 42` smoke
in `Crystal::System::Dir.current` (`File.info?` union PHI mismatch), so unions
remain force-refreshed. Evidence: full-source `STOP_AFTER_HIR` now reports
`process_pending: 316 -> 588 (+272)` and exits in about 137s instead of the
previous `process_pending +14225` / about 234s; canonical `s1 -> s2` no longer
times out and reached `llc` after about 166s. Boundary: `lower_missing` still
materializes about 35k functions; the resulting `ptrtoint`/`double` LLVM
frontier is resolved by the call-argument known-emitted-type checkpoint above.

Nested generic namespace checkpoint (2026-04-29): method/overload lookup now
strips generic arguments per namespace segment instead of truncating the owner
at the first `(`. The root was that owners like
`Indexable(T)::ItemIterator(Array(String), String)` were normalized to
`Indexable`, so `ItemIterator#each` could reuse `Indexable#each` and generate
bogus demand such as `ItemIterator(ItemIterator(...)).new`. Constructor
inference for generic classes under generic namespaces now resolves template
bases such as `Indexable::IndexIterator` and specializes `.new(self)` from the
receiver argument. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_method_index_path3 --error-trace`,
`p2_nested_generic_new_inference.sh`, the fast p2 no-prelude guards, and
`p1_ir_shape_check.sh` passed; full-source `STOP_AFTER_HIR` exits 0 after
about 234s. Boundary: this is a correctness/root fix, not the final demand
pruning fix. The full-source sweep still reports
`lower_missing: 17423 -> 50628 (+33205)`, dominated by concrete-call demand
families (`IO#<<`, `Hash/Array/Indexable`, `Proc#call`, formatting helpers).
Next root remains shrinking `lower_missing.initial` without heuristic depth
limits.

Backend-intrinsic / vdispatch compaction checkpoint (2026-04-29): generated
stage2 now reaches the full-source `STOP_AFTER_HIR` gate with the current
compiler-built `s1`, and backend-owned helper calls no longer masquerade as
missing HIR source demand. The root boundary is that HIR emits some helper
operations as normal `Call` instructions (`__adamas_string_eq`,
`__adamas_hash_get_entry_ptr`, `__adamas_hash_entry_deleted`,
`__adamas_select_ptr`), but MIR/LLVM owns their implementation through
`extern_call` emission / runtime helper definitions. `lower_missing_call_targets`,
`remember_callsite_arg_types`, and `lower_function_if_needed_impl` now skip
that exact allowlist instead of recording them as source-level callees. A fast
no-prelude guard keeps the calls visible in HIR while rejecting their appearance
in missing-target logs. The same checkpoint compacts class vdispatch wrappers
by sharing identical inherited implementation blocks across many runtime type
IDs; union dispatch and dispatch-class-specialized cases remain unshared. It
also explicitly initializes closure by-reference state in `AstToHir#initialize`
because generated stage2 can still miss inline-default ivar initialization for
those sets. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_intrinsic_boundary_check --error-trace`,
`p2_backend_intrinsic_boundary_no_prelude.sh`, `p2_pending_budget_no_prelude.sh`,
`p2_bootstrap_semantic_emit_oracle.sh`, `p2_each_index_block_param_no_prelude.sh`,
and fresh generated `s1` `STOP_AFTER_HIR` full-source run all passed; the
missing summary no longer contains the backend-owned intrinsic names. Boundary:
canonical `s1 -> s2` still times out at 300s after `[ALLOC_FLUSH] Generated 98
deferred allocators`, producing only a partial `cv2_s2.ll` (~3.7MB in this run).
Follow-up phase splitting shows the visible timeout is downstream of HIR volume,
not allocator flush itself: full-source `STOP_AFTER_HIR` with
`ADAMAS_PHASE_STATS=1` reports `lower_missing.initial: 17836 -> 43126
(+25290) in 144271.9ms`, while stale-call repair, receiver repair, deferred
allocators, and final fixed-point missing together add only about 400 functions
and about 11s. `ADAMAS_STOP_AFTER_MIR=1` still times out at 300s while
lowering `Body 20001/35221`, so the next root is the concrete-call demand
volume created by the initial missing-target sweep; MIR/allocator symptoms are
secondary until that reachable HIR set shrinks.

Macro diagnostic JSON checkpoint (2026-04-29): one confirmed supply leak was
`src/compiler/semantic/macro_expander.cr` importing `json` only for env-gated
macro-body diagnostics and using `Hash#to_json` inside diagnostic branches. HIR
lowers whole method bodies, so the runtime-disabled branches still pulled
generic `Array/Hash/Set#to_json` and `JSON::Builder` into the compiler's own
demand graph. The fix removes the `json` require from `MacroExpander` and uses
a scalar-only `MacroDiagJson` JSONL writer. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_macro_json_free --error-trace`,
`p2_pending_budget_no_prelude.sh` -> `total=40 lower_missing_delta=0`,
`p2_bootstrap_semantic_emit_oracle.sh`,
`p2_backend_intrinsic_boundary_no_prelude.sh`, and
`p2_each_index_block_param_no_prelude.sh` all passed. Full-source
`STOP_AFTER_HIR` improves modestly (`42859` functions, exit ~201s), and the
fresh missing summary no longer shows `JSON::Builder`/generic `to_json` in the
top suppliers. Boundary: this is a real root fix for diagnostic JSON demand,
not the final `lower_missing.initial` fix; the next supplier is now dominated
by virtual/abstract calls such as `IO#<<`, `Proc#call`, hash key helpers, and
formatting/object-id corridors.

Static truthiness checkpoint (2026-04-29): HIR branch lowering now prunes
branch bodies whose condition has already lowered to a constant truthiness
value, including RHS branches of short-circuit conditions. The root was that
`responds_to?` can lower to a Bool literal after expression lowering while
`lower_if` still materialized both pre-created body blocks; dead calls such as
`Int32#object_id` then entered `lower_missing_call_targets` as concrete source
demand. The fix preserves condition side effects, converts constant condition
branches to jumps, and for no-`elsif` `if` expressions lowers only the CFG
reachable body after condition lowering. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_static_truthy_if --error-trace`,
`p2_static_truthy_dead_branch_no_prelude.sh`, `p2_pending_budget_no_prelude.sh`,
`p2_bootstrap_semantic_emit_oracle.sh`, `p2_backend_intrinsic_boundary_no_prelude.sh`,
`p2_each_index_block_param_no_prelude.sh`, and `p1_ir_shape_check.sh` passed.
Full-source `STOP_AFTER_HIR` remains green and improves only modestly
(`lower_missing: 17404 -> 42732 (+25328)`), so this is a real root fix for
static dead-branch demand but not the final Hash/object-id corridor fix. The
next frontier is the remaining `Hash#entry_matches?` / union call-shape demand
that still produces value-type `object_id` missing targets.

Object-id responds_to checkpoint (2026-04-29): `responds_to?(:object_id)` now
uses the Crystal ownership rule for `object_id` (Reference and descendants)
instead of trusting the mutable function registry. The root was circular
pollution: once a bogus value-type `UInt32#object_id` / `Tuple#object_id`
specialization had been admitted anywhere in the run, later `responds_to?`
queries could see that synthetic function base and lower to `true`. The fix
answers the `object_id` predicate from the class parent chain and keeps value
types (`UInt32`, `Tuple`, `Int32`, etc.) false while preserving reference types
such as `String`. Evidence: `p2_object_id_responds_to_semantics.sh`, the same
fast p2 guards, `p1_ir_shape_check.sh`, and full-source `STOP_AFTER_HIR` all
passed. Boundary: this removes value-type `object_id` from the top missing
summary but does not materially shrink `lower_missing` (`+25329`), so the next
bootstrap root is still the broader initial missing-target demand volume
(`Indexable#new`, `Proc#call`, value initializers, debug helpers).

Macro control checkpoint (2026-04-29): full-prelude Kqueue HIR no longer
registers both sides of the Darwin `LibC.has_constant?(:EVFILT_USER)` macro
inside `Crystal::EventLoop::Kqueue#after_fork`. The root was registration
ordering for module macro literals: `process_macro_literal_in_module` stripped
`{% if %}` / `{% else %}` control lines before `expand_flag_macro_text` could
choose a platform branch, so the fallback pipe body was parsed and registered
with the EVFILT_USER body. The fix expands platform macro controls before
stripping in the raw-text and per-text module literal paths, keeps the class
literal path on the centralized `register_class_members_from_expansion`
walker, and synchronizes semantic/HIR platform `LibC.has_constant?` fallbacks
for the currently modeled constants. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_macro_control_check --error-trace`,
`regression_tests/p2_macro_control_module_literal_guard.sh
/tmp/cv2_macro_control_check`, `p2_bootstrap_semantic_emit_oracle.sh`, and
`p2_pending_budget_no_prelude.sh` passed; the generated-stage2 no-prelude
guard remains at `frontier=nocodegen_clean_full_codegen_hang`. The new guard extracts
`Kqueue#after_fork` HIR and requires `LibC.@@EVFILT_USER` while rejecting
`Crystal::System::FileDescriptor.system_pipe` / `LibC.@@EVFILT_READ` inside
that function.

Shape-oracle maintenance checkpoint (2026-04-29):
`p2_selfhost_stage2_shape_guard.sh` is green again after making two historical
callback-shape sentinels demand-aware. `Array(String)#each_index` and
`Dir.glob(..._block_splat)` are still checked when their nested proc wrappers
are materialized, but their absence is no longer a failure because recent
demand/RTA and macro-control fixes removed the old incidental materialization
paths. The `each_index` root invariant now has a direct fast no-prelude guard:
`p2_each_index_block_param_no_prelude.sh` forces `["x"].each_index { |i| i }`
and requires an Int32-shaped block proc in HIR. Evidence:
`p2_each_index_block_param_no_prelude.sh /tmp/cv2_shape_guard_check` and
`p2_selfhost_stage2_shape_guard.sh /tmp/cv2_shape_guard_check` passed.

Getter/proc-shape checkpoint (2026-04-29): `of -> Nil` type annotations now
stringify as `Proc(Void)` so registration-time inference for
`Process.after_fork_child_callbacks` does not seed `Array(String)` and later
lower `String#call`. Generic container canonicalization preserves full
`Proc(...)` parameter shapes, and array element typing prefers the value's own
Array descriptor when the lowering context map is stale. Getter field inlining
is now proof-based: only a source method whose body is the trivial `@ivar`
getter can inline as `FieldGet`; methods sharing an ivar name but having side
effects (for example `Function#next_value_id`) stay as calls. The getter proof
also treats out-of-arena body ExprIds as "not proven getter" instead of raising.
Evidence: `crystal build src/adamas.cr -o /tmp/cv2_safe_commit
--error-trace`, `p2_bootstrap_semantic_emit_oracle.sh`,
`p2_pending_budget_no_prelude.sh`, and
`p2_generated_stage2_no_prelude_puts_guard.sh` all passed. The generated-stage2
guard now fails closed on any unrecorded `STUB CALLED` before accepting the
current full-codegen frontier.

Cross-block slot checkpoint (2026-04-29): generated stage2 no longer emits
malformed empty-slot LLVM for the no-prelude `puts 7` smoke. The root was the
LLVM backend consuming `@cross_block_slots` via `hash[key]?` inside an
assignment-in-condition; generated stage2 could enter the branch for a missing
slot and bind an empty local string, producing `store ptr null, ptr %`. The
backend now gates slot consumption by `has_key?` before indexing. Falsifier:
an attempted `Hash#clear` real-function override made generated `Hash#clear`
bodies layout-safe but did not remove the malformed `%`, so stale Hash storage
was not the root. Evidence: `crystal build src/adamas.cr -o
/tmp/cv2_slot_haskey_only --error-trace`,
`p2_bootstrap_semantic_emit_oracle.sh`, `p2_pending_budget_no_prelude.sh`,
`bash -n regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh`,
`git diff --check`, and
`p2_generated_stage2_no_prelude_puts_guard.sh /tmp/cv2_slot_haskey_only` ->
`frontier=extern_puts_arg_type_codegen_gap`. The next root is extern-call
argument typing in generated stage2: the emitted IR calls
`__adamas_print_int32_ln(ptr null)` instead of `i32 7`.

Extern arg type checkpoint (2026-04-29): generated stage2 now emits a single
no-prelude `puts 7` extern call with the correct scalar ABI shape:
`call void @__adamas_print_int32_ln(i32 7)`. The root had two backend
pieces. MIR block ordering used `Set(HIR::BlockId)`; generated stage2
mis-deduped a one-block function and lowered the entry block twice, so the
ordering pass now uses a small linear visited list. LLVM extern-call argument
typing then read `@value_types[arg_id]?` with a pointer fallback; generated
stage2 could miss the present Int32 entry and print `ptr 7`, so extern-call
arg typing and called-function signature tracking now gate by `has_key?` before
indexing. The same key-presence invariant was applied to `value_ref` lookups
for constants, cross-block slots, and emitted value names. Evidence:
`crystal build src/adamas.cr -o /tmp/cv2_extern_arg_type_fix --error-trace`,
`git diff --check`, `bash -n
regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh`,
`p2_generated_stage2_no_prelude_puts_guard.sh /tmp/cv2_extern_arg_type_fix` ->
`frontier=nocodegen_clean_full_codegen_hang`, raw IR inspection of the kept
tmp artifact shows `i32 7`, and the fast p2 semantic/pending oracles pass. The
next root is no longer no-prelude extern-call ABI; it is the full-codegen-only
frontier where `--no-codegen` exits cleanly but the full path does not produce
the executable.

Observed but not landed (2026-04-29): `SystemError#included` expands to a
`BeginNode` containing `extend ::SystemError::ClassMethods`; processing that
`BeginNode` would expose the right root for `RuntimeError.from_errno` stubs, but
the naive recursive expansion branch currently reintroduces a long stage2
`lower_main` timeout. Revisit as a separate CAUTION change with a no-prelude
oracle before landing.

Dirty review note (2026-04-28): the in-progress `Union(*T)` / `StaticArray`
annotation substitution fix is currently verified only for the narrow
`Tuple(Char)#to_static_array` null-buffer corridor. Hostile adversary repros
with real multi-element and nested tuples (`{1, 'a', true}.to_static_array`,
`{{1, 'b'}, 2}.to_static_array`) no longer hit the original null allocation
shape, but still expose a separate StaticArray-of-Union load/unwrap boundary:
direct equality prints false and explicit `as(Int32)` returns the union
type-id-like value (`5`) instead of the payload. Do not claim full
`Tuple#to_static_array` correctness until StaticArray(Union(...), N)
store/load plus union unwrap semantics are covered by a run-safe regression.

Hostile review note (2026-04-28): packed splat call-site types must be consumed
by `lower_def` before named/default parameters after `*args` are assigned.
Otherwise a signature like `buffered(message, *args, exception = nil)` can type
`exception` as the packed splat tuple and supply-drive bogus
`Tuple/Array#inspect_with_backtrace` targets. Covered by
`regression_tests/named_arg_after_splat_type_alignment.sh`.

Dead nil branch checkpoint (2026-04-28): wrappers with `exception = nil` used
to emit dead `Nil#inspect_with_backtrace` in unreachable `if exception`
branches because `lower_if` only learned the constant false condition after
lowering the condition to a Bool literal, after both branches had already been
lowered. `static_nil_condition_value` now treats a bare local whose current HIR
type is exactly `Nil` as statically false. Covered by
`regression_tests/dead_nil_branch_after_splat_repro.sh`. This is a correctness
and demand-source fix, but not the main `lower_missing` growth fix.

RTA root virtual replay checkpoint (2026-04-28): method-part RTA now requires a
live owner to declare or inherit the called instance method before replaying a
virtual target to that owner. This preserves `Exception` subclass overrides for
root-typed calls such as `exception : Object; exception.inspect_with_backtrace`,
but avoids materializing unrelated live owners that cannot answer the method.
Covered by `regression_tests/rta_root_virtual_method_replay_guard.sh`.

Direct `s1 -> s2` previously produced a stage2 compiler in the focused gate:

```bash
crystal build src/adamas.cr -o /tmp/cv2_hir_emit_stop --error-trace
ADAMAS_PHASE_STATS=1 \
  scripts/run_safe.sh /tmp/cv2_hir_emit_stop 300 4096 \
    src/adamas.cr -o /tmp/cv2_s2_hir_emit_stop
```

Verified signal: `[EXIT: 0] after ~265s`, produced `/tmp/cv2_s2_hir_emit_stop`.

Current canonical wrapper checkpoint (2026-04-28): `scripts/build_bootstrap_stages.sh`
needed a Bash 3.2 / `set -u` fix for empty `CHAIN_ARGS`; after that fix the
wrapper reaches the real stage2 build. With `--stages 2`, 300s, and 4096MB,
stage1 builds and both smokes pass, but stage2 times out after writing a 189MB
`cv2_s2.ll` (3,930,328 lines, 39,112 LLVM `define`s, 338 stub markers) and
after `[ALLOC_FLUSH] Generated 98 deferred allocators`. Treat the old direct
success as stale for the canonical bootstrap gate until the IR over-materialized
helper graph is reduced.

AST demand-filter checkpoint (2026-04-28): the default AST reachability path is
still conservative/all-defs unless `ADAMAS_AST_FILTER_DEMAND=1` is set.
The opt-in demand scanner now walks packed `main_exprs`, builds a method-name
worklist, gates candidate owners by constructed/always-reachable types, and
feeds the existing AST filter. It is a diagnostic scaffold, not the default
bootstrap fix. Evidence on a full `src/adamas.cr` `STOP_AFTER_HIR` run:
`process_pending` drops from `+14371` to `+4148`, but `lower_missing` grows
from `+25702` to `+35210`, leaving total HIR functions nearly unchanged
(`43471` -> `43091`). `DEBUG_MISSING_SUMMARY=1` shows the compensating demand
comes from concrete calls already emitted into HIR (`IO#<<`,
`__adamas_string_eq`, `Array#root_buffer`, `Hash` internals,
`JSON::Builder`, and `Hash::Entry#inspect/to_s`). Next root work is therefore
to prevent dead/unneeded serialization/formatting/hash bodies from entering HIR
before `lower_missing`, not to filter concrete missing calls blindly. Guard:
`regression_tests/p2_ast_filter_demand_no_prelude.sh`.

LLVM reachability checkpoint (2026-04-28): backend function reachability is now
available only under `ADAMAS_LLVM_REACHABILITY=1`; the default remains the
previous emit-all behavior. On the full compiler, opt-in backend RTA prunes
`9959` MIR functions (`37792` total -> `27833` emitted) and reduces the
progress-run `.ll` artifact from the previous `189MB` shape to `146MB`, but
the 300s gate still times out later in LLVM finalization/undefined-extern
declaration emission. This is a useful lever, not a complete bootstrap fix.
Guard: `regression_tests/p2_llvm_reachability_no_prelude.sh`.

Fast stage2 HIR emit also passes:

```bash
regression_tests/p2_selfhost_hir_emit_no_prelude.sh /tmp/cv2_s2_hir_emit_stop
```

Verified signal: `p2_selfhost_hir_emit_no_prelude_ok`.

The full wrapper gate now reaches the generated stage2 compiler, then stops on
the generated-compiler smoke:

```bash
BOOTSTRAP_STAGE_OUT=/tmp/cv2_bs_s2 \
BOOTSTRAP_CHAIN_STAGES=2 \
BOOTSTRAP_TIMEOUT_SEC=300 \
BOOTSTRAP_MEM_MB=4096 \
  scripts/build_bootstrap_stages.sh --stages 2 --out /tmp/cv2_bs_s2
```

Current signal after the latest generated-stage2 guard pass: stage1 build and
generated `s2b` build still pass, and the generated-stage2 no-prelude `puts 7`
guard now moves past the old `IO::FileDescriptor#system_pos`,
`Crystal::System::Kqueue.set`, and `File#file_descriptor_close` recursion
frontiers. The accepted guard signal is:

```bash
regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh /tmp/cv2_inherited_owner
```

Verified signal: `p2_generated_stage2_no_prelude_puts_guard_ok
frontier=nocodegen_clean_full_codegen_hang` after `f8313232` cleared the
prior `eventloop_after_fork_rta_gap`. Root cause was not the abstract-base
RTA discovery itself — Polling/Kqueue#after_fork were correctly recorded
in `@rta_called_method_parts` and pushed onto `@pending_function_queue`
by `undefer_rta_functions`. The bug was that
`force_lower_function_for_return_type` mutated the same queue via
`Array#delete(name)` while `process_pending_lower_functions` was iterating
it by index; the delete shifted later entries down, skipping the
undefer-pushed virtual subtypes past the loop's current `idx`. Fix:
drop the queue mutation; existing `has_function_with_body?` /
`function_state.completed?` guards make stale entries safe. The next
recorded frontier is the `--no-codegen` clean exit while full-codegen
still hangs in `Crystal::RWLock#write_lock` reached from `Process.fork`,
tracked separately.

The previous `String contains null byte` frontier was resolved as a div/rem
signedness bug in `llvm_backend`, not a `String#byte_index(0)` search bug.
`CLI` builds `pipeline_hash_str = pipeline_hash.to_s(16)` from a `UInt64` FNV
hash; `Int#to_s(base)` calls `num.remainder(base).abs`; the backend selected
`srem` because it OR-ed operand signedness, which turns high-bit unsigned
values into negative remainders and corrupts hex digits into bytes containing
`0x00`. The fix matches original Crystal `primitives.cr:149`
(`t1.signed? ? srem : urem`): div/rem signedness now follows the dividend
only. See LM-499 and `regression_tests/p2_u64_to_s_base16_no_null.sh`.

The `check_index_out_of_bounds` ABORT-stub frontier was then cleared by
LM-500 as a lazy-RTA allowlist gap, not a virtual-dispatch or receiver-set
bug. `Indexable#fetch(index : Int, &)` calls the private helper
`check_index_out_of_bounds`, which is never virtually dispatched, so its
method-part carries no concrete receiver in `@rta_virtual_receivers` and
`rta_method_part_matches_owner?` returns false for every live container.
The existing allowlist mechanism
(`internal_container_helper_exact_demand?` /
`internal_container_helper_name_exact_demand?` in `ast_to_hir.cr`) already
carries peers like `unsafe_fetch`, `fetch`, and `increase_capacity`; the fix
adds `check_index_out_of_bounds` to the `Array`, `Slice`, and `Deque` arms
in both functions. Evidence: `generated_s2.ll` now has 78 real
`check_index_out_of_bounds` definitions with 0 `abort_stub` lines; the
nocodegen probe exits clean; zero regression suite delta. See LM-500.

The `Crystal::RWLock#write_lock` corridor noted on LM-499 was then narrowed
to a two-layer root by LM-501. Inline lowering of `Atomic#set` / `Atomic#swap`
in `hir_to_mir.cr` was reading `args[2]` as the stored value, but the Crystal
signature is `swap(value : T, ordering = :seq_cst)`, so `args[2]` is the
`AtomicOrdering` enum and `args[1]` is the value. The writer-lock path
therefore stored `AtomicOrdering::Acquire = 4` into `@writer` instead of
`LOCKED = 1`. The fix pins both inlined ops to `args[1]`; fresh
`write_lock` disassembly now emits `ldr w9, [Crystal$CCRWLock__classvar__LOCKED]`
instead of `mov w9, #0x4`. The puts-guard now carries a positive-shape
regression check for both invariants. See LM-501.

LM-502 then closed the `Process.@@rwlock = null` corridor. The four
class-body / macro-expansion iteration loops in `ast_to_hir.cr` recognised
`when AssignNode` but only registered `ConstantNode` targets; the
Darwin-only `@@rwlock = Crystal::RWLock.new` lives under a `{% else %}`
branch with a `ClassVarNode` target, so it never reached
`@deferred_classvar_inits` and no `__classvar_init__` function was emitted.
A new helper `register_class_assign_from_expansion` now records both
`ConstantNode` and `ClassVarNode` AssignNode targets at all four sites; the
deepest macro-literal inner loop is left untouched (an exploratory addition
there flipped `String::Formatter::HAS_RYU_PRINTF` macro branches and stubbed
`current_char`). Lazy classvar count goes from 20 to 21; fork-test IR now
contains a real `__classvar_init__Crystal$$CCSystem$$CCProcess__rwlock`
calling `Crystal$CCRWLock$Dnew()`. The next generated-stage frontier is the
post-fork child hang in `Crystal::System::Signal.after_fork`'s
`@@pipe.each` block (sample shows `Signal.after_fork + 68`). See LM-502.

Current diagnosis / recently fixed roots:

- Generated-stage2 no-prelude `puts 7` moved through three backend/runtime
  helper frontiers in one root-fix cluster. Same-owner system and class helper
  calls are now recorded as exact RTA demand, so concrete helpers such as
  `IO::FileDescriptor#system_pos` and stage2 class helpers are materialized
  instead of synthesized as abort stubs. Overload matching now treats raw
  `Pointer` values as compatible with typed `Pointer(T)` parameters, which
  lets generated stage2 select the real
  `Crystal::System::Kqueue.set(Pointer(LibC::Kevent), Int32, Pointer(LibC::Kevent), Int32, Timespec*)`
  helper instead of falling through to a stub. The later bus-error frontier
  was an inherited-wrapper root cause: `File#file_descriptor_close` was
  materialized by lowering the ancestor `IO::FileDescriptor` body under
  `@current_class = File`, so implicit calls inside the ancestor body resolved
  back to the child wrapper and recursed. The fix preserves requested wrapper
  owner only for value/primitive/generic specialization cases; normal
  reference-class inherited wrappers lower the resolved ancestor body while
  still materializing the requested symbol for dispatch. HIR evidence after the
  fix: `File#file_descriptor_close` calls
  `IO::FileDescriptor#file_descriptor_close$block`, not itself. Guard evidence:
  `p2_generated_stage2_no_prelude_puts_guard.sh /tmp/cv2_inherited_owner` ->
  `frontier=string_null_byte`. `IO#pos` is now accepted as a valid runtime
  dispatch-helper shape for `IO::FileDescriptor#tell`; reject only aborting
  `tell`/`pos` stubs, not this dispatch helper. The self-host shape guard no
  longer requires a tuple allocation inside `Dir.glob(...block_splat)` because
  the current correct HIR forwards directly to the `Enumerable` overload; it
  now checks the real invariant instead: the forwarding block proc remains
  `String`-shaped and the old `_block_splat` / `String#each$block` regressions
  remain absent.
- Bare receiverless `puts/print/p/pp` no longer fall through the late
  `Object#...` implicit-receiver fallback in `AstToHir#lower_call`. That
  fallback was missing the same builtin exemption already present in the
  earlier self-resolution branches, so fresh generated `s2b` no-prelude
  compiles could drift into receiver-call resolution and die in the helper
  tuple-iteration corridor (`Tuple$Heach$$block`) before the direct runtime
  print fallback had a chance to run. Evidence:
  `regression_tests/stage2_no_prelude_puts_runtime_repro.sh /tmp/cv2_puts_receiverfix`
  -> `not reproduced`;
  `regression_tests/p2_generated_stage2_no_prelude_interp.sh /tmp/cv2_puts_receiverfix`
  -> `p2_generated_stage2_no_prelude_interp_ok`;
  `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh /tmp/cv2_owned_return_fix3`
  -> `p2_generated_stage2_no_prelude_puts_guard_ok frontier=io_filedescriptor_tell`.
  The old generated-stage2 no-prelude `Tuple$Heach$$block` frontier is removed;
  the old synthetic-main MIR blockers (`Missing hash key: __crystal_main` and
  `MIR function stub not found for: __crystal_main`) are removed. Generated
  `s2b` used to reach `STUB CALLED: IO::FileDescriptor#tell`.
- Inherited instance-method materialization now lowers child wrappers as real
  bodies instead of short-circuiting on an already-lowered ancestor target.
  That root-fix removes the generated-stage2 `IO::FileDescriptor#tell` abort
  stub corridor without any LLVM hardcode: plain `File.open { |f| f.tell }`
  HIR now contains only `IO#tell`, `lldb --batch -o 'disassemble -n
  IO$CCFileDescriptor$Htell' /tmp/cv2_tell_fix_s2` shows a real delegate body
  calling `IO$CCFileDescriptor$Hpos`, and
  `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
  /tmp/cv2_puts_fix2` now confirms two invariants together: `tell` still
  delegates to `IO::FileDescriptor#pos`, and nilary
  `IO::FileDescriptor#puts` no longer reuses the `puts(String)` body.
  Full self-host MIR emitted by `/tmp/cv2_puts_fix2` now contains
  `func @IO::FileDescriptor#puts(%0: Type#204) -> Nil` with `print(Char '\n')`
  while `func @IO::FileDescriptor#puts$String` stays separate. The old
  generated-stage2 `String#bytesize` crash from newline handling is gone.
  The next generated no-prelude blocker then moved to the HIR/codegen boundary:
  `Array(String)#each$block` materialized its nested `each_index` callback as
  `String ->` because fallback block-param inference treated `each_index` like
  element-yielding `each`. The fix teaches `fallback_block_param_types` that
  `each_index` yields `Int32`; fresh self-host HIR now contains
  `func @__crystal_block_proc_291(%2: 4)` and calls
  `Array(String)#unsafe_fetch$Int32`, not `unsafe_fetch` with a String-shaped
  callback argument. `regression_tests/p2_selfhost_stage2_shape_guard.sh
  /tmp/cv2_emitblock_fix` now checks the `Array(String)#each_index` callback
  shape, and `regression_tests/p2_generated_stage2_no_prelude_puts_guard.sh
  /tmp/cv2_emitblock_fix` reports
  `frontier=hash_each_entry_with_index_null_block`. The next root was a
  two-part HIR/backend issue in
  `Crystal::MIR::LLVMIRGenerator#emit_missing_crystal_function_stubs`: the
  late pass re-walked a temporary `Hash` via `each`/`each_key`, which lowered
  through `Hash#each_entry_with_index` and exposed the still-open nested raw
  block callback ABI; switching that pass to an `Array` snapshot removes the
  artificial Hash iterator. The snapshot must stay flat (`name, return_type,
  arg_count, arg_types`) because nested tuple elements in generated-stage2
  currently still expose aggregate layout bugs. Separately,
  `block_param_types_for_call` did not normalize compiler collection aliases
  such as `Crystal::MIR::Array(T)` before element inference, so
  `Array(T)#each` blocks could be emitted as `Void ->`; the fix reuses
  `normalize_compiler_collection_owner_name` for element/hash block-param
  inference. Fresh self-host HIR now gives the late-emission Array block a
  real `Tuple(String, String, Int32, Crystal::MIR::Array(String))`-shaped
  parameter, not `Void`, and the generated no-prelude `puts 7` frontier moves
  to `STUB CALLED: IO$CCFileDescriptor$Hsystem_pos`.
  The late-emission snapshot must avoid introducing artificial nested tuple
  layouts as a workaround, but nested tuple/aggregate block parameters are a
  real language/runtime invariant: add a separate no-prelude oracle for
  blocks yielding nested tuples/arrays and verify HIR/MIR/LL layout parity
  instead of treating flattening as a general solution. Do not assume only
  shallow tuple payloads: real block-yield values may contain arbitrarily
  nested tuples/arrays/hashes, so the eventual fix must preserve aggregate
  layout recursively instead of special-casing the current flat snapshot.
- Stage2 shape guard now protects four self-host codegen roots in one MIR
  gate (`regression_tests/p2_selfhost_stage2_shape_guard.sh`):
  - stale cache-only call return repair no longer rewrites
    `Slice(UInt8)#[]` from `UInt8` to stale container-shaped returns;
  - bare `return` in nilable functions now materializes a nil union value
    (`String#byte_index(Int32, Int32)` no longer emits bare MIR `ret`);
  - deferred runtime constants update `@constant_types` after real lowering
    (`CRYSTAL_SRC_PATH` now reads as `String`, not `VOID`, avoiding
    `Path | String` variant miswrap);
  - splat parameters are rebound to tuple locals in the method body, so
    `Dir.glob(*patterns, &block)` no longer self-recurses through its
    `_block_splat` wrapper.
  - nested inline-yield fallback no longer emits a call back to the currently
    lowered `_block_splat` wrapper. The fallback now resolves splat/block
    targets through the block-overload table and records the corrected call
    target without eagerly forcing the callee body.
  - scalar splat fallback targets now keep their `_block_splat` wrapper instead
    of being over-corrected to the `Enumerable` overload. This keeps
    `Dir.glob("pattern", &block)` from dispatching `String#each$block` inside
    `Dir.glob$Enumerable...`.
  - `SymbolCollector#@table_stack` is explicitly typed as
    `Array(SymbolTable)`, preventing V2 from widening it to
    `Array(SymbolTable) | Array(String)` and routing `current_table.lookup_macro`
    through `T#lookup_macro`.
  - trivial `NameResolver` zero-arg helpers are no longer required as generated
    compiler call targets; their bodies are inlined at source call sites, moving
    generated no-prelude smoke past the `current_owner_symbol` helper stub
    cluster.
  - `TypeInferenceEngine#guard_watchdog!` now bypasses deferred work-queue
    lowering as a leaf guard, so self-host HIR/MIR contains the helper body
    instead of leaving a concrete call target for LLVM to synthesize as an abort
    stub. A broad stale-Pending requeue was tested and rejected because it
    reopens the deep generic helper fan-out that lazy RTA intentionally prunes.
- Nilable query calls on concrete containers can now materialize inherited
  included-module implementations instead of falling back to the first fuzzy
  overload. This keeps `Array(Nil | Array(ExprId))#[]?$Int32` on the
  `Indexable#[]?` path instead of mis-targeting `#[]?$Range`.
- Semantic compiler cache key hashing no longer calls `.hash` on immediate
  primitive fields (`UInt64`, `Bool`) while self-hosting. The cache keys now
  combine object ids and booleans arithmetically, avoiding the generated
  stage2 `Object#hash` vdispatch corridor.
- `TypeInferenceEngine#primitive_metaclass?` no longer relies on flow narrowing
  across `type.is_a?(PrimitiveType) && type.name...`. It now explicitly casts to
  `PrimitiveType` before calling `#name`, so HIR emits
  `PrimitiveType#name -> String` followed by `String#ends_with?`, not stale
  `Hash(... )#ends_with?`.
- `Hash(String, Nil).new(block, initial_capacity:)` no longer resolves to the
  `default_value : V` overload. Generic overload matching now evaluates
  annotations in the requested concrete owner context, so `V` is `Nil` for
  `Hash(String, Nil)` instead of a wildcard.
- Explicit receiver block calls now keep the concrete generic receiver owner
  when searching block thunks. This removes late generic-module abort stubs such
  as `Indexable(T)#reverse_each$$block`; the self-host HIR trace now lowers
  concrete `Array(...)#reverse_each$block` targets instead.
- Default argument expansion now searches included module chains before final
  target canonicalization. This preserves `Enumerable#each_with_index(offset =
  0, &)` when reached through concrete Array/Slice owners, so zero-arg block
  calls become one-arg calls before block proc lowering.
- Direct LLVM small-Hash linear-scan overrides are disabled. They duplicated
  `Hash::Entry` layout knowledge in the backend and corrupted self-hosted
  `Hash(String, Nil)` / `Hash(String, T)` paths; normal HIR/MIR lowering now
  owns those method bodies.
- Exact-demand helper bodies invalidated by layout repair are requeued and can
  be processed again in the same pending pass. This removed late abort stubs for
  `Array(String)#increase_capacity` and `Array(Crystal::HIR::TypeRef)#to_unsafe`.
- HIR-only emit no longer depends on backend/runtime weak spots:
  - `--emit hir --no-link` stops after writing HIR when MIR/LLVM emit is not
    requested.
  - HIR pretty-printers avoid `Enumerable#join(io, ...)`, which pulled
    `IO::FileDescriptor#tell`.
  - CLI HIR output uses the same `LibC.open` / `LibC.close` pattern as LLVM
    output instead of `File.open` / `IO::FileDescriptor#system_close`.

Remaining risk:

- The current generated stage2 plain smoke times out in prelude loading after
  `prelude exists`. The current generated stage2 no-codegen no-prelude smoke
  times out after `STUB CALLED:
  Adamas::Compiler::Semantic::TypeInferenceEngine#guard_watchdog!`.
  Treat these as the next root-cause targets before any `s3b+` attempt.
- Stage2 still has a separate generic module block corridor around
  `Enumerable(T)#any?$$block`. A no-prelude function-definition HIR emit and a
  full `puts 42` smoke can still hang/abort there under the generated s2
  compiler. A broader implicit-self block receiver experiment was refuted
  because it caused an early `Index out of bounds` in self-host HIR lowering.
- `lower_missing` still grows HIR heavily during full self-compile
  (`17769 -> 43471`, `+25702`, in the latest focused STOP_AFTER_HIR gate). The
  STOP_AFTER_HIR gate exits 0 in ~209s, but the canonical full stage2 build
  still times out at 300s after emitting a 189MB `.ll`; this remains the main
  demand-driven cleanup target before `s2 -> s3`.
- Dominant families are broad fallback helpers on compiler-internal containers:
  `Array#to_s`, `Array#inspect`, `Array#exec_recursive`,
  `Array#object_id`, `Hash#to_s`, `Hash#inspect`,
  `Hash#exec_recursive`, and `Hash::Entry#to_s/#inspect`.
- Current source contexts:
  - `Object#to_s` enqueues `Array#to_s` / `Hash#to_s`
  - `Object#inspect` enqueues `Array#inspect` / `Hash#inspect`
  - `Reference#same?` enqueues `Array#object_id`
  - `Dir::Globber#glob` enqueues some `Hash#each`
- `DEBUG_RTA_KEEP_REASONS=1` shows the active `process_pending` frontier is
  dominated by `keep:exact_called`, not by owner/method-part fallback:
  `Array#to_s`, `Array#object_id`, `Hash#to_s`, `Hash#object_id`,
  `Hash::Entry#to_s`.
- `scripts/timeout_sample_lldb.sh` confirms the time is spent in HIR lowering /
  type-name lookup / string hashing, consistent with excessive admitted wrapper
  volume rather than a single tight runtime loop.

See `LANDMARKS.md` LM-463..LM-475 for detailed evidence and refutations.

## Refuted Fix Branches

Do not retry without new evidence:

- Broad `Object` / `Reference` virtual-target replay gating alone.
- `emit_all_tracked_signatures` universal-method pruning alone.
- Replay gating plus emit pruning combination.
- Defer/enqueue guard for universal helpers on deep generic owners.
- RTA replay-depth guard that prevents speculative replay enqueues from marking
  exact `@rta_called_methods`.
- `rta_method_part_matches_owner?` broad-root helper ancestor filter.
  - No movement on `p2_root_self_replay_no_prelude.sh`: `process_delta=20`,
    `object_replays=28`, `reference_replays=21` unchanged.
- Combined broad-root immediate-replay gate plus broad-root helper RTA filter.
  - Synthetic oracle reduced replay counts (`Object 28->16`, `Reference 21->16`)
    but not `process_delta` or `total`.
  - 120s `STOP_AFTER_HIR` diagnostic still timed out, with queue reaching `40k`
    and the same helper families (`Array#to_json`, `Array#inspect`,
    `Array#to_s`, `Array#exec_recursive`, `Array#hash`, `Hash#...`).
- Replacing `TypeInferenceEngine#guard_watchdog!` calls with direct
  `Frontend::Watchdog.check!` calls.
  - It removes the helper stub but duplicates watchdog lowering at every call
    site and fails the stage2 build envelope before producing `cv2_s2`.
- Changing `guard_watchdog!` visibility from private to public.
  - HIR still contains calls to `guard_watchdog!` but no function body; the
    missing-helper root is not method visibility.

Common lesson: name-family containment can remove individual symptoms but has
not yet removed the underlying broad fallback demand leak.

## Fast Oracles

Run before expensive bootstrap attempts:

```bash
regression_tests/p2_bootstrap_semantic_emit_oracle.sh bin/adamas
regression_tests/p2_selfhost_hir_emit_no_prelude.sh bin/adamas
regression_tests/p2_pending_budget_no_prelude.sh bin/adamas
regression_tests/p2_root_self_replay_no_prelude.sh bin/adamas
regression_tests/p2_universal_helper_fanout_no_prelude.sh bin/adamas
regression_tests/p2_selfhost_stage2_shape_guard.sh bin/adamas
regression_tests/p2_llvm_tail_stats_no_prelude.sh bin/adamas
regression_tests/p2_debug_filter_no_variadic_splat.sh
```

Expected current signals:

- `p2_bootstrap_semantic_emit_oracle_ok`
- `p2_selfhost_hir_emit_no_prelude_ok`
- `p2_pending_budget_no_prelude_ok ... total=103 max_queue=57`
- `p2_root_self_replay_no_prelude_ok process_delta=20 total=47 ...`
- `p2_universal_helper_fanout_no_prelude_ok deep_helpers=0`
- `p2_selfhost_stage2_shape_guard_ok`
- `p2_llvm_tail_stats_no_prelude_ok phase=type_name_table ...`
- `p2_debug_filter_no_variadic_splat_ok`
- `p2_generated_stage2_no_prelude_interp_ok`

Latest generated-stage2 frontier:

- `s1 -> s2b` builds with `/tmp/cv2_puts` in about `241s`.
- Opt-in LLVM tail diagnostics (`ADAMAS_TRACE_STDERR=1
  ADAMAS_LLVM_REACHABILITY=1 ADAMAS_LLVM_TAIL_STATS=1`) show that
  the backend tail helpers are not the current timeout root: on the full
  compiler build, `generate(io)` reaches `finalize_enter` after emitting about
  `180.6MB` of LLVM IR. `emit_type_name_table` is the largest tail-size jump
  (`~27.8MB`, `21694` types) but only costs about `166ms`; the 300s timeout
  happens after IR generation has completed and before the produced stage2
  binary can be linked. Treat the active frontier as total generated-IR volume
  and pre-llc budget, not a single slow tail helper.
- Generated `s2b` no-prelude no-codegen smoke moved past
  `Class$Dcrystal_type_id`, `Char$Hascii_control$Q`,
  `Printer$Dshortest$$Float32_IO`, and the top-level no-prelude `puts`
  semantic error. `regression_tests/p2_generated_stage2_no_prelude_interp.sh
  /tmp/cv2_puts` is now green.
- Generated `s2b` no longer aborts on `STUB CALLED: Tuple$Heach$$block`
  for the tiny no-prelude runtime repro `puts 7`. The root cause was that
  `AstToHir#emit_runtime_print_fallback` inferred "prelude IO print is
  available" from ambient method tables instead of the actual compile mode.
  In generated stage2 that drift disabled the runtime no-prelude print path
  and let `puts` fall back into the variadic tuple corridor. `AstToHir` now
  receives `options.no_prelude` from CLI and treats `--no-prelude` as a
  hard gate for runtime print fallback selection. Evidence:
  `regression_tests/stage2_no_prelude_puts_runtime_repro.sh
  /tmp/cv2_noprel_printfix` -> `not reproduced`, while
  `regression_tests/p2_generated_stage2_no_prelude_interp.sh
  /tmp/cv2_noprel_printfix` stays green.
- Root moved: type-literal `crystal_type_id`/`crystal_instance_type_id`
  must lower to an `Int32` type-id literal before both `lower_call` and
  `lower_member_access` rewrite type literals to static `Class.*` targets.
  `Char#ascii_control?` is a leaf predicate on the raw `Char` codepoint and
  now lowers inline as `self < 0x20 || self == 0x7f`. The shape guard rejects
  both stale `Class.crystal_type_id` / `Class#crystal_type_id` and
  `Char#ascii_control?` self-host MIR targets. Separately, `TypeInferenceEngine`
  debug strings now evaluate lazily, so disabled debug hooks no longer trigger
  `Object#to_s(io)` on compiler-internal objects and accidentally materialize
  float-printing stubs during generated-stage2 semantic inference. Receiverless
  semantic inference now also treats top-level `puts`/`print` as builtins,
  matching the HIR lowering corridor.
- Generated `s2b` also moved past the debug-filter tuple-splat abort:
  `debug_env_filter_match?`, `debug_hook_filter_match?`, and
  `debug_class_repair_enabled_for?` are fixed-arity helpers now. The root was
  bootstrap-hot debug support depending on variadic `*texts`, which generated
  calls to unlowered `Tuple(String)#..._splat` helper bodies before actual
  compile work could proceed. Current `puts 7 --no-prelude` full-codegen
  frontier is now `STUB CALLED:
  Tuple$LString$C$_Crystal$CCMIR$CCType$R$Hjoin$$IO_String_block`, while
  `--no-codegen` stays clean.
- The tuple `join` frontier was localized with lldb to
  `LLVMIRGenerator#emit_extern_call`: `arg_entries.map { |(t, v, _)| ... }`
  forced tuple formatting in generated stage2. That formatter is now an inline
  indexed builder.
- The generated-stage2 `Crystal::EventLoop#close(IO::FileDescriptor)` frontier
  is cleared. Root cause: HIR materialized inherited virtual-dispatch targets
  (for example `Polling#close(Crystal::System::FileDescriptor)`) but final HIR
  RTA pruned them, and MIR later refused to use the unique same-arity inherited
  implementation for the narrower typed suffix. HIR now records lowered
  virtual-dispatch targets as final-RTA roots, inherited resolved targets are
  exact-demanded for lazy RTA, and MIR permits typed-suffix arity fallback only
  when the same-method/arity candidate is unique. The old abstract
  `Crystal$CCEventLoop$Hclose$$IO$CCFileDescriptor` stub is now a regression.
- The generated-stage2 no-prelude `puts 7` full-codegen/link corridor is now
  cleared. The kept artifacts proved the HIR/MIR/LLVM body was already good:
  the old generated compiler emitted `.ll` and a valid Mach-O object but left
  only `.o.cmdtmp` and no final executable. Root chain:
  `Crystal::System::Process.fork` was mis-lowered in the generated compiler as
  a plain `Int32` contract, so the parent compiler also entered the child
  `execvp(llc)` path and skipped the rename/link tail; after switching to raw
  `LibC.fork`, `LibC.waitpid(..., out status, ...)` exposed a second bootstrap
  lowering bug where status storage decoded pointer garbage; the runtime-stub
  freshness check pulled an unlowered `Time#<=>` stub; and the LLVM cache path
  accepted stale/empty artifacts through `File.exists?` + `FileUtils.cp`.
  The CLI tail now uses raw `LibC.fork`, explicit `pointerof(status)`, avoids
  Time ordering in the stub freshness gate, requires non-empty LLVM cache
  artifacts, and copies cache files through a small LibC read/write helper.
  `p2_generated_stage2_no_prelude_puts_guard.sh` now ends with plain
  `p2_generated_stage2_no_prelude_puts_guard_ok`.

- The generated-stage2 `File.new_internal` crash is cleared. Root cause:
  tuple element type recovery only indexed leaf alias suffixes like `Handle`,
  so a full-prelude tuple element observed as `File::FileDescriptor::Handle`
  did not resolve through the canonical
  `Crystal::System::FileDescriptor::Handle => Int32` alias. HIR then typed
  `File.open(...)[0]` as a pointer-shaped handle and LLVM emitted
  `load ptr` from the tuple slot followed by `load i32` from that fd value.
  Alias registration now indexes compound suffixes such as
  `FileDescriptor::Handle`, and qualified alias-chain fallback uses only
  compound suffixes (not broad leaf-only matches). The regression
  `p2_file_open_tuple_handle_alias_shape.sh` asserts that
  `File.new_internal` loads the fd tuple element as `i32` and calls
  `File.new(String, Int32, String, Bool, Nil, Nil)`.

- The generated-stage2 `NamedTuple(Span, ExprId, ExprId)#[](Symbol)` smoke
  stub is cleared. Root cause: generic type materialization resolved the full
  `NamedTuple(name: Type)` entries as ordinary generic parameters before the
  NamedTuple-specific parser ran. For namespaced value types such as
  `Adamas::Compiler::Frontend::Span`, this erased field names and
  materialized a positional `NamedTuple(Span, ExprId, ExprId)`, so
  `branch[:condition]` lowered to a runtime `NamedTuple#[](Symbol)` call
  instead of a static `index_get`. `NamedTuple` generic args are now parsed
  before generic substitution; only the value side is resolved and the original
  keys are rebuilt. The regression
  `p2_named_tuple_annotation_keys_no_prelude.sh` negative-checks the old
  keyless HIR shape and requires `index_get`.

- Next frontier: generated `s2b` still builds, but both smoke tests now abort
  immediately in
  `CLI#debug_cli_root_block_state(String, AstArena, Array(ExprId))`. Do not
  attempt `s3b+` until this generated-stage2 debug-helper stub is root-caused
  and guarded. The previous `NamedTuple(Span, ExprId, ExprId)#[](Symbol)`,
  `Tuple$Heach$$block`,
  `debug_env_filter_match?..._splat`,
  `Tuple(String, Crystal::MIR::Type)#join(IO, String, &block)`,
  `Crystal::EventLoop#close(IO::FileDescriptor)`, and generated-stage2
  no-prelude `puts 7` full-codegen/link repros are now green/regression-guarded.

Boundary: `src/adamas.cr --no-prelude` still exits `11` in an
inline-yield recursion / force-return corridor before it can serve as a green
pending-budget oracle.

- The generated-stage2 lookup/lazy-enum no-prelude frontier is cleared. Root
  causes:
  - hot `lookup_function_def_for_call` fallback sites called
    `function_def_overloads(...)`, whose basename collides with the
    `@function_def_overloads` ivar getter in generated stage2; a wrapper
    (`function_def_overload_keys`) keeps those hot sites away from the getter
    overload family, so local `overload_keys` no longer becomes the backing
    Hash.
  - lazy enum source-discovery state used inline-default ivars outside the
    explicit AstToHir constructor/reset corridor. Generated stage2 can leave
    those inline ivars nil, so the state is now explicitly initialized in both
    `initialize` and `bootstrap_reset_constructor_tail`.
  - lazy enum source discovery was running under `--no-prelude`, where there
    is no prelude sibling graph to recover. That made an ordinary
    `private class Hidden` reducer scan the temp directory through `Dir.glob`.
  `lazy_discover_enum_from_source` now returns false in no-prelude mode.
  Guard: `p2_generated_stage2_lookup_lazy_enum_no_prelude.sh`.
- The `Array(Box)#unsafe_fetch$Int32` no-prelude backend frontier is cleared.
  Root cause: LLVM `emit_extern_call` treated the qualified method suffix
  `$Int32` as return-type evidence, even though it is the index argument
  specialization. Calls were emitted as `i32` and the missing-body pass
  synthesized an abort stub for `Array$LBox$R$Hunsafe_fetch$$Int32`.
  The backend now keeps suffix-return hints only for bare primitive helpers and
  materializes a generic late `Array(T)#unsafe_fetch(Int32)` body using the
  element ABI from `Array(T)`. Guard:
  `p2_array_class_ref_unsafe_fetch_no_prelude.sh`; related checks:
  `p2_array_struct_unsafe_fetch_return_no_prelude.sh`,
  `p2_bootstrap_semantic_emit_oracle.sh`, and
  `p2_generated_stage2_lookup_lazy_enum_no_prelude.sh`.
- The generated-stage2 full-prelude `MacroExpander#resolve_scoped_macro_value`
  null `String#empty?` crash is cleared. Root cause: `lower_if` routed the
  main `if` condition through condition-context short-circuit lowering, but
  lowered `elsif` `&&`/`||` conditions as value expressions and then truthy-
  checked the nil-or-bool result. Generated `s2` miscompiled
  `elsif name && constant_like_name?(name)` so the nil path still reached
  `resolve_scoped_macro_value(name, context)`. `elsif` conditions now create
  their target blocks first and route short-circuit operators through
  `lower_short_circuit_condition`. Guard:
  `p2_elsif_short_circuit_condition_no_prelude.sh`.
- The generated-stage2 full-prelude lib-registration frontier has moved past
  the source-backed extern helper stubs and the invalid parser-slice helper
  calls. Root causes cleared in this corridor:
  - source-backed extern registration exposed redundant `ArenaLike` and mixed
    nilable/concrete lib-name helper signatures, so generated stage2 emitted
    concrete symbols whose bodies were registered under broader overloads;
  - `safe_str_guard` inlined pointer validation at broad `case` sites, losing
    branch-local Slice narrowing and freezing
    `Hash(String, Hash(UInt32, Crystal::HIR::Value))#to_unsafe`;
  - visibility unwrap helpers relied on `current.is_a?` narrowing for a broad
    `Frontend::Node` local, so generated stage2 emitted virtual
    `Node#expression` and then `Hash(... )#null_ptr?`;
  - reparsed macro-body root selection used block-heavy
    `program.roots.map { ... }.find(&.is_a?)` plus unchecked `arena[id]` at a
    boundary already known to be arena-fragile.
- The generated-stage2 full-prelude macro-condition frontier in
  `MacroNumberValue.numeric_suffix` is cleared. Root cause: the fixed numeric
  suffix table used `Array#find` with a block. Generated `s2` lowered that into
  an Array loop with an uninitialized cursor and crashed before the first
  `String#ends_with?`. A first attempt using `while + unsafe_fetch` was
  refuted because it still used an Array and regressed s2 build to corrupted
  `ExprId`; the accepted version keeps the existing hard-coded suffix table
  semantics but spells it as direct `ends_with?` checks with no Array/block
  machinery. Current evidence: `crystal build src/adamas.cr -o
  /tmp/cv2_numeric_suffix_chain_candidate --error-trace` passed;
  `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_numeric_suffix_chain` builds `s2`, passes no-prelude smoke,
  and advances plain smoke to `resolve_lib_global_decl_from_source(Span,
  ArenaLike)` during `LibC` registration.
- The generated-stage2 full-prelude lib global source-recovery stub is
  cleared. Root cause: `resolve_lib_global_decl` delegated to a one-use helper
  with an explicit `ArenaLike` parameter, recreating the same source-helper ABI
  boundary that previously broke extern source recovery. Adding the helper to
  exact-demand was refuted (the same stub remained), so the accepted fix
  removes the helper boundary and performs source recovery directly in
  `resolve_lib_global_decl` using `@arena`. Current evidence: `crystal build
  src/adamas.cr -o /tmp/cv2_lib_global_inline_candidate --error-trace`
  passed; `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_lib_global_inline` builds `s2`, passes no-prelude smoke, and
  advances plain smoke past full `LibC` registration to
  `detect_method_yield(DefNode, ArenaLike, Bool)` during `Errno` enum
  registration.
- The generated-stage2 full-prelude method-yield helper stub is cleared.
  Root cause: `detect_method_yield` was a tiny wrapper around already-lowered
  yield scanners, but generated `s2` materialized the wrapper's broad
  `DefNode, ArenaLike, Bool` symbol without lowering its body. Adding it to the
  exact-demand allowlist was refuted (same stub remained). The accepted fix
  removes the wrapper boundary and inlines the source-scan/fallback selection
  at the three method-registration call sites. Current evidence: `crystal
  build src/adamas.cr -o /tmp/cv2_detect_yield_inline_candidate
  --error-trace` passed; `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_detect_yield_inline` builds `s2`, passes no-prelude smoke, and
  advances plain smoke to `record_phase0_body_infer_walk(DefNode, ArenaLike,
  ExprId?)` during `Errno` enum registration.
- The default generated-stage2 phase0 body-inference metric helper frontier is
  cleared. Root cause: `record_phase0_body_infer_walk` and the canonical
  identity helper chain are diagnostic/identity bookkeeping, but default
  bootstrap smoke executed them unconditionally and exposed broad
  `ArenaLike`/nilable helper symbols. Inlining only the first wrapper moved the
  stub one layer deeper to `canonical_def_identity_for_body_infer`; the accepted
  fix gates canonical identity calculation behind `ADAMAS_PHASE0_METRICS`
  or `ADAMAS_IDENTITY_DRY_RUN`, preserving opt-in metrics/dry-run while
  removing default nonsemantic work. Current evidence: `crystal build
  src/adamas.cr -o /tmp/cv2_phase0_gated_candidate --error-trace` passed;
  `scripts/build_bootstrap_stages.sh --stages 2 --out
  /tmp/cv2_bs_s2_phase0_gated` builds `s2`, passes no-prelude smoke, and
  advances plain smoke to semantic body inference:
  `infer_concrete_return_type_from_body_inner(Array(ExprId), String, String,
  ArenaLike, Bool)`.

## Next Work

0aa. (2026-06-14) Current frontier = s2b STARTUP repr-flip (String<->Slice).
   UPDATE 2026-06-17: one confirmed producer of this family FIXED — see 0a-side6
   (SplatNode/UnaryNode NodeKind collision in lower_node; glob backtrace named it
   directly). Re-measure the s2b/glob crash rate before assuming 0aa is closed.
   lldb-VERIFIED root (memory `s2b-startup-crash-rc-overfree-refuted`): a
   header-less pointer INTO the source buffer is written into a `String`-typed
   SLOT (`HIR::Call#method_name` class field, `DefParamInfo#type_annotation`
   struct field); consumers (`parse_method_name_compact`, `ascii_suffix_bytes?`,
   `String#byte_at`) read the "header" as source ASCII -> huge bytesize -> OOB
   read. ASLR-gated non-determinism (deterministic overshoot; ASLR decides
   mapped vs unmapped). Baseline ~7/8 crash on `src/adamas.cr`. RC-over-free
   REFUTED (no-op-free A/B identical). Allocating helpers (substring/byte_slice/
   String.new(slice)) are correct; the bug is the SLOT receiving a Slice/source
   pointer at a union/phi/struct-ABI boundary.
   PLAN C (user-chosen): (A) producer localization, then (B) MIR load/store-size
   verifier. (A) IN PROGRESS: badstr probe (env `ADAMAS_BADSTR_PROBE`, throwaway,
   stash `throwaway-s2b-heisenbug-probes`) hooks all 11 `HIR::Call` ctors with
   `HIR.badstr_probe_write` -> logs `[BADSTR-WRITE] <where>` at the producer;
   self-calibrates on the live V2 header word (==16) so stage1 stays silent.
   Build debug s2b with probe, run on `src/adamas.cr` to capture first bad write.

0ab. (2026-06-14, SHIPPED `652a629a`) Producer fixed for the 0aa repr-flip:
   `Array#each_with_index` dropped loop-carried accumulation. `parse_def_receiver_name`
   sums part sizes through `each_with_index` (`total += part.size`); the DIRECT
   accumulation became a self-referential header phi (back-edge read via post-pop
   `lookup_local`, which reverts block-scope writes to the header phi) -> `total=0`
   -> `Bytes.new(0)` under-alloc -> source-pointer-in-String-slot overflow. Fix:
   two-phi scheme + dual body-exit resolution (pre-pop snapshot if it advanced past
   the header phi, else post-pop lookup for nested inline-yield). Reducer
   `regression_tests/array_each_with_index_accum_repro.sh` (direct c1-c3 + nested
   c4-c5). Suite 158/158 + 31/31. Memory `each-with-index-accum-drop-fix`.
   NOTE: measure s2b crash-rate impact; do NOT assume it alone clears the Heisenbug
   (the repr-flip SLOT bug may also be reached by other producers).
   FAMILY FOLLOW-UP (SHIPPED 2026-06-14, branch `loop-family-nested-accum-fix`):
   extracted shared `resolve_loop_backedge_value` helper (pre-pop snapshot if it
   advanced past the header phi, else post-pop resolve) and routed it through
   `times`, `range each`, `array each` (static+dynamic), `upto/downto` (Part A
   back-edge + Part B exit phi), and DRY-refactored `each_with_index`. upto/downto
   additionally re-point `@inline_caller_locals_stack[-1][var]` at the exit phi at
   loop exit (they exit via the increment block, so the header phi the inline
   caller-local was pointed at on entry is one iteration stale). hash#each was
   already correct (resolve path + cond-block exit). Reducer
   `regression_tests/loop_family_nested_accum_repro.sh` (direct d1-d8 + nested
   n1-n7). Gates 158/158 + 31/31. Memory `each-with-index-accum-drop-fix`.
   TWO CARVE-OUTS (separate root causes, NOT in this commit):
   (1) `string each_char` nested-yield accumulation: `lower_string_each_char_intrinsic`
   uses plain `ctx.lookup_local` (84651) not `lookup_local_for_phi`, so no phi is
   created for a nested accumulator -> stays at init. Needs the inline_vars phi
   plumbing the array lowerings have. Direct each_char works.
   (2) `next` inside a loop block freezes the accumulator at init for upto/downto/hash
   (direct) and ALL loops (nested). VERIFIED downstream of HIR (no-prelude HIR
   computes the right value but runtime=0); lead = loop exit phi references the
   fall-through-only value, not the next/fall-through merge (incr-phi). Memory
   `loop-next-exit-phi-drop-bug`. Repros in /tmp/loopfam (advall.cr, advdirect.cr).

0ac. (2026-06-15, SHIPPED `cb25a911`) Globber union-array late-generic template
   stride OOB — a CONTRIBUTING layer of the 0aa s2b startup crash (NOT the whole
   thing). `emit_dead_code_stub` synthesizes `Array(T)#<<`/`#push`/`#unsafe_fetch`
   bodies for generics RTA references but never lowers. Three oracles disagreed on
   the union slot stride: realloc grew by `llvm_store_size_bytes` (hardcodes 16 for
   any `.union`), store/read used a typed `getelementptr <union>, ptr %buf, i64 %idx`
   (= LLVM sizeof 20 for `{i32,[4 x i32]}`), while the array literal alloc +
   emit_array_get read used the MIR size (`container_elem_storage_size_u64` = 24).
   For Dir::Globber's PatternType union the buffer was grown by 16, written at 20,
   read at 24 -> Array#<< OOB -> heap corruption in Globber#single_compile. Fix:
   route both templates' realloc + store/read strides through
   `container_elem_storage_size_u64` and emit byte-offset gep (`%byte_off = mul i64
   %idx64, <stride>` + `getelementptr i8, ptr %buf, i64 %byte_off`); shared
   `array_element_mir_type_from_mangled_method` helper. gmalloc-VERIFIED: the old
   binary crashes deterministically in `Globber#single_compile`, the fixed binary
   sails past into normal prelude parsing. Suite 158/158 + 31/31. IR-form guard
   `regression_tests/array_late_generic_union_stride_repro.sh` (validated separator:
   pre-fix build emits the typed direct-index store, fixed build emits 0).
   DOES NOT fully clear the Heisenbug: the non-deterministic pass3/lower_main
   segfault persists (~30%, present in pre-fix builds too — single_compile was only
   the gmalloc-deterministic EARLY manifestation; the runtime crash was always at
   codegen pass3). A/B N=40: OLD 15ok/16segv/9other -> NEW(fix) 21ok/12segv/7other.
   The remaining pass3 crash is the next layer of 0aa (whole-backend window after
   `pass3 after lower_main call`; likely the repr-flip String-slot family). Memory
   `s2b-startup-crash-rc-overfree-refuted`.

0a-side. (2026-06-14, SHIPPED `56ae947b`) Found+fixed en route: macro
   `{% for x in @type.instance_vars %}` (and @type.methods) never iterated in the
   HIR lowering path (`macro_for_iterable_values_with_context` had no
   MemberAccessNode/CallNode case) -> stdlib `Struct#==`/`#hash`/`#to_s` collapsed
   -> `Hash(SomeStruct,V)` merged all distinct keys into one bucket (incl.
   compiler-internal `CallSignature`). Fix delegates to new
   `MacroExpander#evaluate_for_iterable`. Gates: combined 31/31, originals 157/157;
   regression `struct_type_instance_vars_for_loop_repro.cr`. NOTE: likely
   INDEPENDENT of the 0aa repr-flip crash (different mechanism) — measure impact
   on s2b crash rate, do not assume it fixes the Heisenbug. Named-type reflection
   (`Foo.instance_vars`) in method bodies is a separate, still-open gap (needs
   expander symbol-table wiring).

0a-side2. (2026-06-15, SHIPPED `421bed2f`) Found+fixed en route: `Pointer(T).new(
   integer_address).value` returned `address & 0xFF` instead of loading from memory.
   The element type T was dropped, so the inttoptr result was typed as a bare/UInt8
   `Pointer`; `emit_load`'s packed-scalar shortcut (llvm_backend.cr:~17831 — fires
   when `@inttoptr_value_ids.includes? && !ptr_is_typed_pointer`) then emitted
   `ptrtoint ptr to <elem>` instead of a real `load`. Fixed all 3 lowering paths by
   deriving the result element type from the owner via `method_owner(owner) ->
   Pointer(T)`: call-site path (`lower_pointer_new_intrinsic` now takes `owner_name`,
   threaded at all 3 call sites as `target_name`/`full_method_name`), with-prelude
   path (result type had resolved to the method *Class* type `Pointer(Int32).new$UInt64`,
   which naive `rchop(".new")` could not strip — `method_owner` handles the suffix),
   and the no-prelude intrinsic `lower_primitive_pointer_new_intrinsic` (with
   `@current_class` fallback). `to_unsafe`/`malloc`/`.as(T*)` were never affected
   (concrete element type). Verified runtime: 777 / 1234567890123 / 65 (with-prelude),
   exit 123 (no-prelude). Regression `regression_tests/pointer_new_value_load_repro.sh`.
   Gates 158/158 + 31/31 (identical to baseline). NOTE: OFF the 0aa #4 crash path
   (that uses `.as(UInt64*).value`), but it DID corrupt the in-s2b badstr probe (which
   read tid headers via `Pointer.new(addr).value`) — those tid numbers were artifacts;
   use external lldb for #4. Memory `pointer-new-value-element-drop-fix`.

0a-side3. (2026-06-15, SHIPPED `9f5e4acc`) Found+fixed en route: macro-built
   `Slice(T).literal` tables (the stdlib `String::CHAR_TO_DIGIT` pattern) collapsed
   to a single element. FIVE independent root causes: (1) the parser kept only the
   FIRST statement of a multi-statement `{% ... %}` directive and fast-forwarded over
   the rest (table-builder mutations never ran); (2) the macro evaluator lacked
   `Array#each`/`each_with_index`, `MacroArrayValue#[]=`, and Range-as-value
   materialization (`(0...256).map { ... }`); (3) the class-body macro-if "flag text"
   fast path did not thread macro locals (`{% table = ... %}`) into a later
   `{{ table.splat }}`; (4) `pack_splat_args_for_call` packed the splat into a Tuple
   for the `slice_literal` primitive, collapsing it to one element; (5) negative
   literals (`-1`) in the macro-reparsed builder mis-lowered because UnaryNode operator
   text was read via stale source-span extraction (offsets relative to the transient
   reparse buffer) -> garbage char -> `1.<garbage>()` STUB. Fixed by owning
   UnaryNode.operator bytes (`@operator_str`) and preferring them. CHAR_TO_DIGIT is now
   a correct 256-element slice. Reducer `regression_tests/macro_slice_literal_table_repro.sh`
   (positive-fill flag-path + CHAR_TO_DIGIT-shaped negative-fill). Gates 158/158 + 31/31.

0a-side4. (2026-06-15, SHIPPED `c92aa559`) Found+fixed en route: `String#to_i(base)` /
   `to_i32(base)` dropped the base argument. The lower_call intercept matched "any args
   count" and always emitted the decimal-only `__adamas_string_to_i` intrinsic, so every
   non-decimal conversion parsed as base 10 (`"ff".to_i(16)` -> 0, `"101".to_i(2)` -> 101,
   `"z".to_i(36)` -> 0). apply_default_args (earlier in lower_call) already materializes the
   first positional `base` param into args[0]; when present, route to a new base-aware
   intrinsic `__adamas_string_to_i_base` (strtol with runtime base, args[0] cast to Int32).
   No-arg decimal fast path unchanged. strtol covers bases 2..36; base 62 not handled.
   Reducer `regression_tests/string_to_i_base_repro.sh` (255/12/5/35/15/42). Gates: combined
   31/31, originals 157/158. The one failure (`stage2_dir_glob_dir_probe`) is the pre-existing
   non-deterministic lower_main repr-flip crash (0aa), NOT this change: A/B N=24 baseline
   (incl. CHAR_TO_DIGIT fix) 1 crash, with-diff 2 crash — sampling noise. CONFIRMS 0ac:
   neither the CHAR_TO_DIGIT nor the to_i fix clears the 0aa pass3/lower_main Heisenbug
   (~4-8% on the 3-line glob probe). #4 frontier remains the repr-flip String-slot family.

0a-side5. (2026-06-16, SHIPPED `3230c001` + test `c61b7913`) Found+fixed en route: one
   consumer of the 0aa repr-flip. `9f5e4acc` made `unary_operator_text` /
   `safe_unary_operator_string` prefer `safe_slice_to_string(node.operator)` over bounded
   source-span extraction (needed for macro-reparsed `-1` / CHAR_TO_DIGIT / to_i(base)).
   When the #4 String<->Slice repr-flip corrupts the operator slice slot (lldb-captured
   `{ptr=0x100000000, size=311}`), `String.new(slice)` memmoves past mapped memory and
   SIGSEGVs in force_lower of the Dir.glob path. Fix: new `operator_slice_to_string?`
   length-guards `node.operator` (1-4 bytes; real operators <=2: `->`, `&-`) before
   dereferencing; reading `.size` is safe (no deref). Corrupt huge-size slice now falls
   through to the bounded source-span path. Keeps 9f5e4acc's macro-reparse correctness.
   A/B (glob probe, N=40 standalone, ASLR on): operator-slice SIGSEGV 3/40 -> 0/40 (+0 in
   30 lldb tries, +0 in a 60-iter hunt). Reducer
   `regression_tests/operator_slice_corrupt_guard_repro.sh` (manual N-iter SIGSEGV guard).
   Gates 158/158 + 31/31. NOTE: this is a CONSUMER guard restoring the crash-safety
   9f5e4acc removed (regression fix), NOT a 0aa root fix — the producer repr-flip remains
   open. Residual rare rc=1 (a separate non-segfault #4 manifestation, did not reproduce
   in 60 tries) is the next thread on the 0aa frontier.

0a-side6. (2026-06-17, SHIPPED locally — pending commit) ROOT FIX for a confirmed
   0aa #4 producer: `SplatNode` misdispatched as `UnaryNode` in the `lower_node`
   fast `case kind` prefilter. `SplatNode` has no dedicated `NodeKind` and shares
   `NodeKind::Unary` with `UnaryNode` (ast.cr `SplatNode#node_kind` / static
   `self.node_kind(SplatNode)` both return `Unary`; awk-verified Unary is the ONLY
   many-to-one NodeKind collision). The `when NodeKind::Unary` branch
   (ast_to_hir.cr:52229) did an unconditional `node.unsafe_as(UnaryNode)`. Layouts:
   `SplatNode = span + expr:ExprId` (small alloc); `UnaryNode = span +
   operator:Slice(16B) + operand:ExprId + operator_str:String`. `UnaryNode#operand`
   sits PAST the end of SplatNode's smaller allocation, so the cast read `operand`
   from adjacent heap (the source-text buffer) -> a bogus ExprId = the #4
   "source-bytes-in-a-typed-slot" producer. Confirmed by the captured glob backtrace
   (/tmp/glob4_oob_full.txt): `lower_node:52230 (NodeKind::Unary) -> lower_unary ->
   lower_expr -> "ExprId out of bounds: 1701869637"` inside
   `Path.new$(Path|String)_Tuple()` (the splat-param expansion in Dir.glob — the
   exact path 0ac/0a-side5 were chasing). Fix: guard the cast —
   `unless node.is_a?(SplatNode)` — so only a real UnaryNode is unsafe_as-cast;
   SplatNode falls through to the type-safe `case node` arm (52399-52401) that lowers
   it via `lower_expr(node.expr)`. +11/-1, single hunk. Deterministic reducer
   `regression_tests/splat_node_unary_dispatch_repro.sh` (`[*t, 9]` array-literal
   splat in a top-level-called method routes a SplatNode through the exact branch):
   pre-fix rc=11 SIGSEGV in HIR lowering, post-fix rc=0; A/B reconfirmed on the live
   binaries. Gate: 161/161 originals + 31/31 combined, ALL SUITES PASSED (baseline
   was 159; suite grew, 0 new regressions). `bin/adamas` promoted to the fixed binary
   (md5 c63f1832...); scratch `bin/adamas_dbg` removed.
   CALIBRATED SCOPE (anti-theater): this removes ONE confirmed producer of the
   ExprId-OOB / source-pointer-in-String-slot family — the one the glob backtrace
   names directly. It does NOT by itself prove the whole 0aa Heisenbug is gone:
   (a) the statistical glob probe was already in a non-reproducing layout this build
   (clean bin/adamas 0/60), so it can neither confirm nor deny residual; (b) prior
   notes warn the repr-flip SLOT may be reached by other producers. NEXT: re-measure
   the `stage2_dir_glob_dir_probe` / s2b crash rate against the promoted binary to
   quantify how much of 0aa this clears; any residual non-det pass3/lower_main segv
   is the next 0aa layer. Stage2 robustness footnote: in self-hosted stage2 subclass
   RTTI can be lost after arena storage (the reason the fast prefilter exists at all),
   so worst case `is_a?(SplatNode)` returns false -> same unsafe_as as today = no
   regression; a fully stage2-robust fix gives SplatNode its own NodeKind (4
   cross-file consumers: dispatch.cr:34, ast_cache.cr:379/720, name_resolver.cr:128)
   — deferred, higher blast radius. Memory `s2b-startup-crash-rc-overfree-refuted`.

=== ABI REWORK TRACK (branch `abi-rework`, plan `docs/abi_rework_quadr_plan.md`) ===
Owner directive: fix the two ABIs at root, not symptoms; HYP-B safety-net first
(divergence assert + freeze + verifier BEFORE the inline-constructor flip).
Sequencing 0a→0b→0c→0d(SDD)→1→2→3→5a→5b; step 4 (inline flip) on an isolation
branch; closure ABI (C) pairs with fibers. Each step: own mini-Quadr, own commit,
gate = combined 31/31 + originals 158/158 + p2_generated_stage2_* + s2b probe.

ABI-0a. (2026-06-16, SHIPPED — divergence assert) Env-gated `ADAMAS_LAYOUT_ASSERT`
   in `LayoutProbe.check_divergence`: when two phases (or one phase twice) record a
   different storage CLASS for the same `type_name`, emit a `DIVERGENCE\t<CROSS|INTRA>`
   row; abort only on CROSS in mode 2. No-op on the default path (double-gated behind
   `enabled?`/`assert_mode>0`). MEASUREMENT (hello-world, ASSERT=1): 18 CROSS + 3 INTRA
   label-divergences (premise CONFIRMED — the 3 oracles disagree), and 22 distinct
   `(type,phase,context)` rows with slot_size≠access_size, CONCENTRATED in
   `llvm/container-element` (Array(Row) 8/24, Fiber 8/144, Segment64 8/56). VERIFIED at
   `llvm_backend.cr:2781`: non-whitelisted structs get an 8-byte pointer slot — that
   slot≠access is by-design PointerCarrier indirection, NOT a corruption by itself. The
   real corruption is producer/consumer DISAGREEMENT per `(type,context)` (the cb25a911
   stride family). NOTE: label-divergence is a circular falsifier for step 1 (driving
   labels equal ≡ unifying the taxonomy = step 1 itself); the drivable metric is
   producer/consumer agreement. Gate: full suite (in progress at commit time).
   Next: ABI-0b (`ADAMAS_FORCE_STRATEGY=gc` bisector), ABI-0c (real type sizes in
   estimate_size), ABI-0d (Frontier SDD — gate before step 1).

ABI-0a' (2026-06-16, SHIPPED — operational metric). The 0a assert keyed on `type_name`
   alone, so it measured cross-CONTEXT label noise (18 "CROSS"), NOT the §2.7 operational
   bug. Refined `layout_probe.cr` `check_divergence` to two signals: (1) SLOT-CONFLICT —
   same `(type, context)` with >= 2 distinct slot sizes (intra- OR cross-phase; key includes
   context so cross-context field-inline-vs-container-pointer never fires), abort-eligible in
   mode 2; (2) DIVERGENCE — the old label signal, downgraded to REPORT-ONLY (verified mostly
   label noise: String/Fiber/Atomic slot agrees, only the storage NAME differs). VERIFIED NOT
   THEATER: first cut had a `phases_all.size>=2` gate that made it structurally inert (MIR
   logs slot=-1; HIR=field-slot and LLVM=container-element never share a context) → removed
   the phase-count gate so intra-phase conflicts fire. Re-measure on /tmp/abi_layout_probe.cr:
   15 SLOT-CONFLICT + 21 label DIVERGENCE. All 15 are intra-HIR field-slot at the 8-vs-N
   ptr-vs-value boundary = the #4 family: Slice(UInt8) 8/16, Nil|String / Nil|IO /
   Nil|Array(String) 8/16 (union ptr-vs-tagged), Time 8/24, Char::Reader 8/40,
   Time::Location::Zone 16/24. This is the B0-2 "slot born 8-byte ref_fallback then written
   N-byte value view" root, MEASURED not inferred. Diagnostic-only (default path no-op:
   `log` returns at `unless enabled?`). REVISED step-1 falsifier: drive the 15 SLOT-CONFLICTs
   toward 0 (single-sourced repr, no 8-vs-N split for one type/context). Docs: plan §2.7.1 +
   table 0a' row, SDD §4. Gate: full suite (running at commit time).

ABI-0b. (2026-06-16, SHIPPED — force-GC bisector) `ADAMAS_FORCE_STRATEGY=gc` forces
   every allocation through `MemoryStrategyAssigner` to `MemoryStrategy::GC`. One
   chokepoint: override in the `assign` loop (catches both `determine_strategy` and the
   explicit-strategy bypass); cached `self.force_gc?` reads ENV lazily (module-const
   ENV-read crash avoidance). PGO refinement is profile-data-gated → off the default
   path. Verified: `.ll` differs (−308 alloca under force-GC on an allocating probe),
   compiler rc=0, default path is a guarded no-op, known-good test gives identical
   output default vs force-GC. HYBRID-MODEL CAVEAT (owner reminder): this is DIAGNOSTIC
   ONLY, never a fix — GC stays minimal, "expand GC" is forbidden as a remedy, and GC
   env effects are USUALLY layout-masking artifacts. Read ASYMMETRICALLY: *persists*
   under force-GC ⇒ NOT a strategy bug (reliable); *vanishes* ⇒ AMBIGUOUS (real strategy
   bug OR a layout bug masked by GC's larger/zeroed/aligned allocs — confirm layout via
   LayoutProbe / step-3 verifier). Gate: full suite (in progress at commit time).
   ABI-0c REASSESSED: `TypeDescriptor` carries no size, so a "real size" must be computed
   from ClassInfo ivars = a layout oracle. Building one now = the 4th oracle the SDD
   warns against → 0c now CONSUMES step 1's `layout_of` (post-step-1 follow-up, NOT a
   step-0 lever). Next: ABI-0d (Frontier SDD — gate before step 1).

ABI-0d. (2026-06-16, SHIPPED — Frontier SDD) Wrote `docs/abi_struct_value_sdd.md`, the
   ownership contract that gates step 1 (GPT review critique #2: "single oracle" cannot be
   coded safely without it, else step 1 mints a 4th oracle). Verified all three current
   oracles against code: HIR `field_storage_size_impl` (ast_to_hir.cr:39412), MIR
   `mir_field_storage_size` (hir_to_mir.cr:6353, STRING→8 special-case + no small/large
   split), LLVM `container_elem_storage_size`/`inline_container_struct_type?`
   (llvm_backend.cr:2756/:2796 string-prefix whitelist). Contract: the MIR type REGISTRY
   owns the `repr` bit (PointerReference/PointerCarrier/InlineBytes), set ONCE at the
   `align_all_class_ivars` fixed point (co-frozen with size in step 2); registry layout owns
   offsets; `slot_size = inline? value_size : 8` via one shared helper all 3 phases READ; the
   whitelist becomes a registration predicate, not a runtime name-match. Invariant (step-3
   verifier): producer & consumer must AGREE on `(repr, slot_size, value_size)` per
   `(type, context)` — strictly stronger than `slot==access`, catches the `cb25a911`
   16/20/24 family. Guard-only (keep dedicated paths, B1a/B1c history): StaticArray, Tuple/
   NamedTuple, Proc, Pointer, Union, lib structs. NON-GOALS: no inline flip (step 4), no new
   size oracle (reads frozen registry). Step-1 falsifier: 0 CROSS rows + no new slot/access
   class + suites green. Open risks carried to step 1: String slot=8 vs object value_size;
   freeze ordering (bit set at final-align fixed point, NOT earlier); late-mono types get the
   bit at registration. Next: ABI-1 (single `layout_of`, all 3 phases read).

ABI-1 (PLAN, design-corrected 2026-06-16 — step-1 reconnaissance mini-Quadr). The SDD's
   "MIR registry owns repr, all 3 phases read it" is WRONG for the HIR reader: verified
   `field_storage_size` runs INSIDE `align_all_class_ivars` (ast_to_hir.cr:28124), a pure-HIR
   pass that completes BEFORE the MIR registry is populated → a registry-owned bit is
   unreadable at the earliest (offset-producing) site. CORRECTED ownership: single source =
   a PURE PREDICATE `LayoutContract.inline_value?(kind, size, name, is_lib)` callable in all 3
   phases, MEMOIZED as a bit on MIR `Type` for MIR/LLVM (cache, not authority). Also verified:
   `type_size(String)`→ref_fallback→8 (ast_to_hir.cr:38980) == MIR STRING→8, so the String
   field-slot CROSS row is LABEL-only (InlineBytes vs PointerReference), NOT a size bug;
   real size mismatches are container-element/late-generic (0a finding corroborated). SPLIT
   step 1 (smallest/safest first, each its own commit+gate): 1a = pure predicate + MIR memo
   (ADDITIVE, no reader change, SAFE); 1b = unify LayoutProbe storage LABEL via shared repr
   classifier (drives CROSS label rows→0, zero size change); 1c = container-element
   whitelist (llvm_backend.cr:2796) → `elem_type.inline_value?` (lone CAUTION size flip).
   Big-bang reader flip judged VULNERABLE (Adversary). Docs corrected in
   `docs/abi_struct_value_sdd.md` §3/§6/§7. Next: code ABI-1a.

ABI-1a (2026-06-16, SHIPPED — pure predicate + MIR memo, ADDITIVE/SAFE). New
   `src/compiler/layout_contract.cr`: `Adamas::LayoutContract.inline_value?(kind, size, name,
   is_lib)` — the single pure repr decision ("inline bytes at the slot, or 8-byte pointer?"),
   reproducing the CURRENT effective HIR `field_storage_size_impl` decision (class ref/ptr/
   array/proc/Nil → pointer; primitive/enum → inline; union → inline iff >pointer-word; struct
   → inline-container family OR lib OR `size>=pointer-word`; tuple → `size>=pointer-word`).
   Plus a `repr` 3-way label (for 1b) and `inline_container_family?` (the LLVM whitelist, for
   1c). MIR `Type` gains a LAZY-memoized `inline_value?(is_lib=false)` caching the predicate;
   lazy (not eager at creation) so it reads the FINAL registry size — String 8→12 and similar
   post-creation size updates would otherwise freeze a stale small/large carrier decision.
   NO oracle reads the bit yet (computed-but-unused → behavior-neutral by construction).
   Required from `mir/mir.cr`. Gate: build clean; probe UNCHANGED (15 SLOT-CONFLICT + 21
   DIVERGENCE, identical set → no behavior change); originals 158/158 + combined 31/31.
   MEASUREMENT REFINEMENT vs 0a': of the 15 SLOT-CONFLICTs, 13 are true ptr-vs-value (8-vs-N)
   repr conflicts the predicate single-sources (Slice* → inline-16; Time/Char::Reader/Span/
   Stackvec/Path → inline large; Nil|* unions → inline-16); the other 2 —
   `EventLoop::Polling::Event` 88/96 and `Time::Location::Zone` 16/24 — are value-SIZE/padding
   disagreements, NOT repr (the predicate says inline for both; the residual size split is
   owned by the size authority = step 2 freeze, not the repr bit). Open for 1c: nilable-
   reference unions (`String?`) — predicate currently says inline-16 (union>8), but the correct
   repr may be an 8-byte nullable pointer; decide when wiring the union reader. Next: ABI-1b
   (route LayoutProbe storage LABEL through `LayoutContract.repr`, drives label CROSS→0, zero
   size change — also the runtime exercise/verification of the predicate).

ABI-1c FIELD-READER HALF (2026-06-16, SHIPPED — centralize the struct-carrier threshold,
   behavior-NEUTRAL). New `LayoutContract.user_struct_inline?(size, name)` is THE single
   step-4 flip point for the non-lib struct-value carrier decision (today:
   `inline_container_family?(name) || size >= POINTER_WORD_BYTES`). HIR
   `field_storage_size_impl` (ast_to_hir.cr:~39420) now routes its small-struct →
   8-byte-pointer-carrier decision through this predicate instead of the hardcoded
   `storage < pointer_word_bytes_i32` outer-guard threshold (the guard drops the size test;
   the `return pointer_word` is gated `unless user_struct_inline?`). `inline_value?`'s struct
   clause delegates to the same helper. Result: the size split that step 4 flips for the
   inline-struct perf win now lives in ONE place, read by HIR. SPLIT vs the SDD §6 plan: the
   SDD bundled 1c as container-oracle flip + field-reader delegation; I split them — flipping
   `inline_container_struct_type?` (the LLVM container whitelist) alone CORRUPTS Array(Big)
   (Array get/set/push assume pointer stride), so that flip MOVES into step 4 (needs the
   inline Array stride/get/set/push ABI). 1c here is field-readers ONLY. Behavior-neutral
   proof: reproduces the prior threshold exactly (container families are empirically inert in
   this HIR branch — not registered is_struct); probe SLOT-CONFLICT set IDENTICAL (17 types);
   reducers byte-identical (largefield total=6, slice/small/union correct, StaticArray sa0=152
   = unchanged PRE-EXISTING by-value corruption bug, a separate #4-adjacent lead). Gate on the
   post-change binary: combined 31/31 + originals 158/158. Per owner directive
   ([[abi-slot-conflict-metric-invalid]]): consolidation is the path toward the inline-struct
   perf win (step 4), #4 fixed opportunistically on clean moves. Next consolidation: route MIR
   `mir_field_storage_size` through the contract (affects only the coverage-check optimization,
   behavior-safe); then ABI-1b (probe label unification); update SDD §6 to record this split.

StaticArray-by-value FIELD store fix (2026-06-16, SHIPPED — a clean #4-adjacent move that
   the ABI-1c note flagged as the "unchanged PRE-EXISTING by-value corruption bug, sa0=152").
   Root: `StaticArray(T, N)` stored by value into a class field wrote the SOURCE POINTER's low
   bytes into the inline slot instead of the value bytes. `register_class_types` registers
   StaticArray MIR entries as zero-sized Structs (kind=Struct, size=0 — StaticArray has no
   ivars), and `canonical_container_kind_for_descriptor` only matches `"Array("`, so the
   FieldSet memcopy decision read `struct_size=0`, hit the `if struct_size > 0` guard, skipped
   the memcopy, and fell through to a scalar `store ptr`. Fix (hir_to_mir.cr): new shared
   `static_array_storage_size_from_name(type_name)` derives the inline byte count
   (element-storage-size(T) * N) from the type name — the SINGLE source used by both the Alloc
   size path (refactored, behavior-neutral) and the FieldSet memcopy `elsif is_static_array`
   branch, so they never disagree. Kept surgical (compute at the consumer, NOT in the registry):
   globally sizing the registry would flip `inline_container_struct_type?` (gated on `size > 0`)
   to a 4-byte inline element stride for StaticArray container elements — a CAUTION-tier
   Array(StaticArray) regression — so the registry stays size=0. IR proof:
   `store ptr %sa` → `call void @llvm.memcpy.p0.p0.i64(ptr %r3, ptr %sa, i64 4, i1 false)`;
   reducer now `sa0=7 sa3=9` (was 232/1). Regression: `static_array_field_value_roundtrip.cr`
   (EXPECT inner0=7 inner3=9 getter0=7 getter3=9 marker=2222). Gate: combined 31/31 + originals
   158/158.

0. (2026-06-02) M4h family root-caused + narrow fix landed (`2444b2e0`, COMPLETED not
   VERIFIED). The s2b `union_all_reference_types?` SIGSEGV is a short-TypeRef Hash value
   confusion: the resolver minted a SHORT ghost identity for compiler-internal `MIR::X`/`HIR::X`
   (anchored short-circuit in `resolve_type_name_in_context_impl`), whose hash/==/id are never
   materialized. M4h2b canonicalizes {MIR,HIR}::{TypeRef,UnionDescriptor} to FQ before the
   short-circuit (134 canon, combined 31/31). **Blocked on TWO pre-existing bootstrap issues
   before the union fix can be validated on a running s2b** (both proven NOT caused by M4h2):
   (a) [FIXED — M4i0] a freshly-built RELEASE stage1 SIGSEGV'd in the parser
   (`parse_block_body_with_optional_rescue`) building s2b: `crystal build` links with ld64.lld
   which IGNORES `-stack_size`, so stage1 got the default 8MB main stack and the recursive
   parser overflowed on the large source. Fix in `scripts/build_stage1_original_cached.sh`:
   on Darwin force `--link-flags="-fuse-ld=/usr/bin/ld -Wl,-stack_size,0x4000000"` (system ld
   honors it -> 64MB). Validated: recipe s1b otool stacksize=64MB; release s1b builds s2b
   (S2B_EXIT=0); s2b inherits 64MB via cli.cr's clang->system-ld. The M4h2 release s2b no
   longer crashes at union_all_reference_types? — frontier moved to (c).
   (b) debug s2b dies at startup on the `Crystal::Hasher` null-self blocker (deprioritized;
   release corridor is the target).
   (c) [FIXED — M4i1b `2b95eae2`] M4i1 was NOT arena: the release s2b abort in
   `set_synthetic_main_definition_location` was `STUB CALLED: HIR::Function#definition_location=`
   — the SAME short ghost-identity class as M4h, where the narrow M4h2b allowlist left
   `HIR::Function` (and other compiler-internal MIR/HIR types) as unmaterialized ghosts. Fix:
   re-widen `registered_compiler_nested_type_alias` to the whole MIR/HIR family (drop the narrow
   allowlist; keep the `type_name_exists?("Adamas::<name>")` guard that protects user programs).
   474 canon, HIR::Function present, adversary 0 outside MIR/HIR, combined 31/31. s2b on `puts 1`
   no longer aborts on the setter and now progresses INTO lowering the actual `puts 1` call.
   (d) NEW frontier (M4i2) — ROOT VERIFIED by ASAN (M4i2c): the floating, non-deterministic s2b
   crash (seen at lower_call / collect_return_types / CLI#compile across builds) is a
   `heap-buffer-overflow READ of size 8` in `Array(Adamas::HIR::TypeRef)#dup` (-> memcpy). The
   calloc buffer is 4 bytes; dup reads 8 bytes 0-after it. `HIR::TypeRef` is a 4-byte struct
   (`id : Int32`) but dup/memcpy uses an 8-byte ELEMENT STRIDE -> over-read of adjacent heap ->
   garbage -> floating downstream crashes. Allocated in lower_call (+0x179d8). So it is an
   Array-of-struct element-size/stride codegen bug (CLAUDE.md "element stride"/struct-as-pointer),
   NOT arena-lifetime or a null ExprId. M4i2c milestone file-probe was FALSIFIED (probe shifted the
   crash; reverted). ASAN via ADAMAS_EXTRA_LINK_FLAGS=-fsanitize=address works (no GC conflict).
   M4i2d (FIXED, VERIFIED): precise root was `lower_array_map_dynamic` /
   `lower_array_map_with_index_dynamic` (ast_to_hir.cr) emitting the result `ArrayNew` with the
   SOURCE element stride while storing the BLOCK-RESULT values. The s2b case:
   `arg_value_ids.map { |id| ctx.type_of(id) }` — source `Array(ValueId)` (4-byte inline UInt32),
   result `Array(TypeRef)` (8-byte heap ptr). Buffer malloc'd count*4, stores at stride 8 ->
   heap overflow read later by `dup`. NOT a dup/ExprId/tuple/union storage change and NOT the
   global inline-struct ABI: the container-storage helpers were already correct (TypeRef->8,
   ValueId->4) and the generic Array(TypeRef) corridor was uniformly 8-byte. Fix: HIR::ArrayNew
   `element_type` is now settable; both dynamic-map lowerings patch `new_array.element_type =
   set_type` once the store type is known, so alloc==store==read/dup stride. Evidence: s2b IR
   lower_call ArrayNew strides 11x4/23x8 -> 2x4/29x8/3x1; ASAN `puts 1` heap-buffer-overflow in
   Array(...TypeRef)#dup GONE; combined 31/31; 4 p2 stride guards green (ExprId stays 8); no
   regression (HEAD and fix crash at the same pre-existing frontier). See LM-M4i2d.
   Adversary-scan clean: source->result stride class closed for map/map_with_index only;
   select/reject (source->source), zip (tuple_type), hash keys/values are all correct.
   M4i3 (FIXED): tuple container storage policy for Array/Slice + Pointer#value=. Root:
   Slice#[]=/insert_head!/merge! used Array object layout (buffer @ offset 16) on Slice
   values (@pointer @ offset 8); insert_head! stored through null. Also: ref-carrying
   Array(Tuple) and merge `out.value=` must use pointer slots / store ptr, not memcpy
   tuple body into slots; primitive Array(Tuple) literals now memcpy inline into buffers
   (LM-663). Evidence: lldb `insert_head!` null deref fixed; `Array(Tuple(UInt32,UInt32))`
   sort repro prints 1,2,3; no-prelude `arr[0][1]` prints 3; combined 31/31; p2 stride
   guards green. See LM-M4i3.
   M4i5 (FIXED): split String `#hash` ABI (bare UInt64 vs typed `Crystal::Hasher`
   protocol) and compute HIR tuple/named-tuple field storage sizes for Hash::Entry
   layout. This removed the String-hash ABI corruption and the
   `Hash::Entry(Tuple(String, UInt64, UInt64, Int32), Set(String))` 32-byte key memcpy
   into a 24-byte entry body. Evidence: combined 31/31, String#hash reducer, tuple-sort
   reducer, p2 storage guards, direct s2 compiler build, and ASAN no longer reporting the
   old Hash::Entry initialize overflow.
   M4i6a (FIXED/VERIFIED advance): constructor return-type pinning in `lower_call` no
   longer uses `owner_candidates.uniq!`, `sort_by! { ... }`, or `find { ... }`; it
   preserves FQ-first/dedup/class-info/type-ref semantics with explicit while loops. This
   removes the ASAN `lower_call+0x690f8` null deref through the
   `Array(Tuple(String, Int32))#sort!$block` corridor. Evidence: host build, combined
   31/31, p2 guards, tuple-sort reducer, ordinary `puts 1` compile/run green; ASAN s2b
   advances past the old null deref. NEW frontier M4i6b: ASAN now reports
   `__adamas_ptr_copy+0x14` heap-buffer-overflow after `lower_main` (source allocation
   8 bytes, caller frame missing). Next step: add an env/file probe to `__adamas_ptr_copy`
   with return-address, src/dest/count/elem_size, then map the caller to source.
   M4i6b (FIXED/VERIFIED advance): `__adamas_ptr_copy` return-address probe mapped the
   ASAN over-read to `Array(Adamas::HIR::TypeRef)#[]?(Int32, Int32)`, called through
   `Array(TypeRef)#[]?(Range)` from inlined TypeRef tail slices in `lower_def` and
   `lower_module_method`. The accepted fix avoids the generic Range slice corridor for
   compiler-internal TypeRef tails: `type_ref_array_tail` manually copies tail elements
   using `type_ref_array_fetch_or_void`, and the known TypeRef `[1..]` sites now use it
   (`expand_flat_block_param_types`, unbound instance wrappers, inline-yield tuple
   expansion, proc tuple destructuring). Evidence: host build green, combined 31/31,
   p2 tuple/stride guards green, tuple-sort reducer compile/run prints 1/2/3, ordinary
   `puts 1` compile/run prints 1; ASAN s2b `puts 1` no longer reports the old
   `Array(TypeRef)#[]?` heap-buffer-overflow and advances past `lower_main`. NEW
   frontier M4i6c: null `String#bytesize` after `lower_main` (`x0=0`, read at 0x4),
   likely a separate null String/metadata corridor.
   M4i6c (FIXED/VERIFIED advance): advisory enum-value tracking now rejects a null
   generated `String` before calling `String#empty?`. The lldb/ASAN frontier before
   the fix was `String#bytesize -> String#empty? -> AstToHir#track_enum_value ->
   lower_method -> lower_function_if_needed_impl`, with the `String` receiver null.
   This path only records enum metadata for values, so skipping a null type name
   preserves non-null behavior and avoids treating corrupted/absent metadata as a
   real enum type. Evidence: host build green, combined 31/31, p2 tuple/stride
   guards green, tuple-sort reducer compile/run prints 1/2/3, ordinary `puts 1`
   compile/run prints 1; ASAN s2b `puts 1` no longer reports the old
   `String#bytesize`/`track_enum_value` crash and advances to
   `Set(Adamas::HIR::ValueId).new` after `lower_main`. NEW frontier M4i6d:
   null deref inside `Set(ValueId).new`, likely another compiler-internal
   collection/storage corridor.
   M4i6d (FIXED/VERIFIED advance): after M4i1b broad canonicalization,
   root-qualified compiler id sets use `Adamas::HIR/MIR::*` names, but backend
   UInt32-alias delegates still recognized only short/`Crystal::HIR/MIR::*`.
   As a result `$CCSet$LAdamas$CCHIR$CCValueId$R.new` was emitted as the raw
   `Set(UInt32).new(initial_capacity)` path and read the nil default-capacity
   pointer as an `Int32`. Fix: extend compiler UInt32-alias set/key-hash/TypeRef
   delegate recognition to `Adamas::HIR/MIR::*`. Evidence: host build green,
   combined 31/31, p2 tuple/stride guards green, tuple-sort reducer prints 1/2/3,
   ordinary `puts 1` compile/run prints 1; ASAN s2b `puts 1` no longer reports
   the old `$CCSet$LAdamas$CCHIR$CCValueId$R.new` null deref, and IR now emits
   that root alias as a delegate to `Set(UInt32).new(nil capacity)`. NEW frontier
   M4i6e: ASAN heap-buffer-overflow in
   `Array(Tuple(String, Adamas::HIR::TypeRef, Nil|Int64, Nil|String,
   Nil|Adamas::HIR::SourceLocation))#push`, reading 64 bytes at the end of a
   64-byte buffer.
   M4i6e (PARTIAL): call arguments with tuple source/parameter shape mismatches
   now try `try_coerce_tuple_to_tuple` before numeric casts in
   `coerce_args_to_param_types`. Host gates were green, but hostile lldb/IR
   review later showed one remaining lazy `Array#<<` path: the receiver was
   `Array(Tuple(...wide...))`, while the selected method suffix was still
   derived from the narrow source tuple, so parameter-only coercion was a no-op
   and the backend later normalized the call to the wide container slot.
   M4i6f (FIXED/VERIFIED advance): container writes now coerce the stored value
   to the receiver container element type before emitting `Array/Slice#<<`.
   This rebuilds `Tuple(String, HIR::TypeRef, Int64, String?,
   SourceLocation?)` into the declared storage layout
   `Tuple(String, HIR::TypeRef, Int64?, String?, SourceLocation?)` before
   `Array#<<`, instead of passing a narrow heap tuple to a wide tuple container.
   Evidence: host build green, combined 31/31, p2 tuple/stride guards green,
   tuple-sort reducer compile/run prints 1/2/3, ordinary `puts 1` compile/run
   prints 1, ASAN stage2 build succeeds, and ASAN s2b `puts 1` no longer reports
   the old `Array(Tuple(...SourceLocation))#push` heap-buffer-overflow. NEW
   frontier M4i6g: ASAN SEGV/null read in
   `Slice(UInt8)#cmp(Tuple(String, Int32), Tuple(String, Int32), Proc)` while
   compiling s2 `puts 1`.
   M4i6g (FIXED/VERIFIED advance): block forwarding now recognizes the same
   mangled block suffix forms as the resolver (`$block`, typed `_block`, and
   arity/splat variants) and forwards `&block` as a heap Proc carrier, not as a
   raw function pointer. Root: `Array(Tuple(String, Int32))#sort!$block`
   forwarded a null block to `Slice#sort!$block`; the first raw-forwarding
   experiment changed that to a high-PC BUS because `Slice#cmp` expects a heap
   Proc object `{fn, env}` and read machine-code bytes as the Proc header.
   Evidence: final host build green; ordinary `puts 1` compile/run prints 1;
   IR for `Array(Tuple(String, Int32))#sort!$block` allocates a Proc object,
   stores `%block` at offset 0 and null env at offset 8, then calls
   `Slice#sort!$block` with that object; tuple-sort reducer compile/run prints
   1/2/3; p2 tuple/stride guards green; combined 31/31. ASAN s2 `puts 1` no
   longer reports the old null/raw block ABI frontier and advances past
   `lower_main`. NEW frontier M4i6h: invalid/wild `MIR::Type*` in
   `MIR::Type#add_element_type` during `HIRToMIRLowering#register_tuple_types`
   (lldb sample: `self=0x559`), and a separate ASAN sample saw a packed/wild
   `HIR::TypeRef` in `HIR::Module#get_type_descriptor`; treat this as the next
   tuple/type-descriptor memory/layout frontier, not as a block forwarding bug.

0b. (2026-06-02) M4j0 — DWARF debug-info emitter generates DUPLICATE metadata IDs, blocking
   `-g` s2b debugging. Repro: `ADAMAS_DEBUG_EMIT=1 scripts/build_stage2_cached.sh release <stage1>
   /tmp/s2b_dbg` fails at LLVM opt:
   `error: Metadata id is already used !... = !DILocation(line: 14130, column: 15, scope: !...)`.
   `llvm_backend.cr` has a `unique_location_id`, so this may be a cross-section / global metadata
   ID collision rather than a plain DILocation duplicate. SEPARATE diagnostic from M4i2 — do NOT
   let it gate the bootstrap; it only matters as a tooling unblock (would give source lines for
   runtime crashes like M4i2). Pursue only if the M4i2 file-probe does not pin the source.

1. Root-cause the generated-stage2 full-prelude plain-smoke frontier now past
   registration-time block/yield body inference. The enum/class body-inference
   corridor was advanced by: typed `ArenaLike` resolution for
   `infer_concrete_return_type_from_body_inner`, source-backed explicit return
   recovery for enum methods whose self-hosted `return_type` field is lost,
   skipping body-return inference for unannotated enum yield/block methods, and
   a central `infer_concrete_return_type_from_body` guard that refuses to walk
   defs requiring caller block context (`yield` or direct implicit
   `&block.call`). Current evidence:
   `/tmp/cv2_bs_s2_module_name` builds `s2` in ~237s and passes no-prelude
   smoke. Plain smoke still fails, but the wide registration-helper
   abort-stub corridor is advanced: `record_nested_type_names` now threads an
   explicit `ArenaLike`, annotation registration call sites explicitly cast
   proven `AnnotationNode` values, default include debug probes are gated behind
   `DEBUG_REG_CONCRETE_PHASE`, and the class include expansion call now passes
   exact `ArenaLike`/`Set(String)` contracts. The tuple-key alias-cache crash
   is also advanced by replacing `Hash({String, ...}, String)` alias caches
   with nested String-key maps and by rewriting `module_name_from_node` to avoid
   a lambda/map/reject block that lost captured `self` in generated stage2.
   The `body_ids_match_arena?` nilable-array frontier is also advanced by
   splitting the nilable wrapper from the non-nil `Array(ExprId)` arena-fit
   scan and adding a raw low-pointer guard. The later generated-s2 LLVM
   frontiers around broad union/concrete comparison and `Pointer(T)` parameter
   scalar classification are advanced by LM-568. The primitive `each_key`
   fallback-stub LLVM shape is advanced by LM-569: produced `s2` now builds,
   and the old `Float32$Heach_key$$block(float %arg0, ptr %arg1) ret ptr %arg0`
   verifier failure is guarded by a fast no-prelude oracle. The
   `Slice(T).literal` primitive return/lowering contract is advanced by LM-570:
   the old FastFloat `POWER_OF_FIVE_128` null table no longer appears in
   produced-s2 LLVM. Current produced-s2 full-prelude `puts 42` now advances
   past the FastFloat segfault and aborts at
   `STUB CALLED: EquivUint$Dnew$BANG$$UInt64` during early prescan. A produced-s2
   no-prelude `Slice(UInt64).literal` reducer also exposes a separate
   `Indexable$LT$R$Hequals$Q$$Indexable_block` abort before it can be used as a
   produced-stage guard. LM-651 additionally fixes the `Pointer(Void)` byte
   stride/root allocation invariant and guards it against the prior typed-array
   stride regressions. LM-652 additionally fixes the nested generic
   `Pointer::Appender(T).new(pointer)` constructor path: the specialized
   receiver is preserved through path normalization, and LLVM only applies the
   primitive pointer-address constructor shortcut to real `Pointer` receivers.
   Produced s2 still builds, but full-prelude `puts 42` still exits 139 after
   reaching later `Float` module registration; localize that remaining
   memory-corruption frontier before widening to s3b.

   M4i6i (FIXED/VERIFIED advance, 2026-06-27): the Hash default-provider
   block-wrapper frontier is advanced. Root was a three-part shape/materialization
   mismatch: block wrapper specialization was still opt-in, allocator `.new`
   fallback could keep arity-only initializer names even when typed call args
   were available, and raw block callbacks materialized as heap `Proc` values
   were passed bare to `Nil | Proc(...)` parameters instead of being wrapped as
   the non-nil union arm. Fix: enable block shape specialization by default
   (still disableable with `ADAMAS_BLOCK_SHAPE_SPECIALIZE=0`), preserve typed
   allocator initializer names when an arity match has exact typed args, trace
   raw callback sources through `Copy`/`Cast`/`UnionWrap`, materialize them as
   heap Proc objects, and immediately coerce materialized Proc values to the
   target union when needed. The raw callback source walker is bounded and
   allocation-free to avoid self-host `Set(ValueId)`/block iterator fragility.
   Evidence: new `hash_block_shape_default_proc_repro.sh` prints `A=1`/`B=0`;
   `hash_default_provider_proc_repro.sh` green; pointer-filled Array negative
   control green; full suites green (`151/151` originals + `36/36` combined);
   ASAN stage2 bootstrap builds and full-prelude plain smoke now passes. Remaining
   frontier is generated-stage2 no-prelude smoke:
   `EscapeAnalyzer#build_summary` null write under ASAN. Do not claim s2b/s3b
   green until that no-prelude frontier is localized.
2. Root-cause the remaining full-prelude nested-class return-inference crash
   under generated stage2. Current evidence: stale parameter slice frontiers are
   advanced through source-backed initializer capture, source-prefiltered
   implicit-ivar param scanning, and source-backed nested-module method params.
   The latest lldb frontier is now `infer_type_from_expr_inner` from
   `infer_concrete_return_type_from_body` while registering
   `Float::Float::Bigint` through the reparsed/generic nested-class corridor.
   First determine why registration is doing eager body inference there, and
   add a focused no-prelude oracle before changing the inference policy.
3. Run the generated-stage2 compiler on the broader fixed no-prelude corpus and
   add focused oracles for any new first failure.
4. Compare `s1_bootstrap` and `s2b` on the fixed no-prelude corpus before
   trying `s3b+`.
5. Audit remaining compiler hot paths that use tuple block destructuring or
   block `join` formatting; keep the general tuple-block fix as an explicit
   follow-up rather than hiding it with one-off stubs.
6. Add/inspect exact-called provenance for `record_pending_callee_for_rta` so
   the source of remaining `keep:exact_called Array#to_s` / `Hash#to_s` demand
   is explicit.
7. Verify whether broad fallback self-calls should mark exact concrete wrapper
   names as demanded, or whether they should remain virtual/demand-local until a
   real callsite asks for that concrete owner.

### Session 27: repeated "missing stub" roots (LM-672/673, 2026-07-09)

The `__crystal_block_proc_51` link failure exposed two upstream state-supply
bugs. Neither root was a missing-stub policy gap:

1. `HIR::Module#remove_function` trusted the value returned by `Hash#delete`.
   Generated V2 borrows inline `Hash::Entry` storage; `delete_impl` clears that
   storage before consuming the value-typed return, so the key disappeared but
   the returned `Function?` became nil. The stale row remained in `@functions`
   while `@functions_by_name` lost it. Re-materialization then produced duplicate
   callers, RTA followed the last row, and HIR-to-MIR kept the first row with
   pruned block-proc targets. The bounded fix snapshots the Function through a
   non-mutating lookup before deleting the key.
2. Entry boxes survived branch-local snapshots by name. A terminating branch
   boxed `matching_type_ids : Set(UInt32)`; the fallthrough later assigned
   `Array(UInt32)` to the same source name. The stale name-only box swallowed
   the assignment, skipped the new local binding, and forced
   `Array(String)#<<$String` in host HIR. A mismatched box whose owner local is no
   longer visible is now discarded before creating the fallthrough binding.

Verified bounded signals: exact HIR registry insert/lookup/remove/re-add
contract passes; early-return captured-local HIR and runtime contract passes;
filtered stage2 has one `Array(String)#to_s` body, zero dangling block-proc
FuncPointers, and compiles/links both the Array-to-s reducer and the tuple
destructure reducer. Residual: the tuple binary exits 0 with no output instead
of `65`/`3`, and the Array-to-s binary reaches the explicit
`Crystal.trace(Symbol, String, UInt64, Int32, &block)` abort stub. Treat these as
new runtime/value-supply floors. Do not restore a stub or materialization
allowlist until the first missing semantic value is localized.

Systemic follow-up: audit the small set of compiler `Hash#delete` calls that
consume the returned value (`file_loader`, LSP maps, block captures, type-cache
buckets). Pointer-backed structs need a real copy-on-read/borrow contract; the
registry ordering fix is intentionally bounded and does not claim the global
Hash::Entry value ABI is solved.

### Session 27 follow-up: generated Hash compaction regression (2026-07-31)

The `8faaea47` return-order refinement admitted `Hash#each_entry_with_index`
into direct yield inlining because its only explicit return precedes the first
yield. Inside `Hash#do_compaction`, the yielded block mutates the caller's
`new_entry_index`; the nested `upto` loop then reused that branch-local update
on the skipped/deleted-entry path. At the 16-to-32 entry growth boundary,
compaction cleared live entries from offset zero while indices pointed at stale
rows.

Keep the early-return optimization for blocks that do not mutate visible caller
locals. For the narrower early-return plus caller-mutation shape, retain the
closure path until direct inline lowering carries branch-local loop-backedge
state explicitly. The exact generated HIR registry remove/re-add fixture and
the generated nilable-value Hash resize fixture now pass; the full HIR suite
passes 366 examples with 0 failures/errors and 2 existing pending examples.
This closes the registry/Hash compaction regression only; it does not close the
separate formatter specialization residual or the full B4-F bootstrap gate.

Adversary hardening keeps the fallback conservative without broadening the
loop-phi assignment collector: block parameters and block-local assignments are
excluded from captured mutations, while caller-local assignments plus `until`,
`for`, `select`, proc/spawn, macro, and unknown wrapper shapes retain the
closure path. The focused HIR contract covers a nested `until` mutation, a
caller assignment in a condition, a pure block-local assignment, and top-level
plus nested same-name block-parameter shadows. The residual cost is lost
direct-inline coverage for unclassified AST shapes.

Formatter follow-up: concrete generic arguments are now accepted by matching
bare generic arms of a union parameter, so `Tuple(Float64)` can materialize the
real `String::Formatter(Tuple(Float64))` specialization. Before lowering a
short-circuit condition body, HIR now folds the narrow proven-false
`Float64.is_a?(Hash | NamedTuple)` guards used by the formatter. The generated
stdlib HIR contract requires both `arg_at(String)` and the Float64 formatter
body while rejecting the impossible `Float64#[](String)` demand; focused unit
contracts retain legal Hash and NamedTuple indexing.

Nested-struct follow-up: an inherited `Object` convenience wrapper requested
for a concrete runtime generic reference owner now retains that exact owner
when the source wrapper delegates to another overload of the same method. This
makes `Array(Outer::Inner::Point)#inspect` lower with `self : Array(Point)` and
preserves the real stdlib chain through `Array(Point)#inspect(IO)` to the static
`Point#inspect(IO)` call. A negative control keeps a non-delegating inherited
`Object#stable` body with a same-name local under `self : Object`, bounding the
new admission rule to actual self calls instead of identifier-token matches.
The old generated assertion for `Point#inspect()` was retired: the original
Crystal compiler does not emit or call the zero-argument Point wrapper for
`[Point].inspect`; `Array#to_s(IO)` invokes the element overload directly. The
corrected semantic owner gate is RED on the pre-change compiler and GREEN on the
current compiler.

String::Builder follow-up: an explicit wrapper-derived corridor now admits the
exact `String::Builder` call-site type only at `inspect(io : IO)` and
`to_s(io : IO)` boundaries; ordinary specialization may then materialize their
transitive helpers such as `join`. The real stdlib chain materializes and calls
`Array(Point)#inspect(String::Builder) -> Array(Point)#to_s(String::Builder) ->
Point#inspect(String::Builder)`, matching the original Crystal specialization
oracle while retaining the existing `$IO` functions and calls. A focused
negative control keeps an unrelated `render(io : IO)` method at `$IO`, bounding
the rule away from general reference-subtype specialization. On the real
fixture, the corridor emits 3946 functions versus the 3864-function baseline
(+2.1%); the rejected global name-family candidate emitted 4130 (+6.9%). The
full HIR suite is green at 371 examples with two existing pending examples; all
nine generated integration examples pass. Full nested-fixture execution still
reaches the pre-existing
`Fiber#exec_recursive_hash` startup crash, so this slice proves Builder parity
through semantic HIR demand rather than end-to-end runtime readiness.

Concrete Tuple call-owner follow-up: a value receiver whose HIR descriptor is
`Tuple(...)` now specializes a resolved inherited method target to that exact
owner before materialization. Root: `String::Formatter(Tuple(Float64))#arg_at`
selected `Indexable(T)#fetch`, but emitted the target as bare
`Tuple#fetch$Int32_block`; its nested `unsafe_fetch` therefore returned `Int32`
despite a `Tuple(Float64)` self parameter. The real stdlib HIR gate now requires
`Tuple(Float64)#fetch$Int32_block` and its exact
`Tuple(Float64)#unsafe_fetch$Int32` call. A safe runtime regression proves that
the fetched value remains `1.25_f64` and that `%s` formatting no longer crashes.
A fresh replay also invalidates the stale `Fiber#exec_recursive_hash` residual:
the remaining formatter frontier is independent float formatting (`%f` emits
`0.000000`; `%.3f` raises from `consume_type`).

Deferred constant class-call follow-up: non-numeric constant initializers now
carry a separate lexical owner while they are lowered into `__adamas_main`.
Unqualified calls bind to a declared class/module method on that owner without
changing the surrounding method context, and the late module-instance rewrite
does not convert that proven dot target back to `#`. This materializes the real
`Float::Printer::RyuPrintf.put` calls used to populate `POW10_SPLIT` instead of
leaving its tuple rows zero-filled. A broader `@current_method_is_class`
candidate was rejected because it corrupted inline-block locals in
`Exception::CallStack::CURRENT_DIR` and fed a null `self` into `Path[]`.

The module-scoped regression covers a deferred initializer containing both a
bare class-method call and a nilable inline block; its HIR retains the dot call,
the union payload, and no synthetic `self`. The generated formatter runtime now
proves `%s` plus `%f`, with `1.25_f64` rendered as `1.250000`. The full HIR suite
passes 372 examples with zero failures/errors and two existing pending examples;
all ten generated integration examples pass. This closes plain `%f` table
initialization only. `%.3f` still aborts from `String::Formatter#consume_type`
and is the next formatter frontier; B4-F remains independently red.

Formatter precision follow-up: MIR lowering now treats a concrete HIR `yield`
type as the callback ABI when an unannotated block parameter has retained a
stale `Proc(..., Nil)` or `Proc(..., Void)` return descriptor. Previously
`Char::Reader#decode_char_at` invoked a generated `Char` callback as returning
`Nil`, discarded the return register, and wrapped that zero value as `Char`;
`String::Formatter#consume_precision` therefore advanced its reader to `3` but
saw `next_char == '\0'`, skipped `consume_number`, and rejected `%.3f` in
`consume_type`. Ambiguous Proc-union callback descriptors remain fail-closed.
The focused MIR regression proves the indirect call returns `Char`, and the
real formatter runtime now additionally renders `sprintf("%.3f", 1.25_f64)` as
`1.250`. B4-F remains independently red.

## Stop Conditions

- Do not run `s3b+` until generated `s2b` passes plain/no-prelude smokes and
  normalized corpus comparison is green.
- Do not increase timeout or memory to hide pending expansion.
- Do not modify stdlib/runtime.
- Do not land another name-family guard unless it measurably reduces the
  `~61k` process-pending expansion.
- If two more bounded containment fixes fail, pivot from heuristics to explicit
  demand-provenance design.

## Strategic Track

Architecture target:

- `PLAN_DEMAND_DRIVEN_REWRITE.md`
- `PLAN_DEMAND_DRIVEN_REWRITE_RFC.md`

Current short-term track: bootstrap containment plus fast no-prelude oracle
coverage, not a full compile-path switch.

### Session 28: `Array#uniq` large-branch resolver/materialization split (LM-675, 2026-07-12)

The previous `Array(T)#uniq` floor is now split into two independently measured
transactions.

Closed structural slice:

1. Bare included-module identifiers now use recursive module AST fallback after
   registry fast paths, matching explicit-receiver calls.
2. Deferred module lookup no longer returns its `DefNode`/arena through
   captured assignments inside `Set#each`; it uses ordered Array collection and
   an indexed loop.
3. Fresh generated s2 HIR has real `Array(T)#to_set` and `Set(T)#to_a` bodies and
   no `Local<Void>` or abort stub for `to_set`.

Active successor:

- generated `Hash(K, Nil)#upsert` loses every expression after its first
  non-void nested materialization;
- 16-element `Array#uniq` branches are correct;
- 17-element UInt32 returns an empty result and 17-element pointer-backed
  TypeRef segfaults because insertion/size supply is absent;
- Array, scalar, and raw-pointer sequence-ledger substitutions were all fresh-
  rebuilt and refuted. Do not try a seventh carrier wrapper.

Next legal work:

1. Distinguish a true overwrite from re-entrant same-symbol lowering at the
   `lower_method` pre-scan/body-loop boundary. Prefer a write/provenance probe
   or phase stop gate; avoid debug output that changes inference behavior.
2. Add a produced-stage structural fixture for `leading if -> non-void helper ->
   mandatory tail`; keep the host HIR spec as the fast unit layer.
3. After the tail is present, require `Hash#upsert` HIR to contain `key_hash`
   and `add_entry_and_increment_size`, then run the 16/17 UInt32/TypeRef runtime
   matrix.
4. Only after those gates are green, run the full
   `spec/bootstrap/produced_stage_bootstrap_spec.cr` and normalized s1b-vs-s2b
   HIR/MIR/LLVM comparison.
5. Do not attempt s3b until produced s2 passes plain/no-prelude smokes, the full
   produced-stage spec, and the normalized semantic corpus.

Test policy from this floor:

- `spec/*` phase-local tests are the primary fast regression layer;
- produced-stage structural/runtime fixtures prove self-host behavior that host
  specs cannot exercise;
- standalone regression scripts are reducer/probe tools, not the only durable
  regression oracle;
- every stage artifact manifest must record source hash, compiler hash, flags,
  and build time so mixed-generation evidence cannot masquerade as convergence.

### Session 29: receiverless `case` subjects must not become locals (LM-676, 2026-07-13)

The generated parser's escaped-character call-argument failure is closed at
its lowering root. `lower_case` inferred a subject local from the ambient HIR
locals map. That map may contain a cached result for a prior receiverless method
read, so `case current_byte` was treated like `case byte`: later
`current_byte` reads after `advance` copied the stale case subject and left the
closing quote unconsumed. The fix accepts a bare case-subject identifier as a
local only when lexical evidence exists (an assignment in the current method or
a function parameter). Assignment and type-declaration subjects retain their
existing narrowing behavior.

Evidence:

- the focused HIR spec is RED on the old implementation (`1` receiverless
  `current_byte` call instead of `2`) and GREEN on the fix; the full file passes
  237 examples with 0 failures and 2 existing pending examples;
- a fresh original-Crystal-built s1 (`b9361ad5...`, ~572s) emits the correct
  Identifier/LParen/Char/RParen/EOF token sequence for `foo('\\0')`;
- the generated parser probe reports zero diagnostics for `foo('\\0')`;
- `stage2_char_literal_parse_repro.sh` now covers `\\0` and `\\1` call
  arguments and passes against that fresh s1.

Rejected routes remain useful: explicit dotted indexer runtime dispatch and the
production `ArenaLike = AstArena | VirtualArena | PageArena` ordering both pass
generated probes and are not the parser root. A pre-fix s1 cannot validate this
compiler change merely by requiring the new source: lowering is performed by
the AstToHir implementation already embedded in that compiler.

Next legal work: build one fresh s2 with the LM-676 source, rerun the plain
`puts 1` oracle, and record the first successor before widening to the full
produced-stage suite. Do not claim s2b or s3b from the parser gate alone.

### Session 30: case-local provenance restores macro helper materialization (LM-677, 2026-07-13)

The first fresh s2 after LM-676 built successfully but made the next missing
body explicit while compiling `puts 1`:
`CLI#macro_condition_call?(AstArena, Node, Set(String),
MacroReflectionEvaluator)`. Final HIR showed the `IsA(CallNode)` check but no
narrowing cast; the helper call kept `Node`, so no matching specialization was
materialized. The lexical-only classifier from LM-676 was insufficient when
generated re-entrant lowering temporarily had no reliable assigned-var stack.

The classifier now combines lexical evidence with a bounded, allocation-free
walk through `Copy`/`Cast` provenance. A value ending in a method call with the
same source name (`current_byte -> Cursor#current_byte`) is a cached
receiverless read, while a local initialized by a differently named call
(`node -> AstArena#[]`) remains a local and can be narrowed.

Evidence:

- `spec/hir/ast_to_hir_spec.cr` passes 238 examples with 0 failures and 2
  existing pending examples, including direct provenance positive/negative
  controls;
- pre-fix full HIR calls `macro_condition_call?` with `Node` and contains no
  helper body; post-fix full HIR calls it with `CallNode` and contains real
  AstArena and PageArena specializations;
- source-matched s1 SHA-256 is `ec0bef7e...`; its s2 SHA-256 is `18b56da2...`,
  and both build successfully under the safe wrapper;
- the old macro helper abort is gone. The unchanged `puts 1` oracle now reaches
  a later silent runtime failure after about one second and produces no
  consumer artifact.

Next legal work: localize the new post-macro-helper failure with a structural
phase oracle, preserving untraced output as authority. Do not reintroduce the
old Node-typed stub or count the moved failure as s2b success.

### Session 31: inherited generic virtual-wrapper reuse (LM-679, 2026-07-14)

The missing concrete virtual-target repair was caused by two related naming
mistakes. Early replay treated a concrete generic owner spelling as a distinct
implementation whenever lookup resolved to an ancestor, and final repair kept
an overbroad generic-preservation rule. A non-generic ancestor body was
therefore materialized again under owners such as `Box(Int32)#run`, even though
MIR can route the runtime type id through the ancestor chain. Preservation now
requires concrete generic source provenance (captured type-parameter binding,
generic template/module source, or an unbound type-parameter signature); a
materialized non-generic ancestor body is reused at both edges. Value/struct
owner preservation and genuinely type-dependent generic module bodies remain
covered.

Evidence:

- The inherited `Parent#run` replay regression was RED before the early gate
  (`Box(Int32)#run$` existed) and GREEN after it. The explicit `Object#to_s`
  fixture is also GREEN: it records a virtual call through `Object`, marks
  `Box(Int32)` live for replay, confirms an `Object#to_s` body, and emits no
  `Box(Int32)#to_s` wrapper. The true generic `Runner(T)#run` positive remains
  materialized with an `Int32` return.
- `crystal spec spec/hir/ast_to_hir_spec.cr` passes 246 examples with 0
  failures/errors and 2 existing pending examples. A random-order probe later
  hit an unrelated SIGSEGV in the existing
  `collect_defined_instance_method_full_names` test; that order-sensitive
  failure is unclosed and is neither evidence for nor against this fix.
- The bounded final-repair census gate exited 0 in 67.46s. Compared with the
  supplied broader baseline, requests moved `10048 -> 5945` (-40.8%), Array
  owners `8403 -> 1244`, and Hash::Entry owners `1400 -> 554`. The temporary
  histogram was placed after resolved-body skipping, so these reductions are
  directional rather than apples-to-apples. Broad Object/Reference requests
  still account for 5911 entries. No full s1-to-s2 or s2-to-s3 claim is made;
  the fresh host s1 used for the gate was
  `606926d303a7376966b2cafaf132ef94855ae897981eeb6efce61687563d3739`.

Next legal work: classify the remaining child demand by
`resolved_missing_body`, `resolved_body_preserve`, resolved ancestor/other,
and direct/included declaration before changing another replay or preservation
rule. Keep the census placement explicit when comparing future runs.

### Session 32: concrete call suffix rejects sibling typed overloads (2026-08-01)

`lower_function_if_needed` still had a legacy all-callsite fallback after its
requested-suffix compatibility pass. When no compatible candidate existed, a
fully decoded positional request such as `Hash(Int32, String)#==$Int32` could
therefore borrow the body selected for
`Hash(Int32, String)#==$Hash(Int32, String)`. That fallback is now legal only
when the request has no complete positional type evidence. Sparse `$arityN`
and compacted marker suffixes retain callsite-history fallback; complete
negative positional evidence continues to the normal exact-name parent lookup
rather than crossing to a sibling argument ABI.

Evidence:

- the focused regression is RED under condition ablation and GREEN after the
  positional-authority guard is restored; the adjacent valid override remains
  GREEN;
- the suffix-completeness regression admits only unflagged positional types
  whose decoded count matches observed callsite arity; it rejects missing
  arity evidence, shape flags, sparse `$arityN`, dropped marker parts, and
  ambiguous underscore splits;
- the complete `ast_to_hir_spec.cr` file passes 374 examples with no failures
  or errors and two existing pending examples;
- the existing String split collision, no-prelude pending-budget, and universal
  helper fanout guards pass;
- the fresh full-source lookup now preserves
  `Hash(Int32, String)#==$Int32` through `parent_fallback_cached`, and a compiled
  runtime oracle returns `false` for both `Hash == Int32` and `Int32 == Hash`,
  matching host Crystal.

Boundary: this is an ABI/correctness fix, not the B4-F fanout fix. The bounded
iteration-1 census changed only from 13338 to 13300 functions, and the
`Hash#==` supplier remained at 484 enqueue events. The hypothesis that sibling
overload borrowing was the primary growth source is refuted. Block, splat, and
named shape selection are separate resolver contracts, not claimed by this
positional-type guard.

Next legal work: classify the paired concrete and bare equality demands emitted
from `Object#===`, separating required exact parent fallbacks from duplicate
base/typed supply. Do not add a method allowlist, another registry, or a budget
cap; require a measured reduction at the existing census boundary before
calling the next change a B4-F improvement.

### Session 33: concrete generic `Object#===` wrapper ownership (2026-08-02)

The paired equality demand came from losing the concrete receiver while
lowering the inherited `Object#===` wrapper. For a call such as
`Hash(String, Int32)#===$Int32`, lazy RTA queued the concrete wrapper but exact
lookup materialized `Object#===$Int32`; its `self == other` body was then
lowered with `Object` self and opened Object-wide virtual `==` fanout.

Concrete ownership is now preserved only when all of these facts agree:

- the requested owner is a materialized generic type whose direct parent is
  `Reference`, while lookup resolved the source body from `Object`;
- the Object body structurally redispatches through `self`: either the existing
  same-method wrapper shape or exactly `def ===(other); self == other; end`.
  The case-equality form requires one untyped required positional parameter,
  no default/splat/block shape, the same parameter on the binary RHS, and no
  explicit return annotation other than `Bool`;
- binary call-target preference invokes this rule only for `===`; the generic
  target-preference helper and other operators are unchanged;
- an already materialized primary body must have the exact receiver and
  positional argument ABI plus a `Bool` return. A pending primary must still be
  present in the queue and is admitted through the same source-shape producer
  predicate. `Void` argument evidence fails closed.

The negative controls keep ordinary inherited bodies, indirect `self.stable`,
an unrelated method containing `self == 1`, defaulted extra parameters, an
unrelated RHS, typed source parameters, explicit non-Bool returns, and Void
callsite evidence ancestor-owned. Other binary-operator pairs are not admitted
by this corridor. This avoids a method/type allowlist, a new registry, and a
budget cap.

Evidence:

- the focused wrapper examples pass 2/0, the adjacent missing-target repair
  block passes 13/0, the abstract binary-dispatch block passes 3/0, and the
  full `ast_to_hir_spec.cr` file passes 376 examples with no failures/errors
  and two existing pending examples;
- the full-stdlib `Hash === Int32` reducer shrinks from 198999 to 190531 HIR
  lines and from 157 to 3 `#==$Int32` bodies. Its top-level call and wrapper
  body use `Hash(String, Int32)#===$Int32`; no `Object#===$Int32` body remains;
- a compiled runtime control prints `0`, `1`, `1`, `1` for Hash case equality,
  inherited typed equality, direct typed equality, and an explicit concrete
  `===` override;
- the comparable bounded self-build gate remains at 13300 functions after
  `process@iter1`. At `queue@iter2`, `Hash#==` demand falls from 484 to 63
  (-87.0%) while the gate still exits before processing that queue.

Boundary: this is a measured B4-F improvement, not B4-F closure. The same
iteration-2 scan still reports 2048 unique missing targets and 137
`Object#===` occurrences. No full fresh stage2, <=300-second admission, or
produced-stage semantic-smoke claim is made.

Next legal work: classify the remaining 137 `Object#===` occurrences by
receiver ownership and downstream target before changing another contract.
Keep the current structural/ABI guard fixed; do not generalize it to all
operators or add a name allowlist. A new production change needs a reducer and
a measured reduction at the same `queue@iter2` boundary.

### Session 34: enum `Object#===` semantic-owner continuity (2026-08-02)

The remaining 137 `Object#===` demands were enum case-pattern receivers whose
HIR values used integer carriers. Initial binary-call lowering could recover
the enum owner, but late receiver repair reconstructed the owner from the raw
carrier (`Int32` or `UInt32`) and rewrote the semantic target back to an
integer/Object family.

The repair now reuses the existing retained per-function enum-value sidecar
only for `===` receiver dispatch. The sidecar supplies the semantic owner used
by normal method repair; the emitted receiver value, its descriptor, and the
callee receiver ABI remain the original integer carrier. Missing or stale
sidecar evidence therefore falls back to the existing physical-type repair.
No preservation bypass, enum registry, method allowlist, or cast was added.

The regression covers exact and nilable enum patterns, a nilable-left negative
guard, and two hostile bodyful targets. A `CaseKind` receiver is first poisoned
with `OtherKind#===$CaseKind`, where both owners share the same `Int32`
carrier, and then with the same-owner wrong shape
`CaseKind#===$Nil | CaseKind`. Late repair must restore the exact target. The
test also checks `Bool`, non-virtual/no-block call shape, body availability,
both wrapper parameters, and the physical receiver/argument ABI.

Evidence:

- the full HIR suite passes 377 examples with no failures/errors and two
  existing pending examples;
- a fresh source-matched compiler (source SHA-256
  `5491f0d66aac594f98aa08c9d4750e1e736294e28d0a1a79339c5e66f7779b7d`,
  binary SHA-256
  `c3c7c7824d4a2ef3bedf4e64d4dde8291ed27dcd1c3ecce809303a879be321c3`)
  emits exact and nilable `CaseKind#===` wrappers through HIR, MIR, and LLVM;
  the wrapper receiver parameter remains carrier type `4` (`Int32`), and the
  linked reducer exits 0 under `run_safe`;
- the durable `regression_tests/enum_case_equality_owner_hir_repro.sh` oracle
  passes against that fresh compiler;
- at the same fresh `queue@iter2` gate, `Object#===` is absent and the 137
  occurrences are conserved exactly as `NodeKind#===` 78,
  `Token::Kind#===` 47, and `DWARF::AT#===` 12. The gate reports 2052 unique
  missing targets, 12854 functions, and `Hash#==` 55; run-safe telemetry is
  stable at peak 973904 KiB RSS. FD evidence is explicitly unknown because
  one of 132 topology samples was unstable; 131 stable pairs and the full
  process-tree census remained available.

Boundary: this closes the classified enum-owner continuity defect, not B4-F.
The comparable unique-target count increased from 2048 to 2052, so no global
fanout or speedup claim is admitted. No full fresh stage2, <=300-second
admission, or produced-stage semantic-smoke claim is made.

At this session checkpoint the durable oracle was intentionally
function-scoped like the classified full-source occurrences. Its top-level
`__adamas_main` variant still emitted integer-owned `===`; that separate
observed frontier is addressed in Session 35 below.

Next legal work: classify the top-level `__adamas_main` owner loss, then the new
four-target delta and remaining leading `queue@iter2` families before changing
another contract. Preserve the semantic owner/physical ABI split; require a
reducer and the same census boundary for any further production change.

### Session 35: top-level enum-owner ledger continuity (2026-08-02)

The synthetic `__adamas_main` lowering did not follow the function-local enum
provenance lifecycle used by `lower_def` and `lower_method`. Top-level enum
values were tagged while HIR was emitted, but their transient map was never
retained under `__adamas_main`. Late receiver repair therefore saw only the
physical `Int32` carrier and left exact and nilable `case` calls as
`Int32#===` even though the same source inside functions repaired to
`CaseKind#===`.

On successful completion, `lower_main` now mirrors the existing narrow
lifecycle: save the active map, start an empty function-local map, retain it
under the completed synthetic function, and restore the outer map. No `case`
special case, new registry, fallback, cast, dispatch rule, or wrapper contract
was added. The existing semantic-owner/physical-ABI split remains
authoritative.

The durable enum case-equality oracle now contains exact and nilable patterns
both inside functions and directly at top level. It counts the two call sites
for each shape separately from the two carrier-backed wrapper definitions, and
rejects `Object#===`, `Int32#===`, or `Int64#===` targets.

Evidence:

- the pre-fix source-matched compiler reproduces exactly two function-owned
  calls plus two top-level `Int32#===` calls; after the lifecycle fix, all four
  calls are `CaseKind#===` and the integer targets are absent;
- the full HIR suite passes 377 examples with no failures/errors and two
  existing pending examples;
- the fresh source-matched compiler (lowering source SHA-256
  `1e9dbb929f231b95321e7d2eb896391a2005bbad21133ee4900199de74ca6fee`,
  binary SHA-256
  `c6e92237a1cd55628cb036729f0ca5ac5e5f29a31fb5c0ed9894e9725c4b26b7`)
  passes the durable oracle, emits HIR/MIR/LLVM, links the no-prelude reducer,
  and runs it with exit 0 under `run_safe`;
- the fresh `queue@iter2` census is unchanged at 2052 unique missing targets,
  12854 functions, and `Hash#==` 55. `Object#===` remains absent and the enum
  families remain exactly `NodeKind#===` 78, `Token::Kind#===` 47, and
  `DWARF::AT#===` 12. The gate exited 0 after about 101 seconds. Internal RSS/FD
  telemetry is unknown because sandboxed `ps` probes were unavailable; live
  external samples observed one compiler core and at most 1.3% process memory.

Boundary: this closes only the demonstrated synthetic-main enum-ledger gap.
It does not claim B4-F closure, a fanout reduction, a full fresh stage2, the
<=300-second admission gate, or produced-stage semantic smoke. Review also
found at this checkpoint that `lower_main` left `@arena` on the last top-level
arena after normal completion. That context leak was not the cause of this
enum-owner defect and was deliberately excluded from this atomic change; it is
addressed separately in Session 36. The existing main lowering also lacks
exception-safe restoration; successful normal completion is the only cleanup
contract claimed here.

Next legal work: give the `lower_main` arena restoration gap its own source
reproducer and falsifier before changing cleanup structure. Keep the enum
ledger lifecycle fixed; do not broaden this patch into generic main-state
cleanup without evidence for each restored field.

### Session 36: synthetic-main caller-arena restoration (2026-08-02)

`lower_main` saved its caller arena for deferred initializer subphases, but the
top-level expression loop then switched `@arena` for every packed source and
left the converter on the final expression's arena. That state was not an
intentional main owner: the CLI's registration passes can leave any source as
the caller arena, while demand scanning uses the explicit `@main_arenas` table.
Later public lowering still prefers the current arena whenever an `ExprId`
index fits it, so equal indices from different sources could select the wrong
AST body.

The falsifier constructs two structurally aligned arenas whose same-named
function returns `11` in the caller arena and `22` in the foreign arena. It
lowers a packed top-level expression from the foreign arena and then lowers the
caller function without manually resetting converter state. With final arena
restoration ablated, the resulting HIR lacks `11` because the function body is
read from the foreign arena. Restoring the saved caller arena makes `11`
present and rejects `22`.

The production change is one normal-path assignment beside the existing
enum-map and owner restoration. It adds no arena registry, search heuristic,
source recovery, fallback, or generalized cleanup wrapper.

Evidence:

- the final focused `lower_def` falsifier is RED with the single restoration
  line ablated and GREEN when restored; the targeted
  `regression_tests/lower_main_arena_restore_spec.sh` safe wrapper is also
  GREEN;
- the full HIR suite passes 378 examples with no failures/errors and two
  existing pending examples;
- the fresh source-matched compiler (lowering source SHA-256
  `33a7805ea5425462476dec5256d11e730b377d96da10149d3c286a3b74940e74`,
  binary SHA-256
  `e97f4b2d7ec852f2f472d9c3f3133bcdee9eb388e71cfa342caab85626e4ac99`)
  still passes the function/top-level enum-owner durable oracle;
- the fresh `queue@iter2` census remains exactly 2052 unique missing targets,
  12854 functions, and `Hash#==` 55. `Object#===` is absent and the enum
  families remain `NodeKind#===` 78, `Token::Kind#===` 47, and `DWARF::AT#===`
  12. The gate exits 0 after about 101 seconds. Internal RSS/FD telemetry is
  unknown because sandboxed `ps` probes remain unavailable; live samples saw
  roughly one compiler core and at most 1.2% process memory.

Boundary: this closes caller-arena restoration only after successful
`lower_main`. It does not add exception-safe cleanup and makes no B4-F,
full-stage, timing-admission, or produced-stage claim.

Next legal work: first determine whether any supported caller rescues a failed
`lower_main` and reuses the same converter. Add `ensure` cleanup only with a
reentrant failure reproducer; otherwise keep exception-unwind state outside
the successful lowering contract and return to the remaining B4-F demand
families.

### Session 37: explicit aggregate/Proc wraps for concrete generic-struct dispatch (2026-08-02)

The first B4-F run under the 300-second policy did not approach the time gate:
s1 built in 19.60 seconds and s2 stopped after 61.18 seconds while lowering
`Hash::Entry(String, OptionParser::Handler) |
Hash::Entry(String, Proc(Signal, Nil))#value`. The existing inline union
dispatcher typed each concrete getter call as the joined return. That is not a
legal ABI substitution for V2's heap-backed aggregate carrier and a raw Proc
pointer: both are pointer-shaped, but only the aggregate arm has the registered
layout needed for an explicit sidecar-backed wrap.

The repair is restricted to an all-concrete, monomorphized union of one
registered generic struct template. A two-arm heap-backed aggregate/Proc return
is admitted only after both concrete dispatch targets exist with resolved
return ABIs, the aggregate has exact non-lib `ClassInfo`, and both returns map
to distinct authoritative union-sidecar variants. Each
branch call retains its concrete callee return type, then an explicit
`UnionWrap` supplies the joined carrier and discriminator before the phi. No
broad overload fallback, legacy descriptor Hash read, mixed-template receiver,
bare generic template, or arbitrary heterogeneous return is admitted.

Typed Proc HIR descriptors and the canonical MIR `Proc` sidecar carrier can
have different TypeRefs. The bridge first requires exact TypeRef identity and
otherwise accepts exactly one Proc-shaped variant from the same append-only
sidecar; zero or multiple Proc candidates fail closed. This narrow
representation bridge is not a general name-based union matcher.

Evidence:

- focused HIR and HIR-to-MIR structural specs pass. The MIR contract proves two
  distinct concrete call ABIs equal their callee returns, two sidecar-backed
  discriminators, one and only one canonical Proc bridge, explicit wraps that
  consume the calls, and a joined phi whose incoming values are those wraps;
- a fresh current-source compiler builds under `run_safe` with peak RSS
  4,918,208 KiB;
- the runtime oracle returns `OK` after both a captured Handler value and a
  captured raw Proc escape their construction scopes through the generic
  getter union. The adjacent nullable/tagged `Hash::Entry` runtime oracle also
  remains green;
- the focused HIR+MIR suite reaches 734 examples with zero failures and two
  pending. Negative cases reject scalar/Proc and C-struct/Proc lookalikes. All
  observed heavy processes exit naturally.

Boundary: this closes the classified aggregate/Proc branch-call ABI gap, not a
general heterogeneous generic-struct return framework or a full ARC proof.
B4-F remains RED until a clean source commit passes a fresh two-stage run and
the offline <=300-second manifest validator.

### Session 38: 300-second B4-F reaches mixed generic hash return inference (2026-08-02)

Clean commit `55271bc7` moved the fresh two-stage bootstrap beyond the
`Hash::Entry(String, OptionParser::Handler) |
Hash::Entry(String, Proc(Signal, Nil))#value` guard. Stage 1 built in 17.17
seconds and passed both plain and no-prelude smokes. Produced stage 2 then
exited naturally after 293.99 seconds, inside the inclusive 300-second policy,
with the next fail-closed diagnostic:

`cannot safely lower unresolved returns for concrete generic receiver union
Pointer(Void) | Tuple(String, Adamas::Compiler::Semantic::Type)#hash`

Observed stage2 RSS grew smoothly from about 390 MiB to about 2.1 GiB; CPU
stayed active at roughly one to two compiler cores. There was no timeout,
memory breach, or unattended runaway. The manifest preserves a clean source
identity at `55271bc7`; B4-F is still RED because stage2 did not build.

Boundary: the 293.99-second result satisfies only the timing coordinate. It
does not admit unresolved or mixed-template returns. The next legal action is
to prove the concrete zero-argument `hash` return ABI for both variants with a
focused falsifier, then change only the missing materialization contract; a
name-based or general `hash` fallback remains forbidden.

### Session 39: exact typed hash ABI and duplicate bare-demand boundary (2026-08-02)

Nested concrete union dispatch now preserves the requested typed `hash`
symbol for built-in `Nil`, `Pointer`, and `Tuple` receivers. A missing body can
use the `Crystal::Hasher -> Crystal::Hasher` protocol only for the exact
receiver-bound, one-argument typed symbol. A materialized body remains
authoritative, and an explicit conflicting return annotation fails closed.
This is not a name-based contract for arbitrary `hash` methods.

Two adjacent demand amplifiers were narrowed without a global queue policy:

- runtime `===` dispatch no longer also requests the inherited `Object#===`
  body when the concrete primary target is the emitted call;
- after a concrete callsite has admitted the exact typed target of a method
  with an untyped regular parameter, the early fallback does not also queue
  its bare alias. Blocks, splats, named arguments, unknown argument types,
  missing definitions, annotated-only parameters, and unadmitted targets keep
  the previous fallback behavior.

Evidence:

- the focused regressions reconstruct a missing concrete Tuple hash body,
  reject materialized and bodyless explicit ABI conflicts, prove that the
  concrete case-equality target does not enqueue `Object#===$Int32`, and prove
  that `LookupBox#find_entry$String` does not also enqueue
  `LookupBox#find_entry`;
- the full HIR suite passes under `run_safe`: 408 examples, zero failures,
  zero errors, and the two pre-existing pending examples;
- a fresh two-stage B4-F run built stage 1 in 16.23 seconds and passed both
  smokes. Stage 2 remained active until the 300-second safe-runner limit and
  stopped after 302.66 seconds. Observed RSS was about 2.06 GiB at 283 seconds,
  with one compiler process and no surviving process after timeout;
- the comparable first-threshold pending census moved from queue 2168 with
  `Hash#find_entry` dominant to queue 2051 with `Pointer#==`, `Array#==`, and
  `Hash#==` dominant. This is evidence that the classified duplicate-demand
  route moved; it is not proof of a global fanout or runtime improvement.

Boundary: B4-F remains RED because stage 2 did not build within 300 seconds.
The next legal probe is the paired exact/bare `==` demand emitted below
case-equality dispatch. Do not broaden the exact-target guard or add a family
allowlist until that enqueue site and its emitted-call contract are proven.

### Session 40: source-authoritative recursive typed-hash contract (2026-08-02)

The first fresh run after the Session 39 demand narrowing built stage 1 but
failed its plain full-prelude smoke after 13.06 seconds. Recursive return
inference had cached `Bool#hash(Crystal::Hasher)` as `Bool`: the helper calls
`Int#hash(self)`, the local `hasher` consequently narrowed to `Bool`, and the
following Iconv hash call became the invalid bodyless target
`Object#hash$Bool`. The receiver-repair guard detected this corruption; it was
not the cause.

The repair admits the exact one-argument typed hash ABI before recursive body
inference only when the currently selected `DefNode`, its recorded arena, and
its source path are all authoritative under the CLI-pinned stdlib root. A
reopened external definition, a sibling path such as `stdlib_evil`, a
materialized body, an incompatible explicit return, a zero-argument hash, or a
non-exact mangled symbol remains outside the shortcut. Pointer keeps its
separate inherited fallback only while no owner-specific overload exists.
Replacing a same-key definition now also replaces its arena provenance, so a
new `DefNode` cannot inherit the previous source certificate.

Evidence:

- the focused recursive Bool/Hasher falsifier was red before the repair and is
  now green. Its external sibling-path control retains the inferred `String`
  return and receives no canonical typed-hash certificate. An adversarial
  `Bool | Tuple(String, Int32)` union first exposed two narrower legacy
  owner-filters; routing both branch selection and return inference through the
  same canonical contract changed that falsifier from a heterogeneous-return
  error to two exact `Crystal::Hasher` branch ABIs;
- a macro-generated parameter definition under the stdlib path receives no
  canonical certificate and retains its inferred `String` return. A second
  CLI falsifier exposed an unmarked top-level `MacroIf`/`MacroLiteral` arena
  inheriting the stdlib path: before the main-arena provenance guard its caller
  and virtual call returned `Crystal::Hasher` while the selected body returned
  `String`; afterwards all three return `String`. A positive generated body
  that actually returns its hasher remains `Crystal::Hasher`;
- the focused hash-contract group passes 15 examples with zero failures, and
  the full HIR suite passes under `run_safe`: 410 examples, zero failures, zero
  errors, and two pre-existing pending examples;
- fresh run `adamas_b4f_hash_authority_20260802_5` on the final source snapshot
  built stage 1 in 17.22 seconds and passed both the plain and no-prelude
  smokes. Stage 2 remained active until the 300-second limit and stopped after
  302.83 seconds without producing `cv2_s2`; user CPU time was 323.00 seconds.
  Live samples observed roughly one compiler core for most of the run and
  about 2.03 GiB RSS at 270 seconds, below the 4 GiB cap. The safe-runner
  receipt could not recover RSS/FD counters in this sandbox. No compiler or
  harness process survived the timeout;
- the offline validator rejects the preserved manifest at the expected
  `manifest_status` boundary rather than accepting a partial stage2 run.

Boundary: the source-authority guard is a correctness repair, not a B4-F
closure or a performance claim. B4-F remains RED because stage2 did not finish
within 300 seconds. The next legal work is to measure the remaining stage2
lowering demand/cost frontier; no additional method-family allowlist is
admitted without a new exact failing target and its contract. Materialized
bodies with an explicit return annotation that contradicts the body remain a
separate type-checking frontier: the source-authority guard does not validate
general user annotations and must not be expanded to hide that defect.

### Session 41: first missing-sweep cost boundary (2026-08-03)

A source-matched bounded profile against
`adamas_b4f_hash_authority_20260802_5/cv2_s1` refutes the remaining Session 39
paired-equality hypothesis. The first missing sweep observes 696 raw missing
call occurrences and 149 unique concrete targets at 901 HIR functions. The
only equality matches are the exact targets `String#==$String`,
`Adamas::HIR::TypeRef#==$Adamas::HIR::TypeRef`, and
`Slice(UInt8)#==$Slice(UInt8)`, each with one occurrence; no paired bare
equality target is queued.

The dominant debug bucket is `IO#<<` with 252 occurrences, but this is an
observation count rather than a queue count. The summary intentionally strips
generic owner arguments and call suffixes, and `missing.uniq!` runs before the
149 targets enter the pending queue. A stop immediately before the first
missing scan and a stop after scan, uniquing, and queueing both exit after
approximately 60 seconds under the same 180-second / 4096-MiB safe-runner
limits. The scan and deduplication corridor therefore does not explain the
300-second B4-F timeout. The line-buffering wrapper only preserved existing
stop-gate diagnostics inside the rooted `run_safe` process tree; no compiler
behavior or telemetry was changed.

Boundary: B4-F remains RED. The exact/bare equality route and missing-census
optimization are refuted for this source snapshot. The next legal probe is a
bounded first-iteration pending-materialization measurement, using the existing
missing budget and process gates to distinguish target materialization from
later fanout. Do not add a method-family allowlist, another demand registry, or
a scan cache without a new measured falsifier.

### Session 42: synthetic-main exact demand boundary (2026-08-03)

The first bounded materialization ladder identified
`Adamas::Compiler::CLI#run$IO_IO` as the first target that expands the HIR
frontier: admitting it adds approximately 85 functions. Static inspection then
corrected an earlier call-shape assumption. The zero-argument `cli.run` source
expression is lowered through the `MemberAccess` corridor, not the normal
`lower_call` corridor, so a trial that marked every emitted non-virtual normal
call did not cover this root. Although its focused and full HIR specs were
green, a source-matched 180-second probe still deferred `CLI#run` and did not
reach the missing-start gate. That broad trial was reverted.

The retained contract is narrower: an already-emitted concrete call is exact
RTA demand only when it belongs directly to the synthetic `__adamas_main`
function. Virtual calls retain the receiver-aware method-part contract, and
calls found inside ordinary lowered bodies remain structural observations
rather than recursive exact demand. The change reuses the existing initial HIR
scan and adds no pass, cache, registry, or method-family allowlist.

Evidence:

- the focused root-demand regression was red before the change because
  `RootDemandRunner#run` was visible in `__adamas_main` but absent from the exact
  RTA demand set. It is now green, while the adjacent speculative
  `Array(Point)#inspect$IO` control remains neither queued nor exact demand;
- the full HIR suite passes under `run_safe`: 411 examples, zero failures, zero
  errors, and the two pre-existing pending examples;
- a fresh current-source stage 1 builds under `run_safe` in approximately 18
  seconds. Its source-matched stop-before-missing probe exits naturally after
  approximately 57 seconds: `CLI#run$IO_IO` is lowered through the direct
  lookup instead of deferred, the gate observes 983 HIR functions, and no
  pending item remains at the gate. The +82 functions relative to the 901
  baseline agree with the independently measured approximately +85 target
  corridor;
- the complete 300-second stage2 attempt remains RED. One compiler process
  stayed active at roughly one core, observed memory rose smoothly to about
  2.8 percent of the host near 272 seconds, and `run_safe` stopped it at the
  timeout without producing `cv2_s2`. No concurrent compiler fanout was
  observed. `Adamas::Compiler::CLI#run_check$String_Adamas::Compiler::CLI::Options_IO_IO`
  was still deferred during the bounded probe.

Boundary: this is a root-reachability correction, not B4-F closure. The claim
that admitting the synthetic-main exact call alone is sufficient for B4-F is
refuted. B4-F remains RED because stage 2 did not build within 300 seconds. The
next legal action is a bounded phase localization after missing-start. Do not
add recursive exact-demand provenance, another helper corridor, or an
optimization until that probe identifies the late cost boundary.

### Session 43: recursive missing-materialization boundary (2026-08-03)

Source-matched gates on the fresh Session 42 stage 1 localize the remaining
300-second B4-F cost inside the recursive `missing_initial` fixed point, not in
the first 32-target materialization ladder. A bounded first-pass ladder, which
includes the complete initial scan, finishes in approximately 56--58 seconds
throughout: budget 1 leaves 983 HIR functions, budget 8 leaves 990, budget 16
leaves 1014, and budget 32 leaves 1774. The 760-function jump from budget 16 to
32 does not materially change sampled first-pass wall time; it does not prove
that function count is irrelevant to later recursive cost.

The unbounded first missing pass has 170 unique demands and reaches its
context-scoped pending-done gate after approximately 87 seconds with
`pending=0`, 10,324 HIR functions, 1,967 lowered items, and 3,537 deferred
items. Iteration 1 then scans 7,740 raw occurrences and uniquifies them to
1,962 exact demands. Its scan and uniq gates both exit at approximately the
same 87-second cumulative elapsed time as the iteration-0 pending-done gate;
its pending process finishes at approximately 143 seconds cumulative with
`pending=0` and 28,647 HIR functions. Iteration 2 has 2,630 unique demands and
finishes at approximately 193 seconds cumulative with `pending=0` and 39,106
HIR functions.

A direct stop after the complete `missing_initial` flush does not fire within
the 300-second / 4096-MiB safe-runner limit. The preserved summaries show
unique-demand waves of 170, 1,962, 2,630, 2,107, and 1,783 for iterations 0
through 4. Reaching the iteration-4 summary proves that iteration 3 completed;
the timeout therefore falls after iteration 4 uniquing and before iteration 4
pending processing completes, without yet separating its queue and process
subphases. The `ADAMAS_STOP_AFTER_HIR_FLUSH_MISSING_INITIAL` gate is not
reached. The safe-runner receipt reports timeout exit 143, but resource maxima
remain unavailable in this sandbox receipt and must not be inferred from that
absence.

The existing exact queue trace permits a narrower target-level comparison
without compiler changes or a retained raw log. A streaming adjacent-iteration
set intersection reaches the iteration-4 queue gate after approximately 236
seconds with 50,479 HIR functions. Iterations 1 through 4 respectively contain
17 overlapping / 1,945 new, 65 / 2,565, 160 / 1,947, and 268 / 1,515 unique
target names relative to the immediately preceding queue. Adjacent-name
overlap, a rediscovery candidate rather than a causal classification, grows but
remains the minority through iteration 4. At the target-name set level, 1,515
iteration-4 names are outside the iteration-3 queue; this is not a runtime or
frontier estimate. The relation does not identify whether an overlapping name
came from a stable or newly materialized source body and is not a
source-provenance certificate.

Boundary: B4-F remains RED, but the old first-target and first-pass cost
hypotheses are refuted within the sampled ladder. The measured frontier is the
observed sequence of recursive demand waves inside `missing_initial`; whether
one target dominates later expansion and which source bodies create the new
target edges remain open. The next legal falsifier must correlate source
function identity/revision with prior target body/queue state before changing
production semantics. Do not add another demand registry, method-family
allowlist, scan cache, or recursive root-demand rule from function count alone.

### Session 44: source-provenance aggregate refutes immediate retry as the dominant cost (2026-08-03)

The default-off exact-shadow diagnostic now correlates occurrence-admitted,
bodyless demand with existing per-function HIR body/demand revisions and the
immediately prior post-enqueue target snapshot. It adds no persistent demand
registry and does not change production queueing, resolution, or lowering.
Stable versus new-or-changed source input is one axis; invalidation during the
current scan is reported independently. Unique-target categories intentionally
overlap when multiple source classes demand the same target and therefore are
not a causal partition.

A fresh current-source stage 1 builds safely in approximately 16 seconds. Its
source-matched iteration-2 gate exits 0 after approximately 144 seconds with
the authoritative full and exact-shadow demand vectors equal at every sampled
iteration. Warm iteration 1 has 7,740 admitted occurrences and 1,962 unique
targets: 42 occurrences and 17 targets have stable source input, while 17
targets were bodyless in the immediately prior queue snapshot. Warm iteration
2 has 8,067 admitted occurrences and 2,630 unique targets: 225 occurrences and
66 targets have stable source input, while 65 targets came from the immediately
prior queue. Thus stable-source occurrences are approximately 0.5% and 2.8%,
and immediately repeated targets approximately 0.9% and 2.5%, at the two
sampled warm boundaries. The pre-scan availability replay simultaneously
reports 24 model mismatches at iteration 2, so target-state reuse remains an
explicit safety falsifier rather than an optimization route.

The focused exact-shadow group passes 17 examples under `run_safe`. The full
HIR suite produces 668 passing examples, two pending examples, and one known
baseline failure in `as_question_try_spec.cr`: the exact example fails
identically with the pre-change Session 42 stage 1 and the current stage 1
(`"truetrue\\n\\n"` instead of `"true\\ntrue\\n"`). No matching compiler or
spec process remains after the probes.

Boundary: B4-F remains RED and no speedup is claimed. Immediate target retry
and stable-source rescanning are refuted as dominant sampled costs; simply
skipping either is both low-yield and insufficiently certified. The next legal
probe is a bounded classification of the existing demand-producing corridors
behind new-or-changed-source fan-out. Do not add a cache, target allowlist, or
new provenance registry before that measurement.

### Session 45: return-type force-lowering amplification boundary (2026-08-03)

Two independent CPU samples during source-matched missing iteration 1 move the
cost boundary from demand discovery to function materialization. The first
sample places 312 of 373 main-thread samples in pending function processing
and 279 in `lower_method`. The later sample places 364 of 414 samples in
pending processing and 318 in `lower_method`; a synchronous
`force_pending_call_targets_for_return_type` subtree accounts for 105 samples,
and 92 of those descend through another force-lower into nested method
lowering. This is real single-core body work, not scan/uniquing overhead or a
process/RSS leak. Monitored runs retained one compiler process at approximately
one core with no compiler fan-out.

The existing Phase 0 force counters are now included in the default-off
missing process gate. A fresh stage 1 builds safely in approximately 16
seconds. Its source-matched iteration-0 process gate exits 0 after
approximately 89 seconds with 10,324 HIR functions, 1,860 admitted force calls,
and 1,306 exact names. The iteration-1 gate exits 0 after approximately 146
seconds with 28,647 functions, 9,409 calls, and 5,801 names. The warm delta is
7,549 admitted calls but only 4,495 newly observed exact names: at least 3,054
admissions, approximately 40.5% of the interval, target a previously observed
name or repeat a new exact name inside the interval.

The focused exact-shadow group remains green with 17 examples. Independent
source inspection finds robust body-emission fences at request, canonical,
materialization, method, and worklist boundaries, but vulnerable efficiency
ownership: return-type forcing deliberately resets lowering depth and bypasses
the queue, while the stale queue entry remains for safe indexed traversal.
The force helper returns success after an admitted implementation call even if
that implementation takes an early exit, so `total - unique` is only an upper
bound on removable work and not a redundant-body count.

Boundary: B4-F remains RED and no speedup is claimed. A global forced-name
cache or conversion of synchronous force-lowering into ordinary queueing is
rejected: bodyless completed state can be reopened, aliases can converge only
after lookup, and callers require the return type synchronously. The next legal
falsifier must classify materialized, canonical-alias, and early-return outcomes
within the measured force corridor. Only then may a local exact-name dedup or
precheck be evaluated against wall time and semantic gates.

### Session 46: NotStarted force-lowering is mostly noise but not safely skippable (2026-08-03)

A default-off streaming outcome diagnostic now records request state before
force-lowering, state after it, requested-body availability, and HIR function
count growth. It introduces no cache, registry, queue mutation, or production
branch. The focused exact-shadow group remains green with 17 examples, and a
fresh current-source stage 1 builds safely in approximately 17 seconds.

The source-matched iteration-1 process gate exits 0 within the 240-second and
4096-MiB safe-runner bounds with the unchanged boundary totals of 28,647 HIR
functions, 9,409 force admissions, and 5,801 unique exact names. Of 3,930
Pending admissions, 3,624 materialize the requested body and 306 have no
visible body/function-count effect. Of 5,479 NotStarted admissions, 152
materialize the requested body, 15 materialize another symbol, and 5,312 have
no visible effect. Therefore approximately 97% of admitted NotStarted calls
are no-effect in this trace, but 167 still produce visible materialization.

The largest no-effect request is the bare alias
`Crystal::Hasher#reference` at 262 calls. A focused trace shows the concrete
`Crystal::Hasher#reference$Reference` specialization entering through Pending,
resolving by exact lookup, and materializing normally. Later bare-alias requests
remain NotStarted, resolve to the same family, and stop at the existing
materialized-body fence. This identifies repeated canonical lookup as a real
CPU-amplification corridor without proving that every no-effect NotStarted
request has the same cause.

Boundary: a global Pending-only guard is BROKEN because useful NotStarted
materialization exists. The aggregate combines all force callsites, so it does
not prove whether the three-name helper itself needs those 167 productive
admissions; a helper-wide guard is therefore not admitted. A global forced-name
cache is still rejected for reopening and alias/callsite reasons. The next legal
probe must reuse the existing materialization identity ledger to classify the
5,312 no-effect NotStarted outcomes as canonical-body reuse, lookup miss, or
another early return. The only currently proven semantic optimization is exact
duplicate name elimination inside one helper invocation; its material impact is
not yet measured.

### Session 47: local force-helper exact-name dedup (2026-08-03)

The three-name return-type helper now skips only a name whose spelling is
exactly equal to an earlier argument in the same helper invocation. The change
uses two local string comparisons: it adds no `Set`, cache, registry, callsite
parameter, or state transition. A duplicate invocation cannot observe any
intervening action; the first identical call either leaves the same rejection
conditions in place or performs the only lowering work and contributes the
helper's `forced` result.

The focused exact-shadow group passes 17 examples. Four adversary surfaces run
individually because their top-level test aliases conflict in one Crystal test
binary: yield inlining integration, block destructuring inference, multiple
assignment union inference, and inline-yield HIR all pass (five examples total).
A fresh current-source stage 1 builds safely in approximately 16 seconds.

The source-matched iteration-1 process gate preserves the complete observed
boundary: `missing=1962`, `pending=0`, `funcs=28647`, and 5,801 unique forced
names. Total force admissions fall from 9,409 to 8,990, proving that 419 exact
duplicate alternatives, 4.45% of the baseline force corridor, were removed.
The gate exits 0 after approximately 143 seconds versus the prior approximately
146-second non-outcome-logging baseline. That three-second observation is
directionally consistent but remains inside single-run noise; the admission
count reduction, not wall time, is the strong local certificate.

Boundary: the local exact-name dedup is ROBUST at the sampled iteration-1
boundary and suitable for an atomic commit. It is not B4-F closure and does not
authorize a broader alias, Pending-only, or forced-name cache. The remaining
measured corridor is 8,990 admissions, including 5,312 baseline NotStarted
no-effect outcomes whose exact early-return categories still need bounded
classification before another semantic precheck.

### Session 48: force-origin attribution rejects helper-wide Pending-only skipping (2026-08-03)

The default-off force outcome row now carries a two-valued origin:
`pending_helper` for calls admitted by the three-name return-type helper and
`direct` for every other callsite. This is a call argument only; it adds no
mutable context, event id, cache, registry, or production decision. The focused
exact-shadow group remains green with 17 examples, and a fresh source-matched
stage 1 builds safely in approximately 16 seconds.

At the unchanged iteration-1 boundary (`missing=1962`, `pending=0`,
`funcs=28647`, 8,990 force admissions, 5,801 unique names), the helper accounts
for 3,836 Pending calls: 3,555 materialize the requested body and 281 have no
visible effect. It also accounts for 4,987 NotStarted calls: 147 materialize
the requested body, 11 materialize another symbol, and 4,829 have no visible
effect. Direct callsites account for only 94 Pending calls (69 requested bodies,
25 no-effect) and 73 NotStarted calls (5 requested bodies, 4 other-symbol
materializations, 64 no-effect).

This attribution changes the safety conclusion. The earlier combined aggregate
already rejected a global Pending-only guard; the new rows prove that a
helper-wide Pending-only guard is also BROKEN because 158 useful NotStarted
helper admissions exist. At the same time, the 4,829 no-effect NotStarted
helper calls are now the dominant measured optimization corridor. Its largest
members remain bare family names such as `Crystal::Hasher#reference` (262),
`Parser#emit_unexpected` (176), and typed `Hash#[]?` bases (157 and 114).

Boundary: origin attribution is ROBUST, but it does not distinguish the
helper's primary, mangled, and base positions or prove that every bare name is
an already-settled alias. The next legal falsifier is a position/shape
partition, followed only if warranted by a guard requiring an earlier exact
body plus a settled non-generic return type. A cache, family allowlist, or
unconditional base skip remains forbidden.

### Session 49: helper position and shape do not form a safe skip boundary (2026-08-03)

The default-off force outcome row now records helper alternative position as
`slot=1`, `slot=2`, or `slot=3`; direct callsites retain `slot=0`. This replaces
the previous origin boolean with an integer call argument and derives the same
origin label from it. It adds no persistent state, event identity, cache,
registry, queue mutation, or production branch. The focused exact-shadow group
passes 17 examples, and a fresh current-source stage 1 builds safely in
approximately 17 seconds.

At the source-matched iteration-1 boundary, all 4,987 helper `NotStarted`
admissions have bare names. Slot 3 accounts for 4,941 of them: 147 materialize
the requested body, 11 materialize another symbol, and 4,783 have no visible
effect. Slots 1 and 2 account for the remaining 46 and have no visible effect
in this trace. Slot 3 also has 71 Pending admissions, including 16 requested
bodies. Therefore the dominant 4,783-call no-effect corridor and all 158 useful
`NotStarted` helper admissions occupy the same late bare-name position.

The positional split also preserves useful earlier work: slot 1 contributes
3,759 Pending calls (3,533 requested bodies), and slot 2 contributes six
Pending requested bodies. Shape is not a discriminator because useful and
no-effect slot-3 requests are both bare. The bounded diagnostic exits 0 after
approximately 143 seconds with one compiler process at approximately one core
and no fan-out; memory grows within the safe-runner bound rather than showing a
runaway resource leak.

Boundary: unconditional slot-3 skipping is BROKEN, and a bare-name guard is
equally unsupported. Position and shape are robust diagnostic attribution but
not semantic authority. The next legal falsifier must classify the 158 useful
slot-3 `NotStarted` outcomes against the already-materialized earlier exact
candidate and its return-type resolution. Only a predicate that separates
those outcomes may become a local precheck; global caches, family allowlists,
and state-only guards remain forbidden.

### LTP/WBA optimizer speedup candidates (2026-06-12 code review, NOT profiled)

V2's release-compile speed advantage over original Crystal comes from the
LTP/WBA MIR pre-optimization feeding LLVM lean IR (original's bottleneck is
LLVM -O3 on raw IR; its frontend is fast). Keeping the optimizer itself fast
preserves that lever. Candidates from reading `src/compiler/mir/optimizations.cr`
— **profile first** with the built-in `--debug-profile` per-pass timing and
A/B via `--no-ltp` / `--no-mir-opt` / `--no-llvm-opt`; only then optimize:

1. Incremental analysis after LTP moves (`LTPEngine.run` ~:2483): each applied
   move does a full `build_analysis_maps` + `compute_frame_potential` O(N)
   rebuild, up to max_iters=10 per function; a move touches one
   window/corridor — update affected blocks only. Biggest candidate on
   stdlib megafunctions.
2. Per-pass allocation churn: every pass run allocates fresh
   `Hash(ValueId,…)`/`Array`/`Set`; pipeline loops ≤4× per function. Pool and
   clear instead of new (zero-copy policy). Bonus: V2 struct ABI makes Hash
   ops extra costly in s2b, so this disproportionately speeds the bootstrap
   compiler itself.
3. Dominance recompute in CopyPropagation (`compute_dominance_info` ~:1702):
   recomputed per run; cache keyed on CFG version.
4. `find_window` full rescan per LTP iteration (~:2531): collect RCIncrement
   candidates once in `build_analysis_maps`, maintain incrementally.
5. `PeepholePass` lacks a hint gate (pipeline ~:2067): only pass that runs
   unconditionally even with zero candidates.

Healthy as-is (do not touch without a profile): hint-gated passes, DCE-2 only
after DCE-1 progress, `optimize_with_potential` monotone-potential break.
