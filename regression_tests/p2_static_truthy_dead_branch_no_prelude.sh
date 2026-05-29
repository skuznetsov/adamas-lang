#!/usr/bin/env bash
# Guard that compile-time-known truthiness prunes dead branch bodies after the
# condition itself has been lowered.
#
# The bootstrap failure mode was Hash#key_hash lowering
# `key.responds_to?(:object_id)` to a Bool literal while still lowering the dead
# `key.object_id` branch. That dead call then entered lower_missing as concrete
# source demand (for example Int32#object_id / Tuple#object_id).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/adamas}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_static_truthy_dead_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

SRC="$TMP_DIR/dead_responds_to.cr"
OUT="$TMP_DIR/out"
LOG="$TMP_DIR/run_safe.log"

cat >"$SRC" <<'CR'
def probe(x : Int32)
  if x.responds_to?(:object_id)
    x.object_id
  else
    7
  end
end

def probe_and(x : Int32, dynamic : Bool)
  if dynamic && x.responds_to?(:object_id)
    x.object_id
  else
    9
  end
end

probe(1)
probe_and(1, true)
CR

CRYSTAL_V2_STOP_AFTER_HIR=1 \
CRYSTAL_V2_PHASE_STATS=1 \
DEBUG_MISSING_SUMMARY=1 \
DEBUG_MISSING_SAMPLES=1 \
DEBUG_MISSING_TOP=20 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" 20 512 \
    "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

if grep -q 'Int32#object_id' "$LOG" "$OUT.hir"; then
  echo "p2 static truthy dead-branch regression: dead Int32#object_id was emitted" >&2
  grep -n 'Int32#object_id' "$LOG" "$OUT.hir" >&2 || true
  exit 1
fi

lower_missing_delta="$(grep -E '\[PHASE_STATS\] lower_missing: [0-9]+ -> [0-9]+ \(\+[0-9]+\)' "$LOG" \
  | tail -1 \
  | sed -E 's/.*\(\+([0-9]+)\).*/\1/' || true)"
lower_missing_delta="${lower_missing_delta:-0}"
if (( lower_missing_delta != 0 )); then
  echo "p2 static truthy dead-branch regression: lower_missing delta ${lower_missing_delta} != 0" >&2
  tail -80 "$LOG" >&2
  exit 1
fi

echo "p2_static_truthy_dead_branch_no_prelude_ok lower_missing_delta=${lower_missing_delta}"
