#!/usr/bin/env bash
# Repro: the String#to_i/to_i32/to_i64/to_u* strtol intercepts must NOT fire on
# BLOCK forms.
#
# Root cause (fixed): stdlib to_i32? lowers to `to_i32(...) { nil }`; the
# lower_call intercept matched method_name "to_i32" regardless of the block and
# replaced the whole nil-signalling chain with __adamas_string_to_i_base, which
# cannot represent nil -> "".to_i? returned a wrapped Int32(0) instead of nil.
# Companion fix: the numeric-conversion Cast fallback (to_* -> Cast) now
# requires arg-less/block-less calls on primitive receivers; it used to bitcast
# the STRING POINTER into the Int32 union payload once the intercept was gated.
#
# GREEN: String#to_i32? IR contains no strtol intrinsic call; the real
# to_i32(&block) wrapper is called instead.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/to_i_block_intercept.XXXXXX")"
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
FUNC_IR="$TMP_DIR/to_i32q.ll"

cat > "$SRC" <<'CR'
w = "64".to_i32?
STDERR.puts w.nil?
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 8192 \
  "$SRC" --emit llvm-ir --no-link -o "$OUT" >"$LOG" 2>&1

IR="$OUT.ll"
if [[ ! -s "$IR" ]]; then
  echo "to_i_block_intercept_failed: missing IR" >&2
  tail -60 "$LOG" >&2 || true
  exit 1
fi

awk '
  /^define .*@String\$Hto_i32\$Q/ { inside = 1 }
  inside { print }
  inside && /^}/ { exit }
' "$IR" > "$FUNC_IR"

if [[ ! -s "$FUNC_IR" ]]; then
  echo "to_i_block_intercept_failed: String#to_i32? not found in IR" >&2
  grep -n 'String\$Hto_i32' "$IR" >&2 | head -5 || true
  exit 1
fi

if grep -q '__adamas_string_to_i' "$FUNC_IR"; then
  echo "to_i_block_intercept_failed: strtol intrinsic replaced the nil-signalling block chain" >&2
  cat "$FUNC_IR" >&2
  exit 1
fi

if ! grep -q 'String\$Hto_i32\$\$.*_block' "$FUNC_IR"; then
  echo "to_i_block_intercept_failed: to_i32? does not call the block wrapper" >&2
  cat "$FUNC_IR" >&2
  exit 1
fi

echo "to_i_block_intercept_ok"
