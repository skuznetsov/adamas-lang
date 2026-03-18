#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <compiler> [source]" >&2
  exit 2
fi

COMPILER=$1
SOURCE=${2:-"$(dirname "$0")/stage2_pointerof_nested_call_parser_repro.cr"}
OUT="${TMPDIR:-/tmp}/stage2_pointerof_nested_call_parser_repro_bin"
LOG="${TMPDIR:-/tmp}/stage2_pointerof_nested_call_parser_repro.log"

set +e
"$COMPILER" --release "$SOURCE" -o "$OUT" >"$LOG" 2>&1
rc=$?
set -e

if [ $rc -ne 0 ]; then
  echo "reproduced: compiler crashed or failed on nested pointerof call parser repro" >&2
  echo "source: $SOURCE" >&2
  echo "log: $LOG" >&2
  /usr/bin/tail -n 120 "$LOG" >&2 || true
  exit $rc
fi

echo "not reproduced: compiler compiled nested pointerof call parser repro"
