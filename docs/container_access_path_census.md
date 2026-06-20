# Container element access-path census (A′ vs C decision data)

Read-only census gated by `ADAMAS_CONTAINER_ACCESS_CENSUS=1`, run on the
fully-lowered MIR (`run_container_access_census` in `hir_to_mir.cr`). Strictly
read-only / behavior-free: gate OFF emits nothing; gate ON vs OFF LLVM IR is
byte-identical once the pre-existing non-deterministic `@.stub_name_<hash>`
symbols are normalized (the linked binary's only diff is the linker `LC_UUID`,
which also varies between two OFF compiles).

Probe: `/tmp/access_census_probe.cr` — `Array(Vec2)`/`Array(Vec3)` with `<<`,
`av[0]` index read, `.each`, `.map`, with prelude.

## Buckets

```
recoverable  — concrete Array(T) provenance AT the site: ArrayGet/ArraySet
               carrying container_type, OR a call to a monomorphic
               Array(Concrete)#push/<</unsafe_fetch.
concrete_np  — concrete element type known but NO Array container identity at
               the site: container-less ArrayGet/ArraySet, or a raw
               GetElementPtrDynamic Load/Store whose element_type is the candidate.
erased       — neither: a shared generic Indexable/Enumerable fetch whose return
               union merely INCLUDES the candidate, or an Array(T)-unresolved body.
```

## Result (this probe)

```
READ provenance  (total candidate reads = 29)
  recoverable_array_provenance = 22 (75.9%)
  concrete_elem_no_container   =  6 (20.7%)
  type_erased                  =  1 ( 3.4%)
STORE provenance (total candidate stores = 15)
  recoverable_array_provenance =  8 (53.3%)
  concrete_elem_no_container   =  5 (33.3%)
  type_erased                  =  2 (13.3%)
```

35 InlineValueCopy candidate types classify — Vec2/Vec3 are the only user
types; the other 33 are pervasive stdlib value structs (Range, Crystal::Hasher,
Atomic, Time::Span/Instant, Float internals, PointerLinkedList, …). This is the
type-driven blast radius that refuted the standalone gated slice.

## The decisive finding — where concrete_np lives

```
concrete_np site enclosing functions:
  Array(Vec2)#push$Vec2                          :: raw_gep_store
  Array(Vec2)#unsafe_fetch$Int32                 :: raw_gep_load
  Array(Vec3)#push$Vec3                          :: raw_gep_store
  Array(Vec3)#unsafe_fetch$Int32                 :: raw_gep_load
  Array(Range(Int32,Int32))#push                 :: raw_gep_store
  Array(Range(Int32,Int32))#delete_at            :: raw_gep_load
  Array(Range(Int32,Int32))#shift_when_not_empty :: raw_gep_load
  Array(Float::…::Power)#unsafe_fetch            :: raw_gep_load
  Array(Float::…::UInt128)#push                  :: raw_gep_store
  Array(Float::…::UInt128)#unsafe_fetch          :: raw_gep_load
  Crystal::DWARF::LineNumbers#read_lnct_format    :: raw_gep_store   <- only non-Array
```

The actual element bytes are stored/loaded by a **raw GetElementPtrDynamic +
Store/Load INSIDE the monomorphic `Array(Concrete)#push`/`#unsafe_fetch` body**
— NOT via ArrayGet/ArraySet, and NOT via the type-erased Indexable#fetch path.
The `recoverable` bucket counts the CALL SITES into those methods; the bytes
themselves land in `concrete_np`. Store and load are SYMMETRIC (push has the
store, unsafe_fetch has the load), both inside the same `Array(Concrete)#` body.

Of 29 candidate reads, 28 (96.6%) are tied to concrete Array provenance either
by call-site name OR by enclosing monomorphic-Array-body identity; only 1 is
truly erased. Of 15 stores, 12 (80%) are Array-tied; 1 is a genuine non-Array
struct write (DWARF), 2 are erased Array(T) param.

## Implications for A′ vs C

- **The erased-fetch falsifier does NOT fire.** The earlier worry that a large
  fraction of `Array(Vec2)` reads go through the type-erased `Indexable#fetch`
  mega-union is refuted for this workload: 3.4% of reads, 0 for Vec2/Vec3.

- **Pure ArrayGet/ArraySet keying is WRONG** — the real store/load sites are raw
  GEP inside the monomorphic Array bodies, which emit no ArrayGet/ArraySet.

- **Type-driven marking is WRONG** (already refuted): fires on all 35 types incl.
  `Pointer#value` GEPs outside Array (the IO#gets_peek `switch i32` blocker).

- **A′'s correct lever is enclosing-function-context GEP marking**: mark the raw
  GEP element store/load ONLY when the enclosing MIR function is a monomorphic
  `Array(Concrete)#{push,<<,unsafe_fetch,delete_at,shift,…}` body whose GEP
  element_type is an InlineValueCopy candidate. Provenance = the function
  identity. This is symmetric, and the IO#gets_peek site is naturally excluded
  (it is outside any `Array(Concrete)#` body).

- **One bounded A′ correctness item**: the few erased generic bodies that exist
  (`Indexable(T)#fetch$Int32_block`, `Enumerable(T)#none?`) must be reconciled —
  if a monomorphic `Array(Vec2)#push` stores inline but an erased
  `Indexable(T)#fetch` reads the same buffer through the pointer-slot path, the
  reprs disagree. Small surface (3 sites here) but must be closed before A′ ships.

- **C (full by-value struct ABI)** remains the root fix and would make container
  inlining fall out uniformly (like tuples), but is a far broader front.

**Net:** A′ is tractable as a bounded slice via function-context gating; it is
NOT the refuted type-driven slice. The remaining decision (ship A′ now vs go
straight to C) is the owner's.

## A′ provenance marker — read-only proof (step 2)

Gate `ADAMAS_ARRAY_BUFFER_PROVENANCE_PROBE=1`, `run_array_buffer_provenance_probe`
in `hir_to_mir.cr`. Refines the census's "enclosing-function-context" idea into a
precise **buffer-base provenance** rule that does NOT depend on the function name.

Mark rule (the `buffer_value` category): a candidate `GetElementPtrDynamic` G with
`element_type C` is in the A′ mark set iff

1. C is an InlineValueCopy candidate, AND
2. `G.base` is defined by a `Load` whose `.ptr` is a static `GetElementPtr` of the
   `@buffer` ivar on a receiver whose static type is `Array(C)` (string-parsed arg
   AND `element_type` id both checked), AND
3. G is the ADDRESS of a `Load`/`Store` of C (the value-access discriminator).

Four categories separate the mark set from the look-alikes:

```
buffer_value     — (P) direct @buffer chain AND (V) value access  → THE A' MARK SET
buffer_ptr_arith — (P) but NOT (V): root_buffer / shift_buffer_by / delete_at
                   memmove pointer arithmetic (feeds ret / compaction; repr-agnostic)
value_derived    — (V) but NOT (P): raw Pointer(C) indexed access with no @buffer
                   chain (e.g. DWARF::LineNumbers, a bare Pointer(Vec2) in main)
neither          — resize_to_capacity (realloc result stored as ptr), check_needs_resize
```

Results on `regression_tests/array_buffer_provenance_marker_probe.cr` (Array(Vec2)
POSITIVE inline-buffer access + a NEGATIVE raw `Pointer(Vec2)[idx]` access in main):

```
buffer_value=8 buffer_ptr_arith=7 value_derived=3 neither=7
A' MARK SET (buffer_value) sites OUTSIDE an Array(...) body = 0   <- THE invariant
broader value-access raw GEPs OUTSIDE an Array(...) body         = 3 (NOT marked)

buffer_value:  Array(Vec2)#push, Array(Vec2)#unsafe_fetch, Array(Range)#push/
               delete_at/shift_when_not_empty, Array(Float::…UInt128)#push/
               unsafe_fetch, Array(Float::…Power)#unsafe_fetch   — ALL Array(C)# bodies
value_derived: Crystal::DWARF::LineNumbers#read_lnct_format, __adamas_main x2
               (the raw Pointer(Vec2) store+load — correctly NOT marked)
```

**Proven (the GPT step-2 requirement):** the A′ mark set lands ONLY inside
`Array(C)#` bodies — `buffer_value_outside_array = 0` even with a deliberate raw
`Pointer(Vec2)` access present. The `IO#gets_peek`-class `Pointer(C)#value` blocker
that sank the refuted type-driven slice is structurally excluded (no `Array(C)`
@buffer chain → `value_derived`/`neither`, never `buffer_value`).

**Read-only / gate-neutral:** the probe only writes STDERR; gate ON vs OFF LLVM IR
is byte-identical once the pre-existing non-deterministic `@.stub_name_<hash>`
symbols are normalized (normalized diff = 0; raw diff = the stub-name noise that
also varies between two OFF compiles). Asserted by
`regression_tests/array_buffer_provenance_marker_probe.sh`.

**Still open before behavior (step 3):** (a) restore the leaf-gate narrowing so
raw-pointer-field structs are NOT leaf-storage-POD; (b) NO global type-driven
`Pointer(T)#<<`; (c) close the erased-`Indexable(T)#fetch`/`Enumerable(T)`
reconciliation OR ship a per-type safe-set (only types with no erased access in
the lowered module) — note an erased generic body's buffer GEP is `value_derived`
(self typed `Indexable(T)`, not `Array(C)`), so it is NOT in `buffer_value` and
would read the inline-stored buffer through the pointer-slot path unless
reconciled; (d) the negative reducer above must keep producing 0 `ivc_raw`.

## A′ step (c) — read-only per-type inline-value SAFE-SET (2026-06-20)

Gate `ADAMAS_INLINE_VALUE_SAFE_SET_PROBE`; `run_inline_value_safe_set_probe` in
`src/compiler/mir/hir_to_mir.cr`. Read-only (only STDERR; gate ON vs OFF LLVM IR
byte-identical, normalized diff = 0). Closes step-3 condition (c): produces the
per-type safe-set AND empirically settles the erased-`Indexable(T)#fetch` worry.

**Per InlineValueCopy candidate C, computed from the fully-lowered MIR:**

| signal        | meaning | role |
|---------------|---------|------|
| `bv`          | a `buffer_value` Load/Store of C exists (the `@buffer`-base chain inside an `Array(C)#` body — A′ WOULD convert) | required for SAFE |
| `vd`          | a `value_derived` access of C exists — a Load OR Store through a raw `Pointer(C)` not on the `@buffer` chain (may alias a buffer with the wrong stride) | HAZARD → UNSAFE |
| `erased_flow` | `Array(C)` — or an upcast `Indexable/Enumerable/Iterator/Iterable(C)` — actually FLOWS as an arg into a type-erased body (abstract-module method, or generic `Array(<unresolved param>)#…`) | HAZARD → UNSAFE (the SOUND erased gate) |
| `mega_union`  | C appears in some shared `Indexable(T)#fetch` RETURN union | INFORMATIONAL only — over-fires, NOT a gate |

**v1 SAFE-SET = `{ C | bv && !vd && !erased_flow }`.**

**Key result — flow-based erased replaces the over-coarse variant signal.** The
program-wide `Indexable(T)#unsafe_fetch` mega-union includes nearly every element
type, so the naive variant gate (C ∈ mega-union) FALSE-POSITIVES on monomorphic
types. On the reducer it would *wrongly exclude 3 types* (incl. `Vec2`,
`mega_union=1`) that the flow gate correctly keeps. Flow-based keys on whether
`Array(C)` actually flows into an erased body — which, in this compiler, it never
does for candidate types.

**Empirical: this compiler monomorphizes ALL candidate-array access → `erased_flow`
is a sound but DORMANT guard.** The durable reducer exercises `Vec2` through
`push`/`each`/`[]`/`map` AND every erasure-attempt form — an explicit
`Indexable(Vec2)` parameter, an `.as(Indexable(Vec2))` cast, and a two-implementer
abstract dispatch (`include Indexable(Vec2)` class + `Array(Vec2)`, both passed to
one `Indexable(Vec2)` method) — and `Vec2` still classifies SAFE with
`erased_flow=0`. Each form devirtualizes to the concrete `Array(Vec2)#…` body:
`Vec2` flows ONLY into `Array(Vec2)#…` methods, never `Indexable`/`Enumerable`. So
the step-3 condition-(c) repr-mismatch hazard ("an erased generic body reads the
inline buffer through the pointer-slot path") does **not** occur for candidate
types here. `erased_callee` IS exercised (it returns false for every concrete
`Array(Vec2)#…` name); the upcast sub-branch stays defensively correct for a future
where abstract container types survive to MIR. (Beyond the durable reducer, the
same `erased_flow=0` result was observed in standalone local probes for a purely
monomorphic struct used only via `push`+`unsafe_fetch`.)

**Negative reducer (`regression_tests/inline_value_safe_set_probe.{cr,sh}`):** one
compile asserts both poles —
`Vec2 (bv=1 vd=0 erased_flow=0)` → **SAFE** (even under the abstract-dispatch
forms above), and
`Vraw (bv=1 vd=1) — value_derived access` → **UNSAFE** (a raw `Pointer(Vraw)` read
and write, not the @buffer chain) — plus `flow-based erased=0`, mega-union would
wrongly exclude ≥1 type, and gate-neutrality (normalized IR diff = 0).

**Step-3 conditions status:** (a) DONE — leaf-gate narrowing (commit `d9dd8989`);
(b) held — no global type-driven `Pointer(T)#<<`; (c) DONE — safe-set shipped +
erased path proven empirically absent for candidates; (d) negative reducer keeps
0 `ivc_raw` (no codegen consumes the label on this base). Behavior slice (step 3)
remains owner-gated.
