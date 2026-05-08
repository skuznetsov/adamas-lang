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
