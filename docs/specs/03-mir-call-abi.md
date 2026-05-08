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
