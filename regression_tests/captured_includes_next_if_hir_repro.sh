#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <compiler>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="$1"
SOURCE="$ROOT_DIR/regression_tests/captured_includes_next_if_hir_repro.cr"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/captured_includes_next_if.XXXXXX")"
PROBE_SOURCE="$WORKDIR/probe.cr"
PROBE_HIR="$WORKDIR/probe.hir"
MUTATION_HIR="$WORKDIR/mutation.hir"
PROC_HIR="$WORKDIR/proc.hir"
LOG="$WORKDIR/compile.log"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

if [[ ! -x "$COMPILER" ]]; then
  echo "error: compiler binary not found/executable: $COMPILER" >&2
  exit 2
fi

cp "$SOURCE" "$PROBE_SOURCE"

set +e
"$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 120 2048 \
  "$PROBE_SOURCE" --emit hir --no-link >"$LOG" 2>&1
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  echo "reproduced: compiler failed to narrow the captured includes receiver" >&2
  tail -n 120 "$LOG" >&2
  exit 1
fi

if [[ ! -f "$PROBE_HIR" ]]; then
  echo "inconclusive: compiler succeeded without emitting the expected HIR" >&2
  tail -n 120 "$LOG" >&2
  exit 2
fi

if rg -q 'Nil#includes\?\$' "$PROBE_HIR"; then
  echo "reproduced: emitted HIR still dispatches includes? through Nil" >&2
  rg -n 'Nil#includes\?\$' "$PROBE_HIR" >&2
  exit 1
fi

if ! rg -q 'Set\(String\)#includes\?\$String' "$PROBE_HIR"; then
  echo "inconclusive: expected Set(String)#includes? call was not emitted" >&2
  exit 2
fi

awk '
  /^func @/ {
    if (capture) exit
    if (index($0, "func @snapshot_with_argument_mutation") == 1) capture = 1
  }
  capture { print }
' "$PROBE_HIR" >"$MUTATION_HIR"

if [[ ! -s "$MUTATION_HIR" ]]; then
  echo "inconclusive: mutation probe function was not emitted" >&2
  exit 2
fi

PROC_NAME="$(sed -n 's/.*func_pointer @\([^ ]*\).*/\1/p' "$MUTATION_HIR" | head -n 1)"
if [[ -z "$PROC_NAME" ]]; then
  echo "inconclusive: mutation probe did not materialize its block" >&2
  exit 2
fi

awk -v function_prefix="func @$PROC_NAME(" '
  /^func @/ {
    if (capture) exit
    if (index($0, function_prefix) == 1) capture = 1
  }
  capture { print }
' "$PROBE_HIR" >"$PROC_HIR"

if [[ ! -s "$PROC_HIR" ]]; then
  echo "inconclusive: materialized mutation block $PROC_NAME was not emitted" >&2
  exit 2
fi

GET_MATCH="$(rg -n -m1 'classvar_get __closure\.' "$PROC_HIR" || true)"
if [[ -z "$GET_MATCH" ]]; then
  echo "reproduced: materialized block does not read the captured receiver cell" >&2
  exit 1
fi
GET_LINE="${GET_MATCH%%:*}"
GET_ID="$(printf '%s\n' "$GET_MATCH" | sed -E 's/^[0-9]+:[[:space:]]*%([0-9]+).*/\1/')"
CELL_NAME="$(printf '%s\n' "$GET_MATCH" | sed -E 's/.*classvar_get ([^ ]+) .*/\1/')"

UNWRAP_MATCH="$(rg -n -m1 "^[[:space:]]+%[0-9]+ = union_unwrap %${GET_ID} " "$PROC_HIR" || true)"
if [[ -z "$UNWRAP_MATCH" ]]; then
  echo "reproduced: captured receiver cell is not unwrapped in $PROC_NAME" >&2
  exit 1
fi
UNWRAP_LINE="${UNWRAP_MATCH%%:*}"
UNWRAP_ID="$(printf '%s\n' "$UNWRAP_MATCH" | sed -E 's/^[0-9]+:[[:space:]]*%([0-9]+).*/\1/')"

COPY_MATCH="$(rg -n -m1 "^[[:space:]]+%[0-9]+ = copy %${UNWRAP_ID} " "$PROC_HIR" || true)"
if [[ -z "$COPY_MATCH" ]]; then
  echo "reproduced: one-shot captured receiver payload is not copied in $PROC_NAME" >&2
  exit 1
fi
COPY_LINE="${COPY_MATCH%%:*}"
RECEIVER_ID="$(printf '%s\n' "$COPY_MATCH" | sed -E 's/^[0-9]+:[[:space:]]*%([0-9]+).*/\1/')"

SET_MATCH="$(rg -n -m1 -F "classvar_set $CELL_NAME" "$PROC_HIR" || true)"
if [[ -z "$SET_MATCH" ]]; then
  echo "inconclusive: mutation probe does not write the captured receiver cell" >&2
  exit 2
fi
SET_LINE="${SET_MATCH%%:*}"

CALL_MATCH="$(rg -n -m1 "call %${RECEIVER_ID}\\.Set\\(String\\)#includes\\?\\\$String" "$PROC_HIR" || true)"
if [[ -z "$CALL_MATCH" ]]; then
  echo "reproduced: concrete includes? call does not consume the saved receiver payload" >&2
  exit 1
fi
CALL_LINE="${CALL_MATCH%%:*}"

if ! ((GET_LINE < UNWRAP_LINE && UNWRAP_LINE < COPY_LINE && COPY_LINE < SET_LINE && SET_LINE < CALL_LINE)); then
  echo "reproduced: receiver proof is not captured before argument-side cell mutation" >&2
  printf 'get=%s unwrap=%s copy=%s set=%s call=%s\n' \
    "$GET_LINE" "$UNWRAP_LINE" "$COPY_LINE" "$SET_LINE" "$CALL_LINE" >&2
  exit 1
fi

echo "captured_includes_next_if_hir_ok"
