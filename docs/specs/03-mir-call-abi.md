# MIR Call ABI Contract

> Status: Draft v0.1, 2026-05-08.
> Scope: calls lowered from HIR into MIR and the ABI facts LLVM may trust.

## 1. Purpose

MIR is the boundary where HIR semantic intent becomes executable call ABI.
Generated-stage bugs often appear here when static calls are treated as
receiver calls, function ids are stale, or return type information is widened
or erased.

## 2. Call Kinds

Every MIR call MUST be one of:

- static function call;
- receiver/instance call;
- virtual dispatch call;
- extern call;
- intrinsic/lowered primitive call.

The lowering path MUST choose the kind before mutating the argument list.

## 3. Static Calls

A call with a fully qualified static method name and an exact MIR function
match MUST lower directly to that function when arity matches.

The lowering MUST NOT prepend a receiver argument when the receiver value is
only a stale HIR artifact for a static/class method.

Guard: `regression_tests/p2_stage2_static_call_named_llvm_no_prelude.sh`
covers `Exception::CallStack.skip("x")`.

The preferred MIR-level guard should emit MIR for the same reducer and verify:

- the call target is the named static function;
- the argument count matches the callee parameter count;
- no synthetic receiver argument is inserted before the string argument.

## 4. Receiver Calls

Receiver calls MUST include the runtime receiver as argument zero. Static calls
MUST NOT.

This distinction is ABI, not only dispatch policy. Mixing the two changes
callee arity, function id, and emitted LLVM call shape.

## 5. Function Identity

MIR `Call#callee` is a semantic function id. LLVM emission MAY use names for
output, but it MUST resolve the function id to the same MIR function that HIR
and MIR selected.

If a function id lookup fails, emitting fallback names such as `@func1` is not
a valid recovery when the MIR call has a real callee id.

## 6. Return ABI

MIR return type MUST be valid for the selected callee.

Rules:

- `Void` return type lowers to LLVM `void`.
- Empty return type strings are invalid and MUST be normalized or rejected
  before emission.
- If the callee returns a union, call result storage MUST use union ABI.
- If the HIR call type is a union but the callee return type is scalar,
  lowering must explicitly wrap or select the correct call return type.
- Null or missing HIR `TypeRef` MUST NOT be treated as an ordinary runtime
  object type.

## 7. Debug Metadata

Debug value-location metadata is not semantic call ABI. It MAY be opt-in during
bootstrap when generated-stage hash-backed metadata is not reliable.

Disabling debug metadata MUST NOT change HIR/MIR semantics.

## 8. Exact wide integer literal payloads

An Int128 or UInt128 literal MUST retain its exact payload through the parser,
HIR Literal, MIR Constant, and LLVM emission. Narrow host-integer builders
creating a wide typed constant MUST initialize the corresponding wide payload.
An Int64 or UInt64 compatibility cache cannot supply a wide constant's emitted
value. Optimizations whose constant domain is limited to 64 bits MUST leave
wide constants outside that domain.

Malformed digits and values outside the declared integer range MUST produce a
diagnostic before executable publication. Valid boundary values MUST retain
their signedness and all 128 bits. Decimal, hexadecimal, binary, and octal
spellings share this contract.

The original-first wide_integer_literal_retention_repro.sh runner checks
boundary values, values above 2^64, distinct low bits, signed ordering, and
rejections. Parser and HIR/MIR cache specs check intermediate ownership.
Refresh these checks after literal parsing, cached payload construction,
constant folding, or LLVM constant emission changes. Macro numeric evaluation
and checked arithmetic have separate contracts and qualification obligations.
