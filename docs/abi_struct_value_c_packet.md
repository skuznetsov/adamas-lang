# Struct-Value ABI — C design packet (C-narrow vs C-wide)

Status: **PROPOSED. Census-grounded design packet for GPT review. No code beyond
the read-only censuses.** Companion to `docs/abi_struct_value_sdd.md` (the layout
ownership contract), `docs/inline_value_array_storage_behavior_plan.md` (the
shipped A′ Array-storage slice), and the memory notes
`struct_value_abi_gap_root_cause`, `mixed_memory_model_analysis`,
`inline_value_copy_container_abi_blocker`.

Purpose: the A′ Array-storage slice is closed (gated, byte-neutral perf, kept
OFF — see `47477d25`). The next lever is **C = the by-value struct ABI**, the
IR-confirmed root cause of V2's ~10×/~2× struct perf gap. Per the agreed cadence
(census → SDD → GPT review), this packet is the **census output as the input to
the C SDD**. It does NOT replace the SDD; it bounds it with two branches, each
with its own DoD and falsifier, so the GPT review is a coverage/risk table, not a
philosophy debate.

The packet resolves one open divergence (carried in
`inline_value_copy_container_abi_blocker`): a TRIZ reframe says the A′ residual is
**two separable contradictions → two bounded slices** (push construct-in-place;
escape-conditioned load) short of the full sret/call/return/union front; GPT
frames both as full-C territory. **The census resolves this empirically — both
are right, on different scopes (§3).**

---

## 0. Method (this session, read-only)

All numbers below are from two read-only, gate-OFF-byte-identical census passes in
`src/compiler/mir/hir_to_mir.cr`:

- **Store-side** (pre-existing): `ADAMAS_STRUCT_BYVALUE_CENSUS` — per-site struct
  ctor RESULT flow (`CtorFlow`), per-type aggregation (`ByvalTier`), placement-ctor
  fusion census. Classifies where a `$Dnew` result is consumed.
- **Load-side** (NEW this session): `ADAMAS_STRUCT_BYVALUE_LOADSIDE_CENSUS` — for
  every load of an InlineValueCopy element value (main-inlined `ArrayGet`, a `Call`
  to an `Array(C)#` accessor, or a raw `Load(gep_dyn)`), a **fail-closed escape
  walk** of the result classifies it `stack_local` / `recv_borrow` / `heap:<reason>`.
  This is the decisive measurement separating C-narrow from C-wide: only
  `stack_local` (and, if the callee is borrow-proven, `recv_borrow`) loads can drop
  the A′ heap carrier.

Gate-OFF is byte-identical by construction (the passes never run); gate-ON LLVM IR
is byte-identical to gate-OFF modulo non-deterministic `stub_name` hashes (verified:
124 changed IR lines, 0 non-stub). The censuses read MIR and write STDERR only — no
`Type`/`Value` mutation.

The population is **prelude-dominated**: a tiny user program adds only a handful of
sites, so the counts below (365 ctor sites, 1481 container writes, 25 InlineValueCopy
candidate types) are a fair self-host/prelude proxy. Bench numbers are called out
separately.

---

## 1. Store-side census (where a `$Dnew` result goes)

Prelude + `Array(Vec3)` bench (`/tmp/loadside_bench.cr`), 365 user-struct ctor sites:

| CtorFlow bucket | count | C lever |
|---|---:|---|
| `arg` (forwarded 82 / no_callee 45) | **127** | C-wide (call ABI — `.new`→`initialize` forwarding, Hasher) |
| `local` | **118** | Shape-C stack promotion (already partly shipped) + by-value `$Dnew` |
| `copy` | 42 | C-wide (`CopyStruct` at value boundaries) |
| `return` | 28 | C-wide (sret / by-value return) |
| `field_store` (inline 8 / carrier 10) | 18 | step-4 inline fields (gated, byte-neutral alone) |
| `container` (push / `<<` / `[]=`) | **6** | **C-narrow store slice** (placement-ctor fusion) |
| `mixed` / `other` | 15 | C-wide / case-by-case |

Placement-ctor fusion census (the C-narrow store target): of **1481** container
writes, **6** are a fresh sole-use ctor at the push site (`fresh_ctor`), **1475**
are INDIRECT (the pushed value is a variable / forwarded / non-ctor). Of the 6
fresh-ctor sites, **5 are removable** (semantic-POD → transient `malloc` 1→0), 1
ineligible (non-POD `FileEntry`).

**Store-side finding.** The C-narrow store slice (construct the ctor directly in the
buffer slot) addresses ONLY the fresh-sole-use container push — **6/365 = 1.6% of
ctor sites, 6/1481 = 0.4% of container writes**. The bulk of self-host struct ctor
traffic is `arg`/`local`/`copy`/`return` (315/365 = 86%), which only the by-value
call/return/copy ABI (C-wide) touches.

Per-type tiers (Stage 0++): `non_pod` 25, `blocked` 14, `container` 2 (Vec3, UInt128),
`needs_flip` 3, `trivial` 3. The whole-type by-value flip set (Shape A) is tiny and
contains no perf-relevant types — confirmed in prior sessions, unchanged here.

---

## 2. Load-side census (where an `arr[i]` result goes) — NEW

`/tmp/loadside_probe.cr` (validation: all four verdict classes fire correctly) and
the benches. User-level totals (excluding container-internal accessor bodies):

| workload | user loads | stack_local (C-narrow LOWER) | +recv_borrow (UPPER) | heap_carrier (C-wide / stay-legacy) |
|---|---:|---:|---:|---:|
| `Array(Vec3)` read bench | 7 | 3 | 4 | 3 |
| V3 storage reducer | 10 | 6 | 7 | 3 |
| validation probe | 10 | 3 | 5 | 5 |

Heap-escape reasons observed (the negative-gate evidence): `heap:returned`
(function returns a loaded value — sret/by-value-return = C-wide), `heap:union_wrapped`
(loaded value wrapped into a nilable/erased union — union payload ABI),
`heap:passed_arg` (loaded value pushed into another container / passed as a non-recv
arg), `heap:stored`/`stored_global` (stored into a field / closure global cell).

**Load-side finding.** In self-host/prelude, ivc loads are dominated by `recv_borrow`
(Range iteration: 11) — stack-eligible ONLY if the callee is proven borrow-only — and
a small `stack_local` set. **The static stack_local count is small, but the perf
weight is dynamic**: the bench's single `v=arr[i]; v.x+v.y+v.z` is ONE static
`stack_local` site executed 1M times — the hot read loop. C-narrow's
escape-conditioned load drops the heap carrier exactly there.

---

## 3. Divergence resolution (empirical)

> **Both framings are right, on different scopes.**

- **On the targeted struct bench** (`Array(Vec3)`, push + read heavy — the advertised
  ~10×/~2× perf gap): `arr << Vec3.new(...)` is a fresh-ctor fusion site (removable)
  AND `v=arr[i]` is `stack_local`. So **C-narrow's two slices close BOTH A′ residuals**
  (transient `$Dnew` on store; heap carrier on load) on this workload. The TRIZ reframe
  is empirically supported HERE: the two costs are separable contradictions, each with
  a local resource (store: ctor args → slot, no escape analysis; load: escape +
  no-intervening-mutation condition).

- **On self-host/prelude breadth**: struct traffic is 86% `arg`/`local`/`copy`/`return`
  ctor flows and `recv_borrow` loads — which C-narrow's two slices do NOT cover.
  Closing those needs by-value `$Dnew`/sret + call/return/union ABI = **C-wide**. GPT's
  full-C framing is correct for the bootstrap workload.

**Decision consequence.** The project goal is BOOTSTRAP (self-host s2b/s3b), where the
self-host population dominates. So **C-wide is the eventual necessity**; **C-narrow is a
safe, low-UAF-risk incremental first slice** with a real but narrow win (the container
bench) that does not block or conflict with C-wide. The order question (C-narrow first
as a confidence-building bounded win, or straight to C-wide) is the owner/GPT call this
packet feeds.

---

## 4. Branch C-narrow — two bounded slices

Scope: keep the pointer-carrier `$Dnew` ABI everywhere; add two local, gated rewrites.

### C-narrow-a — push construct-in-place (placement-ctor fusion)

At a `container << T.new(args)` where the ctor is the sole use of a fresh value, T is
recursive-POD, and the push is a monomorphic `Array(T)#push/<<`, construct T's fields
directly at `@buffer[size]` (ensure-capacity first), skipping the transient
`T$Dnew` malloc + inline memcpy.

- **Coverage:** 5 removable fresh-ctor sites (prelude) + every `arr << T.new(...)` in
  user struct-array code (the bench: 1M mallocs → 0).
- **DoD:** on the `Array(Vec3)` bench, `Vec3$Dnew __adamas_malloc64` callsites in the
  push loop → 0; runtime checksum identical ON vs OFF; peak RSS approaches original;
  gate-OFF byte-identical; suite green.
- **Falsifier:** a non-sole-use ctor (`v = Vec3.new(..); arr << v; use(v)`) must NOT
  fuse (v still observable); a non-POD element (`arr << Box.new(str)`) must NOT fuse
  (inner pointer ownership); a non-monomorphic / erased `Array(T)#<<` must NOT fuse.
- **Risk:** LOW. Construct-in-buffer is sound (the buffer is heap, outlives the frame —
  not stack promotion). Negative gates §6 fail-closed.

### C-narrow-b — escape-conditioned direct-slot load

At a `v = arr[i]` whose result is `stack_local` (read-only local consumption, proven
by the load-side walk) AND no array mutation occurs between the load and the last use,
read fields directly from `@buffer[i]` without materializing the A′ heap carrier.

- **Coverage:** the `stack_local` user loads (bench hot loop; 3–6 static sites per
  workload but dynamically dominant).
- **DoD:** on the bench read loop, 0 heap-carrier (`[i64 INT64_MAX][payload]`) allocs;
  checksum identical; gate-OFF byte-identical; suite green.
- **Falsifier:** a loaded value that escapes (`heap:returned`/`stored`/`passed`/
  `union_wrapped`/`addr_taken`) must KEEP the carrier; an intervening `arr[i]=` or
  `arr.push`/`delete_at` between load and use must KEEP the carrier (the slot may move
  on realloc / be overwritten — the A′ copy-on-load no-alias invariant).
- **Risk:** MEDIUM. Correctness hinges on the no-intervening-mutation condition and the
  borrow-only proof for `recv_borrow` promotion (deferred — v1 covers only `stack_local`,
  the fail-closed lower band).

---

## 5. Branch C-wide — by-value struct ABI

Scope: the root fix. `T$Dnew` returns an LLVM aggregate / `sret` (not a malloc'd ptr);
structs passed by value; struct temporaries stack-allocated; the 8-byte GC sentinel
header dropped for by-value POD (rc_inc/dec are static no-ops on these today — dropping
is rc-neutral, per the Stage 1a brief). Covers the full producer/consumer surface from
the SDD §5: call args, return, plain assignment, `CopyStruct` at value boundaries,
union payload, field store, container element.

- **Coverage:** the 86% self-host struct traffic (`arg` 127 / `local` 118 / `copy` 42 /
  `return` 28) + everything C-narrow covers (falls out uniformly, like tuples today).
- **DoD:** `Vec2/Vec3$Dnew` returns `{i32,i32}`/`{i32,i32,i32}` by value (SROA → regs);
  the Particle bench (`Array(Particle)` of struct-valued fields) drops to original-Crystal
  allocation traffic (3M×2 inner field mallocs → 0); s2b builds and runs clean; combined
  + originals + `p2_*` + s2b smoke green.
- **Falsifier (the hazard surface):** a struct that escapes by reference (pointer taken,
  stored across frames, captured by a real closure env) must still get a heap home;
  a non-POD struct must retain retain/release; a union-erased / virtual-generic struct
  whose ABI is unknown must fail-closed to the carrier; the layout-oracle contract
  (SDD §3) must hold (one repr source, no fourth oracle).
- **Risk:** HIGH. Broad front (call/return/union/generic/field/self-host at once); the
  non-uniform struct ABI wall (`inline_value_copy_container_abi_blocker`) and the 3
  unsynchronized layout oracles (`mixed_memory_model_analysis`) must be consolidated via
  `LayoutContract` FIRST (SDD step 1).

---

## 6. Negative gates (fail-closed, both branches)

A struct value is by-value-eligible ONLY if ALL hold; any unproven condition → keep the
pointer carrier / heap home (never optimistically inline):

1. **Recursive-POD.** T transitively holds only value scalars/enums — no String, Array,
   ref, ref-union, Proc, or **raw pointer field** (a memcpy would duplicate an owned
   interior pointer with no retain/release → UAF/leak under ARC). Predicate
   `struct_type_is_semantic_recursive_pod?`. ⚠️ **Open accuracy bug** (carried from
   `inline_value_copy_container_abi_blocker`): nested-struct false-negative — `Pair{@a,@b:Vec2}`
   wrongly reports non-POD. MUST be fixed before recursive-POD gates any real flip, or it
   wrongly rejects the exact Particle/Pair nested-POD shape C targets.
2. **No pointer escape / address-taken.** `pointerof` / `to_unsafe` / `AddressOf` of the
   value → carrier. Load-side `heap:addr_taken`.
3. **No user `to_unsafe` interior leak.** A user `Box#to_unsafe{@a.to_unsafe}` leaks an
   interior pointer → ineligible. Distinguish compiler-SYNTHESIZED abstract dispatchers
   (`@synthetic_abstract_dispatchers`, excluded) from real user escapes (the surgical fix
   already shipped for A′ in `eceb349d`).
4. **No union erase.** Value wrapped into a union (`UnionWrap`) or flowing into a
   type-erased `Indexable/Enumerable(T)` body → union payload ABI / carrier. Load-side
   `heap:union_wrapped`; store-side `erased_flow` gate.
5. **No virtual/generic unknown.** A struct reaching a virtual call or generic dispatch
   whose callee ABI is unknown → fail-closed carrier. Load-side `heap:passed_arg` /
   `passed_indirect` / `other`.
6. **No block/yield capture.** Closure capture (today via the global-cell mechanism =
   `GlobalStore`, or a real proc env) → carrier (closure env ABI is a separate track).
   Load-side `heap:stored_global`.
7. **Escapes the frame (returned / stored).** `heap:returned` / `heap:stored` → carrier
   (C-narrow) or by-value-return/CopyStruct ABI (C-wide).

---

## 7. Coverage / risk summary (the GPT-review table)

| | C-narrow-a (push fuse) | C-narrow-b (load) | C-wide (by-value ABI) |
|---|---|---|---|
| store ctor sites covered | 6 fresh-ctor (5 POD) / 365 | — | 315 arg/local/copy/return + 6 |
| load sites covered | — | `stack_local` (hot on bench) | + `recv_borrow` + escapes via sret |
| self-host coverage | 0.4% container writes | small static / hot dynamic | ~86% struct traffic |
| bench gap closed | store residual (1M→0 malloc) | load residual (0 carriers) | both + Particle-field allocs |
| UAF/repr risk | LOW | MEDIUM | HIGH |
| prerequisite | recursive-POD fix (gate 1) | no-intervening-mutation proof | LayoutContract consolidation (SDD step 1) |
| isolation | one gated rewrite | one gated rewrite | isolation branch, big-bang surface |

**Recommendation (PROPOSED, owner/GPT decision):** land **C-narrow-a then -b** as
low-risk, gated, bench-measurable confidence slices (each closes one A′ residual on the
container workload, neither conflicts with C-wide), while treating **C-wide as the
eventual root fix** for self-host struct traffic — sequenced AFTER the SDD step-1
LayoutContract consolidation and the recursive-POD accuracy fix. Fix gate-1
(nested-struct POD false-negative) FIRST regardless of branch order — it blocks both.

---

## 8. Reproduce

```
# store-side
ADAMAS_STRUCT_BYVALUE_CENSUS=1 bin/adamas /tmp/loadside_bench.cr -o /tmp/o 2>&1 | grep BYVAL_
# load-side (new)
ADAMAS_STRUCT_BYVALUE_LOADSIDE_CENSUS=1 bin/adamas /tmp/loadside_bench.cr -o /tmp/o 2>&1 | grep LOADSIDE
# validation probe (all four verdict classes)
ADAMAS_STRUCT_BYVALUE_LOADSIDE_CENSUS=1 bin/adamas /tmp/loadside_probe.cr -o /tmp/o 2>&1 | grep LOADSIDE
```

Benches: `/tmp/loadside_bench.cr` (Array(Vec3) read-heavy), `/tmp/loadside_probe.cr`
(load-side classifier validation), `regression_tests/inline_value_array_storage_behavior.cr`
(V3 storage family), `/tmp/bench_struct_rss.cr` (Array(Particle-class) store bench).
