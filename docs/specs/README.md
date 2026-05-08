# Crystal V2 Specification Index

> Status: Draft v0.1, 2026-05-08.
> Audience: agents and maintainers implementing the Crystal V2 bootstrap
> corridor.

This directory defines the executable contracts for Crystal V2. These
documents are not a full Crystal language specification. The original Crystal
compiler remains the semantic oracle for language behavior.

The purpose of these specs is narrower: define the invariants that Crystal V2
must preserve across HIR, MIR, LLVM IR, and generated-stage bootstrap so that
agents can implement by contract rather than rediscovering one edge case at a
time.

## Documents

| Document | Scope |
|----------|-------|
| `00-bootstrap-contract.md` | Stage corridor, equivalence model, and acceptance gates. |
| `01-hir-name-resolution.md` | HIR ownership, qualified names, type literals, nested modules, and source recovery. |
| `02-generic-template-registration.md` | Generic template registration, nested body scan, and no-depth-cap policy. |
| `03-mir-call-abi.md` | Receiver/static call split, function identity, and MIR return ABI. |
| `04-llvm-emission.md` | LLVM callee naming, return spelling, and backend lookup invariants. |
| `05-falsifier-matrix.md` | Claim-to-reproducer mapping for the above contracts. |
| `06-cli-output-contract.md` | CLI compile modes, output side effects, and post-LLVM tail behavior. |

## Contract Language

- **MUST**: release-blocking invariant for the relevant phase.
- **SHOULD**: expected behavior; deviations require a LANDMARK entry and a
  follow-up falsifier.
- **MAY**: implementation freedom.
- **NON-GOAL**: explicitly outside the current contract.

## Evidence Model

Every normative claim should have one of:

- an existing regression script under `regression_tests/`;
- a named TODO/LANDMARK frontier with verified evidence;
- a `[MISSING-FALSIFIER]` marker in `05-falsifier-matrix.md`.

Claims without a falsifier are design intent, not verified bootstrap contract.
`[MISSING-FALSIFIER]` rows must name the phase or frontier that needs the guard;
otherwise the marker is just backlog noise.
