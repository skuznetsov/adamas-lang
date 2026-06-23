# Root Struct/Union Call-ABI — Software Design Document + Preflight Ledger

Status: **PROPOSED** (design + read-only preflight ledger; no behavior change). Owner-direction
SUPPORTED by data; root NOT fixed. Baseline HEAD `6a1662c4`.

## 0. Decisions (review-locked)

- **Carrier = MIR-level `PtrProvenance` fact (authoritative).** A `ptr` value's provenance is
  born at its MIR producer and propagated; it is NOT reconstructed in the backend. Rationale:
  the preflight ledger already shows the failing actuals arriving as `PARAM/unknown`, `load`,
  `Phi` — by the time the backend sees a bare `ptr` the storage-addr/payload distinction is
  gone, so a backend-only plan would need a second oracle.
- **`CallArgPlan` / `AbiValue` = LLVM CONSUMER, not authority.** `emit_call` may consume a
  planned ABI value, but it reads the MIR `PtrProvenance` fact; it does not invent it.
- **First slice = A (struct-storage provenance), FACTS-ONLY first.** No materialization until
  the facts can name the failing actual. B (union-payload ABI) comes only after A gives the
  vocabulary "this union payload must be rematerialized into struct storage". Reducer `/tmp/med.cr`
(s2b-context-only). Sibling fixes that are tactical and must stay untouched:
`85cde370` (join wrong-edge), `6a1662c4` (nilable-receiver overload bridge).

## 1. Problem: one `ptr` collapses three distinct entities

`src/compiler/mir/llvm_backend.cr` `compute_llvm_type_for_type` maps to LLVM `ptr`:
- `.struct?` → `"ptr"` (line ~309, comment "V2 ABI: structs as pointers — to be refactored to inline")
- `.reference?` → `"ptr"`
- all-ref `.union?` → `"ptr"`; non-all-ref union → `%Name.union` value-aggregate (~318)

So at a call boundary a `ptr` argument may be any of THREE semantically different things,
with no carried fact to tell them apart:

| Entity | What the `ptr` is | Deref as struct-storage? |
|---|---|---|
| **storage_addr** | address of memory laid out as `%TypeRef` (alloca / gep) | YES — correct |
| **object_ptr** | pointer to a heap object/header (reference type) | only the header |
| **union_payload / packed / null** | a *value* reinterpreted as a pointer (union payload, inttoptr'd wrapper scalar, or null) | **NO — UAF/garbage/null deref** |

A callee whose formal is a by-value small struct (`hir_type_is_lib_struct?(type : HIR::TypeRef)`,
which immediately does `type.id` → `ldr w8,[x8]`) ASSUMES storage_addr. When the actual is
a union_payload / param-unknown / null, the deref crashes (the MIR lib_struct frontier:
`HIRToMIRLowering#hir_type_is_lib_struct? +84`, EXC_BAD_ACCESS addr 0x0).

## 2. Evidence: call-boundary provenance ledger (read-only, removed after capture)

Added (temporarily) in stage1 `emit_call` per-arg formatting an exact-name-filtered ledger
(no ENV — s2b miscompiles `ENV.has_key?` in MIR; this fires in STAGE1 during the s2b build)
classifying each ptr actual by its producer MIR inst via `find_def_inst` →
`abi_ptr_provenance`: `storage_addr(stack_alloc|gep)` | `object_ptr(heap|array_new)` |
`union_payload(wrap|unwrap)` | `cast(kind)->…` | `load` | `const/null` | `PARAM/unknown`.

Result at the failing frontier — `hir_type_is_lib_struct?(arg1 = field_hir_type)`, formal
`HIR::TypeRef/ptr`, transparent-wrapper `i32`:

| provenance | count | storage_addr? |
|---|---|---|
| `PARAM/unknown(no_def_inst)` | 8 | unknown |
| `load` | ~7 | ambiguous |
| `union_payload(unwrap)` | 2 | **NO (provably a payload)** |
| `other(Phi)` | 2 | unknown |
| `storage_addr(*)` | **0** | — |

And one frame up — `lower_field_store_to_ptr` call:
- arg2 `obj_mir_type` formal `Nil | MIR::TypeRef` = `%Nil$_$OR$_…TypeRef.union` actual, provenance `Phi` / `call_ret`.
- arg5 `field_hir_type` formal `HIR::TypeRef/ptr`, provenance `load` (so `field.type` is loaded, not a fresh storage_addr; it then becomes the callee's PARAM, hence `PARAM/unknown` at the inner call).

**Falsifier outcome:** at the frontier NO actual is a provable `storage_addr`; the dominant
cases are `PARAM/unknown` and `load` (both indeterminate at emit time), and 2 are provably
`union_payload` (NOT storage). The previous "emit is type-correct" was correct ONLY under the
broken oracle: `ptr %field_hir_type` proves nothing about whether it is a storage address.
**emit_call cannot, from current facts, distinguish storage_addr from payload.** Per the
stop/falsifier rule: **do not patch behavior; we need an ABI provenance fact/contract first.**

## 3. Why no local emit_call shim is safe

- Forcing materialization (`alloca`+`store`) for struct-`ptr` formals would (a) be wrong when
  the actual IS a real storage_addr/object_ptr (double indirection), (b) ptrtoint a value of
  unknown provenance, (c) risk UAF if the callee stores the pointer (no borrow/escape proof).
- The `union_payload(unwrap)` cases need union-UNPACK, not struct-materialize — mixing both in
  one rule is the adjacent-mechanism trap (GPT hard-stop). 
- `PARAM/unknown` cannot be resolved without cross-boundary provenance.

## 4. Proposed contract: ABI value provenance (the prerequisite)

Introduce a first-class provenance fact so a `ptr` is never anonymous at a call boundary.
Two viable carriers (pick in review):
- **MIR fact** `@value_ptr_provenance : Hash(ValueId, PtrProvenance)` populated at producer
  sites (Alloc→StorageAddr, Gep→StorageAddr, malloc/new/array_new→ObjectPtr,
  UnionUnwrap/payload→UnionPayload, Const0→Null, inttoptr-of-scalar→PackedScalar), propagated
  through Load/Phi/Copy/Cast and across call boundaries via formal provenance contracts.
- **Backend `CallArgPlan` / `AbiValue`** wrapping `{value, llvm_type, provenance}` so `emit_call`
  consumes a planned ABI value instead of re-deriving type from a bare `ptr`.

Enum `PtrProvenance = StorageAddr | ObjectPtr | UnionPayload | PackedScalar | Null | Unknown`.

Rule for a struct-storage formal (`hir_type_is_lib_struct?`-like): accept only `StorageAddr`;
`PackedScalar`/`UnionPayload` → materialize/unpack to a storage slot before the call;
`Unknown` → **fail closed** (keep legacy passthrough + log; never silently materialize).

## 5. First behavior slice (AFTER this SDD is reviewed; NOT in this artifact)

Exactly ONE of (not both — keep the union-overload bug `6a1662c4` separate):
- **(A) struct-storage provenance + materialization**: populate `PtrProvenance` for struct
  producers, and in `emit_call` route `PackedScalar`→struct-storage formal through stack
  materialization; `Unknown`→fail closed. Smaller, more contained.
- **(B) union-payload ABI**: stop emitting an unwrapped union payload into a struct-storage
  formal; carry the struct by value through the union or re-materialize on unpack.

DoD for the first slice: frontier IR shows a slot/store/pass-storage_addr (no anonymous
`ptr` of unknown provenance into a struct formal); gated s2b passes the MIR
`hir_type_is_lib_struct?` frontier (next crash, if any, is separate); original 148/148 +
combined 36/36; no stage1 behavior change; `85cde370`/`6a1662c4` intact.

## 6. Claim calibration

- VERIFIED: the frontier `ptr` provenance is param/load/phi/union_payload, **never a provable
  storage_addr** (ledger). The 3-entity collapse is real and unresolved.
- NOT claimed: root fixed; emit_call correct; s2b clean.
- Next artifact: this SDD → review (pick MIR-fact vs CallArgPlan carrier, and slice A vs B) →
  one narrow behavior slice. Do not attempt a generic inline-i32 / union ABI rewrite by
  intuition (that is the C-wide AbiFacts arc, not a small unblock).

## 7. Slice-1 result — slot-VALUE contract built; data REPRIORITIZES the layers (no behavior)

KEY correction adopted: a GEP yields a slot ADDRESS; the LOADED value's kind comes from the
field/element DECLARED type (slot-value contract), not from the address's provenance. Built
(read-only) `slot_value_kind` + `classify_loaded_value` with the negative guarantee
(reference/String/Array/Hash/Pointer/Proc -> ObjectPtr; transparent-wrapper struct ->
PackedScalar; only a non-wrapper struct -> StructStorageRef), plus a Pointer(T) element-slot
case. NO behavior (read-only classifier + stderr ledger; IR byte-identical by construction).

**Empirical bucket distribution across ALL struct-`ptr`-formal call args in the s2b build:**
`param` 30 · `ptr_no_element_type` (opaque Pointer) 10 · `phi_mixed` 2 ·
`UnionPayload(union_unwrap)` 2 · `call_ret` 1 · **resolvable struct-field load: 0**.

So the slice-1 struct-field slot-value contract is correct but **never fires** for the relevant
calls: the actuals are NOT struct-field loads. The 3-entity collapse is wider than assumed — it
also erases **Pointer(T) -> opaque `Pointer`** (element type gone), and the DOMINANT carrier is
**cross-boundary params (30×)**. The failing `field_hir_type` itself = 8× param + 6× opaque-ptr
load + 2× union + 2× phi; **0 storage_addr**, and still Unknown after slot-value. Per hard-stop
#4: NO behavior.

**Reprioritized facts layers (the actual unblockers, both read-only):**
1. **Param formal-provenance propagation (was "slice 2", now the FIRST real lever — 30× params):**
   thread an actual's `PtrProvenance` into the callee's formal so a param resolves from its
   caller(s); merge across call sites (Unknown on conflict).
2. **Pointer(T) element-type facts (10× opaque `Pointer`):** the MIR loses `Pointer(T)`'s element
   type to opaque `Pointer`; without it a `Load(Pointer)` cannot be classified. Either recover the
   element type at the producer or fail-closed Unknown (never assume).
The struct-field slot-value classifier is kept in the SDD as the eventual consumer once values
become field-backed, but it is NOT committed (it would be dead infra today). Behavior remains
forbidden until `field_hir_type` is non-Unknown via (1)+(2).
