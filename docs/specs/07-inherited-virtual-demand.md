# Inherited Virtual-Demand Contract

> Status: bounded implementation slice, 2026-07-16.
> Scope: ordinary reference-class inheritance across HIR virtual-target replay,
> HIR function materialization, and MIR class dispatch.

## 1. Problem and boundary

An inherited virtual call has one selected implementation owner, but the
requested receiver may be a live subclass.  Materializing the requested name
as a new body for every non-overriding subclass creates a demand multiplier and
then makes MIR enumerate those duplicate bodies in a dispatcher.  The original
Crystal compiler retains the defining implementation and calls it directly for
this case.

This contract covers one selected method shape at a time.  It does not claim
that all excess full-selfhost definitions have this cause.

## 2. Admitted canonicalization

HIR MAY canonicalize an inherited request to the selected ancestor body only
when all of the following facts hold:

1. overload resolution selected the ancestor-owned `DefNode`;
2. the requested owner is proven to inherit that resolved owner in the current
   class graph (generic base names may be compared only after their concrete
   owner relation is established);
3. the selected target is concrete, not abstract;
4. the requested owner is not a concrete value/struct owner; and
5. no generic source-owner binding or value-owner specialization requires a
   distinct body.

The canonical materialization symbol and the call target are then the resolved
ancestor spelling.  A requested child spelling MUST NOT create a child-owned
body merely because it arrived through virtual replay or a later materializer
lookup.

## 3. Required preservation boundaries

The canonicalization guard MUST NOT apply when:

- the resolver selects a true child override;
- an abstract target still needs runtime dispatch admission;
- a value/struct receiver needs its own layout or source specialization;
- a generic source owner requires concrete type-parameter substitution; or
- the call is a tagged or all-reference union whose nil/unwrap ABI is still
  required.

These cases remain on their existing owner-preserving or dispatcher paths.

## 4. MIR direct-call rule

For a non-union HIR class receiver, MIR MAY bypass the dispatcher only when
every admitted runtime candidate is concrete, has no `dispatch_class` fallback,
and points to the exact same MIR `FunctionId`.  The selected function's
parameter count must equal the call argument count; normal ABI coercion is still
applied.  If any candidate is missing, abstract, owner-specific, or points to a
different function id, MIR MUST retain the switch dispatcher.

The completeness boundary for this statement is the existing
`virtual_dispatch_candidates` census: the static receiver's registered class
plus `subclasses_for(base)`, filtered to registered runtime-header-backed MIR
types. A class with no resolved function enters as a fallback candidate or
prevents unification; non-header value types are not runtime object candidates.
This is a registered-class census guarantee, not a claim about classes hidden
outside the current HIR class graph.

Union receivers retain their existing discriminator/header and nil semantics.
An LLVM function count is not the objective or proof of this rule; HIR body
identity and MIR candidate identity are the authoritative signals.

## 5. Falsifiers and verification

The focused reducer is
`regression_tests/inherited_virtual_demand_amplifier_no_prelude.sh <compiler>`.
It must report one `Parent#value$Int32` body and no child body or dispatcher for
0, 1, 8, and 16 empty descendants; a real `Child0` override must retain two
bodies and one dispatcher; generic and overload controls must remain narrow.

The phase-local unit guards are `spec/hir/ast_to_hir_spec.cr` (canonical body
repair) and `spec/mir/hir_to_mir_spec.cr` (same-`FunctionId` direct call).  The
same-source runtime matrix is recorded in
`docs/evidence/inherited_virtual_demand_runtime_matrix_20260717.md`; its fresh
per-row LLVM pairs and forward/reachability census are recorded in
`docs/evidence/inherited_virtual_demand_llvm_matrix_20260717.json`; original
HIR/MIR for that matrix is unavailable and is not inferred from runtime
agreement. A base compiler failing the reducer is the RED baseline; a changed
compiler must pass the reducer, both focused files, the runtime matrix, and
`git diff --check` before this slice is called verified.

## 6. Residual boundary

This slice does not prove full-prelude LLVM equivalence, complete attribution of
the historical function-count delta, or any `s2b`-to-`s5b` bootstrap stage.  A
fresh full Adamas selfhost remains independently blocked by the known HIR
`OverflowError` in `resolve_call_tuple`.  Changes to class registration,
generic source binding, union storage, or candidate enumeration decay this
certificate and require rerunning the reducer and focused specs.

## 7. Executed G2 goal: s1b to s2b blocked (2026-07-17)

The bounded G2 run started from clean snapshot commit
`d38e243c0c4c130f662e7d99dae2a47859303a5c` (clean descendant of
`30b6e5a164405ded337d39905150d2f96b16aeb6`) and bound source, producer,
output, flags, host/cache context, and run identity in
`20260717T125255Z-12696`. Host Crystal was 1.20.3, LLVM was 22.1.8, and the
target was `aarch64-apple-darwin25.5.0`. The fresh stage-1 producer was
`cv2_s1` SHA-256
`66428bcba74d70f780e954ebd9675e37744a4aaa0e01f1f0cbff7bf15c267009`.

Stage 1 built and both plain and canonical no-prelude smokes passed. Stage 2
was then killed by the bounded `run_safe` timeout after 902.74 seconds (exit
143), with peak RSS 4,155,600 KB and complete process-tree coverage. No
`cv2_s2`, stage-2 semantic smoke, or later stage was produced or accepted.
This leaves the G2 claim at `IN_PROGRESS`, not `VERIFIED` or ready.

The focused HIR/MIR specs, exact-stage-1 inherited-demand reducer, and the
same-source runtime/LLVM preconditions remain green. A HIR-only probe and two
read-only samples place the timeout in lazy HIR pending lowering and forced
class-method inline-yield/while work; `resolve_call_tuple` is not the hot-root
owner. Progress telemetry shows finite but accelerating worklist demand, so the
residual is a broad HIR performance/demand frontier rather than a proven
stationary loop. Raw LLVM function totals remain inventory evidence only.

The harness contract was repaired narrowly after two RED probes: the first
exposed the stale one-line no-prelude assumption, and the second proved that
line count plus marker presence admitted semantically wrong output. Plain and
no-prelude smokes now require exact canonical stdout plus exactly one marker;
missing, duplicate, and wrong-content fixtures fail closed. The durable blocked
handoff is `.landmark/evidence/lep-20260717-s2b-semantic-readiness-blocked.json`.

Next legal action is one focused per-owner/context falsifier for lazy-worklist
demand with fresh provenance. Do not retry a longer heavy stage-2 run, reopen
this inherited-demand slice, or advance to `s3b`-`s5b` until a fresh `s2b`
artifact and semantic runtime gate exist. Changes to source/producer/toolchain,
cache or manifest semantics, process-probe availability, or classifier
authority decay this checkpoint and require refreshed evidence.
