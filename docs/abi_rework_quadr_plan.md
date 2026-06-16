# ABI Rework — Quadrumvirate Plan (root-cause, not symptoms)

Status: **PROPOSED plan, no behavior change in this commit.**
Branch: `abi-rework` (off `main` @ 7f18f326).
Owner directive: fix the root cause, not symptoms. Execute step-by-step, each
step under its own mini-Quadrumvirate, its own commit, and the full gate.

This document is the durable strategy reference. Per-step execution notes go in
`TODO.md`; durable findings go in project memory. The named source of truth for
the *why* is `mixed-memory-model-analysis` (Сказочник / Fable 5) and
`docs/layout_freeze_proposal.md` (B0/B1a/B1b/B1c registry findings).

---

## 0. Scope: two ABIs (not equal in size)

The owner flagged "~two ABIs to fix". Verified against code, they are very
unequal in remaining effort:

- **ABI #1 — struct value ABI.** Large, mostly-untouched root. Source of the
  `#4` String↔Slice repr-flip family.
- **ABI #2 — closure env ABI.** Already ~70% migrated on `main`; remaining work
  is dual-path retirement + the raw-callback/yield carrier. Pairs naturally
  with the fibers task.

---

## 1. Verified current state (code anchors, checked 2026-06-16)

### 1.1 ABI #1 — struct value ABI

- Structs are heap `PointerCarrier` in V2 (CLAUDE.md: "heap-allocates structs …
  FieldGet always loads a pointer"), not inline aggregates as in original
  Crystal.
- "ptr-to-struct vs the struct itself?" is decided by **three unsynchronized
  oracles**:
  - HIR `field_storage_size_impl` — `src/compiler/hir/ast_to_hir.cr:39412`
    (family of `*_storage_size` helpers around :38806–:39448).
  - MIR `mir_field_storage_size` — `src/compiler/mir/hir_to_mir.cr:6353` — plus
    the side-set `@inline_struct_ptrs : Set(HIR::ValueId)` (decl :114, populated
    :2849–:2875, :7646).
  - LLVM `inline_container_struct_type?` — `src/compiler/mir/llvm_backend.cr:2796`
    — a **string-prefix whitelist** (`Slice(` / `StaticArray(` / `Hash::Entry(`).
    Any new inline family silently falls out → wrong stride/store size.
- Registry ghost / stale-slot family is **already fixed** (B1a/B1b/B1c, see
  `docs/layout_freeze_proposal.md`): force-monomorphize ref-fallback types,
  on-demand monomorphization in the `type_size` fallback, kind-upgrade
  interning. What is NOT yet done: a registry **freeze + assert**, and unifying
  the value-repr decision.
- The plan's "single oracle" (step 1) shipped only as a **diagnostic logger**:
  `src/compiler/layout_probe.cr` (`Adamas::LayoutProbe`, `ADAMAS_LAYOUT_PROBE=1`),
  taxonomy `InlineBytes | PointerCarrier | PointerReference | BorrowedAddress`.
  It records each phase's independent decision; it does **not** enforce one, and
  does **not** assert on divergence.

### 1.2 ABI #2 — closure env ABI

- Heap-env migration is **partly live on main** (`docs/closure_env_abi_p1_plan.md`,
  checkpoint 2026-04-19): `@boxed_locals` (ast_to_hir.cr:60), `HIR::MakeProc`
  (hir.cr:806), `emit_make_proc_value` (ast_to_hir.cr:80516), proc literals
  (:80634), MIR `allocate_proc_object` (hir_to_mir.cr:774), `call_heap_proc`
  (:799/:3010), `MakeClosure` env lowering (:5306).
- Remaining: (a) **dual path** — legacy global `@__closure_cell_N` class vars
  still active alongside heap env (ast_to_hir.cr:3115/:48665/:78139/:81101);
  (b) **raw-callback / yield carrier** — bare `FuncPointer` + legacy cells;
  switching `lower_yield` to `call_heap_proc` on Proc-typed `block_val` was
  rejected (combined block/yield tests regressed — some raw carriers are
  Proc-typed in HIR but are not heap procs).

---

## 2. Quadrumvirate

### 2.1 Competing hypotheses

```
[HYP-A] Inline-flip first: lead with step 4 (constructors -> inline aggregate
        + explicit CopyStruct), matching original Crystal directly.
  predicts: fixes value semantics + kills the null-self family at once; #4
            repr-flip disappears.
  cost: VERY high — touches every value boundary (assign/arg/closure-capture/
        container-write) + constructors across HIR/MIR/LLVM at once.
  cheapest_falsifier: flip ONE struct's $Dnew to inline on a branch -> segv/
        garbage in a dependent owner.

[HYP-B] Safety-net first: steps 1 -> 2 -> 3 -> 5, THEN step 4 last on an
        isolation branch.
  predicts: #4 (String<->Slice) closes at steps 1+3 — it is born of the
            "ptr-or-value" ambiguity in 3 places (B0-2: a slot born as an
            8-byte ref_fallback then written with the 16-byte value view),
            NOT of heap-vs-inline; the MIR verifier catches every divergence
            before runtime.
  distinct_from HYP-A: does NOT flip representation first; builds the
            verification net first so the eventual inline flip is falsifiable,
            not a leap.
  cheapest_falsifier: turn LayoutProbe into a divergence assert; if hello-world
            shows ZERO divergences, the "3 oracles disagree" premise is false.
```

### 2.2 Cassandra

- Confidence HYP-B fixes #4 without step 4: **~0.7** (basis: the
  mixed-memory-model analysis + B0 findings — repr-flip = slot-size vs
  access-size mismatch, not heap-vs-inline).
- Failure modes: (1) layout update after lowering starts is **unsound**
  (B1a falsification #1: IO::FileDescriptor relaid mid-pipeline → NUL garbage).
  (2) Unfiltered force = 4.3GB OOM on stage2. (3) Flipping one oracle without
  the others = a fresh divergence.
- Cheapest measurable step: env-gated **divergence assert** in LayoutProbe
  (`ADAMAS_LAYOUT_ASSERT=1`): when two phases record different `storage` for the
  same `(type_name, type_id)`, abort with the diff. Zero default-path change.

### 2.3 Maieutic

- Assumption: "killing #4 requires the full inline flip (step 4)".
- Hardest question: why in THIS code? The repr-flip writes `{ptr=image-base,
  size=311}` into a String slot. That is "slot sized as an 8-byte ref, written
  with a 16-byte value view" (B0-2 ref_fallback) — curable by single oracle +
  freeze + verifier (`store_size == slot_size`), with NO inline flip.
- Falsifier: if after steps 1+3 the glob-probe A/B still segfaults on the
  repr-flip, the HYP-B premise is wrong → pull step 4 earlier.
- Stumble: yes — nearly led with step 4 because memory calls it "the biggest
  step". That is the trap: leading with the most expensive irreversible step
  before the verification net exists.

### 2.4 Daedalus (frame shift)

The recurring blind spot across prior ABI work (B1a/B1c falsifications): every
direct representation flip / relayout WITHOUT a net hit an unsound mid-lowering
state empirically, at the cost of a broken stage2. Shift: **static→dynamic
verification first.** Not "flip the ABI and run suites" but "first build an
invariant checker (verifier + freeze-assert + force-strategy bisector) that
makes any flip falsifiable in one run". Then step 4 stops being a leap.

### 2.5 Adversary

- Edge: divergence-assert may false-positive on legitimate ptr families (class
  `PointerReference` vs struct `PointerCarrier`). → assert only on
  `InlineBytes`↔`PointerCarrier` conflict for one `type_id`, not across ptr
  families.
- Scaling: a verifier on every FieldGet/Set is a perf cost. → env-gated, never
  in the release path.
- Regression risk: a freeze-assert breaks any class currently mis-sized (by
  intent) — needs invalidation of already-lowered functions; mid-lowering
  invalidation is unsound (B1a). → put the freeze at the SAME fixed point as the
  final `align_all_class_ivars`, before MIR.
- Compat: stage2 self-build (4GB budget) — gate every step on
  `p2_generated_stage2_*` + the s2b probe, not just combined.
- **Verdict: ROBUST for HYP-B; VULNERABLE for HYP-A** (irreversible flip without
  a net → history shows a broken stage2).

### 2.6 Decision + trust

**HYP-B (safety-net first). HYP-A step 4 last, on an isolation branch, under the
net.** Trust `{F:0.7, G:0.8, R:0.7}` — F/R capped until step 0 measures the
actual divergence frequency.

---

## 3. Sequencing (this branch executes 0,1,2,3,5; step 4 isolation; C separate)

Each step: its own mini-Quadr, its own commit, gate =
`combined 31/31 + originals 158/158 + p2_generated_stage2_* + s2b probe`
(plus the glob-probe A/B specifically for step 3).

| # | Step | Tier | Mini-Quadr falsifier |
|---|------|------|----------------------|
| **0** | Divergence-assert in LayoutProbe + `ADAMAS_FORCE_STRATEGY=gc` bisector | diagnostic, zero risk | hello-world: how many divergences? 0 → HYP-B premise false |
| **1** | Single `layout_of(type)→{repr, offsets}`; all 3 phases READ it (2796 whitelist → registry property) | CAUTION | probe: 0 divergence rows |
| **2** | Registry freeze-point + assert after the final align, before MIR | CAUTION | any class_info write after freeze = abort |
| **3** | `FieldAddr`(borrow=GEP) vs `FieldGet`(value) split + MIR verifier `store_size == slot_size` | CAUTION | glob-probe A/B: repr-flip segv → 0 (#4 should die here) |
| **5** | Union all-ref-as-ptr → registry property; TypeRef short→FQ on MIR entry | CAUTION | M4h reducer |
| **4** | Constructors → inline + explicit CopyStruct (value semantics; kills null-self) | **isolation branch** | null-self reducer; per-type incremental |
| **C** | Closure ABI: retire legacy `@__closure_cell_N`, then yield-carrier | separate, pairs with fibers (#3) | spawn-in-loop reducer `b8b482ba` |

**Key bet:** #4 dies at step 3, BEFORE the expensive step 4. If not (step-3
falsifier fires), pull step 4 earlier.

---

## 4. Falsification history — do NOT repeat (from B1a/B1c)

- **Mid-lowering relayout cascade — REJECTED empirically.** Re-laying-out
  dependent owners from inside `register_concrete_class` breaks in-progress
  functions (mixed old/new offsets); IO::FileDescriptor → hello-world NUL
  garbage. Layout updates after lowering started are unsound, period.
- **Unfiltered force-mono — REJECTED empirically.** Forcing all generic
  fallback keys (classes included) ballooned stage2 past the 4096MB budget
  (killed at 4.34GB). The struct filter is both correctness-scope and the memory
  fix.
- **Forcing magic bases — REJECTED empirically.** `StaticArray(UInt64, N)` with
  an unresolved size arg minted a bogus specialization → invalid LLVM
  (`inttoptr ptr -> ptr`) → llc failed stage2. StaticArray/Tuple/Proc/Pointer/
  Union have dedicated layout paths and must stay skip-listed.

---

## 5. Cheap reliability levers (build in step 0)

- Hook real type sizes into `MemoryStrategyAssigner.estimate_size` (today
  `DEFAULT_TYPE_SIZE=64` for all user types — Stack-vs-ARC decided on fictional
  sizes).
- `ADAMAS_FORCE_STRATEGY=gc` one-line bisector (all → GC): "bug vanishes under
  force-GC" instantly separates a memory-strategy bug from a layout bug. Runtime
  equivalent today is only `DYLD_INSERT_LIBRARIES=/tmp/noopfree.dylib`.
- Reliability rule (ARC is the riskiest mode): ARC/Stack only on PROVEN
  non-escape; any doubt → GC. Unknown HIR opcode defaults to HeapEscape
  (fail-safe), never "didn't see it → not escape" (fail-open).
