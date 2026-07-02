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

### 4.1 Type-Visible Runtime Values

`typeof(expr)`, runtime `expr.class`, explicit type literals, and type-literal
name queries are one semantic family. They MUST NOT be implemented as unrelated
runtime pointer placeholders, interpolation-only side paths, or backend string
stubs.

HIR SHOULD own a single type-visible value fact that records:

- the semantic `TypeRef`;
- the canonical display name;
- the origin of the value (`typeof`, runtime `.class`, explicit type literal,
  or name query);
- whether the value is compile-time-only or needs runtime stringification.

Direct output and interpolation MUST consume the same fact. A guard that only
proves one of `puts typeof(x)`, `"#{typeof(x)}"`, `puts x.class`, or
`"#{x.class}"` is not wide enough to claim this contract fixed.

Current frontier: the B3 original-vs-stage oracle prints blank `TYPE=` and
`UNION=` lines in the stage output where original Crystal prints `Int32`. This
is a `TypeValue` / `RuntimeTypeIdentity` frontier, not permission for a
string-only `typeof` patch.

Focused guard: `regression_tests/type_value_runtime_identity_contract.sh`.
It is strict by default and measured-red only with
`ADAMAS_EXPECT_TYPEVALUE_MISMATCH=1`.

Current H6-core guard:
`regression_tests/type_value_core_runtime_identity_contract.sh`. It covers the
bounded owner-fact surface for direct/interpolated `typeof(1)`, multi-arg
`typeof(1, "x")`, direct/interpolated `1.class`, local and parenthesized
nilable `.class`, and type-literal name/string queries.

Known residual: dynamic multi-variant union `.class` still requires a runtime
type-name service rather than compile-time union display. Guard:
`regression_tests/type_value_dynamic_union_class_residual.sh`, measured-red
with `ADAMAS_EXPECT_DYNAMIC_UNION_CLASS_MISMATCH=1`.

Important boundary: a `RuntimeTypeIdentity` fact is not automatically a string.
Explicit type literals may carry identity for name/query semantics but must not
be stringified when used as normal call arguments. The concrete guard is
`regression_tests/test_byteformat_decode_u32.cr`: `IO::ByteFormat::LittleEndian`
must remain a format/type value so `String#encode(UInt32, IO)` materializes
normally.

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
