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

## 2. v1 is BRUTALLY NARROW (GPT caveat 2)

A load is C-narrow-b-eligible ONLY if ALL hold — any unproven condition ⇒ keep the
A′ carrier (fail-closed):

- **same basic block**: every use of the loaded value is in the SAME block as the load.
- **local field reads ONLY**: every use is a field read of the value (GEP + Load of the
  carrier / the getter inlined to a field load).
- **no calls**: the value is not passed to any call — including **NO `recv_borrow`**
  (receiver-position is excluded in v1; it is the optimistic band, not proven borrow).
- **no Array mutation** between the load and the last use: no `arr[i]=`/`push`/`<<`/
  `delete_at`/`shift`/`insert`/`clear`/`concat` on the source array (the slot may move on
  realloc or be overwritten).
- **no alias writes**: no aliasing reference to the source array is written through
  between the load and the last use (`b = arr; b << …`).
- **no escape**: not returned / stored / union-wrapped / address-taken.

Widening (cross-block dataflow, `recv_borrow` with a proven borrow-only callee, loop-carried)
is deferred v2, each behind its own proof.

## 3. A′ coupling (GPT caveat 5)

C-narrow-b REQUIRES A′ on: the direct-slot read is only correct when the buffer stores the
value INLINE. Without A′ the buffer holds POINTERS — a direct-slot read would read a
pointer as a value (repr-flip). So: `ADAMAS_CNARROW_B_LOAD=1` WITHOUT
`ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1` ⇒ **0 direct-slot loads** (mandatory guard reducer).
The behavior hook is placed inside the A′ block (as C-narrow-a's is), so the coupling holds
by construction.

## 4. Fact to consume (no second oracle)

Mirror C-narrow-a: a durable MIR mark on the eligible load (`MIR::ArrayGet#cnarrow_b_direct`
or the load instruction), computed POST-MIR-opt (the optimizer clones/drops pre-opt marks).
The eligibility = the §2 conjunction over the load result's uses (an escape/use walk within
the block), gated on the element type being `inline_array_storage_eligible`. The later
behavior transform consumes the mark; it does NOT re-derive provenance/storage (GPT hard-stop).

## 5. Reducers (reducer-first; NO behavior yet)

**Read-only preflight** (gate `ADAMAS_CNARROW_B_PREFLIGHT`): classify each inline-`C` load
with a reason code — `eligible` / `escapes:<why>` / `intervening_call` /
`intervening_mutation` / `aliased` / `recv_borrow` / `cross_block` — and mark the eligible
loads. Behavior-neutral (gate-OFF byte-identical).

**Positive reducer — C-SPECIFIC (GPT caveat 3, the value-proxy lesson):** a clean
`Array(V3)` same-block local-read loop. Assert: V3 load `eligible`; AND (once behavior
lands) the carrier alloc (`[i64 INT64_MAX][payload]`) disappears SPECIFICALLY in the
Array(V3) read path — NOT a global `ivc_raw`/carrier-count proxy. The behavior DoD greps
the carrier in the V3 read block, not module-wide.

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
