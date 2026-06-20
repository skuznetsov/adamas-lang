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
