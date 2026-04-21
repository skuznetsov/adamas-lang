#!/usr/bin/env bash
# Tier-1 no-prelude budget guard for HIR pending-lowering growth.
#
# This is not a bootstrap proof. It is a fast sentinel that keeps focused
# compiler-file lowering from regressing into the same supply-driven shape as
# the full s1 -> s2b blocker.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
SRC="${P2_BUDGET_SOURCE:-$ROOT_DIR/src/compiler/hir/ast_to_hir.cr}"

TIMEOUT_SEC="${P2_BUDGET_TIMEOUT_SEC:-60}"
MEM_MB="${P2_BUDGET_MEM_MB:-4096}"
PROCESS_DELTA_LIMIT="${P2_PROCESS_DELTA_LIMIT:-500}"
EMIT_DELTA_LIMIT="${P2_EMIT_DELTA_LIMIT:-500}"
LOWER_MISSING_DELTA_LIMIT="${P2_LOWER_MISSING_DELTA_LIMIT:-1000}"
TOTAL_FUNCTION_LIMIT="${P2_TOTAL_FUNCTION_LIMIT:-2000}"
PENDING_QUEUE_LIMIT="${P2_PENDING_QUEUE_LIMIT:-5000}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi
if [[ ! -f "$SRC" ]]; then
  echo "ERROR: source not found: $SRC" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_pending_budget_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

OUT="$TMP_DIR/out"
LOG="$TMP_DIR/run_safe.log"

CRYSTAL_V2_STOP_AFTER_HIR=1 \
CRYSTAL_V2_PHASE_STATS=1 \
CRYSTAL_V2_LOWER_PROGRESS=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT_SEC" "$MEM_MB" \
    "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

extract_delta() {
  local label="$1"
  local value
  value="$(grep -E "\\[PHASE_STATS\\] ${label}: [0-9]+ -> [0-9]+ \\(\\+[0-9]+\\)" "$LOG" \
    | tail -1 \
    | sed -E 's/.*\(\+([0-9]+)\).*/\1/' || true)"
  echo "${value:-0}"
}

process_delta="$(extract_delta process_pending)"
emit_delta="$(extract_delta emit_tracked_sigs)"
lower_missing_delta="$(extract_delta lower_missing)"

total_functions="$(grep -Eo 'Top type prefixes \([0-9]+ total functions\)' "$LOG" \
  | tail -1 \
  | sed -E 's/[^0-9]*([0-9]+).*/\1/' || true)"
total_functions="${total_functions:-0}"

max_queue="$(awk '
  match($0, /idx=[0-9]+\/[0-9]+/) {
    text = substr($0, RSTART, RLENGTH)
    sub(/^idx=[0-9]+\//, "", text)
    if (text + 0 > max) max = text + 0
  }
  END { print max + 0 }
' "$LOG")"

fail=0
if (( process_delta > PROCESS_DELTA_LIMIT )); then
  echo "p2 pending budget regression: process_pending delta ${process_delta} > ${PROCESS_DELTA_LIMIT}" >&2
  fail=1
fi
if (( emit_delta > EMIT_DELTA_LIMIT )); then
  echo "p2 pending budget regression: emit_tracked_sigs delta ${emit_delta} > ${EMIT_DELTA_LIMIT}" >&2
  fail=1
fi
if (( lower_missing_delta > LOWER_MISSING_DELTA_LIMIT )); then
  echo "p2 pending budget regression: lower_missing delta ${lower_missing_delta} > ${LOWER_MISSING_DELTA_LIMIT}" >&2
  fail=1
fi
if (( total_functions > TOTAL_FUNCTION_LIMIT )); then
  echo "p2 pending budget regression: total functions ${total_functions} > ${TOTAL_FUNCTION_LIMIT}" >&2
  fail=1
fi
if (( max_queue > PENDING_QUEUE_LIMIT )); then
  echo "p2 pending budget regression: pending queue ${max_queue} > ${PENDING_QUEUE_LIMIT}" >&2
  fail=1
fi

if (( fail != 0 )); then
  tail -120 "$LOG" >&2
  exit 1
fi

echo "p2_pending_budget_no_prelude_ok process_delta=${process_delta} emit_delta=${emit_delta} lower_missing_delta=${lower_missing_delta} total=${total_functions} max_queue=${max_queue}"
