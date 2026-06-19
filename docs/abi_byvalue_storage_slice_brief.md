# By-value struct ABI — `Array(leaf-storage-POD struct)` STORAGE slice brief (hostile review)

Status: DESIGN / PROPOSED. No codegen written. This is the first concrete A-slice
GPT scoped, **tightened after GPT review round 1**: storage ABI for
`Array(LEAF-storage-POD struct ≤16B)`, NOT placement fusion (fusion
`arr << T.new(...)` is a separate later sub-slice — the Option C fusion census
`6937803d` showed it is a narrow lever: 4 sites in the prelude). Anchors verified
against the tree at this commit; attack every claim.

**v1 scope (the exact coding slice):** `Array(leaf-storage-POD struct ≤16B)` +
a MIR `ContainerElemRepr` enum (PointerSlot | InlineAddress | InlineValueCopy) +
copy-on-store + **escape-aware** copy-on-load materialization. Fusion later.

---

## 0. Purpose framing (read first — avoids a value-proxy trap)

The storage slice's job is **CORRECTNESS of the inline element ABI**, not a perf
number yet. Concretely it makes `Array(Vec2)` store the Vec2 **payload inline**
with proper **copy-on-store AND copy-on-load**, killing the interior-alias hazard.

It does **NOT** by itself reduce malloc/RSS under our leak-to-exit GC: today
`arr << Vec2.new(1,2)` heap-boxes via `Vec2$Dnew` (16B: 8B sentinel header + 8B
payload), and an inline-storage push still calls `Vec2$Dnew` then memcpy's the
payload into the slot — the box survives (leaked, not freed). The malloc/RSS win
(`$Dnew` 1→0) comes from the **later placement-fusion sub-slice**, which can only
land safely once the storage ABI is correct. So the DoD here is aliasing/copy
correctness + self-host green, explicitly **not** a malloc-count drop.

Sequence (GPT): storage-first (this brief) → fusion-second (separate brief).

---

## 1. The gate (single source today)

Inline container-element storage already exists, gated by a NAME ALLOWLIST:

- `llvm_backend.cr:2796` `inline_container_struct_type?(elem)` →
  `Adamas::LayoutContract.inline_container_family?(elem.name)`.
- `layout_contract.cr:146` `inline_container_family?(name)` = `name.starts_with?`
  one of `"Slice("`, `"StaticArray("`, `"Hash::Entry("`. Plain user structs
  (Vec2) are NOT in the list → `container_elem_storage_size_u64_impl`
  (`llvm_backend.cr:2756`) returns `pointer_word` (8) → **pointer storage**.

**The flip (v1 — leaf-storage-POD only, GPT round-1 blocker):** semantic-
recursive-POD is **NOT a sufficient gate**. It answers "declared fields are
recursively bit-copyable" but not "the CURRENT payload layout has no pointer
carriers". VERIFIED on the field ABI: `user_struct_inline?` (`layout_contract.cr:117`,
step-4 OFF default) is `size > POINTER_WORD_BYTES` (8) — so a `Vec2` (size 8)
**field** is a pointer carrier. `Pair{@a:Vec2,@b:Vec2}` therefore has a payload of
**two pointers**, and an inline memcpy of a `Pair` into `Array(Pair)` would copy
pointers, not the nested Vec2 bytes → exactly the semantic-vs-storage caveat the
predicate's own doc comment warns about (`hir_to_mir.cr:898`).

So v1 gates on a STRICTER, storage-aware predicate — **leaf-storage-POD**: every
field is primitive / enum / raw pointer (no nested struct / tuple / union / ref),
AND `size ≤ 16`, AND non-union, AND non-lib. `Vec2{Int32,Int32}` qualifies (payload
= 8 real bytes); `Pair{Vec2,Vec2}` does NOT (nested carrier). semantic-recursive-
POD stays as the FUTURE gate once the field-inline ABI (step-4) lands and nested
PODs are truly inline. The new predicate `storage_pod_inline_safe?` is best
expressed as the `InlineValueCopy` arm of the repr enum (§4.1), not a bare bool.

---

## 2. Verified surface — three buckets

### 2a. Already CORRECT for inline families (the model to match)
- `emit_array_set` inline branch `llvm_backend.cr:25406-25416`: byte-stride GEP
  (`stride = stride_type.size`) then **memcpy stride bytes** from `value` into the
  slot (memset on null). Copy-on-STORE is already correct for inline families.
- MIR pointer lowering routes stride through `container_elem_storage_size_u64`:
  `lower_pointer_realloc :8386`, `lower_pointer_store :8293`, `_add :8364`,
  `_load :8235` (`hir_to_mir.cr`). So buffer realloc on grow sizes by
  `elem.size` — correct stride after the first capacity grow.

### 2b. BROKEN / bypass for the value ABI (must fix in this slice)
1. **Copy-on-LOAD gap (the #1 blocker, GPT caveat #2).**
   `emit_array_get` inline branch `llvm_backend.cr:25121-25128`: computes the
   byte-stride GEP and **returns the SLOT ADDRESS with no load/copy**
   (`#{name} = getelementptr ...; record_emitted_type(name,"ptr"); return`). For a
   value element this hands out an **interior pointer into the buffer**:
   `v = arr[0]; v.mutate` mutates the slot; a realloc invalidates `v`. FIX:
   **materialize a copy per §4.4** (escape-aware: entry-block `alloca` + `memcpy
   stride` for a non-escaping use, heap-copy for an escaping load), return the copy.
2. **`emit_array_new` element sizing bypass (GPT caveat).**
   `llvm_backend.cr:24615-24622`: `elem_size` is a case on the **LLVM type string**
   (`i64/double/ptr → 8`, `else → 8`), NOT `container_elem_storage_size_u64`. For
   Vec2 (size 8) it coincidentally equals 8 so it's masked; for a POD struct with
   size > 8 (e.g. `Vec3` = 12, `Pair` = 16) it **under-allocates** the initial
   buffer. Masked further because Array starts empty and the first push reallocs
   via the stride-correct path — but the ABI must not rely on that. FIX: size the
   initial buffer via `container_elem_storage_size_u64(elem_mir)`.
3. **`Pointer(T)#<<` appender hardcodes stride 8 + stores a pointer.**
   `llvm_backend.cr:13837-13856`: `elem_size = pointer_word_bytes_u64` and
   `store value_llvm %value, ptr %self` then advance by 8. The comment says this
   is "Array(T)#<< paths where T is a V2 struct carried as a pointer slot". For an
   inline POD payload, push must **memcpy the payload** (stride =
   `container_elem_storage_size_u64`) and advance by that stride. FIX: branch on
   the inline-POD predicate.
4. **raw `Array#<<` primitive fallback store (GPT round-1, promoted from verify).**
   `llvm_backend.cr:4453` ("primitive Array#<<(T) for late generic append
   bodies"). The grow path already sizes the buffer via
   `container_elem_storage_size_u64` (`:4452`), but the store path does
   `store #{elem_type} %value, ptr %slot` where `elem_type` is `ptr` for a struct
   → **stores the box POINTER into the payload slot, corrupting inline storage**.
   FIX: for an InlineValueCopy element, memcpy `stride` bytes from `%value` into
   the slot (mirror `emit_array_set` :25414), not `store ptr`.
5. **`Array#unsafe_fetch` primitive fallback load (GPT round-1, promoted).**
   `llvm_backend.cr:4499`. Byte-offsets correctly by stride (`:4498`) but then
   `%value = load #{elem_type}, ptr %slot; ret` with `elem_type = ptr` → **loads
   the first 8 payload bytes AS a pointer and returns it** (interior/corrupt).
   FIX: for InlineValueCopy, copy-load (materialize a temp per §4.4), not a raw
   `load ptr`.

### 2c. To VERIFY during implementation (anchors, not yet classified)
- `Pointer(T)#clear` `:13863` already routes through
  `container_elem_storage_size_u64` (`:13868`) — likely fine, confirm it memsets
  the payload stride, not 8.

---

## 3. Hazards → required reducers (each is a gate-ON DoD item)

1. **copy-on-store**: `arr << v; v.mutate` (v a struct local) leaves `arr[0]`
   unchanged (buffer holds an independent copy, not v's cell).
2. **copy-on-load**: `w = arr[0]; w.mutate` leaves `arr[0]` unchanged (load
   returns a copy, not the interior slot pointer). *This is the §2b.1 fix.*
3. **double-store independence**: `arr << v; arr << v` then mutating `arr[0]`
   leaves `arr[1]` unchanged (two independent slots, not one shared cell).
4. **realloc stride + ArrayNew sizing**: push past capacity preserves earlier
   elements bitwise (buffer byte size = `cap * container_elem_storage_size_u64`);
   IR check the stride equals payload size, not 8. **Reducer MUST include a
   12-byte leaf POD** (`Vec3{@x,@y,@z : Int32}`), not just Vec2 — otherwise the
   `emit_array_new` under-allocation path (§2b.2, masked at size 8) stays untested.
   `Pair` is NOT a valid ">8 simple check" (nested carrier, rejected by the gate).
5. **`to_unsafe` / interior pointer**: exposing `Pointer(Vec2)` into an inline
   buffer hands out interior pointers invalidated on realloc — carve-out or
   documented hazard (matches existing inline-family behavior).
6. **non-POD fallback**: `Array(WithStr)` (String field) stays pointer-stored
   (predicate rejects) — negative reducer.
7. **union fallback**: `Array(Vec2 | Nil)` is NOT a flat POD array — stays
   union/pointer storage. Gate on non-union.
8. **self-host**: s2b/s3b use `Array(struct)` internally; the flip must keep the
   regression suite (131/131 + 36/36) AND self-host green (broad blast radius).

---

## 4. Open questions for the owner/GPT (decide before coding)

RESOLVED with GPT round-1 (recorded so the impl follows them):

1. **Predicate placement → (b), but NOT a bool.** Precompute on the MIR `Type` a
   three-way **`ContainerElemRepr` enum: `PointerSlot | InlineAddress |
   InlineValueCopy`** (single source, the LayoutContract memo pattern step-1c
   used). Rationale (GPT): the existing `inline_container_struct_type?` branch is
   SHARED by the families that need **address-return** (`Slice(` / `StaticArray(` /
   `Hash::Entry(` → `emit_array_get` :25121 returns the slot ptr by design) and
   the new POD case that needs **value-copy**. Just adding Vec2 to that predicate
   would (a) give Vec2 address-return = the alias bug, and (b) risk the existing
   families. So: existing families → `InlineAddress` (current behavior, untouched);
   leaf-storage-POD ≤16 → `InlineValueCopy` (copy-on-store + escape-aware copy-on-
   load); everything else → `PointerSlot`. Every site in §2 switches on this enum.
2. **Gate semantics → confirmed separate.** New env `ADAMAS_INLINE_POD_CONTAINERS`
   (default OFF, gate-OFF byte-identical), independent of `ADAMAS_INLINE_SMALL_STRUCTS`
   (step-4 FIELD flip, `layout_contract.cr:134`). Independence is valid **only
   because v1 is leaf-POD** (no nested struct field whose repr depends on step-4).
   A future nested-POD extension MUST depend on / imply the field-inline ABI.
3. **Size bound → ≤16 for v1**, but the reducer set MUST exercise a 12-byte leaf
   POD (`Vec3`, §3.4) so the `emit_array_new` >8 under-allocation path is covered.
4. **Copy-on-load temp lifetime → escape-aware, NOT always-stack (GPT: always-
   stack = UAF).** For a NON-escaping rvalue use (`v = arr[0]; v.x` consumed in
   frame) materialize into an **entry-block stack `alloca`** (hoisted, never inside
   a loop body). For an ESCAPING load — `return arr[0]`, storing `arr[0]` into a
   field / another container, closure capture, `pointerof` — emit a **heap copy**
   (or explicitly reject the site → keep PointerSlot for that element type). v1
   needs a small escape classifier on the ArrayGet result; if that proves fiddly,
   the conservative v1 fallback is **heap-copy-always on load** (correct, costs one
   alloc/elem read) with the stack-alloca fast path added behind the escape check
   later.

---

## 5. DoD (when this storage slice lands)

- MIR `ContainerElemRepr` enum computed once per type; existing inline families
  classified `InlineAddress` (behavior unchanged — diff their IR to prove it);
  leaf-storage-POD ≤16 → `InlineValueCopy`; else `PointerSlot`.
- New gate `ADAMAS_INLINE_POD_CONTAINERS` (default OFF); gate-OFF byte-identical
  to current IR (diff a representative module + the full prelude module).
- Gate-ON: `Array(Vec2)` and `Array(Vec3)` buffer stride = payload size in IR
  (reducer #4, both 8B and 12B); push memcpy's payload (not `store ptr`) at ALL
  store sites (`emit_array_set` §2a, `Pointer(T)#<<` §2b.3, raw `Array#<<` §2b.4);
  `[]` / `unsafe_fetch` return a materialized copy (reducers #2, §2b.5),
  escape-aware.
- Reducers #1-#3, #6, #7 green; #5 (`to_unsafe` interior pointer) carve-out
  documented; escaping-load reducer (`return arr[0]` then mutate caller-side) does
  NOT alias the buffer.
- Regression suite 131/131 + 36/36; self-host s2b green vs current branch.
- **NOT claimed:** malloc/RSS drop — that is the later placement-fusion sub-slice.
