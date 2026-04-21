#!/usr/bin/env bash
# Tier-1 sentinel for universal helper fanout on deep compiler containers.
#
# It intentionally compiles a compiler implementation file with --no-prelude:
# enough declarations to exercise the lowering machinery, but still fast enough
# for frequent local runs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
SRC="${P2_FANOUT_SOURCE:-$ROOT_DIR/src/compiler/hir/ast_to_hir.cr}"

TIMEOUT_SEC="${P2_FANOUT_TIMEOUT_SEC:-60}"
MEM_MB="${P2_FANOUT_MEM_MB:-4096}"
MAX_DEEP_HELPERS="${P2_MAX_DEEP_HELPERS:-0}"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi
if [[ ! -f "$SRC" ]]; then
  echo "ERROR: source not found: $SRC" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_universal_fanout_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

OUT="$TMP_DIR/out"
LOG="$TMP_DIR/run_safe.log"

CRYSTAL_V2_PENDING_EXPLOSION_TRACE=1 \
CRYSTAL_V2_STOP_AFTER_HIR=1 \
CRYSTAL_V2_PHASE_STATS=1 \
CRYSTAL_V2_LOWER_PROGRESS=1 \
  "$ROOT_DIR/scripts/run_safe.sh" "$COMPILER" "$TIMEOUT_SEC" "$MEM_MB" \
    "$SRC" --no-prelude --emit hir --no-link -o "$OUT" >"$LOG" 2>&1

if grep -q '\[PENDING_EXPLOSION\]' "$LOG"; then
  echo "p2 universal helper fanout regression: pending explosion diagnostic fired" >&2
  grep '\[PENDING_EXPLOSION\]' "$LOG" >&2
  exit 1
fi

deep_helper_lines="$(grep -E '\[LOWER\].*(Array|Hash|Tuple)\(.*(Array|Hash|Tuple)\(.*#(inspect|to_s|object_id|hash|to_json|to_i)(\$|$)' "$LOG" || true)"
deep_helpers="$(printf '%s\n' "$deep_helper_lines" | sed '/^$/d' | wc -l | tr -d ' ')"
if (( deep_helpers > MAX_DEEP_HELPERS )); then
  echo "p2 universal helper fanout regression: deep helper lowers ${deep_helpers} > ${MAX_DEEP_HELPERS}" >&2
  printf '%s\n' "$deep_helper_lines" | head -40 >&2
  exit 1
fi

echo "p2_universal_helper_fanout_no_prelude_ok deep_helpers=${deep_helpers}"
