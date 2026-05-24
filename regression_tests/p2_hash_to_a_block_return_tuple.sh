#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/p2_hash_to_a_tuple.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"
WRAPPER_HIR="$TMP_DIR/wrapper.hir"
RUN_LOG="$TMP_DIR/run.log"

cat > "$SRC" <<'CR'
h = {"a" => 1}
arr = h.to_a
puts arr[0][0]
puts arr[0][1]
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 \
  "$SRC" --emit=hir --no-link -o "$OUT" >"$LOG" 2>&1

HIR="$OUT.hir"
if [[ ! -f "$HIR" ]]; then
  echo "missing HIR output" >&2
  tail -80 "$LOG" >&2 || true
  exit 1
fi

awk '
  /^func @Hash\(String, Int32\)#to_a_super_from_Enumerable/ { inside = 1 }
  inside { print }
  inside && /^}/ { exit }
' "$HIR" > "$WRAPPER_HIR"

if [[ ! -s "$WRAPPER_HIR" ]]; then
  echo "missing Hash(String, Int32)#to_a_super_from_Enumerable wrapper" >&2
  rg -n 'Hash\(String, Int32\)#to_a' "$HIR" >&2 || true
  exit 1
fi

if grep -q 'Array(Int32)\.new' "$WRAPPER_HIR"; then
  echo "Hash#to_a wrapper allocated Array(Int32), expected Array(Tuple(String, Int32))" >&2
  cat "$WRAPPER_HIR" >&2
  exit 1
fi

if ! grep -q 'Array(Tuple(String, Int32))\.new' "$WRAPPER_HIR"; then
  echo "Hash#to_a wrapper did not allocate Array(Tuple(String, Int32))" >&2
  cat "$WRAPPER_HIR" >&2
  exit 1
fi

if grep -Eq 'Tuple#as[$]Int32|Tuple[$]Has[$][$]Int32' "$HIR"; then
  echo "unexpected Tuple-to-Int32 specialization remains in HIR" >&2
  rg -n 'Tuple#as[$]Int32|Tuple[$]Has[$][$]Int32' "$HIR" >&2 || true
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 "$SRC" -o "$OUT" >"$LOG" 2>&1
"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 10 512 >"$RUN_LOG" 2>&1

grep -qx 'a' "$RUN_LOG"
grep -qx '1' "$RUN_LOG"

echo "p2_hash_to_a_block_return_tuple_ok"
