#!/usr/bin/env bash
# Tier-1 guard for the opt-in AST demand reachability filter.
#
# This does not enable the demand filter by default. It proves the opt-in path
# can lower a compiler implementation file under --no-prelude without falling
# back to broad all-defs materialization.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"
SRC="${P2_AST_DEMAND_SOURCE:-$ROOT_DIR/src/compiler/hir/ast_to_hir.cr}"

TIMEOUT_SEC="${P2_AST_DEMAND_TIMEOUT_SEC:-60}"
MEM_MB="${P2_AST_DEMAND_MEM_MB:-4096}"
PROCESS_DELTA_LIMIT="${P2_AST_DEMAND_PROCESS_DELTA_LIMIT:-200}"
LOWER_MISSING_DELTA_LIMIT="${P2_AST_DEMAND_LOWER_MISSING_DELTA_LIMIT:-500}"
TOTAL_FUNCTION_LIMIT="${P2_AST_DEMAND_TOTAL_FUNCTION_LIMIT:-1000}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi
if [[ ! -f "$SRC" ]]; then
  echo "ERROR: source not found: $SRC" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_ast_filter_demand_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

OUT="$TMP_DIR/out"
LOG="$TMP_DIR/run_safe.log"

CRYSTAL_V2_AST_FILTER=1 \
CRYSTAL_V2_AST_FILTER_DEMAND=1 \
CRYSTAL_V2_STOP_AFTER_HIR=1 \
CRYSTAL_V2_PHASE_STATS=1 \
CRYSTAL_V2_LOWER_PROGRESS=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT_SEC" "$MEM_MB" \
    "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

if ! grep -q '\[AST_FILTER\] demand:' "$LOG"; then
  echo "p2 ast demand regression: demand filter did not run" >&2
  tail -120 "$LOG" >&2
  exit 1
fi

extract_delta() {
  local label="$1"
  local value
  value="$(grep -E "\\[PHASE_STATS\\] ${label}: [0-9]+ -> [0-9]+ \\(\\+[0-9]+\\)" "$LOG" \
    | tail -1 \
    | sed -E 's/.*\(\+([0-9]+)\).*/\1/' || true)"
  echo "${value:-0}"
}

process_delta="$(extract_delta process_pending)"
lower_missing_delta="$(extract_delta lower_missing)"

total_functions="$(grep -Eo 'Top type prefixes \([0-9]+ total functions\)' "$LOG" \
  | tail -1 \
  | sed -E 's/[^0-9]*([0-9]+).*/\1/' || true)"
total_functions="${total_functions:-0}"

fail=0
if (( process_delta > PROCESS_DELTA_LIMIT )); then
  echo "p2 ast demand regression: process_pending delta ${process_delta} > ${PROCESS_DELTA_LIMIT}" >&2
  fail=1
fi
if (( lower_missing_delta > LOWER_MISSING_DELTA_LIMIT )); then
  echo "p2 ast demand regression: lower_missing delta ${lower_missing_delta} > ${LOWER_MISSING_DELTA_LIMIT}" >&2
  fail=1
fi
if (( total_functions > TOTAL_FUNCTION_LIMIT )); then
  echo "p2 ast demand regression: total functions ${total_functions} > ${TOTAL_FUNCTION_LIMIT}" >&2
  fail=1
fi
if grep -q '\[PENDING_EXPLOSION\]' "$LOG"; then
  echo "p2 ast demand regression: pending explosion diagnostic fired" >&2
  grep '\[PENDING_EXPLOSION\]' "$LOG" >&2
  fail=1
fi

if (( fail != 0 )); then
  tail -120 "$LOG" >&2
  exit 1
fi

echo "p2_ast_filter_demand_no_prelude_ok process_delta=${process_delta} lower_missing_delta=${lower_missing_delta} total=${total_functions}"
