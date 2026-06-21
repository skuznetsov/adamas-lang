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

**The first s2b runtime failure is PRE-EXISTING and gate-independent.** Baseline (no
gates), A′-only, A′+C-narrow-a, and A′+all-three crash identically (139, same trace point).

**ROOT (localized 2026-06-21 via lldb — NOT two-heap GC):** the crash is a NULL-deref in
`String#split(Char, Nil, Bool)` (`ldr w2,[x9]`, x9=0) reached from
`Dir::Globber#single_compile`'s `glob.split('/')` during the compiler's require-glob
resolution (`parse_required_files` → `Dir.glob`). It is NOT the byte_at / two-heap-GC
startup crash (that fix `e635fbc4` IS present; String layout is the correct
`{ptr,i32,i32}`). It is also NOT optimization-induced (`--no-mir-opt --no-llvm-opt` s2b
still crashes). It is a **context-specific nilable-`limit` miscompile in String#split**:
standalone `Dir.glob(...)` no longer CRASHES on bin/adamas, but the family is NOT fully
clean standalone — the minimal semantic reducer `string_split_default_nil_limit_repro.{cr,sh}`
shows `"a/b/c/d".split('/')` (default nil limit) already returns the WRONG count (1, not 4)
WITHOUT s2b/lldb. The full s2b self-build escalates the same nilable-limit family to a
SIGSEGV: the inner `String#split$Char$$arity3_block` monomorphizes with `i32 %limit` (vs
`ptr %limit` standalone) and the outer coerces its Nil limit via `load i32, ptr %limit` on a
null ptr. See memory `s2b_startup_crash_split_glob_localization`.

So GPT's combined-gate-incompatibility worry is **NOT realised**, but the precise,
evidence-bounded claim is narrower than "self-host-clean":

> **C-narrow gates BUILD s2b (all exit 0) and do NOT change the first observed startup
> crash** (baseline and all-gates configs hit the identical first failure). This does NOT
> prove the gated s2b is runtime-clean after the Globber/split root cause is fixed — that
> remains unverified and is the next gate before any default-ON discussion.

The String#split/Globber crash blocks ALL gate-ON self-host validation equally; it must be
fixed independently. It is not a C-narrow regression.

## Consequences

- **C-narrow-a/b build s2b and do not change the first observed startup crash** (NOT a
  proof of gated-s2b runtime-cleanliness — that needs the Globber/split root cause fixed
  and re-verified).
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
