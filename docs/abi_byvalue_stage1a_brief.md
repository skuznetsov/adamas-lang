# By-value struct ABI — Stage 1a brief (for hostile review)

Status: DESIGN / PROPOSED. No codegen written yet. This brief is meant to be
attacked: every claim below is anchored to verified source/IR so a reviewer can
falsify it. The goal of the review is to decide the **flip mechanism and its
gating boundary** before any codegen lands.

Owner decision (2026-06-19): write this GPT-reviewed brief BEFORE implementing
Stage 1a. Prior stages (Stage 0 census `19e72d7d`, Stage 0+ predicate `b16bf758`,
predicate reducer `5db89885`) are shipped on branch `abi-struct-byvalue`, gated
and behavior-neutral (suite 131/131 + 36/36).

---

## 1. Goal and root cause (verified)

Memory `struct-value-abi-gap-root-cause`: V2 is ~10× slower / ~2× RSS than
original Crystal on struct-heavy code because **V2 has no by-value struct ABI**.
Every struct constructor heap-allocates and returns a pointer; structs are passed
and returned by pointer. Original Crystal returns small structs by value (SROA →
registers, zero heap).

Verified IR ground truth (`bin/adamas --emit llvm-ir`, minimal `Vec2{@x,@y:Int32}`):

```llvm
define ptr @Vec2$Dnew$$Int32_Int32(i32 %x, i32 %y) {
  %raw2 = call ptr @__adamas_malloc64(i64 16)          ; 8-byte header + 8-byte payload
  store i64 9223372036854775807, ptr %raw2, align 8    ; i64 INT64_MAX sentinel header
  %r2 = getelementptr i8, ptr %raw2, i64 8             ; returned ptr = payload (header at ptr-8)
  ...zero-init @x@y...
  call void @Vec2$Hinitialize$$Int32_Int32(ptr %r2, i32 %x, i32 %y)
  ret ptr %r2                                          ; struct value = pointer to payload
}
```

For a Vec2 with an 8-byte payload this is a **16-byte heap allocation per
construction** (2× overhead) plus pointer-passing forever after.

---

## 2. The header is the GC/RC sentinel — and structs are already non-refcounted

The `i64 9223372036854775807` (= INT64_MAX, = 2^63−1) at `ptr-8` is NOT a type-id;
it is the **GC/RC sentinel header** read by `__adamas_rc_inc`/`__adamas_rc_dec`
(`llvm_backend.cr:6591-6641`), `realloc`/`malloc_size` wrappers (`:6596/6617/6648/6668`),
and the static-string emitter (`:5920` comment: "so rc_inc/rc_dec at ptr-8 safely
skip static strings"). Two facts make this central to Stage 1a:

1. **rc_inc/rc_dec are raw-base-validated AND null-safe.** They compute
   `malloc_size(ptr-8)`; if it is 0 they no-op (`%has_header` false → `done`). They
   then load the header and if `old >= 4611686018427387904` (2^62) treat it as
   **static** and skip. INT64_MAX satisfies that, so:
   - A struct allocated with the sentinel header is treated as **static: never
     incremented, never decremented, never freed** → it **leaks to program exit**
     (consistent with the documented "$Dnew GC-never-free" / "GC = leak-to-exit"
     strategy). Structs are effectively NOT reference-counted today.
   - A **stack/headerless** pointer reaching rc_inc/rc_dec is a **no-op, not a
     crash**, on a platform where `malloc_size(non-heap)` returns 0 (true on
     Darwin; `malloc_usable_size` on a non-heap pointer is UB on glibc — see §6.a).

**Implication:** dropping the header for a by-value POD struct does NOT change RC
semantics (PODs were never rc'd). It removes the heap allocation. This is the
strongest safety argument for the flip — but it leans on the platform behavior of
`malloc_size` for the (rare) case a headerless struct still reaches an rc path.

---

## 3. Scope from the census (verified, per-SITE)

Stage 0+ census on the Particle/Vec2 bench (`ADAMAS_STRUCT_BYVALUE_CENSUS`, 366
struct-ctor sites):

| dimension | step-4 OFF | step-4 ON |
|---|---|---|
| `field_store` inline / carrier | 8 / 10 | 17 / 1 |
| `arg` forwarded / no_callee / **copy_field_only** | 82 / 46 / **0** | 82 / 46 / **0** |
| **flip_eligible** (recursive-POD ∧ [inline field_store ∨ arg_copy_field_only]) | **6** | **12** |
| coarse-POD overcount vs recursive-POD | 18 | 18 |

- `arg` is entirely `forwarded`/`no_callee` at one hop — the common
  `Particle.new(Vec2.new(..))` forwards through `.new`→`initialize`, so a one-hop
  arg predicate flips **zero** arg sites. Arg is therefore OUT of Stage 1a.
- The realistic Stage 1a population is the **direct inline `field_store`** set,
  recursive-POD-gated: **6 sites (step-4 OFF) / 12 (ON)**.
- The eligibility predicate is `struct_type_is_recursive_pod?` (definite, recurses
  struct fields, rejects ref/array/union/proc/tuple/opaque, no optimistic default)
  composed with `classify_arg_param_consumption == copy_field_only`
  (`hir_to_mir.cr`, Stage 0+ section).

---

## 4. THE CRUX: per-SITE eligibility vs per-TYPE ABI

`Vec2$Dnew$$Int32_Int32` is **one** function; every `Vec2.new(Int32,Int32)` call
dispatches to it. **The constructor's return ABI is per-type-global, not per-site.**
The census counts per-SITE consumption, but you cannot flip a single call site —
flipping `Vec2$Dnew` to return a value changes EVERY consumer of that type
(field stores, locals, args, returns, container pushes, copies, mixed).

So Stage 1a needs a **whole-type** gate, not the per-site count. Two candidate
shapes (this is the main question for review):

- **Shape A — whole-type flip (single ABI):** flip `T$Dnew` to by-value only when
  struct type `T` is recursive-POD AND *every* ctor site of `T` and *every*
  consumer of a `T` value is by-value-safe (inline field store, stack local,
  by-value arg to a by-value-safe callee, by-value return, by-value copy; reject
  container push / pointer-carrier field / unknown). Requires a new per-TYPE
  aggregation pass (Stage 0++). Simpler ABI, smaller initial set.
- **Shape B — dual ABI:** keep the pointer-returning `T$Dnew` and add a by-value
  variant `T$Dnew$byval`; route only proven-safe consumers to the by-value variant,
  leave the rest on the pointer path. Larger eligible set, but two ABIs to keep
  consistent and a higher correctness surface (every consumer must pick the right
  variant; mismatch = repr-flip/UAF).

The census numbers (6/12 per-site) are a FLOOR; the whole-type set is likely
smaller for Shape A (any single escaping consumer disqualifies the type) and could
be larger for Shape B. **We currently have no per-type aggregation** — that is the
first concrete Stage 0++ task whichever shape wins.

---

## 4a. Shape C — per-site stack promotion (ALREADY EXISTS; empirically verified)

A hostile review (GPT, 2026-06-19) argued the A/B framing is a false dichotomy: a
**Shape C** already lives in the tree — `lower_stack_local_struct_allocator_call`
(`hir_to_mir.cr:6163`, intercepted by `lower_call` at `:3973`) does per-SITE
caller-side stack promotion and keeps the existing pointer ABI. I verified this
claim independently with two falsifiers (`bin/adamas --emit llvm-ir`,
`ADAMAS_STACK_PROMO_TRACE=.new`; note the MIR-level name is `T.new$...`, the
`$Dnew` mangling is backend-only):

- **Non-escaping local** `p = Particle.new(Vec2.new(1,2), Vec2.new(3,4))`:
  `Particle.new` + both `Vec2.new` trace **PROMOTED**. IR shows `alloca %Vec2` /
  `alloca %Particle`, inline constant stores, **zero `__adamas_malloc64`, zero
  `call @Vec2$Dnew`/`@Particle$Dnew`**; signatures stay `(ptr, ptr)`. Shape C is
  real and already firing.
- **Escaping into a container** `arr << Particle.new(Vec2.new(i,i), Vec2.new(i,i))`:
  `Particle.new` traces **reject lifetime=ArgEscape** → heap `Particle$Dnew`
  (`__adamas_malloc64(24)`) + **two inner `__adamas_malloc64(16)` for the @pos/@vel
  Vec2 field slots**. Only the two Vec2 *temporaries* promote.

**Decisive consequence for Stage 1a.** Shape C is correct, narrow, and ABI-neutral,
but it **does NOT close the benchmark gap**. The measured ~10×/~2× gap comes from
structs that **escape into `Array(Particle)`** (the bench builds 3M of them). Those
are *correctly* rejected by the lifetime walker (`ArgEscape`) because they outlive
the frame — by definition they cannot be stack-promoted. GPT's DoD ("Particle Vec2
mallocs → 0") only holds for non-escaping locals, which the bench does not have.
The real lever is the **container/escape value ABI**: `Array(Particle)` must store
Particle *values* inline (as original Crystal does) instead of pointers to heap
Particles whose struct fields are themselves separate heap blocks — that is the
Shape A direction, not stack promotion.

So the review correctly removed the A/B-only framing (Shape C exists and should be
acknowledged), but its recommendation to adopt Shape C *as the Stage 1a that closes
the gap* is **VULNERABLE**: verified no-op on the actual bench. Shape C's eligibility
extension (allow a recursive-POD struct as an inline-memcpy copy-sink — the walker
rejects FieldSet-value today at `:6320`) remains a legitimate, correctness-neutral
improvement for **non-escaping nested construction**, just not the perf headline.

**Revised path ordering (after the 3rd-lever finding + GPT round-2 review):**
1. **Dead default-init malloc elimination** (bounded slice, real perf signal, no
   Array-ABI change): escaping `Particle$Dnew` does 3 heap allocs — 1 Particle + 2
   *dead* default-init Vec2 (one per struct-typed field), each `alloc gc` +
   memcopy'd into the field, then *immediately overwritten* by `initialize`.
   VERIFIED origin: `ast_to_hir.cr:29679` (regular allocator) + `:30200` (overload)
   emit `Allocate(zero-filled struct)` + `FieldSet` for every struct-typed ivar with
   no usable default, unconditionally. MIR proof: `/tmp/bench_mir_on.mir:65958/65961`
   (`%6/%9 = alloc gc Type#911, size=8` before `call @61` initialize). **Skip the
   zero-struct alloc ONLY if `initialize` has a dominating, unconditional `FieldSet`
   to that ivar before ANY read/escape of self or that field.** REJECT on:
   `FieldGet self.@field` (read-before-write — `log(@pos)` would see garbage);
   `call`/`yield`/`super` passing `self` (`register_self(self)` escape-before-write);
   branch / return / raise before the store; address-of self or field;
   union/default/fixup paths; non-POD or ref-owning struct field (until recursive
   ownership lands). Gated default OFF. DoD: reducer shows the 2 inner Vec2 allocs
   vanish (Particle$Dnew stays); negative reducers (read-before-write,
   self-escape-before-write, branch-partial-write) are NOT optimized; suite + s2b
   gate-ON; bench shows malloc-count/RSS/time delta (else the slice is not worth it).
2. **Container/escape value ABI** (the true final perf lever, Shape A direction):
   inline struct storage in `Array(T)` buffers + by-value/sret `T$Dnew` for escaping
   PODs. Needs the per-type aggregation from §4. Too broad to start now (stride,
   pointer-vs-value ABI, return ABI, Array(T) storage, self-host) — do after one
   local win + new probes.
3. **Shape C eligibility extension** (optional cleanup): extend
   `stack_local_struct_constructor_uses_safe?` to accept a recursive-POD struct
   consumed only by an inline-memcpy field store (non-escaping nested
   `Outer.new(Inner.new(..))`). Correctness-neutral; **bench unchanged (proven)** —
   not a perf move, do only if the cleanliness is wanted.

---

## 5. Proposed mechanism (Stage 1a, gated `default OFF`)

For a struct type `T` that passes the whole-type gate (Shape A) — or per safe
consumer (Shape B):

1. `T$Dnew` returns the struct **by value**: a small `T` (≤ 2 machine words) as an
   LLVM aggregate (`{i32,i32}` for Vec2) returned in registers; a larger `T` via
   `sret` (caller-allocated stack slot). No `__adamas_malloc64`, no header store.
2. **Field store consumer** (the eligible set): the inline `field_store` path
   (`field_store_uses_inline_memcopy? == true`) stores the SSA aggregate directly
   into the field slot instead of `memcpy`-ing from a heap payload pointer. This is
   why small structs are coupled to step-4: a ≤ pointer-word struct field is a
   pointer-carrier unless `ADAMAS_INLINE_SMALL_STRUCTS=1` makes it inline
   (`LayoutContract.user_struct_inline?`), which is exactly the 6→12 jump.
3. **Local consumer:** stack temporary (`alloca {i32,i32}`); the existing
   `lower_stack_local_struct_allocator_call` + return-alias/stack-promotion
   machinery (`struct-dnew-stack-promotion`, `hir_to_mir.cr:6163+`) is the
   prerequisite groundwork and must be reconciled with the new return ABI.
4. **FieldGet** on a by-value struct local becomes `extractvalue`/GEP-on-alloca
   rather than a load through a heap pointer.

Initial Stage 1a delivers only steps 1–2 for the whole-type-safe set, gated OFF.
Everything else (arg via forwarding trace, header removal for the general case,
register-ABI tuning) is later.

---

## 6. Hazards for the reviewer to attack

a. **`malloc_size(ptr-8)` on a stack pointer.** Darwin returns 0 (safe no-op in
   rc_inc/dec). On glibc `malloc_usable_size` on a non-heap pointer is UB. If any
   by-value POD struct can reach rc_inc/dec on Linux, this is a portability bug.
   Falsifier: a POD struct stored into a `(T | Nil)` union or passed to a generic
   that emits rc on its argument. Does the recursive-POD gate actually exclude
   every such path? (Union fields are rejected by the gate; union *wrapping of a
   POD value* at a call boundary may not be.)

b. **Per-type ABI (the §4 crux).** Is Shape A's whole-type gate sound, or do we
   need Shape B's dual ABI? What is the actual whole-type-flippable set size after
   aggregation (we have not measured it — only per-site 6/12)?

c. **sret vs register threshold.** What is the boundary, and does it match how
   callers receive the result everywhere (direct assign, field store, arg forward,
   return, phi)? A mismatch is a silent repr-flip.

d. **Mixed/copy/return consumers.** A `T` value in the `mixed`/`copy`/`return`
   buckets — under Shape A these must ALL be by-value-safe or `T` is disqualified.
   Are `return` (by-value return) and `copy` (SSA copy of an aggregate) actually
   safe, or do they hit code that assumes a pointer?

e. **Header drop vs anything that reads `ptr-8`.** Beyond rc_inc/dec: realloc/
   malloc_size wrappers, `is_a?`, hashing, union descriptors, GC scanning. Confirm
   none reads a struct value's `ptr-8` for a flipped type. (Structs carry the
   sentinel today, so any such reader currently sees INT64_MAX → static; after the
   flip it sees stack garbage unless the reader is unreachable for PODs.)

f. **Step-4 coupling.** Stage 1a for small structs only bites with
   `ADAMAS_INLINE_SMALL_STRUCTS=1`. Do we ship Stage 1a gated independently, or
   fold it under the step-4 gate? Two gates interacting raises the test matrix.

g. **Recursive-POD gate v1 conservatism.** Tuples are rejected (a small struct in a
   tuple slot is a pointer-carrier — the finding-2 hazard), unions rejected,
   raw pointers allowed (match `type_needs_rc? == false`). Is "pointer allowed"
   correct for a struct that owns heap behind a raw pointer (e.g. a hand-rolled
   buffer)? It is not rc'd today, so memcpy duplicating it matches current
   semantics — but confirm no destructor double-free path.

---

## 7. Verification plan (DoD for the eventual flip)

- Gate `default OFF`; gate-OFF build byte-behavior unchanged (diff the emitted IR).
- Gate-ON: full suite green (131/131 + 36/36), combined + originals.
- Re-verify s2b rebuild end-to-end (the byte_at/GC-sensitive path) with gate ON.
- Per-type census shows the flipped set; assert every flipped `T$Dnew` emits no
  `__adamas_malloc64` and no header store; assert eligible field stores emit a
  direct aggregate store, not a memcpy-from-heap.
- IR perf check on the Particle/Vec2 bench: Vec2 heap allocs → 0; wall-time / RSS
  move toward original. (This is the whole point; a flip that doesn't move the
  numbers is not worth the ABI risk — see the root-cause memory's step-4 lesson.)
- Adversary: §6.a union-wrap of a POD, §6.d return/copy of a by-value struct,
  Linux `malloc_size` path.

---

## 8. Anchors (for independent verification)

- `Vec2$Dnew` IR: `bin/adamas --emit llvm-ir <vec2.cr>`; grep `Vec2$Dnew`.
- Struct MIR size = ivars only, no header at MIR level: `hir_to_mir.cr:1028`
  (`register_class_types`, comment "struct: just ivars").
- rc_inc/rc_dec raw-base validation + static skip: `llvm_backend.cr:6591-6641`.
- Sentinel = GC/static marker: `llvm_backend.cr:5920`, `:10553`.
- Eligibility predicate + census: `hir_to_mir.cr` Stage 0+ section
  (`struct_type_is_recursive_pod?`, `classify_arg_param_consumption`,
  `param_value_is_consumed_only_by_inline_field_memcopy?`,
  `field_store_uses_inline_memcopy?` at `:3367`).
- Stack-promotion groundwork: `hir_to_mir.cr:6163`
  (`lower_stack_local_struct_allocator_call`); memory `struct-dnew-stack-promotion`.
- Step-4 inline gate: `layout_contract.cr:137` (`ADAMAS_INLINE_SMALL_STRUCTS`),
  `LayoutContract.user_struct_inline?`.
