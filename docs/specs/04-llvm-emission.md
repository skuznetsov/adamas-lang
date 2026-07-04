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

`LLVMIRGenerator#generate` builds one `LLVMEmissionSession` owner record per
LLVM generation run. The session — not scattered CLI locals, backend locals,
or mutable backend fields — owns:

- the final function plan (reachability, skip set, dedup);
- the effective worker plan (worker count, debug-info sequential override);
- the side-effect merge contract (worker `.se` row schema and the parent
  merge consumer boundary).

Guard: `scripts/llvm_emission_session_source_shape_guard.sh` (strict rows via
`REQUIRE_WORKER_PLAN=1` and `REQUIRE_SIDE_EFFECT_CONTRACT=1`).

Behavior changes to worker policy, tail declaration/stub behavior, output-file
ownership, or resource acceptance MUST be justified by a generated-stage
transaction report that joins invocation setup, function plan, worker policy,
side-effect rows, tail inputs, output ownership, resource evidence, and the B4
classification for the same produced-compiler run:
`scripts/generated_stage_execution_transaction_report.sh`.

Learned cautions:

- Crystal `record` macros as generated-stage owner carriers regressed B4 (a
  produced-stage stub for `LLVMEmissionFunctionPlan#functions_to_emit`); use
  explicit private classes until the carrier's materialization surface is
  proven, and keep small plan facts as scalar fields on the session carrier.
- A green source-shape row is necessary but never sufficient admission
  evidence for a behavior change; the transaction report and the B4/B5
  classifiers decide.

History: this section previously carried the slice-by-slice 0k-BQ..0k-CC log;
it is preserved in git (`git show 95539f64:docs/specs/04-llvm-emission.md`)
and summarized in `docs/sdd_process_review_2026_07_03.md`.
