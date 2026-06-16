# Struct-Value ABI — Frontier SDD (step 0d)

Status: **CONTRACT for step 1. Gate before any step-1 code.** Strategy doc, not
yet implemented. Companion to `docs/abi_rework_quadr_plan.md` (the *why* and
sequencing) and `docs/layout_freeze_proposal.md` (the registry B0/B1 findings).

Purpose: the GPT adversarial review (critique #2) and the step-0a measurement
both concluded that "single oracle" (step 1) cannot be coded safely without a
written ownership contract — otherwise step 1 risks *minting a fourth oracle*
instead of unifying the three. This SDD names, in advance:

1. who OWNS the representation decision,
2. who OWNS field offsets,
3. what `slot_size` and `access_size` mean and the invariant that ties them,
4. which value boundaries the unified `layout_of` ADMITS, which it REJECTS
   (guard-only / skip-listed), and
5. the explicit migration of the LLVM string-prefix whitelist into a registry
   property.

It binds the hybrid-memory-model invariant from the plan §0: this contract makes
non-GC strategies SAFE by making layout deterministic. No clause here "fixes" a
repr-flip by routing to GC.

---

## 0. Non-goals (what this SDD does NOT do)

- **No inline-struct flip.** Step 4 (constructors emit inline aggregates +
  explicit `CopyStruct`) is out of scope and stays on an isolation branch. The
  contract below describes the *current* PointerCarrier ABI plus a single source
  of truth for it; it does not change whether a struct is heap-backed.
- **No new size computation oracle.** `layout_of` reads the already-computed
  registry layout (the `align_all_class_ivars` fixed point); it does not
  re-derive ivar sizes. Step 0c was deferred for exactly this reason
  (`TypeDescriptor` has no size; computing one is a layout oracle — plan §5).
- **No change to the skip-listed dedicated paths** (StaticArray / Tuple / Proc /
  Pointer / Union) beyond reading their repr through the same accessor.

---

## 1. The three current oracles (verified 2026-06-16) and where they split

| Oracle | Anchor | Decides | Rule (verified) |
|--------|--------|---------|-----------------|
| HIR | `ast_to_hir.cr:39412` `field_storage_size_impl` | field slot size | `storage = type_size(t)`. Small user struct (`0<storage<8`, `id≥FIRST_USER_TYPE`, `is_struct`, non-lib) → **8**. Small Tuple/NamedTuple → **8**. `NIL`(0) → **8**. Else → **`storage`** (large struct keeps inline size). |
| MIR | `hir_to_mir.cr:6353` `mir_field_storage_size` (+ side-set `@inline_struct_ptrs`, decl :114) | field slot size | Primitives hardcoded. **STRING → 8 (pointer)**. Else registry `desc.size if >0`, else **8**. **No small/large struct split.** |
| LLVM | `llvm_backend.cr:2756` `container_elem_storage_size_u64_impl` + `:2796` `inline_container_struct_type?` | container element slot size | primitive/enum → elem size; union `>8` → elem size; primitive-tuple → elem size; struct **only if name `starts_with` `Slice(`/`StaticArray(`/`Hash::Entry(`** → elem size; else → **8**. |

Where they disagree (the measured 18 CROSS + 22 slot≠access rows, plan §2.7):

- **String.** MIR field slot = **8 (pointer)** by an explicit `when … STRING`
  branch; HIR `type_size(String)` returns the **object size** and (being `≥8`)
  flows to the `else storage` line. Same value, two slot sizes recorded → the
  `(String, field-slot)` CROSS row. This is the exact seam the `#4` repr-flip
  lives in: a String slot sized as a pointer on one side, as a value on the
  other.
- **Small user struct.** HIR forces **8** (pointer carrier); MIR uses
  registry `desc.size` directly (could be `<8`). A small struct field can get an
  8-byte HIR slot and a `desc.size` MIR slot.
- **Container element struct.** LLVM inlines a struct ONLY via the string-prefix
  whitelist; any non-whitelisted struct element → **8 (pointer)**. A new inline
  family (e.g. a user struct that *should* be inline) silently falls through to
  8 → wrong stride (the `cb25a911` late-generic family: realloc 16 vs store 20
  vs read 24).

These are three independent functions answering the SAME question ("is a value
of type T at this slot a pointer or inline bytes, and how many bytes?"). The
contract gives them ONE answer source.

---

## 2. Representation taxonomy (single vocabulary)

The unified accessor classifies every type into exactly one `repr`, matching the
LayoutProbe taxonomy (`layout_probe.cr:24`):

- **`PointerReference`** — a class reference. The slot holds an 8-byte pointer to
  a heap object with a type-id header. Loads/stores move the pointer. *Correct by
  construction; never a repr-flip candidate.*
- **`PointerCarrier`** — a struct/tuple VALUE held via an 8-byte heap pointer
  (V2 legacy ABI). The slot holds 8 bytes (the pointer); the VALUE behind it is
  `value_size` bytes. This is *by-design indirection*, not corruption.
- **`InlineBytes`** — the value bytes live at the slot itself; slot size =
  value size (primitives, enums, explicit-layout unions `>8`, the whitelisted
  inline structs, primitive tuples).
- **`BorrowedAddress`** — an ACCESS MODE, not a storage class: a field access
  returns the address of inline storage with no load. Tracked for the
  FieldAddr/FieldGet split (step 3), never compared as a storage class in the
  divergence assert (`layout_probe.cr:149`).

`repr` answers "pointer or inline"; it does NOT by itself answer "8 or N bytes" —
that is the slot/access split in §4.

---

## 3. Ownership

> One owner per question. Phases READ; they do not each re-decide.

| Question | Owner (single source) | Readers |
|----------|----------------------|---------|
| **repr** (`PointerReference` / `PointerCarrier` / `InlineBytes`) of type T | the **MIR type registry** — a new `repr`/`inline?` property on the registered `Type`, set ONCE at the `align_all_class_ivars` fixed point | HIR `field_storage_size_impl`, MIR `mir_field_storage_size`, LLVM `container_elem_storage_size` + `inline_container_struct_type?` |
| **value_size** (bytes of the value itself) of T | the same registry layout (`desc.size` after final align) | all three phases |
| **slot_size** (bytes reserved AT a given slot in a given context) | derived: `repr == InlineBytes ? value_size : pointer_word_bytes` | all three phases, via one shared helper |
| **field offsets** within an owner | the registry's per-owner ivar layout (already the `align_all_class_ivars` output) — unchanged | all three phases |

Rationale for "registry owns repr": it is the only structure that already
survives all three phases, is frozen at a single fixed point (step 2), and
already carries `kind`/`size`. Putting `repr` next to `size` keeps the two
co-decided and frozen together — the B1a falsification proved that splitting
size across phases (relayout mid-lowering) is unsound. The LLVM string-prefix
whitelist (`:2796`) becomes a registry-population rule, not a runtime
name-match: at registration, a struct is marked inline iff it matches the
inline-ABI predicate; thereafter every phase reads the bit.

---

## 4. Slot vs access semantics (the drivable invariant)

The step-0a measurement sharpened the invariant away from bare
`slot_size == access_size`:

- `slot_size` = bytes reserved at the storage location for the slot's declared
  repr in that context.
- `access_size` = bytes the access actually reads/writes.

For a `PointerCarrier` slot, `slot_size = 8` and `access_size = 8` AT THE SLOT
(you move the pointer); the VALUE move behind the pointer is a separate
`value_size`-byte copy. So `slot==access` holds per slot **and** the producer
and consumer must agree on which of the two they are doing.

**Invariant (what step 3's verifier enforces):**

> For every value boundary, the PRODUCER's `(repr, slot_size, value_size)` for
> `(type, context)` equals the CONSUMER's. A producer that writes 8 bytes (a
> carrier pointer) into a slot a consumer reads as `value_size` inline bytes —
> or vice versa — is the repr-flip and MUST abort the verifier.

This is strictly stronger than `slot==access` and exactly catches the
`cb25a911` family (realloc 16 / store 20 / read 24 = three different
`(slot,value)` views of one container element).

---

## 5. Admitted vs rejected surface

`layout_of` / the unified accessor governs these boundaries (step 3 verifier
covers ALL — plan §3 "producer/consumer surface"):

**Admitted (must read the single repr source):**

- `FieldSet` / `FieldGet` / `FieldAddr`
- `IndexSet` / `ArraySet` / `unsafe_fetch` / `Array#<<` late-generic templates
- `return`, call `args`, plain `assignment`
- closure capture (env write/read)
- union payload store/load
- `CopyStruct` (once step 4 lands — guard-only until then)

**Rejected / guard-only (keep their dedicated paths; read repr but do NOT route
through the generic struct branch).** These have empirically-proven dedicated
layout paths; the B1a/B1c falsification history (plan §4) shows forcing them
through the generic path breaks stage2:

- `StaticArray(T, N)` — magic-base size arg; forcing it minted `inttoptr ptr ->
  ptr` (plan §4).
- `Tuple` / `NamedTuple` — HIR already special-cases small ones to 8 (:39440).
- `Proc` — closure env ABI (#2), separate track C.
- `Pointer(T)` — raw address, never a carrier.
- `Union` — explicit payload layout already inline when `>8` (`:2765`).
- lib structs (`@lib_structs`) — C ABI, never the V2 carrier.

The contract is: guard-only types still answer `repr` through the single
accessor (so the verifier can reason about them), but their slot/stride
computation stays in the dedicated path. The unified change is the *source of
the repr bit*, not a collapse of every path into one branch.

---

## 6. Migration shape for step 1 (informative, not yet code)

1. Add a `repr` (or `inline_value?`) property to the MIR registry `Type`, set at
   the `align_all_class_ivars` fixed point. Population rule absorbs the current
   `inline_container_struct_type?` whitelist predicate.
2. Replace the three independent decisions with one shared helper
   `slot_size_for(type, context)` that reads `repr` + `value_size`:
   - HIR `field_storage_size_impl` → delegate.
   - MIR `mir_field_storage_size` → delegate (drop the `STRING→8` special-case
     once String's `repr = PointerReference` makes the helper return 8 anyway).
   - LLVM `container_elem_storage_size` → delegate; `inline_container_struct_type?`
     becomes `elem_type.inline_value?`.
3. Keep the side-set `@inline_struct_ptrs` only if it survives as a *cache* of
   the registry bit; otherwise retire it (it is a fourth shadow oracle).

**Falsifier for step 1 (from the plan table):** with `ADAMAS_LAYOUT_PROBE=1
ADAMAS_LAYOUT_ASSERT=1`, a hello-world compile shows **0 CROSS rows** AND no NEW
slot/access mismatch class, while combined 31/31 + originals 158/158 +
`p2_generated_stage2_*` + s2b probe stay green. If a CROSS row remains, the bit
is not actually single-sourced (a phase still re-decides).

---

## 7. Open risks carried into step 1

- **String repr.** String is a class (`PointerReference`) but `type_size(String)`
  returns object size; the helper must return 8 for a String *slot* while the
  object itself is `value_size`. Verify the String header-size self-calibration
  (`v2_string_object_header?`) is not disturbed.
- **Freeze ordering (step 2 dependency).** The repr bit must be set at the SAME
  fixed point as final align; setting it earlier re-introduces the B1a
  mid-lowering unsound state. Step 1 writes the bit; step 2 freezes it.
- **Late monomorphization.** A type first registered AFTER the fixed point (B1
  on-demand mono) must get its repr bit at registration via the same predicate,
  not a default — else it falls back to a guess and re-splits.
