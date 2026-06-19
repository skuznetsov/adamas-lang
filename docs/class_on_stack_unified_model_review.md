# "struct vs class on stack" / unified object model — Hostile Review

**Status: DEFERRED (discussion record).** Not an approved plan. Captures three
design intuitions about collapsing the struct/class distinction (so they are not
forgotten), the hostile Quadrumvirate that stress-tested them against the code,
what survives, and the blockers. Reviewed 2026-06-16 on branch `abi-rework`.

Sibling record: `docs/inline_field_annotation_sdd.md` (the `@[Inline]` idea,
same blockers). The active near-term work is **struct inlining** (the deferred
step-4 in `docs/abi_struct_value_sdd.md`), not anything in this file.

## 1. The three intuitions

- **T1 — "struct vs class = only copy semantics."** The only meaningful
  difference is value-copy vs reference.
- **T2 — "a class can live on the stack when temporary/local."** Transparent
  optimization, zero stdlib changes, "LLVM SROA finishes the job."
- **T3 — unified object model.** One representation/model for struct and class.

## 2. Verified anchors (read 2026-06-16, not from memory)

- **Identity reads the address.** `object_id`/`same?` lower to `ptrtoint` of the
  pointer: `llvm_backend.cr:4960-4962` (object_id), `:13911-13912` (2nd site),
  `Pointer#address :13691`. Reference identity == the address bits.
- **Constructor-malloc elision is struct-gated.** The stack-promotion of an
  allocator call (`lower_stack_local_struct_allocator_call`) bails unless
  `mir_type.kind.struct?` — `hir_to_mir.cr:5800` and again in the initializer
  query `:5854`. There is **no** class-reference path.
- **The malloc lives in the callee.** `$Dnew`/allocator calls `__adamas_malloc64`
  internally (`hir_to_mir.cr:7635`); for a class it is a call in the callee, not
  an `alloca` at the use site.
- **Escape analysis is smarter than a blanket "any call escapes."** Optimistic
  start (all StackLocal, `escape_analysis.cr:154`); effect summaries
  `transfer`/`NoEscape` (`:199-205`); unknown virtual calls mark *arguments*
  (not the receiver) at a boundary (`:212-217`); and `is_virtual_call?` exempts
  receivers of kind Struct/Primitive/Pointer (`:447`).
- **No runtime safety net on the value/stack path.** Structs have
  `type_needs_rc?` == false and no header (`emit_alloc`); a stack alloc has no
  rc word. An escape-analysis miss is a UAF with no fail-safe — unlike the GC
  sentinel that currently masks #4.

## 3. Hostile findings

- **T1 is an oversimplification (not "only").** Copy-vs-reference is the *root*,
  but four further differences are *derived* from it: identity (`same?` is
  meaningless for an inline value), mutation visibility (`x.f = 1` through a copy
  is invisible to the original), nil representation (class nil = null pointer;
  inline value needs a presence flag), and dispatch (virtual by type_id vs
  static). Restate as "copy semantics is the root difference; the other four
  follow," not "only."

- **T2's capability exists but the win does NOT fire end-to-end.** A StackLocal
  class already routes to the Stack strategy, but the `$Dnew` malloc is **not**
  elided for classes (struct-gated at `:5800`/`:5854`). "LLVM SROA finishes the
  job" is **false**: LLVM does not promote a `malloc` across a call boundary
  without inlining + heap-to-stack, which it does not do for a general malloc.
  Making the win real needs all three of: (a) extend allocator stack-promotion
  to final classes, (b) prove the object's identity is not observed (else
  scalar-replacement breaks `same?`/`object_id`), (c) sound interprocedural
  escape with no false `NoEscape` (else UAF without an rc net — exactly the #4
  class, minus the masking sentinel).

- **T3 is premature.** Highest sycophancy risk: an elegant north star that
  collides with the already-diverged struct ABI and Crystal compatibility, and
  whose perf premise is unmeasured and likely off the current critical path
  (correctness of the bootstrap, while #4 is open — and the historical
  bottleneck is LLVM -O3, not front-end allocation).

### Sycophancy self-audit

- Was too favorable: "LLVM SROA finishes class→stack" — false (malloc lives in
  `$Dnew`; elision is struct-only).
- Was too hostile (also a distortion): "any method call marks the receiver as
  HeapEscape" — the code does not support this (effect summaries +
  Struct/Primitive/Pointer-receiver exemption). The analysis is more capable
  than I claimed; this shifts the bottleneck onto class-constructor malloc
  elision, which is absent.

## 4. What survives — one measurement, no code

Count the demand before any code: how many `HIR::Allocate` *class* nodes with
`LifetimeTag::StackLocal` reach the Stack strategy yet still pay the `$Dnew`
malloc. That count is the ceiling of T2's win. If it is significant **and** the
sites are hot, a "class allocator stack-promotion for final classes" step
becomes worth designing — behind the same blockers as `@[Inline]`.

## 5. Blockers / kill-conditions

Blocked-until (same as `@[Inline]`):
1. the 3 layout oracles are consolidated through `LayoutContract`
   (ABI-rework 1b/1c/2);
2. the #4 repr-flip producer/consumer is fixed;
3. sound interprocedural escape analysis (no false `NoEscape`);
4. a non-observable-identity proof for any class promoted off the heap.

Kill if: the StackLocal-class-with-malloc demand count is small or cold; or the
unified model cannot preserve `same?`/object_id identity and Crystal nil/dispatch
semantics without a stdlib rewrite (T1 says it cannot, cheaply).

## 6. Relationship to active work

- This is **not** the current task. Current task = struct inlining (deferred
  step-4, `docs/abi_struct_value_sdd.md`).
- Shares all blockers with `docs/inline_field_annotation_sdd.md`.
- Must not precede the #4 repr-flip fix
  (`[[s2b-startup-crash-rc-overfree-refuted]]`).
