# C-narrow-a promotion-gate measurement (value-proxy check)

Status: **MEASURED + VERDICT. 2026-06-21.** Closes the value-proxy check GPT required
before any further ABI work: C-narrow-a was justified as a *bench-measurable narrow win*,
so the IR signal (transient `$Dnew` call eliminated) must be backed by an actual
RSS/time win on the targeted workload, not asserted.

Bench: `Array(Vec3)` (12-byte leaf-POD struct), 3M elements. Two shapes:
- **push-only** (`/tmp/bench_vec3_pushonly.cr`) — 3M `arr << Vec3.new(..)`, no read pass
  (isolates the store side).
- **push+read** (`/tmp/bench_vec3_pushread.cr`) — + one 3M read pass (the read heap
  carrier = the C-narrow-b cost, present in both A′ configs).

Three configs: OFF (legacy), A′ (`ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1`), A′+C-narrow-a
(`+ ADAMAS_CNARROW_A_PLACEMENT=1`). `/usr/bin/time -l`, best-of-3 wall, max RSS.

## Results

| config | push-only RSS | push-only wall | push+read RSS | push+read wall |
|--------|--------------:|---------------:|--------------:|---------------:|
| OFF (legacy)        | 120.3 MB | 0.06 s | 120.3 MB | 0.07 s |
| A′ only             | 132.1 MB | 0.06 s | **224.0 MB** | 0.09 s |
| **A′ + C-narrow-a** | **40.1 MB** | **0.03 s** | **132.0 MB** | 0.06 s |

- `checksum` identical across all configs (4499998500000 push-only / 13500004500000
  push+read) — behavior-correct.
- IR signal (placement reducer): `Vec3$Dnew` call `1 → 0` at the marked site; `placed=2`.

## Verdict

**C-narrow-a CONFIRMED its role — the store residual is real and large.**
- **push-only:** A′ 132 → **40 MB (−70%)**, *below even OFF* (inline 12 B vs OFF's 8 B
  pointer + 16 B heap Vec3 + GC overhead per element); wall ~2× faster. The transient
  `$Dnew` heap allocation is gone.
- **push+read:** A′ 224 → **132 MB (−41%)** — the store residual (~92 MB of leak-to-exit
  transients) is eliminated. But **still above OFF (132 vs 120 MB)**: the remaining gap is
  the **read heap carrier** (3M copy-on-load carriers, leak-to-exit), which C-narrow-a
  (store-side only) does not touch. That is the **C-narrow-b** target.

So the A′ packet's two residuals are now empirically separated and quantified:
- store residual (transient `$Dnew`) ≈ the push-only A′→narrow delta (**−92 MB**) — CLOSED
  by C-narrow-a.
- load residual (copy-on-load carrier) ≈ the push+read narrow-vs-OFF gap (**+12 MB and the
  224 vs 132 read-pass inflation**) — OPEN, the C-narrow-b lever.

## Decision (per GPT promotion gate)

The push-heavy delta is large AND read-heavy is still above OFF purely due to the heap
carrier → **C-narrow-b (escape-conditioned direct-slot load) has evidence-backed value**;
proceed C-narrow-b design/reducer-first (NOT C-wide yet, NOT widen narrow blindly).
C-narrow-a stays gated default OFF until the owner flips it (the slice is correct and a
real win, but flipping default-ON is a CAUTION ABI change requiring s2b smoke under the
gate, not yet run).

Reproduce: compile each bench in the 3 configs, then
`/usr/bin/time -l <binary>` and read `maximum resident set size` + `real` + `checksum=`.
