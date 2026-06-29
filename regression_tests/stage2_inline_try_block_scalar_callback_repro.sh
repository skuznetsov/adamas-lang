#!/usr/bin/env bash
# Regression: produced stage2 must compile the stdlib Exception#backtrace?
# try-inline path without crashing in the generated block callback for
# AstToHir#inline_try_core.
#
# The old failure was a compile-time SIGSEGV while lowering:
#   @callstack.try &.printable_backtrace
# from Exception#backtrace?. The generated block callback treated the scalar
# ValueId passed by inline_try_core as a pointer and crashed before MIR lowering
# could finish. This guard only asserts that the compiler gets past that
# frontend crash; it does not run the produced program.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2-inline-try-block.XXXXXX")"
SRC="$TMP_DIR/repro.cr"
OUT="$TMP_DIR/repro"
LOG="$TMP_DIR/compile.log"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cat >"$SRC" <<'CR'
begin
  raise "boom"
rescue ex
  ex.backtrace?
end
CR

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 4096 "$SRC" -o "$OUT" >"$LOG" 2>&1
status=$?
set -e

if [[ $status -eq 0 && -x "$OUT" ]]; then
  echo "stage2_inline_try_block_scalar_callback_ok status=0"
  exit 0
fi

if [[ $status -eq 139 ]] || grep -Eq 'Segmentation fault|EXC_BAD_ACCESS' "$LOG"; then
  LLDB_LOG="$TMP_DIR/lldb.log"
  set +e
  lldb --batch \
    -o "run $SRC -o $OUT.lldb" \
    -k 'bt 20' \
    -k 'quit' \
    "$COMPILER" >"$LLDB_LOG" 2>&1
  set -e

  if grep -Eq 'inline_try_with_block|inline_try_core|__crystal_block_proc' "$LLDB_LOG"; then
    echo "stage2_inline_try_block_scalar_callback_failed: old inline try block callback crash returned" >&2
    tail -120 "$LLDB_LOG" >&2 || true
    exit 1
  fi

  echo "stage2_inline_try_block_scalar_callback_failed: unclassified segfault status=$status" >&2
  tail -120 "$LOG" >&2 || true
  tail -80 "$LLDB_LOG" >&2 || true
  exit 1
fi

echo "stage2_inline_try_block_scalar_callback_failed: status=$status" >&2
tail -120 "$LOG" >&2 || true
exit 1
