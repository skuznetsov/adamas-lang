#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cv2-pointer-tuple-inline.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
BIN="$TMP_DIR/repro_bin"
LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"
MAIN_IR="$TMP_DIR/main.ll"

cat >"$SRC" <<'CR'
lib LibC
  fun abort : NoReturn
end

def pointer_tuple_sum : Int64
  ptr = Pointer(Tuple(Int64, Int64)).malloc(4)

  i = 0
  while i < 4
    ptr[i] = {i.to_i64, (i * 2).to_i64}
    i += 1
  end

  acc = 0_i64
  i = 0
  while i < 4
    tuple = ptr[i]
    acc += tuple[0] + tuple[1]
    i += 1
  end

  acc
end

LibC.abort if pointer_tuple_sum != 18_i64
CR

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 2048 \
  "$SRC" --no-prelude --emit llvm-ir --no-link -o "$OUT" >"$LOG" 2>&1

awk '/^define .*@pointer_tuple_sum/{inside=1} inside{print} inside && /^}/{exit}' "$OUT.ll" >"$MAIN_IR"

if grep -q 'tuple_slot_copy' "$MAIN_IR"; then
  echo "expected Pointer(Tuple(Int64, Int64)) store to avoid heap tuple slot copies" >&2
  cat "$MAIN_IR" >&2
  exit 1
fi

if ! grep -Eq 'mul i64 .*, 16' "$MAIN_IR"; then
  echo "expected Pointer(Tuple(Int64, Int64)) GEP to use 16-byte inline stride" >&2
  cat "$MAIN_IR" >&2
  exit 1
fi

"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 30 2048 \
  "$SRC" --no-prelude -o "$BIN" >"$LOG" 2>&1

if ! "$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1; then
  echo "p2_pointer_primitive_tuple_inline_stride_no_prelude_failed: runtime failed" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "p2_pointer_primitive_tuple_inline_stride_no_prelude_ok"
