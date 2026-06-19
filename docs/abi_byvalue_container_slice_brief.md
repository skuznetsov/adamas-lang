# By-value struct ABI — container/value slice brief (for hostile review)

Status: DESIGN / PROPOSED. No codegen written yet. Attack every claim; each is
anchored to verified IR so a reviewer can falsify it. Goal of the review: decide
the **scope of the first container/value slice** and whether GPT's
"destination-driven `Array(POD) << POD.new(...)`" framing is implementable as a
bounded step, given the ground truth below.

Prereqs shipped on branch `abi-struct-byvalue` (all gated / behavior-neutral,
suite 131/131 + 36/36):
- Stage 0 census `19e72d7d`, Stage 0+ predicate `b16bf758`.
- Dead struct default-init elimination `8076254f` (gated `ADAMAS_SKIP_DEAD_DEFAULT_INIT`).
- Enum classifiers + Stage 0++ per-type aggregation `5af2b452`.
- recursive-POD nested-sibling fix `42467d7b` (predicate is now a trustworthy
  decision instrument; renamed `struct_type_is_semantic_recursive_pod?`).

---

## 1. Verified ground truth (the decisive finding)

Probe `/tmp/arr_pod_push.cr`: `struct Vec2{@x,@y : Int32}`; `arr = [] of Vec2;
arr << Vec2.new(1,2)`. `bin/adamas --emit llvm-ir`:

**Producer — boxed `$Dnew` (heap alloc + return pointer):**
```llvm
define ptr @Vec2$Dnew$$Int32_Int32(i32 %x, i32 %y) {
  %raw2 = call ptr @__adamas_malloc64(i64 16)        ; 8B header + 8B payload
  store i64 9223372036854775807, ptr %raw2, align 8  ; INT64_MAX sentinel header at ptr+0
  %r2 = getelementptr i8, ptr %raw2, i64 8           ; returned ptr = payload (header at ptr-8)
  ... zero-init @x/@y, call initialize ...
  ret ptr %r2
}
```

**Consumer — `Array(Vec2)#push` stores the POINTER, buffer is a pointer-array:**
```llvm
define ptr @Array$LVec2$R$Hpush$$Vec2(ptr %self, ptr %value) {
  %r3 = getelementptr i8, ptr %self, i32 16     ; @buffer field
  %r4 = load ptr, ptr %r3                        ; buffer base
  %r5 = getelementptr i8, ptr %self, i32 4       ; @size field
  %r6 = load i32, ptr %r5
  %r7 = getelementptr ptr, ptr %r4, i64 %idx     ; *** stride = sizeof(ptr) = 8 ***
  store ptr %value, ptr %r7                       ; *** stores the $Dnew POINTER ***
  ... size += 1 ...
}
```

**Conclusion (F:0.9, R:0.9):** `Array(Vec2)` stores Vec2 **by pointer** — the
buffer is `ptr[]`, each slot holds the heap pointer returned by `Vec2$Dnew`.
There is no inline payload storage today. Element type Vec2 behaves as a
reference-like element at the container boundary.

---

## 2. What this means for GPT's proposed slice

GPT's slice: "only `Array(PODStruct) << PODStruct.new(...)` where the container
slot becomes the destination and no boxed `$Dnew` is created. DoD: Particle bench
remaining `$Dnew` malloc 1→0, Array stores payload inline, alias/mutation reducer
shows no shared carrier."

Given §1, this is **two coupled changes**, not a producer-only rewrite:

1. **Inline element storage (prerequisite).** The buffer must change from `ptr[]`
   to `payload[]`: stride = `sizeof(Vec2 payload)` (8), push must **memcpy the
   payload** into the slot (not `store ptr`), and `arr[i]` must **GEP into inline
   payload** (not load-ptr-then-deref). This is the container VALUE ABI.
2. **Destination-driven ctor (removes the box).** Even with inline storage, a
   naive push still calls `Vec2$Dnew` (heap) then memcpy's the payload into the
   slot — the box survives. To hit "malloc 1→0" the `arr << T.new(...)` pattern
   must construct **in place** into the slot (placement): pass the slot address as
   the ctor destination instead of allocating.

So inline storage is necessary but not sufficient for the malloc win; the
destination-driving is what removes `$Dnew`. They must land together to satisfy
the DoD.

### Why this is the real lever (and the real aliasing bug)

With pointer storage, the lever-(i) container-aliasing hazard is concrete:
`v = Vec2.new(1,2); arr << v; arr << v` stores the **same pointer twice** → both
elements alias one heap cell; mutating one mutates the other. `arr << v` then
mutating `v` (a by-pointer struct local) also aliases. Inline storage fixes this
by copying the payload per slot. So the value ABI is simultaneously a **perf** win
(no box, half the footprint) and a **correctness** fix.

---

## 3. Surface (VERIFIED — all anchors confirmed by content; line numbers @ `42467d7b`)

Element representation is consumed by EVERY `Array(Vec2)` accessor, and — the
decisive part — it is **NOT centralized**. There are two classes of sites:

**(a) Stride-aware central path (good):** the HIR→MIR pointer lowering routes
element stride through `container_elem_storage_size_u64`:
- `hir_to_mir.cr:1820` def `container_elem_storage_size_u64`; `llvm_backend.cr:2728`
  the backend twin (`_impl` taxonomy: primitives/enums/big-unions/inline-tuple/
  `inline_container_struct_type?` → `InlineBytes`; plain struct/tuple →
  `PointerCarrier`; ref → `PointerReference`).
- `lower_pointer_store` `:8293`, `lower_pointer_add` `:8364`, `lower_pointer_realloc`
  `:8386`, `lower_pointer_load` `:8235` — all stride via that fn.

**(b) Raw LLVM overrides that BYPASS the central path (the hazard GPT flagged):**
- `emit_array_new` `llvm_backend.cr:24609` — sizes the buffer by an **LLVM-type
  case**: `elem_size = case element_type when "i64"/"ptr" then 8 ...`. A struct
  maps to `ptr` → **8 bytes/slot**, NOT `container_elem_storage_size_u64`. So
  ArrayNew silently allocates a pointer-array even if other sites think inline.
- `emit_array_get` `:24665` — the inline branch at `:25121`
  (`inline_container_struct_type?(stride) || inline_primitive_tuple_type?`) emits
  `getelementptr i8, ptr buf, byte_off` and **returns the SLOT ADDRESS with no
  load** (`record_emitted_type(name,"ptr"); return`). For a value element this is
  an **interior alias**: `v = arr[0]; v.mutate` would mutate the slot. Copy-on-LOAD
  is required, not just copy-on-store (GPT caveat #2, VERIFIED).
- `emit_array_set` `:25141` — the copy-on-store counterpart.
- raw `Array#<<` primitive override `:~4453` ("primitive Array#<<(T) for late
  generic append bodies").
- `Pointer(T)#bytesize`/`#<<`/`#clear` raw overrides (per GPT `~13766`).

**Existing partial mechanism (important):** inline struct storage in containers
already EXISTS but is gated by a NAME ALLOWLIST, not the POD predicate:
`inline_container_struct_type?` `:2796` → `LayoutContract.inline_container_family?
(elem_type.name)`. Vec2 is NOT in the family list → today it is a `PointerCarrier`.
Extending the value ABI to general semantic-POD structs = flip that gate from the
name allowlist to `struct_type_is_semantic_recursive_pod?` (+ size bound + non-
union) AND make every site in (b) agree — especially `emit_array_new`'s sizing
and `emit_array_get`'s copy-on-load.

**Destination-driving is HIR/MIR-level, not backend-only (GPT caveat #1,
VERIFIED):** in MIR the `$Dnew` result is already built as the `push` argument
BEFORE entering `Array#<<` (`Array(Vec2)#<<(%0: buf, %1: Type#911=$Dnew result)`).
Backend element lowering cannot remove the box; a HIR/MIR `container << fresh_ctor`
fusion must run AFTER capacity-grow and pass the slot pointer as the ctor
placement destination. This is a separate transform from the storage flip.

Hazards (each needs a reducer or an explicit carve-out):
1. **Aliasing/mutation** (the WHY) — copy-on-store AND copy-on-load; `arr << v;
   v.mutate` and `w = arr[0]; w.mutate` must both leave the other unchanged;
   double-push of the same value must yield independent slots.
2. **`to_unsafe` / interior pointers** — exposing `Pointer(Vec2)` into an inline
   buffer hands out interior pointers invalidated on realloc.
3. **Stride/capacity math** — buffer byte size = `cap * sizeof(payload)`;
   `emit_array_new` and realloc must agree on payload stride.
4. **Mixed/union element** — `Array(Vec2 | Nil)` is NOT a flat POD array; fall
   back to pointer/union storage. Gate on semantic-POD AND non-union.
5. **Non-POD element** — ref-owning struct stays pointer-stored (predicate rejects).
6. **Self-host** — s2b/s3b use `Array(struct)` internally; the element-ABI flip
   must keep self-host green (broad blast radius).
7. **`$Dnew` callers outside containers** — fusion fires ONLY for
   `container-slot << fresh-ctor`; an escaping `$Dnew` keeps the boxed path.

---

## 4. Scoping options for the owner/GPT

- **Option A — perf slice (GPT's, broader than "narrow"):** inline element
  storage for `Array(semantic-POD-struct)` + destination-driven `<< T.new(...)`.
  Real malloc/RSS win + fixes aliasing. Blast radius = all `Array(POD)` accessors
  + self-host. Must land behind a gate, with Stage-0 surface enumeration first.
- **Option B — correctness-first, bounded:** keep pointer storage; make push/`[]=`
  **copy** the payload into a fresh per-slot cell when storing a struct value
  (kills aliasing). Bounded, no accessor-ABI flip, but **no perf win** (box stays;
  arguably adds a copy). Useful only if we want lever-(i) correctness decoupled
  from perf.
- **Option C — measure-then-decide (TWO axes, per GPT):** the static storage-site
  enumeration is §3 above (already done — surface is NOT centralized: ArrayNew +
  ArrayGet-inline bypass the stride fn). The missing piece is a **second census
  axis**: count `container << fresh_ctor(...)` **placement-fusion sites** per
  semantic-POD type. A storage census alone CANNOT prove "malloc 1→0" — only the
  fusion-site axis quantifies the removable boxes. C = add that fusion-site axis
  to the Stage 0++ census (read-only, gated), then let the numbers name A's exact
  first pattern.

**Recommendation (VERIFIED, matches GPT):** Option C as the immediate next step —
read-only fusion-site census axis, gated, behavior-neutral. Then Option A, scoped
to the single pattern C identifies (likely `Array(semantic-POD)#push(fresh_ctor)`
with copy-out/copy-in semantics pinned by reducers), landing the storage flip
(all §3(b) sites) and the placement fusion together behind a gate. Option B does
not advance perf and adds a copy — skip unless aliasing correctness is needed
standalone. Option A as a next-coding-step now is VULNERABLE: blast radius
(ArrayNew sizing + copy-on-load + HIR/MIR fusion + self-host) is wider than a
backend element-lowering tweak.

## 5. DoD (when Option A lands)

- Particle/Vec2 bench: `$Dnew` malloc for the pushed POD 1→0 on the
  `arr << T.new(...)` path; whole-module malloc-site count drops; peak RSS drops
  by ~`elements * header(8B)`.
- New reducer: inline storage proven (buffer stride = payload size in IR);
  alias/mutation reducer — `arr << v; v.mutate` leaves `arr[0]` unchanged, and
  double-push yields independent slots.
- Non-POD/union element falls back to pointer storage (negative reducer).
- Suite 131/131 + 36/36; self-host s2b green (no regression vs current branch).
- Gated; gate-OFF byte-identical to pre-slice.
