#!/usr/bin/env bash
# Repro: macro fresh-var scanner treated `a % b` (spaced modulo) inside a
# macro-for body as a fresh macro variable `%b`, rewriting it to
# `__macro_b_N`. The corrupted def then derailed the recovery parser, so
# every def AFTER it in the same expansion lost its module owner:
# Random#rand_int registered ONLY the Int8 overload under Random/PCG32,
# and rand(Int64) truncated the bound to i8 ("Invalid bound for rand: 0",
# rand(10_i64) returning values far outside [0, 10)).
#
# Red pre-fix : rand_int$$Int64 missing from IR; runtime aborts on
#               rand(0x100000000) and rand(10_i64) goes out of range.
# Green post-fix: per-width rand_int overloads emitted; values in range.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/macro_percent_modulo.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"

# NOTE: value-range checks are deliberately absent. The caller-side static
# type of `r.rand(n)` is still wrong (return type taken from the base-name
# cache -> Float64 from the zero-arg `def rand : Float64`), so comparisons
# and interpolation of the result compile through broken typing and cannot
# serve as a reliable gate. See rand_int64_abstract_int_return_repro.sh for
# the open return-width family. The reliable signals here are:
#   1) IR: rand_int$$Int64 must exist (overloads kept their module owner);
#   2) runtime: no "Invalid bound for rand" abort (pre-fix the Int64 bound
#      truncated to i8 0 inside the only surviving Int8 overload).
cat > "$SRC" <<'CR'
r = Random.new
r.rand(10_i8)
r.rand(10_i16)
r.rand(10)
r.rand(10_i64)
r.rand(10_u64)
r.rand(0x100000000)
STDERR.puts "RAND_DONE"
STDERR.flush
exit(0)
CR

if ! "$COMPILER" "$SRC" -o "$OUT" >"$LOG" 2>&1; then
  echo "compile failed" >&2
  tail -20 "$LOG" >&2
  exit 1
fi

# Second pass just for the IR probe (--emit=llvm-ir does not link).
"$COMPILER" "$SRC" -o "$OUT.ir" --emit=llvm-ir --no-link >>"$LOG" 2>&1 || true
LL="$OUT.ir.ll"
if [[ ! -f "$LL" ]]; then
  echo "missing $LL" >&2
  exit 1
fi

# Registration probe: the Int64 bound must dispatch to the Int64 overload.
if ! grep -q 'define i64 @Random$CCPCG32$Hrand_int$$Int64(' "$LL"; then
  echo "FAIL: rand_int\$\$Int64 not emitted (macro-for overloads lost their owner)" >&2
  grep -oE 'define[^(]*rand_int[^(]*\(' "$LL" | sort -u >&2 || true
  exit 1
fi

# Runtime probe: completes without the Int8-overload bound abort.
RUN_LOG="$TMP_DIR/run.log"
"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 >"$RUN_LOG" 2>&1
if grep -q "Invalid bound for rand" "$RUN_LOG"; then
  echo "FAIL: Invalid bound abort — bound truncated into wrong overload" >&2
  tail -20 "$RUN_LOG" >&2
  exit 1
fi
if ! grep -q "RAND_DONE" "$RUN_LOG"; then
  echo "FAIL: runtime crashed before completing rand calls" >&2
  tail -20 "$RUN_LOG" >&2
  exit 1
fi

echo "PASS: spaced modulo in macro-for body survives expansion; rand dispatches per width"
