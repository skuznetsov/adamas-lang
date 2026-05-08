# HIR Name Resolution Contract

> Status: Draft v0.1, 2026-05-08.
> Scope: HIR ownership, nested names, type literals, and source-backed recovery.

## 1. Purpose

HIR is the first durable compiler boundary in Crystal V2. Most bootstrap
frontiers in the current project are not "bad LLVM" first; they originate as
wrong ownership, wrong receiver shape, or wrong source recovery in HIR.

This contract defines the HIR invariants that downstream MIR and LLVM are
allowed to trust.

## 2. Qualified Ownership

### 2.1 Canonical Names

Every class, module, lib, enum, alias, and function owner MUST have one
canonical qualified name.

Nested declarations MUST be joined with owner-aware logic:

```text
qualified_nested_type_name(owner, child)
```

The join MUST:

- preserve an already-qualified `child` when it is already under `owner`;
- prefix only genuinely relative children;
- avoid duplicating namespace components.

Falsifier: `Float::FastFloat::ParsedNumberStringT` MUST NOT become
`Float::Float::ParsedNumberStringT` or
`Float::FastFloat::Float::FastFloat::ParsedNumberStringT`.

### 2.2 Self-Reopen Wrappers

A qualified reopen wrapper whose canonical name is the current owner itself
MUST NOT be registered as a recursive nested module.

Its direct nested types and aliases still MUST be visible under the owner.

This prevents `Float::FastFloat -> Float::FastFloat` self-recursion while
preserving `Float::FastFloat::ParsedNumberStringT`.

## 3. Builtin and Top-Level Names

Unqualified builtin/top-level type annotations inside a nested owner MUST remain
top-level unless the active namespace chain structurally records a nested type
with that name.

Registry fallback alone is not sufficient evidence that `String` inside
`Float::FastFloat` means `Float::FastFloat::String`.

## 4. Type Literals

Type literals are compile-time values in HIR. Calls to name-query methods on a
type literal MUST lower to compile-time string values unless a real dot-method
override exists on the owner/parent chain.

Covered name-query methods:

- `to_s`
- `inspect`
- `name`

Invalid lowering:

```text
Bool.to_s -> Bool$Dto_s runtime/static stub
NameProbe.name -> NameProbe$Dname runtime/static stub
```

Valid lowering:

```text
NameProbe.to_s -> "NameProbe"
NameProbe.name -> "NameProbe"
```

Guard: `regression_tests/p2_type_literal_name_query_no_stub.sh`.

## 5. Source-Backed Recovery

When generated stages cannot trust raw frontend slices, HIR MAY recover
parameter, return, receiver, and owner metadata from source providers.

Recovery MUST obey these limits:

- It MUST use the file/provider boundary, not raw arena slices that the
  generated compiler has already shown to corrupt.
- It MUST preserve explicit static owner names for class methods.
- It MUST NOT broaden into source-first body scans for generic templates unless
  a focused falsifier proves the scan is required.

Refuted branch: broad source-gated generic-template body scan regressed earlier
around `Crystal::PointerLinkedList` / trace paths and is not an acceptable
general fix.

## 6. Function Body Presence

HIR MUST distinguish a registered function stub from a function with an emitted
body.

A function has a body when at least one block has emitted instructions or a
real terminator. An initial `Unreachable` terminator on an empty entry block is
not evidence of a body.

Downstream stages MAY use this to avoid trusting stale stubs.
