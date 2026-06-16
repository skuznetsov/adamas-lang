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

**Phase-ordering correction (verified 2026-06-16, step-1 reconnaissance).** The
single source is NOT the MIR registry — it CANNOT be, because the HIR reader
`field_storage_size` runs *inside* `align_all_class_ivars`
(`ast_to_hir.cr:28124`), a pure-HIR pass that completes **before** the MIR
registry is populated. A registry-owned bit would be unreadable at the earliest
(and offset-producing) site. The single source is therefore a **pure decision
function** `inline_value?(kind, size, name, is_lib_struct)`, callable in all
three phases from the type metadata each phase already has, and **memoized as a
bit on the MIR `Type`** for the two later phases (the bit is a *cache* of the
function, not the authority). HIR calls the function directly against its
`class_info` view; MIR/LLVM read the memoized bit (populated at MIR `Type`
creation from the already-aligned HIR layout — which IS the post-align fixed
point, since HIR align happens-before MIR `Type` creation).

| Question | Owner (single source) | Readers |
|----------|----------------------|---------|
| **repr** (`PointerReference` / `PointerCarrier` / `InlineBytes`) of type T | a **pure predicate** `LayoutContract.inline_value?(kind, size, name, is_lib)` + repr classifier; **memoized** on the MIR `Type` for MIR/LLVM | HIR `field_storage_size_impl` (calls fn directly, pre-MIR), MIR `mir_field_storage_size` (reads memo), LLVM `container_elem_storage_size` + `inline_container_struct_type?` (reads memo) |
| **value_size** (bytes of the value itself) of T | the HIR class_info layout (the `align_all_class_ivars` output), copied to MIR `Type.size` at creation | all three phases |
| **slot_size** (bytes reserved AT a given slot in a given context) | derived: `inline_value? ? value_size : pointer_word_bytes` | all three phases, via one shared helper |
| **field offsets** within an owner | the HIR class_info per-owner ivar layout (the `align_all_class_ivars` output), copied to MIR `Type` fields — unchanged | all three phases |

Rationale for "pure function + MIR memo": the DECISION must be identical in all
three phases, but the HIR reader runs before any registry exists, so the
authority has to be a function each phase can call against its own type view —
not a shared data structure. Memoizing the result on the MIR `Type` (next to
`size`) keeps repr and size co-frozen for the two later phases — the B1a
falsification proved that splitting *size* across phases (relayout mid-lowering)
is unsound; the same discipline applies to the repr bit (write once at MIR
`Type` creation from the frozen HIR layout, never re-decide). The LLVM
string-prefix whitelist (`:2796`) becomes the predicate's struct-family clause,
not a runtime name-match.

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

## 6. Migration shape for step 1 (SPLIT into 1a/1b/1c — phase-ordering correction)

The step-1 reconnaissance (mini-Quadr, 2026-06-16) showed a single big-bang
reader flip is VULNERABLE: most CROSS rows are *labels* (String field-slot
verified to be 8 on BOTH HIR and MIR — a name divergence, not a size one), while
the only size-affecting flip is the container-element whitelist. So step 1 is
split into independently-gated sub-steps, smallest/safest first:

**1a — pure predicate + MIR memo (additive, SAFE).** Add a single pure function
`LayoutContract.inline_value?(kind, size, name, is_lib)` (new module) reproducing
the *current* effective decisions, plus a memoized `inline_value?` bit on the MIR
`Type` populated at `Type` creation from the frozen HIR layout. No reader changed
yet — the bit is computed but unused. Gate: build + suites green (no behavior
change); the probe shows the SAME divergence set as before.

**1b — label unification (no size change).** Route the three phases' LayoutProbe
`storage` LABEL through the shared repr classifier so the same 8-byte String slot
is labelled identically everywhere. This drives CROSS *label* rows → 0 without
touching any slot size. Gate: probe 0 CROSS rows that are label-only; suites
green (sizes unchanged by construction).

**1c — container-element reader flip (the lone CAUTION size change).** Replace
`inline_container_struct_type?`'s string-prefix whitelist (`:2796`) with
`elem_type.inline_value?` (the memo bit). This is the only sub-step that can
change a slot size (a struct family newly recognized as inline). Falsifier: no
NEW slot/access mismatch class in the probe; combined 31/31 + originals 158/158 +
`p2_generated_stage2_*` + s2b probe green; the `cb25a911` late-generic reducer
stays fixed. HIR `field_storage_size_impl` and MIR `mir_field_storage_size`
delegate to the predicate here too; the MIR `STRING→8` special-case is dropped
only once String's `PointerReference` repr makes the helper return 8 anyway.

Side-set `@inline_struct_ptrs` is kept only if it survives as a *cache* of the
predicate; otherwise retired (it is a fourth shadow oracle).

**Falsifier for step 1 overall:** with `ADAMAS_LAYOUT_PROBE=1
ADAMAS_LAYOUT_ASSERT=1`, a hello-world compile shows **0 CROSS rows** AND no NEW
slot/access mismatch class, while combined 31/31 + originals 158/158 +
`p2_generated_stage2_*` + s2b probe stay green. If a CROSS row remains, a phase
still re-decides instead of calling the predicate.

---

## 7. Open risks carried into step 1

- **String repr — VERIFIED 2026-06-16.** `type_size(String)` falls to the
  `ref_fallback` branch (`ast_to_hir.cr:38980`) and returns `pointer_word_bytes`
  (8); MIR `mir_field_storage_size` returns 8 via its explicit `STRING` case. So
  the String *field* slot is already 8 on BOTH sides — the CROSS row is a LABEL
  divergence (`InlineBytes` vs `PointerReference`), closed by step 1b without any
  size change. The String OBJECT is `value_size` bytes behind that pointer; keep
  the header-size self-calibration (`v2_string_object_header?`) undisturbed.
- **Freeze ordering (step 2 dependency).** The repr bit must be set at the SAME
  fixed point as final align; setting it earlier re-introduces the B1a
  mid-lowering unsound state. Step 1 writes the bit; step 2 freezes it.
- **Late monomorphization.** A type first registered AFTER the fixed point (B1
  on-demand mono) must get its repr bit at registration via the same predicate,
  not a default — else it falls back to a guess and re-splits.
