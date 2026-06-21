# C-narrow-b — escape-conditioned direct-slot load (SDD / reducer-first)

Status: **PROPOSED. Design for GPT review BEFORE reducers/behavior.** Follows
`docs/abi_cnarrow_a_placement_brief.md` (the store-side slice, SHIPPED `5bf066fb`) and
`docs/abi_cnarrow_a_promotion_measurement.md` (which quantified the OPEN residual this
slice targets). C-narrow-a closed the *store* residual; C-narrow-b targets the *load*
residual — the copy-on-load heap carrier.

**Evidence this is worth doing (from the promotion measurement, Array(Vec3) 3M):** under
A′+C-narrow-a the push+read RSS is 132 MB vs OFF 120 MB; the gap (and the 224→132 read
inflation) is the 3M copy-on-load heap carriers (leak-to-exit). C-narrow-b eliminates
them on the eligible read path. GPT trust for the DIRECTION: `{F:0.75, G:0.65, R:0.8}`
(insufficient for promotion/default-ON — that needs the DoD below + s2b smoke).

---

## 1. Mechanism

Under A′ (`ADAMAS_INLINE_VALUE_ARRAY_STORAGE`), `v = arr[i]` for an inline-stored
`Array(C)` reads the inline slot `@buffer[i]` and copies it into a **heap carrier**
(`[i64 INT64_MAX header][payload]`, returns raw+8) — escape-safe but always heap. The
result `v` is then used (`v.x`, `v.y`, …).

C-narrow-b: when the loaded value is consumed **only by local field reads in the same
basic block** (no escape, no intervening array mutation), skip the carrier — read each
field DIRECTLY from `@buffer[i] + field_offset`. No heap carrier is materialized.

This is a load-site optimization conditioned on the *consumption* (the load-side census
already classifies `stack_local` vs `heap_carrier`; C-narrow-b is a strictly narrower
subset of `stack_local`).

## 2. v1 is BRUTALLY NARROW — as an EXECUTABLE MIR pattern (GPT caveats 2, 3)

A load is C-narrow-b-eligible ONLY if ALL hold — any unproven condition ⇒ keep the
A′ carrier (fail-closed). Stated as MIR predicates over the `MIR::ArrayGet` result `R`
(v1 source = `ArrayGet` only — see §4):

**(a) Field-read-only USE pattern.** Every use of `R` (and of its transparent `Cast`
forwards — MIR has no `Copy`, so `b = arr`-style aliases reuse the value-id) is exactly
the chain `R -> optional Cast -> STATIC field GEP (MIR::GetElementPtr, base ∈ R-closure)
-> Load`, all in the SAME basic block as the `ArrayGet`. The field GEP's only use is the
`Load`. A **`GetElementPtrDynamic`** off `R` is pointer arithmetic, NOT a proven field
read ⇒ **carrier** (`dynamic_gep`, GPT v1 fail-closed). **Any** other consumer of `R` or a
forward — `Call`/`IndirectCall`/`ExternCall` (incl. receiver position = `recv_borrow`,
excluded in v1), `Phi`, `Store`-as-value, `Return`, `MemCopy`, `UnionWrap`, `AddressOf`,
`ArraySet`-value, or an unknown instruction — ⇒ **carrier** (reason-coded).

**(b) Same block.** Any use of `R` outside the `ArrayGet`'s block ⇒ **carrier**
(`cross_block`).

**(c) Order-based no-intervening-mutation.** Let `lo` = the `ArrayGet`'s index in the block
and `hi` = the MAX index among the field-`Load` uses. Mutations BEFORE `lo` or AFTER `hi`
are irrelevant. Strictly between `lo` and `hi`, FORBID: any `Call`/`ExternCall`/`IndirectCall`
(`intervening_call` — covers `push`/`<<`/`delete_at`/`shift`/`insert`/`clear`/`concat`, which
all lower to a Call), and **any `ArraySet`** (`intervening_mutation`). Forbidding *any*
`ArraySet` (not just on the source-array closure) is the fail-closed choice — robust to
alias representation (GPT blocker 1); a raw buffer `Store` only occurs inside `Array(C)#`
bodies, never in user code between a load and its field use. Any such site ⇒ **carrier**.

**(d) Alias closure must be PROVEN.** The source-array SSA closure is computed forward
through `Cast`/`Copy` only. If `A` (or a forward) flows into an opaque/unknown instruction
within `lo..hi` whose aliasing cannot be ruled out (e.g. passed to a call — already barred
by the no-call rule), REJECT (`aliased`). Fail-closed: unproven ⇒ carrier.

Widening (cross-block dataflow, `recv_borrow` with a proven borrow-only callee, loop-carried)
is deferred v2, each behind its own proof.

## 3. A′ coupling (GPT caveat 5)

C-narrow-b REQUIRES A′ on: the direct-slot read is only correct when the buffer stores the
value INLINE. Without A′ the buffer holds POINTERS — a direct-slot read would read a
pointer as a value (repr-flip). So: `ADAMAS_CNARROW_B_LOAD=1` WITHOUT
`ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1` ⇒ **0 direct-slot loads** (mandatory guard reducer).
The behavior hook is placed inside the A′ block (as C-narrow-a's is), so the coupling holds
by construction.

## 4. Fact to consume + pass ordering (no second oracle; GPT caveats 1, 5)

**Mark target = `MIR::ArrayGet#cnarrow_b_direct : Bool`, ONLY.** v1 handles the
main-inlined `ArrayGet` (`arr[i]`). The raw `Load(gep_dyn)` and the `Call` to
`Array(C)#unsafe_fetch`/`[]` accessors are a DIFFERENT provenance surface (the load is
inside the accessor body, returned) — explicitly **future path**, not marked in v1.

The eligibility = the §2 conjunction over the `ArrayGet` result's uses, gated on the
element type being `inline_array_storage_eligible(C)`. The later behavior transform
consumes the mark; it does NOT re-derive provenance/storage (GPT hard-stop).

**Pass ordering = identical to C-narrow-a placement (GPT caveat 5).** The mark is
populated POST-MIR-opt (the optimizer clones/moves instructions and drops pre-opt marks);
`populate_cnarrow_b_marks` CLEARS all `cnarrow_b_direct = false` before re-marking from
scratch; and per-worker MIR opt stays disabled after population (the A′ flow already sets
`fused_parallel = false` inside the A′ block) so workers cannot re-clobber the marks.

## 5. Reducers (reducer-first; NO behavior yet)

**Read-only preflight** (gate `ADAMAS_CNARROW_B_PREFLIGHT`): classify each inline-`C` load
with a reason code — `eligible` / `escapes:<why>` / `intervening_call` /
`intervening_mutation` / `aliased` / `recv_borrow` / `cross_block` — and mark the eligible
loads. Behavior-neutral (gate-OFF byte-identical).

**Positive reducer — C-SPECIFIC + MECHANICAL (GPT caveats 3, 4 — the value-proxy lesson):**
a clean `Array(V3)` same-block local-read loop.
- *Preflight stage (read-only):* emit `[CNARROW_B] eligible type=V3 in=<fn>`; the reducer
  asserts the V3 `ArrayGet` is marked `cnarrow_b_direct` and the negatives are NOT —
  no global counter.
- *Behavior stage (later):* the signal is C-SPECIFIC, not a global ivc_raw count —
  assert in the V3 read block's IR that the field reads are DIRECT slot loads off
  `@buffer[i]` AND there is NO `ivc_raw` ArrayGet carrier for that marked V3 load (grep
  scoped to the marked load's region, never module-wide). Exactly the check that catches
  the earlier V3-ineligible value-proxy theater.

**Negative reducers — MANDATORY (GPT caveat 4), each stays carrier-required:**
- escape: `return arr[i]` / `sink << arr[i]` / `x = arr[i]; pass(x)` / union-wrap / `pointerof`.
- `v = arr[i]; maybe_call(); v.x` (intervening call).
- `v = arr[i]; arr << V3.new(..); v.x` (intervening push).
- `b = arr; v = arr[i]; b.delete_at(0); v.x` (alias mutation).
- `v = arr[i]; arr.delete_at/shift/insert/clear; v.x` (array mutation).
- `arr[i].some_method` (load used as receiver — recv_borrow, excluded in v1).
- cross-block use of the loaded value.

**A′-coupling guard reducer (caveat 5):** `ADAMAS_CNARROW_B_LOAD=1` without A′ ⇒ 0 direct-slot loads.

## 6. DoD (GPT caveats 3 + 6)

- positive: V3 direct-slot load used; carrier alloc gone in the Array(V3) read path
  (C-specific, not global).
- all negatives: carrier retained.
- A′-coupling: 0 direct-slot loads without A′.
- construct/behavior identity: read-heavy V3 bench checksum identical ON vs OFF.
- **RSS delta is the perf signal** (the push+read 132→~120 MB target, carriers removed);
  **wall-time at 3M (0.03–0.09 s) is SECONDARY** — for a real wall claim, increase the
  workload, do not lean on sub-100 ms deltas (GPT caveat 6).
- gate-OFF byte-identical.
- **s2b smoke** (`ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_CNARROW_A_PLACEMENT=1
  ADAMAS_CNARROW_B_LOAD=1` → s2b builds + runs clean): in the DoD AFTER C-narrow-b behavior
  / before any default-ON discussion — NOT a gate on building this read-only packet.

## 7. NEXT

Owner/GPT review of this design → build the read-only preflight + reducers (positive +
negatives + A′-coupling) → GPT review → behavior transform (gated, post-opt, consuming the
durable mark). Not C-wide; not s2b-first.
