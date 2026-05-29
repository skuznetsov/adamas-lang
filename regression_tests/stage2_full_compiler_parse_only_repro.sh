#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler> [source] [iterations]" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="$1"
SOURCE="${2:-"$ROOT/src/adamas.cr"}"
ITERATIONS="${3:-5}"
OUT_DIR="${TMPDIR:-/tmp}/stage2_full_compiler_parse_only_repro.$$"
LOG="$OUT_DIR/run.log"

mkdir -p "$OUT_DIR"
: >"$LOG"

rcs=()

for ((i = 1; i <= ITERATIONS; i++)); do
  OUT="$OUT_DIR/out_$i"
  set +e
  env CRYSTAL_V2_STOP_AFTER_PARSE=1 \
    "$COMPILER" "$SOURCE" --release -o "$OUT" >>"$LOG" 2>&1
  rc=$?
  set -e
  rcs+=("$rc")

  if [[ $rc -ne 0 ]]; then
    echo "reproduced: compiler failed full-compiler parse-only loop on iteration $i/$ITERATIONS" >&2
    echo "source: $SOURCE" >&2
    echo "log: $LOG" >&2
    echo "rcs: ${rcs[*]}" >&2
    /usr/bin/tail -n 120 "$LOG" >&2 || true
    exit $rc
  fi
done

echo "not reproduced: compiler survived ${ITERATIONS} full-compiler parse-only iterations"
echo "rcs: ${rcs[*]}"
