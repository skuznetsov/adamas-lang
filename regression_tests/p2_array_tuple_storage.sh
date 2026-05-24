#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cv2_array_tuple_storage.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cat >"$SRC" <<'CR'
def tuple_array_sum : Int64
  arr = Array(Tuple(Int64, Int64)).new
  i = 0
  while i < 4
    arr << {i.to_i64, (i + 10).to_i64}
    i += 1
  end

  sum = 0_i64
  i = 0
  while i < arr.size
    t = arr[i]
    sum += t[0] + t[1]
    i += 1
  end

  sum
end

def pointer_tuple_sum : Int64
  ptr = Pointer(Tuple(Int64, Int64)).malloc(3)
  ptr[0] = {1_i64, 10_i64}
  ptr[1] = {2_i64, 20_i64}
  ptr[2] = {3_i64, 30_i64}

  ptr[0][0] + ptr[0][1] + ptr[1][0] + ptr[1][1] + ptr[2][0] + ptr[2][1]
end

exit 1 unless tuple_array_sum == 52_i64
exit 2 unless pointer_tuple_sum == 66_i64
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 build "$SRC" --release -o "$BIN" >"$LOG" 2>&1
compile_rc=$?
set -e

if [[ $compile_rc -ne 0 ]]; then
  echo "p2_array_tuple_storage_failed: compile failed" >&2
  tail -120 "$LOG" >&2 || true
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_rc=$?
set -e

if [[ $run_rc -ne 0 ]]; then
  echo "p2_array_tuple_storage_failed: run failed rc=$run_rc" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "p2_array_tuple_storage_ok"
