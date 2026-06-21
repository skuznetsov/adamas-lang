# C-narrow s2b smoke — readiness packet

Status: **MEASURED. 2026-06-21.** GPT's pre-default-ON gate: prove the combined gated
mode (A′ + C-narrow-a + C-narrow-b) at least survives a self-host smoke before widening
the surface. Conclusion: **the gated build is clean; the s2b binary's startup crash is
PRE-EXISTING (not introduced by C-narrow), so there is no combined-gate incompatibility.**

## Method

`bin/adamas src/adamas.cr -o <s2b>` builds the compiler with itself (stage-1 → s2b),
applying the gated ABI to the compiler's own code. The resulting s2b then compiles a
tiny program (`x = 1`). Output binaries run only via `scripts/run_safe.sh`.

## Matrix

| config (s2b build) | build exit | s2b compiles `x=1` |
|---|---:|---|
| baseline (no gates) | 0 | **139 (SIGSEGV)** — owner-confirmed pre-existing |
| A′ only | 0 | 139 |
| A′ + C-narrow-a (placement) | 0 | 139 |
| A′ + C-narrow-a + C-narrow-b | 0 | 139 |

All four BUILD cleanly (exit 0 — the gated ABI compiles the whole compiler without a
compile-time failure; the C-narrow preflight/behavior marks fire on the compiler's own
eligible structs, e.g. `Range(Int32,Int32)`). All four s2b binaries then SIGSEGV (139)
at the SAME startup point (the `[STAGE2_DEBUG] pass3 after lower_main` region) when run.

## Finding

**The s2b startup SIGSEGV is PRE-EXISTING and gate-independent.** Baseline (no gates),
A′-only, A′+C-narrow-a, and A′+all-three crash identically (139, same trace point). This
is the long-documented s2b startup crash family (the two-heap GC hazard / startup
segfault, see memory `s2b_startup_crash_rc_overfree_refuted`), unrelated to the inline-
value-array ABI or the C-narrow slices.

So GPT's combined-gate-incompatibility worry is **NOT realised**: C-narrow-a/b add NO new
self-host crash — they crash exactly where baseline does. The gated ABI does not break the
self-host BUILD (all exit 0), and the runtime startup crash is the separate pre-existing
issue that blocks ALL gate-ON self-host validation equally (it must be fixed independently;
it is not a C-narrow regression).

## Consequences

- **C-narrow-a/b are self-host-clean** relative to baseline: no new crash, gated build OK.
- **Default-OFF is safe** (existing behavior byte-identical; verified across the reducer suite).
- **Default-ON readiness is blocked by the pre-existing s2b startup crash**, NOT by C-narrow.
  A broader gate-ON suite + a working s2b smoke both require that pre-existing crash fixed
  first (it affects baseline too).
- Therefore the next lever is NOT "fix a C-narrow self-host bug" (there is none) — it is the
  pre-existing s2b startup crash (separate track) OR proceed to the C-wide SDD with the
  understanding that self-host validation is currently floored by that pre-existing crash
  for ALL gate-ON ABI work.

## Reproduce

```
for cfg in "" "ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1" \
           "ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_CNARROW_A_PLACEMENT=1" \
           "ADAMAS_INLINE_VALUE_ARRAY_STORAGE=1 ADAMAS_CNARROW_A_PLACEMENT=1 ADAMAS_CNARROW_B_LOAD=1"; do
  env $cfg bin/adamas src/adamas.cr -o /tmp/s2b   # exit 0
  env $cfg /tmp/s2b /tmp/x.cr -o /tmp/x_bin        # 139 (pre-existing)
done
```
