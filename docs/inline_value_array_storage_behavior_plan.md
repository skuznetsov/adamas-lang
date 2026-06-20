# A′ inline-value Array storage — behavior slice plan & DoD

**Status: PROPOSED (owner-gated). NOT implemented.** This is the design/DoD packet
that must be reviewed before the first commit where LLVM reads the A′ marks — that
read already changes the Array(C) ABI (CAUTION-tier). Risk tier: **CAUTION**
(serialization/layout + ABI change). Branch: `abi-struct-byvalue`.

## PREFLIGHT FINDING (2026-06-20) — behavior is NOT one bounded diff yet

Measuring the mutation-family lowering BEFORE writing any codegen fired GPT's
stop-rule. Evidence chain:

- `Array#delete_at`/`shift`/`insert`/`concat` move elements with
  `(@buffer + i).move_from/copy_from(...)` (src/stdlib/array.cr:819, 854, 1029, 332).
- `Pointer#move_from_impl`/`copy_from_impl` → `Intrinsics.memmove(self, src,
  bytesize(count))` (src/stdlib/pointer.cr:262, 276).
- `Pointer#bytesize(count)` = `count * sizeof(T)` → LLVM
  `count * container_elem_storage_size_u64(T)` — **type-global** (llvm_backend.cr:
  13774, 13807). That helper is shared with standalone `Pointer(T)` and
  `StaticArray`, so it must NOT be flipped globally (GPT #3 / the refuted slice).

Crucially, the memmove executes inside `Pointer(T)#move_from_impl` / `#bytesize`
bodies — monomorphized per element T, but **NOT `Array(C)#` bodies**. So §2/§3's
"Array-context provenance = the enclosing monomorphic `Array(C)#` body" does NOT
reach the memmove byte-count: by the time control is in `Pointer(Vec3)#bytesize`,
the Array identity is gone, and `Pointer(Vec3)#bytesize` is the SAME body whether
the pointer is an `Array(Vec3)` `@buffer` or a standalone `Pointer(Vec3)`.

**Consequence:** the durable `array_buffer_value` mark covers only the value
Load/Store gep_dyn (push/`<<`/`[]`/unsafe_fetch). The mutation family has NO
provenance. If `Array(Vec3)` stored inline (stride 12) while `bytesize` stayed
type-global (8), the first `delete_at`/`shift`/`insert` would memmove the wrong byte
count → heap corruption. A store/load-only flip is exactly the partial flip GPT
forbids.

**Decision: STOP before behavior; do the pre-authorized infrastructure commit for
mutation-family coverage marking first** (see §8). This is the architectural
non-uniformity the standalone slice hit earlier (struct buffer wants inline; the
shared `Pointer(T)` byte-count path wants the existing type-global size).

## 0. Where we are (infrastructure already shipped, read-only)

- `classify_container_elem_repr` / `leaf_storage_pod_struct?` — leaf-POD value
  structs classified `InlineValueCopy` (raw-pointer-field structs excluded, commit
  `d9dd8989`).
- `run_array_buffer_provenance_probe` — proves the buffer-base mark set lands 0
  times outside an `Array(C)` body (commit `22814b4f`).
- `compute_inline_value_safe_set` + `run_inline_value_safe_set_probe` — per-type
  safe-set `{ C | bv && !vd && !erased_flow }`, flow-based erased gate (commit
  `20749d09`).
- `populate_inline_value_safe_set` / `verify_inline_value_annotation` — durable
  marks `Type#inline_value_safe` and `GetElementPtrDynamic#array_buffer_value`,
  read by NO lowering site yet (commit `b4597141`).

The behavior slice CONSUMES exactly those two marks. It does NOT re-derive
provenance by element type/name in LLVM (that is the refuted type-driven slice).

## 1. Single behavior gate that owns the annotation (GPT #1)

One gate: **`ADAMAS_INLINE_VALUE_ARRAY_STORAGE`**. Turning it on MUST itself run
`populate_inline_value_safe_set` (so the marks exist whenever lowering reads them)
AND `verify_inline_value_annotation` (so the `[IVANNOT]` evidence is emitted under
this single gate too). Never require two env vars (`ANNOTATE` + behavior): a
behavior-on / annotate-off combination would read default-`false` marks and
silently box everything (or worse, read stale marks) — a silent false-mark path.
Emitting `[IVANNOT]` under the behavior gate is also what lets the post-behavior
guard (§5.4) keep its mark evidence after re-pointing `GATE` to the behavior gate.
Implementation: in `lower_all_bodies`, `populate_inline_value_safe_set` +
`verify_inline_value_annotation` run if `ADAMAS_INLINE_VALUE_ARRAY_STORAGE` is set
(in addition to the existing standalone `ADAMAS_INLINE_VALUE_ANNOTATE`). LLVM
lowering reads the marks only when `ADAMAS_INLINE_VALUE_ARRAY_STORAGE` is set.

## 2. Array-CONTEXT stride, never type-global (GPT #2)

Do NOT change `container_elem_storage_size_u64_impl` (llvm_backend.cr:2756) to
return `elem.size` for `inline_value_safe` structs. That function is shared by
NON-Array callers — `Pointer(T)#bytesize` (~13774), `StaticArray(T,N)` alloca
(~6416) — so a type-global flip re-introduces the refuted over-firing on
`Pointer(T)` paths (the IO#gets_peek `switch i32` blocker; see
`inline_value_nonarray_pointer_guard.{cr,sh}`).

Instead introduce an **Array-context** stride, e.g.
`array_inline_stride(elem) = inline_value_safe?(elem) ? elem.size : container_elem_storage_size_u64(elem)`,
used ONLY at sites that carry Array provenance:
- the marked `GetElementPtrDynamic` (`array_buffer_value == true`), and
- the monomorphic `Array(C)#…` bodies / Array-literal allocation keyed by the
  `Array(...)` container type.

`Pointer(T)`, `Slice(T)`, `StaticArray`, and generic non-Array uses keep
`container_elem_storage_size_u64` unchanged.

## 3. Atomic Array(C) storage family — all sites flip together (GPT #3)

"Inline-store at marked GEPs" alone is INSUFFICIENT: allocation size, store offset,
load offset, realloc size and memmove byte counts must all agree on the same stride,
or the buffer is under/over-sized and grows corrupt. The slice must flip the whole
family in one commit:

| site | today (plain struct) | target (inline_value_safe in Array context) |
|---|---|---|
| array-literal / capacity alloc | `n * 8` (ptr slot) | `n * elem.size` |
| grow / realloc stride (`Array#<<` late-generic :4470; `resize_to_capacity`) | `cap * 8` | `cap * elem.size` |
| store (`push`/`<<`/`[]=`; marked gep_dyn + Store; late-generic :4480) | `store ptr %value` | `memcpy(slot, value, elem.size)` |
| load / copy-on-load (`unsafe_fetch`/`[]`; marked gep_dyn + Load; late-generic :4499) | `load ptr` | heap-carrier copy (see §4) |
| memmove family (`delete_at`/`shift`/`insert`/`shift_buffer_by`/`root_buffer`) | byte count `n * 8` | `n * elem.size` |
| `concat` / `ptr_copy` / `ptr_move` (`elem_size` param, :7802/:7901/:7909) | passes 8 | passes `elem.size` |

The provenance probe's four categories map here: `buffer_value` = store/load sites;
`buffer_ptr_arith` (root_buffer / shift_buffer_by / delete_at memmove) = the memmove
family — repr-agnostic on direction but stride-dependent on byte count.

**The whole family is MANDATORY — no "if touched" (GPT blocker).** Once `Array(Vec2)`
holds an inline payload, EVERY `delete_at` / `shift` / `insert` / `root_buffer` /
`shift_buffer_by` / `ptr_move` path must use the same stride, or the first call to
such a method is heap corruption — not an edge case. So the memmove/arith family is
a required part of the behavior commit, not a follow-up.

**Provenance for the memmove/arith family (GPT #2).** The durable per-site mark
`array_buffer_value` covers only the value Load/Store gep_dyn — there is no
value-access gep to mark on a memmove byte-count or a `shift_buffer_by` pointer add.
These sites must therefore NOT be fixed type-global. They get their stride from
`array_inline_stride(C)` applied with **Array-context provenance = the enclosing
function is a monomorphic `Array(C)#…` body** (the census confirms
`Array(Range(Int32,Int32))#delete_at` / `#shift_when_not_empty` are monomorphic, so
the element type C and the Array identity are both statically present in the body).
`array_inline_stride(C)` returns `elem.size` only when `inline_value_safe?(C)`.

**Fail-closed (GPT #1 blocker, completeness).** If the analysis cannot confirm that
EVERY mutating-family method used on an `Array(C)` in the program resolves to a
monomorphic `Array(C)#…` body covered by `array_inline_stride` — e.g. the program
routes an `Array(C)` through a shared/erased mutation body — then C must NOT be
inline-stored. `erased_flow` already excludes any C whose `Array(C)` flows into a
type-erased body; the behavior commit extends the same fail-closed stance to the
mutation family: ship inline storage ONLY for the families actually lowered, and
exclude any type that would reach an uncovered path.

## 4. Copy-on-load v1 = heap carrier (GPT #4)

v1 returns each loaded element as a **heap-allocated carrier copy in the EXISTING V2
struct carrier layout** — `[i64 INT64_MAX sentinel header][payload]`, returning the
pointer to the payload (`raw + 8`), exactly the 8-byte GC sentinel-at-`ptr-8`
convention every V2 object / `$Dnew` / String allocation uses (e.g.
llvm_backend.cr:10553-10572, `store i64 9223372036854775807, ptr %raw`). NOT
`malloc(payload)`: a header-less buffer would make the loaded value distinguishable
from a real `$Dnew` struct pointer and break `rc_inc`/`rc_dec` at `ptr-8` and GC
scanning. The plan adds (or reuses) one helper, e.g.
`emit_inline_value_load_carrier(payload_ptr, size)` → mallocs `8 + size`, stores the
sentinel at `raw`, `memcpy(raw+8, payload_ptr, size)`, returns `raw+8`; named here so
the behavior commit wires one helper rather than open-coding the carrier at each load
site. NO stack fast path in v1 (a stack temporary / SROA path is a separate, later
optimization — it is also the real perf win, but it is NOT this slice). Rationale: a
heap carrier is escape-safe by construction (it cannot dangle when the loaded value
outlives the buffer), so v1 trades the perf win for correctness; the stack fast path
needs escape analysis we are not landing here.

## 5. DoD — reducers required before/with the behavior commit (GPT #5)

Runtime reducers (run via `scripts/run_safe.sh`; observe via STDERR + flush):
1. **Vec2 copy-on-store / copy-on-load / no-alias** — push N, read back, mutate a
   loaded copy, confirm the buffer is unchanged (value semantics, not aliasing).
2. **Vec3 12-byte realloc stride** — push past the initial capacity so a realloc
   fires; confirm all elements survive the grow (stride agreement across alloc /
   store / realloc / load).
3. **Vraw remains boxed / not inline** — a struct excluded by the safe-set
   (value_derived) keeps the existing pointer-slot ABI and stays correct.
4. **raw Pointer(Vraw) / non-Array Pointer(T)#value unchanged** — the existing
   `inline_value_nonarray_pointer_guard.{cr,sh}` with `GATE` re-pointed to
   `ADAMAS_INLINE_VALUE_ARRAY_STORAGE`: out=42, Disc not-marked, array_buffer_value
   outside=0, 0 `ivc_raw`. This requires the behavior gate to emit `[IVANNOT]`
   (§1); otherwise the re-point loses the mark evidence.
5. **delete_at / shift / insert (MANDATORY, not "if touched")** — element removal /
   insertion preserves the remaining elements at the inline stride. Because the
   memmove family is part of the atomic flip (§3), these reducers are required, not
   conditional; a partial store/load-only flip is VULNERABLE.
6. **Negative: Pointer(Range)/Pointer(Hasher)#value and an IO-class path** emit 0
   `ivc_raw` — the type-driven blast-radius types are NOT inline-loaded outside an
   Array buffer.

Static / neutrality checks:
- gate OFF: byte-identical LLVM IR vs pre-slice (the only durable safety net).
- `ivc_raw` appears ONLY at Array(C) `array_buffer_value` sites; 0 elsewhere.
- full A′ reducer set (`inline_value_safe_set_probe`, `inline_value_annotation_probe`,
  `leaf_pod_struct_pointer_field_repro`, `array_buffer_provenance_marker_probe`)
  stays green.
- regression suites (`run_all_suites` / combined / original) no new failures.

## 6. 48h pre-mortem (CAUTION-tier)

- **Likely breakage:** stride disagreement between any two of {alloc, store, load,
  realloc, memmove} → heap OOB on grow or garbage reads (the historical s2b Globber
  PatternType crash family). **Fastest signal:** reducer 2 (realloc stride) +
  ASAN-style OOB; and the gate-OFF byte-identical check catching accidental
  non-gated changes.
- **Silent miscompile:** an Array(C) read that A′ does NOT convert (an unmarked but
  real buffer read) → reads inline bytes as a pointer. **Signal:** reducer 1 no-alias
  + value read-back; provenance probe `buffer_value_outside_array == 0` must still
  hold for any new access form added.
- **Blast-radius leak:** the stride flip reaching a non-Array path. **Signal:**
  reducer 4 + 6 (0 `ivc_raw` on Pointer/IO paths); §2 keeps
  `container_elem_storage_size_u64` untouched.
- **Escape / dangling:** a loaded element outliving its buffer. **Mitigation:** §4
  heap carrier (escape-safe); no stack fast path in v1.
- **Rollback:** single gate; gate OFF = byte-identical. Commit is isolatable on
  `abi-struct-byvalue`; revert is one commit.

## 7. Sequencing

1. (this packet) plan + preflight guard reducer — review gate.
2. **(NEXT, pre-authorized) Infrastructure: mutation-family coverage marking** — see
   §8. Read-only first. Without it, behavior cannot be one bounded diff.
3. Behavior commit: single gate runs annotation + verify (emits `[IVANNOT]`);
   `array_inline_stride` + the §3 family flip (store/load AND the MANDATORY
   memmove/delete_at/shift/insert/root_buffer family) + §4 heap-carrier load,
   guarded by `array_buffer_value` && `inline_value_safe` (value sites) and by the
   §8 mutation-family marks (memmove/arith sites), with fail-closed exclusion of any
   type reaching an uncovered path; all §5 reducers + gate-OFF neutrality. One
   atomic commit (the whole Array storage family). A partial store/load-only flip is
   VULNERABLE and must not ship.
4. Later (separate): stack fast path / SROA for the loaded carrier (the perf win),
   and folding into the broader by-value struct ABI (C).

## 8. NEXT infra commit — mutation-family coverage marking (read-only first)

The value path already has a durable per-site mark (`array_buffer_value`). The
mutation family (memmove / pointer-arith byte counts) has none, and its byte count
is computed by the type-global `Pointer(T)#bytesize` — see PREFLIGHT FINDING. So the
next infra commit must give the mutation family the SAME provenance discipline:

- **Provenance to establish:** a `Pointer(C)` that is derived from an `Array(C)`
  `@buffer` (via the static `@buffer` GEP, possibly through `+ index` pointer
  arithmetic) and then flows into `move_from`/`copy_from`/`memmove`/`bytesize`. The
  call site is inside the monomorphic `Array(C)#` body (delete_at/shift/insert/
  concat/…), so the Array identity IS present AT THE CALL SITE — it is only lost once
  control enters the shared `Pointer(T)#` body. Mark must therefore be attached at
  the call site / the @buffer-derived pointer value, not inside `Pointer(T)#bytesize`.
- **Read-only deliverable (matches the `array_buffer_value` pattern):** a new durable
  mark (e.g. `array_buffer_derived` on the relevant MIR value/instruction, or a
  per-call flag) set by an analysis that taints `@buffer`-derived `Pointer(C)`;
  `verify` reports it; prove the mark lands 0 times outside an `Array(C)#` body, and
  that it covers every delete_at/shift/insert/concat site for the safe-set types.
- **Executable fail-closed (GPT #2):** refine the eligibility set to
  `inline_value_safe && mutation_family_fully_covered(C)` — a separate behavior-
  eligibility bit. If any mutation method used on `Array(C)` is NOT a marked,
  monomorphic, covered site, C is excluded from inline storage. Text alone is
  insufficient; this bit is the executable gate.
- **Then** the behavior commit (step 3) can make BOTH the value sites (via
  `array_buffer_value`) and the mutation sites (via the new mark) Array-context,
  leaving `container_elem_storage_size_u64` / standalone `Pointer(T)` untouched.

### 8.1 Design decision: (b′) call-site Array bulk-op marking/rewrite (GPT)

Decision = **(b′)**, NOT inter-procedural taint (a). (a) would have to carry taint
through `@buffer + index`, into `move_from`/`copy_from` args, then into the shared
`Pointer(T)#bytesize` — requiring a hidden param / specialized clone, i.e. an
inter-procedural taint ABI. That is broader than this slice and re-raises repr-flip
risk. (b′): the Array identity and element type ARE present at the call site inside
the monomorphic `Array(C)#` body, so we rewrite only the proven Array-buffer bulk ops
there to a direct inline-stride op, never touching standalone `Pointer(T)`.

**Verified MIR shape (grounds (b′)).** The bulk ops are already INLINED inside each
monomorphic `Array(C)#` body as raw extern_calls — `@llvm.memmove.p0.p0.i64`,
`@llvm.memcpy.*`, `@llvm.memset.p0.i64`, `@__adamas_malloc64` — not `Pointer#move_from`
Calls. The family bodies exist as named monomorphic functions
(`Array(Vec3)#delete_at$Int32`, `#concat$Array(Vec3)`, `#insert$…`, `#shift_when_not_empty`,
`#shift_buffer_by$Int32`, `#resize_to_capacity$Int32`, `#increase_capacity`,
`#root_buffer`, `#to_unsafe`, `#unshift$Vec3`, `#insert_elements_at$…`, …), so
"is this op inside an `Array(C)#` body" is answerable by function name. (b′) =
rewrite the byte-count/stride of those extern_calls within Array(C)# bodies.

### 8.2 Full bulk-op surface (GPT #1 — bigger than move_from/copy_from)

`src/stdlib/array.cr` routes element bytes through MANY bulk ops, all sized by the
type-global element size today:
- **move_from / move_to** (overlap memmove): :463, :528, :534, :819, :854, :1029,
  :1071, :2183 — delete_at / shift / insert / unshift / rebalance.
- **copy_from** (memcpy): :332, :333, :390, :394, :398, :523, :527, :535, :665, :884,
  :1081, :1087, :1243, :1470, :1505, :1506, :2073, :2114 — concat / replace / dup /
  rotate / shift-buffer.
- **clear** (`Pointer#clear` = `memset(self,0,bytesize(count))`, pointer.cr:562/570):
  :459, :464, :529, :687, :821, :856, :1209, :1342, :1380, :1467, :1550, :1588, :1875,
  :1876, :1991, :2084, :2117, :2184 — ALSO type-global, must be covered.
- **alloc** (`Pointer(T).malloc(capacity)` / `malloc(size, value)`): :122, :156, :2166,
  :2186 — buffer allocation stride.
- **elementwise** (`@buffer[i] = …`, `<=>`): :249, :1776, :1785 — the value `[]`/`[]=`
  path, already covered by `array_buffer_value`.

### 8.3 Heterogeneous / same-class guard (GPT #2 — verified)

`Pointer#copy_from_impl` / `move_from_impl` (pointer.cr:258-287) branch on
`self.class == source.class`:
- **same class** → `Intrinsics.memcpy/memmove(self, src, bytesize(count))` — the
  type-global byte count = the hazard (b′) rewrites.
- **different class** → elementwise `self[i] = source[i]` — the value `[]`/`[]=` path
  (per-element), already the `array_buffer_value` path. NOT a raw memcpy.

So (b′) is valid ONLY where the call site proves SAME element representation
(`Array(C)` ↔ `Array(C)`). For `Array(T|U).build` / union-widening concat, the path is
heterogeneous (elementwise) — leave it to the value path OR fail-closed. Concrete
leaf-POD `C` (the safe-set) is monomorphic, so `Array(C)` bulk ops are same-class; the
census must PROVE this per type, not assume it.

### 8.4 Read-only census categories + executable fail-closed (GPT #3, #4)

A read-only `run_array_bulk_op_census` (new gate) walks each monomorphic `Array(C)#`
body (C ∈ InlineValueCopy candidates) and classifies its bulk extern_calls:
- `array_bulk_move_copy_same_elem` — memmove/memcpy whose stride is the element
  storage size on the `@buffer` (covered: direct-byte rewrite is safe).
- `array_bulk_clear` — memset on `@buffer` (covered).
- `array_bulk_alloc` — `@buffer` malloc by capacity (covered).
- `array_bulk_uncovered` / `heterogeneous_copy` — anything else (an elementwise/union
  path, an op whose stride can't be tied to the element size, or a bulk op the rewrite
  doesn't handle) → **excludes C**.

Executable eligibility bit: `behavior_eligible(C) = inline_value_safe(C) &&
no array_bulk_uncovered/heterogeneous op exists in any Array(C)# body it uses`. If any
uncovered/heterogeneous bulk path exists for `Array(C)`, C is NOT inline-stored. This
bit (not prose) gates the eventual behavior.

### 8.5 Reducer (before behavior)

`delete_at` / `shift` / `insert` / `clear` / `concat` on `Array(Vec3)` (12-byte, so
stride ≠ pointer) are all classified covered for Vec3; PLUS a negative: a union /
heterogeneous element Array (or `Array(T|U)`) shows `heterogeneous_copy` →
`behavior_eligible=false`. Read-only / gate-OFF byte-identical.

### 8.6 IMPLEMENTED (read-only, 2026-06-20) — mini-AbiFacts census

Built per (b′) + GPT's strict constraints. Gate `ADAMAS_ARRAY_BULK_OP_FACTS`.
Typed facts in `mir.cr`: `ArrayBulkOpKind`, `ArrayBulkCoverageReason`,
`Type#inline_array_storage_eligible`, `ExternCall#array_bulk_op`, `Call#array_bulk_op`.
Pass in `hir_to_mir.cr`: `populate_array_bulk_op_facts` + `classify_array_bulk_op`
(extern: `__adamas_ptr_move`/`ptr_copy`, `llvm.memmove`/`memcpy`/`memset`,
`malloc`/`realloc`) + `classify_array_bulk_call` (`Pointer(C)#clear`/`move_from`/…) +
`compute_array_buffer_roots` + `traces_to_array_c_buffer?` + `count_is_strided?` +
`verify_array_bulk_op_facts`.

Provenance is structural via a precomputed per-body `buffer_roots` set (GPT #1/#2,
strict): (a) the `@buffer`-ivar Load `Load(GEP(Array(C)-param, [16]))`; (b) a
`Array(C)#to_unsafe`/`#root_buffer` Call with EXACT element match and an Array(C)
param receiver (not Indexable/Enumerable/union); (c) a fresh `malloc`/`realloc`
(strided size) whose result is stored INTO `self.@buffer` (the create/grow path,
GPT #3 — realloc included). Eligibility = `inline_value_safe(C) && no
Heterogeneous/Uncovered op` (GPT #4, composed; no concat exception). Read-only:
gate ON vs OFF LLVM IR byte-identical.

Reducer `regression_tests/inline_array_storage_facts_probe.{cr,sh}`: `Cov`
(push/[]/delete_at/shift/insert/concat) → ELIGIBLE `[AllocRealloc Clear
MoveCopySameElem]`; `Unc` (adds dup/reverse, which copy into a fresh non-self
buffer) → ineligible `[… Uncovered]` — proving the refinement did NOT open a hole
(GPT #5 fail-closed). No `ivc_raw`; gate-neutral. Standalone `Pointer(C)#value`
stays boxed via the existing `inline_value_nonarray_pointer_guard`.

### 8.7 Hardening before behavior (2026-06-20, GPT pre-behavior review)

Three blocker-level fixes so the facts are safe for LLVM consumption:
1. **Root-bound AllocRealloc.** A malloc/realloc is `AllocRealloc` ONLY if its
   extern_call id is in `alloc_roots` (it provably reaches a Store into self.@buffer)
   AND its size is strided. A strided local `Pointer(C).malloc` that is not a buffer
   alloc is fail-closed (Uncovered), never silently rewritten as a buffer allocation.
2. **Stronger stride proof.** `count_is_strided?` now requires a `count * CONST`
   multiply (a constant operand = the legacy element size, verified = 8 for boxed
   structs), not any runtime multiply; `__adamas_ptr_move/ptr_copy` require the
   `elem_size` arg to be a compile-time constant. Rules out a spurious `i*j` being
   mistaken for a stride.
3. **Raw `to_unsafe` escape disqualifier.** An `Array(C)#to_unsafe` Call from OUTSIDE
   an `Array(C)#` body hands the bare @buffer pointer to user/opaque code (passed /
   returned), which `value_derived` does not catch. Any such escape disqualifies C
   (fail-closed). Composed: `inline_array_storage_eligible(C) = inline_value_safe(C)
   && no Heterogeneous/Uncovered op && no raw to_unsafe escape`.

Reducer extended with `Esc` (raw `esc.to_unsafe` passed to an opaque `sink_ptr`) →
ineligible despite all-covered per-site facts, proving the escape disqualifier. Cov
stays ELIGIBLE; Unc stays ineligible (Uncovered). Read-only / gate-neutral preserved.

## 9. Behavior implementation map — MECHANICAL fact consumer (GPT GO, CAUTION)

Feasibility verified read-only before any edit (GPT stop-signal check = NOT
triggered): every site that must change has the MIR instruction (and thus its fact)
in scope; the string-template `Array#<<`/`#unsafe_fetch` fallback fires ONLY for a
late-generic Tuple-union (a NON-eligible type) — eligible leaf-POD types use real
MIR-walked bodies. So the backend reads facts, never re-derives provenance/stride.

**Single gate `ADAMAS_INLINE_VALUE_ARRAY_STORAGE`** (gate #1): in `lower_all_bodies`
runs `populate_inline_value_safe_set` + `populate_array_bulk_op_facts` +
`verify_*` (emits `[IVANNOT]`/`[ABIFACTS]`). LLVM reads facts only under this gate.
Drop the separate `ADAMAS_ARRAY_BULK_OP_FACTS` requirement for behavior.

**The stride source (GPT core constraint).** Behavior NEVER patches the old
constant. It BUILDS `new_bytes = logical_count * inline_payload_stride(C)`, where
`inline_payload_stride(C) = elem.size` (the layout payload size). The proven
`count * CONST` / explicit `elem_size` const is used ONLY as shape-proof that the
site was an element-strided bulk op; `logical_count` = the NON-const operand of that
proven multiply (or the `count` arg of `__adamas_ptr_move/copy`).

**Consumption map (each reads exactly one fact; ineligible/legacy untouched):**

| LLVM site | fact read | action when set |
|---|---|---|
| `emit_gep_dynamic(inst)` | `GetElementPtrDynamic#array_buffer_value` && elem `inline_array_storage_eligible` | byte-GEP stride = `inline_payload_stride`; mark `inst.id` in `@inline_value_gep_aliases` |
| `emit_store(inst)` | `inst.ptr ∈ @inline_value_gep_aliases` | `memcpy(slot, value_payload, stride)` instead of `store ptr` |
| `emit_load(inst)` | `inst.ptr ∈ @inline_value_gep_aliases` | heap carrier `[i64 INT64_MAX][payload]` (raw+8), `memcpy(raw+8, slot, stride)` — reuse the existing sentinel-carrier convention (llvm_backend.cr:10553-10572), NOT `malloc(payload)` |
| `emit_extern_call(inst)` memmove/memcpy/memset | `ExternCall#array_bulk_op ∈ {MoveCopySameElem,Clear}` | rebuild byte count = `logical_count * stride` |
| `emit_extern_call(inst)` `__adamas_ptr_move`/`ptr_copy` | same | substitute the `elem_size` arg = `stride` (count arg already logical) |
| `emit_extern_call(inst)` malloc/realloc | `ExternCall#array_bulk_op == AllocRealloc` | rebuild size = `logical_count * stride` |
| `emit_call(inst)` `Pointer(C)#clear`/`move_from`/… | `Call#array_bulk_op` | rewrite to the inline-stride op (clear=memset stride, move/copy=ptr_move stride) |

**Eligible-only / atomic (gates #2, #4).** Every action is additionally gated on the
element type's `inline_array_storage_eligible`. Ineligible types (`Unc`, `Esc`,
non-Array `Pointer` paths, the string-template Tuple-union) take the unchanged legacy
path. The flip is atomic: all rows land in ONE commit; a partial store/load-only
flip is forbidden (stride mismatch on the first grow/delete_at = heap corruption).

**Helper.** `inline_payload_stride(elem : Type) : UInt64 = elem.size` (the Array-
context stride; `container_elem_storage_size_u64` / standalone `Pointer(T)` /
`StaticArray` stay UNCHANGED — gate #3 / §2). A shared
`emit_inline_value_load_carrier(slot, stride) -> raw+8` for the load row.

**DoD reducers (gate #5, runtime via run_safe.sh):** Vec3 12-byte
push+grow/realloc + delete_at/shift/insert/clear/concat read-back (value-correct, no
heap OOB); Vec2 copy-on-load no-alias (mutate a loaded copy, buffer unchanged); Unc/
Esc stay legacy (still correct); the non-Array `Pointer` guard re-pointed to the
behavior gate; gate-OFF byte-identical; `ivc_raw` only at eligible Array(C) sites.

**Stop-signal honored:** if any row needs provenance/stride NOT already in the facts,
STOP and extend the facts — do not add a second backend oracle.

## 10. Facts extension — arith-gep stride + bulk logical_count (read-only, 2026-06-20)

The §9 behavior attempt hit GPT's stop-signal: the facts did not cover (1) the
pointer-ARITHMETIC geps (`@buffer + offset`) feeding `__adamas_ptr_move`/clear —
proven by IR on `Array(Vec3)#delete_at`: `%r15 = getelementptr ptr, %r14, idx`
(stride 8) + `__adamas_ptr_move(%r15, %r20, %r24, i32 8)` — and (2) the
`logical_count` needed to rebuild byte counts. Per the stop-signal rule the partial
behavior was stashed and the facts extended instead of adding a backend oracle.

Added (read-only; gate `ADAMAS_ARRAY_BULK_OP_FACTS`):
- `GetElementPtrDynamic#array_buffer_element_stride : UInt64?` — set for EVERY
  @buffer-derived gep of an eligible C (value-access AND pointer-arith), via the
  existing `buffer_roots` provenance (`gep.element_type == C` && `gep.base` traces to
  a buffer root). Eligibility-baked (nil for ineligible). emit_gep_dynamic will read
  ONLY this for the stride; `array_buffer_value` still decides load/store semantics.
- `ExternCall#array_bulk_stride` / `Call#array_bulk_stride` (eligibility-baked) and
  `…#array_bulk_logical_count : ValueId?` — the logical element count so the behavior
  rebuilds `logical_count * stride` (never trusting the old const). Cases:
  ptr_move/copy → count arg; memmove/memcpy/memset → non-const Mul operand;
  malloc/realloc → non-const Mul operand; Pointer#clear → count arg; Pointer#
  move_from/copy_from → count arg. A covered op with no extractable count fail-closes
  to Uncovered.

Verify + reducer (`inline_array_storage_facts_probe`): `Cov` ELIGIBLE with
`stride-geps Cov` (value+arith) and every covered bulk op carrying a logical_count
(`missing=0`); strides land ONLY inside `Array(...)` bodies (`outside=0`); `Unc`/`Esc`
(ineligible) receive NO stride marks; `Vec3#delete_at` arith geps now strided
(stop-signal site closed); gate ON vs OFF IR byte-identical; no `ivc_raw`.

Behavior (§9) now has every fact it needs and resumes as a pure mechanical consumer:
emit_gep_dynamic reads `array_buffer_element_stride`; emit_store/load key off
`array_buffer_value`; emit_extern_call/emit_call read `array_bulk_stride` +
`array_bulk_logical_count` + `array_bulk_op`. No backend provenance oracle.
