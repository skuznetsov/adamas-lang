#!/usr/bin/env bash
# Regression target for the stage2 `Range -> Indexable.range_to_index_and_count`
# path. This currently guards the whole frontier: owner/name recovery, virtual
# dispatch materialization, and the downstream tuple-key Hash crash family.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/stage2_indexable_range.XXXXXX")"
OUT="$TMP_DIR/range_repro"
LOG="$TMP_DIR/compile.log"
RUN_LOG="$TMP_DIR/run.log"
trap 'rm -rf "$TMP_DIR"' EXIT

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 180 4096 "$ROOT_DIR/regression_tests/range_to_index_repro.cr" -o "$OUT" >"$LOG" 2>&1
compile_status=$?
set -e

if [[ $compile_status -ne 0 ]]; then
  echo "FAIL: compiler could not materialize Indexable.range_to_index_and_count (status $compile_status)" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$OUT" 5 512 >"$RUN_LOG" 2>&1
run_status=$?
set -e

if [[ $run_status -ne 0 ]]; then
  echo "FAIL: compiled range_to_index repro exited $run_status" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

if ! grep -Fxq "0:1" "$RUN_LOG"; then
  echo "FAIL: expected 0:1 from range_to_index repro" >&2
  cat "$RUN_LOG" >&2
  exit 1
fi

echo "stage2_indexable_range_materialization_ok"
