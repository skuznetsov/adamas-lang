#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cv2_array_heap_struct_dup.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/repro.cr"
BIN="$TMP_DIR/repro"
COMPILE_LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"

cat >"$SRC" <<'CR'
struct IdBox
  getter index : Int32

  def initialize(@index : Int32)
  end
end

ary = Array(IdBox).new(71) { |i| IdBox.new(i) }
copy = ary.dup

exit 1 unless copy.size == 71
exit 2 unless copy[34].index == 34
exit 3 unless copy[35].index == 35
exit 4 unless copy[36].index == 36
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 "$SRC" --release -o "$BIN" >"$COMPILE_LOG" 2>&1
compile_rc=$?
set -e

if [[ $compile_rc -ne 0 ]]; then
  echo "p2_array_heap_struct_dup_stride_failed: compile failed" >&2
  tail -120 "$COMPILE_LOG" >&2 || true
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$BIN" 5 512 >"$RUN_LOG" 2>&1
run_rc=$?
set -e

if [[ $run_rc -ne 0 ]]; then
  echo "p2_array_heap_struct_dup_stride_failed: run failed rc=$run_rc" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "p2_array_heap_struct_dup_stride_ok"
