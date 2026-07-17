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

## 7. Prepared next G2 goal (not executed)

Start from the clean `s1b` boundary at the commit containing this slice and run
only `s1b -> s2b`; do not widen the run to `s2b -> s5b`. Fresh provenance must
bind the source, producer, output, flags, host/cache context, and run identity.
The inherited-demand reducer, focused HIR/MIR specs, and same-source runtime /
LLVM evidence are preconditions, not a raw function-count target. The goal is
the produced `s2b` compile plus its semantic runtime gate, with a refreshed
evidence packet and fallback JSON/schema/path checks. The known
`resolve_call_tuple` HIR `OverflowError` is a separate blocker to classify if
encountered; it is not evidence to relax this slice or to jump to later stages.
