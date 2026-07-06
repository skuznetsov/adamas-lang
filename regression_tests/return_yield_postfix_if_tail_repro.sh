#!/usr/bin/env bash
# Repro: `return yield if cond` inside a block method must NOT swallow the
# statements after it.
#
# Root cause (fixed): parse_prefix's Yield case called parse_postfix_if_modifier
# unconditionally, ignoring @consume_postfix_modifiers. Inside parse_return's
# without_postfix_modifiers scope the suffix `if` therefore bound to the YIELD
# value instead of the return statement, turning
#     return yield if v > 10
#     v * 2
# into `return (v > 10 ? yield : nil)` — an unconditional return that made every
# statement after it dead. stdlib victim: String#to_i32(&block) gen_to_ — all
# String#to_i?/to_i32?/to_u*? conversions lost their value/nil semantics.
#
# GREEN: pick's block wrapper HIR keeps BOTH the yield and the tail Mul, and the
# then-branch return-terminates instead of feeding an if-merge phi.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/return_yield_postfix_if.XXXXXX")"
cleanup() {
  if [[ "${KEEP_TMP:-0}" == "1" ]]; then
    echo "kept_tmp=$TMP_DIR"
  else
    rm -rf "$TMP_DIR"
  fi
}
trap cleanup EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/compile.log"
WRAPPER="$TMP_DIR/wrapper.hir"

cat > "$SRC" <<'CR'
def pick(v : Int32, &block)
  return yield if v > 10
  v * 2
end
a = pick(5) { -1 }
b = pick(20) { -1 }
CR

ADAMAS_STOP_AFTER_HIR=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 60 2048 \
  "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

HIR="$OUT.hir"
if [[ ! -s "$HIR" ]]; then
  echo "return_yield_postfix_if_failed: missing HIR" >&2
  tail -60 "$LOG" >&2 || true
  exit 1
fi

awk '
  /^func @pick\$Int32_block/ { inside = 1 }
  inside { print }
  inside && /^}/ { exit }
' "$HIR" > "$WRAPPER"

if [[ ! -s "$WRAPPER" ]]; then
  echo "return_yield_postfix_if_failed: pick block wrapper not found" >&2
  grep -n 'func @pick' "$HIR" >&2 || true
  exit 1
fi

# The tail expression (v * 2) must survive in the wrapper.
if ! grep -q 'binop Mul' "$WRAPPER"; then
  echo "return_yield_postfix_if_failed: tail after return-yield-if was dropped (no Mul)" >&2
  cat "$WRAPPER" >&2
  exit 1
fi

# The yield must still be present.
if ! grep -q ' = yield' "$WRAPPER"; then
  echo "return_yield_postfix_if_failed: yield missing from wrapper" >&2
  cat "$WRAPPER" >&2
  exit 1
fi

# Pre-fix shape merged both arms into an if-value phi that was returned
# unconditionally. Post-fix there must be no phi merging a yield arm with a
# nil arm in this wrapper (the then-branch return-terminates instead).
if grep -q 'phi \[' "$WRAPPER" && ! grep -q 'binop Mul' "$WRAPPER"; then
  echo "return_yield_postfix_if_failed: if-value phi shape without tail" >&2
  cat "$WRAPPER" >&2
  exit 1
fi

echo "return_yield_postfix_if_ok"
