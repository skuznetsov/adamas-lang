# Inline Value-Tuple ABI — Frontier SDD

> Scope: move a **value-aggregate tuple element** from `PointerCarrier` (8-byte heap
> pointer) to `InlineBytes` (value stored inline in its container), matching original
> Crystal, to fix a verified aliasing miscompile **and** remove the per-element heap
> box (perf-positive). This is the **Tuple arm** of `abi_struct_value_sdd.md` §5, which
> today lists Tuple as guard-only.
>
> Blast radius is controlled the project-standard way: one env gate, gate-OFF =
> byte-identical no-op; a repr-flip verifier that aborts instead of miscompiling; and
> phased behavior slices, each verified against the RED oracle + suites + s2 + a perf
> delta before the next.

## 0. Verified root cause (the driver)

`Array#sort_by!` lowers to `map { |e| {e, yield(e)} }.sort! { … }` then writes the
sorted originals back into `@buffer`. For `Array(Tuple(Int32,Int32))` the map builds
`Tuple(Tuple(Int32,Int32), Int32)` — a **nested** tuple. Under the current ABI its
inner-tuple element is a `PointerCarrier`: the slot holds an 8-byte pointer, and that
pointer is `array_get`'s **borrow into the source `@buffer`** — not a copy.

Evidence (all VERIFIED, `bin/adamas` @ 5a866fe9):
- `.ll` (writeback loop): `%carrier = load ptr, sorted[i]+0` then `memcpy(costs[i],
  %carrier, 8)` — offset 0 is a pointer read, then a deref-copy.
- Runtime probe: `mapped[j].box == &costs[j]` for every `j` (the box aliases the
  source buffer exactly).
- Exact output match: `map→sort→writeback` on `[{1,100},{2,50},{3,75}]` yields
  `[{1,100},{3,75},{3,75}]` because writing `costs[1]` overwrites the slot that
  `sorted[2][0]` still borrows.

Two facets of ONE root (both route the borrow through HIR `copy`):
- **A — construction:** `{arr[i], k}` stores the borrow (`lower_allocate`). The s2
  `sort_by!` blocker (reducer `regression_tests/array_tuple_sort_by_merge_sort_repro.sh`).
- **B — local binding:** `a = arr[i]; arr[i] = …; use a` reads the mutation (ADV1).

The existing `inline_value_safe_set` machinery was built for exactly this class but
(1) is gate-OFF and (2) **excludes tuples** (`classify_container_elem_repr` → tuple →
`ExistingLowering`). This SDD closes that gap for tuples.

## 1. Non-goals

- NOT structs/NamedTuple/Proc/Union/StaticArray — they keep their dedicated paths
  (`abi_struct_value_sdd.md` §5). Tuple only.
- NOT the generic monomorphization/magic-base layout path — routing tuples through it
  is a **refuted branch** (§3).
- NOT a copy-on-every-`copy` box patch (the naive "Fix 2"): keeping the box and adding
  a memcpy per materialization is correct but **perf-negative** and not original-like.
  This SDD removes the box instead.

## 2. Target representation (single vocabulary — `abi_struct_value_sdd.md` §2)

| element | today | target |
|---|---|---|
| `Tuple(Int32,Int32)` in `Array(...)` buffer | PointerCarrier (ptr→stack/heap tuple) | **InlineBytes** (8 value bytes in-buffer) |
| inner `Tuple(Int32,Int32)` in `Tuple(…, Int32)` | PointerCarrier | **InlineBytes** at the parent's field offset |
| a **reference** element in a tuple | PointerReference | PointerReference (unchanged; shared + rc_inc) |
| a tuple element carrying a ref/raw-ptr/proc | PointerCarrier | PointerCarrier (unchanged; not POD) |

With InlineBytes, `{arr[i], k}` and `a = arr[i]` become **inline byte copies**
(value_size bytes, LLVM-optimizable to register moves) — no heap box, no shared
storage. This is precisely original Crystal's value-tuple model; correctness (no
alias) and perf (no box) fall out of the same change.

## 3. Refuted branches — do NOT repeat (`abi_rework_quadr_plan.md` §4)

1. **Mid-lowering relayout** — REJECTED (IO::FileDescriptor → NUL garbage). Freeze the
   repr bit at MIR `Type` creation from the post-align HIR layout (the B1a fixed
   point); never re-decide after lowering starts.
2. **Unfiltered force-mono** — REJECTED (memory blow-up). Not relevant here (no new
   monomorphization), but the "filter is correctness-scope" discipline applies: admit
   ONLY POD tuples.
3. **Forcing magic bases through the generic path** — REJECTED (`inttoptr ptr→ptr`,
   llc failed stage2). Tuple has a **dedicated** layout path; the fix lives THERE
   (`register_tuple_types`, `lower_allocate` offset loop, the tuple index_get/index_set
   read/write, and the `@inline_value_array_storage` array sites), never in the generic
   struct branch.

## 4. Single-source repr + the POD predicate (reuse, do not add a 4th oracle)

The repr decision stays the one pure predicate + MIR-`Type` memo of
`abi_struct_value_sdd.md` §3. Extend its POD clause with a **recursive** tuple gate
(the current `leaf_storage_pod_struct?` deliberately does NOT recurse):

```
pod_tuple?(T) :=  T.kind.tuple?
              &&  0 < value_size(T) <= INLINE_TUPLE_MAX          # size bound, tune in P4
              &&  every element E:  E.kind.primitive? || E.kind.enum? || pod_tuple?(E)
```

Recursion is the only new idea vs. the struct predicate; it is what makes
`Tuple(Tuple(Int32,Int32),Int32)` inline-eligible. A tuple with ANY
reference / raw-pointer / proc / non-POD-struct / union element is NOT `pod_tuple?`
and stays PointerCarrier (fail-closed — same exclusion `leaf_storage_pod_struct?`
already makes for raw-pointer struct fields).

## 5. Phased migration (each phase: gate-OFF byte-identical, then verify ON before next)

Gate: `ADAMAS_INLINE_VALUE_TUPLE` (new; composes with the existing
`ADAMAS_INLINE_VALUE_ARRAY_STORAGE` behavior slice). Every phase's DoD is the SAME
five oracles: (o1) `array_tuple_sort_by_merge_sort_repro.sh` PASS, (o2) ADV1+ADV3
reducers PASS (added as regression), (o3) suites **152/152 + 36/36**, (o4) s2
classification string not regressed (and, from P2, reaches past the sort_by! tail),
(o5) perf delta non-regressing (bench + s2 build wall-clock + binary size).

- **P0 — repr predicate + verifier arm (NO behavior).** Add `pod_tuple?`; classify
  such tuples InlineBytes; wire them into the step-3 producer/consumer repr-flip
  verifier (`layout_probe.cr` SLOT-CONFLICT). Gate-OFF byte-identical. ON emits ZERO
  code change but makes the verifier ENUMERATE every producer/consumer that currently
  disagrees on `(repr,slot,value)` for a pod-tuple — i.e. prints the exact blast-radius
  site list before any lowering changes. (Proven "annotate + verify, no behavior"
  discipline.)

- **P1 — flat pod-tuple inline in Array buffers.** `Array(Tuple(Int32,Int32))`: size
  literal buffer at inline stride, store via `memcpy(value_size)`, read via
  BorrowedAddress/inline-load. Reuse the existing `@inline_value_array_storage` sites
  (stride, literal-size, value-slot). Smallest behavior slice; proves read/write/stride
  agree for the simplest pod tuple.

- **P2 — recursive (nested) pod-tuple inline.** The sort_by! shape. In the
  `lower_allocate` offset loop, a `pod_tuple?` element is `is_inline` → occupies
  `value_size` and is written with `memcpy(value_size)`; `register_tuple_types` sizes
  the parent accordingly; the read side (`index_get nested[0]`) returns the inline
  address, no `load ptr`. Closes Facet A → o1 flips green.

- **P3 — materialization copy semantics.** With inline storage, HIR `copy` /
  `lower_allocate` of a pod-tuple `arg` is an inline `memcpy(value_size)` from the
  borrow into owned inline storage. Closes Facet B (ADV1) as a byte copy, matching
  original — no separate box-copy path.

- **P4 — perf validation + default-on.** Measure (o5) across the struct/tuple
  benchmarks and s2. Tune `INLINE_TUPLE_MAX`. Flip the gate default ON only after o1–o4
  green AND o5 shows the box removal is net-positive (expected: fewer allocations,
  fewer pointer chases on `Array(Tuple)` traffic). Then delete the gate (probe hygiene:
  gates shrink monotonically).

## 6. Hard preconditions (MUST abort, never silently miscompile)

- Producer/consumer `(repr, slot_size, value_size)` disagreement for any `pod_tuple?`
  type → step-3 verifier ABORT (the existing repr-flip / SLOT-CONFLICT invariant). This
  is the safety net that turns "I missed a site" from a miscompile into a build error.
- Reference tuple elements are NEVER inlined (stay PointerReference, shared + rc_inc).
- A tuple that fails `pod_tuple?` is NEVER inlined (stays PointerCarrier).
- Repr bit is written once at MIR `Type` creation and never re-decided (refuted §3.1).

## 7. Kill-conditions + stopgap

- If P1 or P2 cannot reach byte-identical-OFF **and** green-ON within a bounded attempt
  budget (STANDARD: ~14), STOP the inline track and ship the **correctness-only
  stopgap** for s2: in `lower_allocate`, copy a `pod_tuple?` constructor-arg into a
  fresh owned box before storing the carrier (keeps the PointerCarrier ABI, fixes the
  alias, perf-neutral). This unblocks s2 while the inline ABI is deferred to the broader
  `abi_struct_value` workstream. The stopgap is explicitly a fallback, not the goal.
- If the perf delta (o5) is negative at P4, do not flip default-on; keep gate-gated and
  re-open the size-bound / borrow-vs-copy question.

## 8. Falsifiers / behavior oracles (kept executable, per process rules)

- RED: `regression_tests/array_tuple_sort_by_merge_sort_repro.sh` (currently RED:
  wrong output `100,75,75`).
- NEW regressions to add: `adv1_local_tuple_borrow_repro`, `adv3_construct_tuple_borrow_repro`
  (the two reducers from this investigation).
- Suites: `scripts/run_all_suites.sh` → 152/152 + 36/36.
- s2: classification-string movement (must not regress; P2+ must pass the sort_by!
  emission tail).
- Perf: struct/tuple benchmarks + s2 build wall-clock + binary size.

## 9. Relationship to existing work / ownership

- This is the Tuple arm of `abi_struct_value_sdd.md`; it consumes that spec's repr
  taxonomy (§2), single-source repr predicate + memo (§3), and step-3 verifier (§4). It
  does NOT introduce a new layout oracle.
- It extends the `ADAMAS_INLINE_VALUE_ARRAY_STORAGE` behavior slice
  (`llvm_backend.cr` stride/literal-size/value-slot sites) to pod-tuple elements.
- Facet-A and Facet-B reducers are new regression coverage (the July gap the process
  review flagged: zero new tests).

## 10. Open risks

- **Recursion depth / bound.** `pod_tuple?` recurses; a deeply nested tuple inflates
  value_size. `INLINE_TUPLE_MAX` bounds it; above the bound → PointerCarrier (safe).
- **BorrowedAddress escape.** P1/P2 read side returns an interior address; if a caller
  stores that address durably WITHOUT the P3 copy, Facet-B-style alias returns. The
  step-3 verifier + the ADV1 regression guard this; P3 must land before default-on.
- **Array growth/realloc.** Inline element buffers realloc at `value_size` stride; the
  existing `inline_array_storage` realloc-size sites must be confirmed for tuple
  strides (o3/o4 on `Array(Tuple)` push/realloc paths).
- **Mixed live old/new repr during rollout.** Mitigated by the gate (all-or-nothing per
  build) + the freeze-at-Type-creation discipline (refuted §3.1).
