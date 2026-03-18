#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <compiler> [source]" >&2
  exit 2
fi

COMPILER="$1"
SOURCE="${2:-"$(dirname "$0")/stage2_block_body_exprid_parser_repro.cr"}"
OUT="${TMPDIR:-/tmp}/stage2_block_body_exprid_parser_repro_bin"
LOG="${TMPDIR:-/tmp}/stage2_block_body_exprid_parser_repro.log"

set +e
env CRYSTAL_V2_STOP_AFTER_PARSE=1 \
  "$COMPILER" --release --no-prelude "$SOURCE" -o "$OUT" >"$LOG" 2>&1
rc=$?
set -e

if [[ $rc -ne 0 ]]; then
  echo "reproduced: compiler crashed while parsing the reduced block-body ExprId repro" >&2
  echo "source: $SOURCE" >&2
  echo "log: $LOG" >&2
  /usr/bin/tail -n 120 "$LOG" >&2 || true
  exit $rc
fi

echo "not reproduced: compiler parsed the reduced block-body ExprId repro"
