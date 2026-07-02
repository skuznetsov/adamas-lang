# LLVM Emission Contract

> Status: Draft v0.1, 2026-05-08.
> Scope: LLVM IR emitted from MIR.

## 1. Purpose

LLVM emission is allowed to choose spelling details, but not semantic ABI. It
must faithfully lower MIR call identity, return types, object layout, and link
surface.

## 2. Callee Names

When MIR provides a callee `FunctionId`, LLVM emission MUST resolve that id to
the corresponding MIR function and emit the mangled name of that function.

Invalid fallback:

```llvm
call void @func1(...)
```

when MIR selected `Exception::CallStack.skip(String)`.

Valid output:

```llvm
call void @Exception$CCCallStack$Dskip$$String(ptr @.str.0)
```

The backend MUST NOT rely on generated-stage-fragile hash lookup for this
critical path. A dense `FunctionId -> Function` index is acceptable.

## 3. Return Type Spelling

LLVM calls and definitions MUST never have an empty return type.

Invalid output:

```llvm
call  @Some$Dcallee(...)
```

Valid outputs:

```llvm
call void @Some$Dcallee(...)
%x = call ptr @Some$Dcallee(...)
```

Cached emitted return types MAY override primitive placeholder return types
only when the cached value is non-empty and not `void`.

## 4. Object and IO Overrides

Hardcoded LLVM overrides are allowed only when they preserve the semantic ABI
of the generated method. They SHOULD call generated accessors rather than
duplicating class layout offsets when the offset is not part of a stable
contract.

Example: IO file-descriptor overrides should use the generated fd getter rather
than hardcoding an ivar offset that may move as type registration frontiers are
fixed.

## 5. Debug Metadata and Paths

Debug metadata MUST NOT be required for semantic correctness. Metadata path
normalization MAY remain relative when generated-stage file/dir APIs are not
yet reliable.

## 6. Validation

Every LLVM-emission contract fix SHOULD have a guard that:

- emits LLVM IR through `--emit llvm-ir --no-link`;
- checks for forbidden spelling;
- checks for required semantic spelling;
- runs `llc` when available.

Guard: `regression_tests/p2_stage2_static_call_named_llvm_no_prelude.sh`.

## 7. LLVMEmissionSession

Generated-stage LLVM entry is now governed by Slice 0k-BQ in
`docs/compiler_architecture_sdd.md`.

Before changing worker policy, side-effect merge behavior, undefined-extern or
missing-body stubs, output-file ownership, or resource acceptance, the compiler
MUST introduce an explicit `LLVMEmissionSession` owner record in behavior-neutral
mode. The session record must capture the setup facts, final function plan,
worker plan, side-effect merge contract, tail declaration/stub plan, output
ownership boundary, and generated-stage evidence for one LLVM generation run.

The first implementation slice MUST include a source-shape guard proving that at
least one old authority edge is consumed by the session record instead of living
only as scattered CLI locals, backend locals, or mutable backend fields.

Slice 0k-BR consumes the first edge, `function-list-inline`.
`scripts/llvm_emission_session_source_shape_guard.sh` is the guard. It requires
`LLVMIRGenerator#generate` to build an `LLVMEmissionSession` and consume the
final function plan through it, while rejecting reachability, skip-set, or
dedup authority that still lives inline in `generate`.

Slice 0k-BS consumes the second edge, `worker-policy-inline`. The same guard
with `REQUIRE_WORKER_PLAN=1` requires `generate` to consume effective worker
count through `LLVMEmissionSession`, while rejecting inline
`parallel_llvm_workers` and debug-info sequential override logic in `generate`.
The slice does not change worker defaults or fallback behavior.

Slice 0k-BT adds a stop rule before the next production slice. A session field,
getter, string vocabulary, or report is not enough to satisfy the side-effect,
tail, output, or resource contract. The next LLVM emission architecture change
must define a vertical contract and move a downstream consumer to that contract
in behavior-neutral mode before changing merge behavior, tail stubs, output-file
behavior, or resource acceptance.

Slice 0k-BU selects `SideEffectMergeContract` as that next vertical contract.
The first implementation must keep the current worker `.se` format and merge
semantics, but `emit_functions_parallel` must stop being the inline owner of both
raw worker side-effect row writing and parent raw-tag merge switching. The
session contract owns the schema and the writer/merge consumer boundary.

Slice 0k-BV adds the convergence gate before that implementation. The
side-effect implementation is now the future 0k-BW slice. A green
`REQUIRE_SIDE_EFFECT_CONTRACT=1` source-shape row is necessary but not
sufficient: the slice must also report the generated-stage convergence vector
from the SDD, including B4 before/after, worker-mode split, tail-input versus
semantic-failure classification, and output/resource evidence boundaries. If
another behavior-neutral `LLVMEmissionSession` edge preserves the same B4
frontier and narrows no vector row, the next admitted movement is a
`GeneratedStageExecution` transaction redesign checkpoint rather than another
session edge hoist.

Generated-stage owner carriers SHOULD use explicit private classes/methods
until their materialization surface is proven. A rejected 0k-BR preflight using
Crystal `record` macros preserved local checks but changed B4 to a produced
stage stub for `LLVMEmissionFunctionPlan#functions_to_emit`.
Slice 0k-BS adds the narrower caution that separate helper classes can still be
too expensive for generated-stage bootstrap; keep small plan facts on the
existing session carrier when scalar fields are enough.
