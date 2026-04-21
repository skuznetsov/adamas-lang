#!/usr/bin/env bash
# Tier-0 emit oracle for the fixed no-prelude bootstrap semantic corpus.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPILER="${1:-$ROOT_DIR/bin/crystal_v2}"
SRC="$ROOT_DIR/regression_tests/bootstrap_semantic_corpus.cr"

if [[ ! -x "$COMPILER" ]]; then
  echo "ERROR: compiler not found: $COMPILER" >&2
  exit 2
fi

TMP_DIR="$(mktemp -d /tmp/p2_bootstrap_semantic_emit_XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

PREFIX="$TMP_DIR/corpus"
LOG="$TMP_DIR/emit.log"

BOOTSTRAP_IR_TIMEOUT_SEC="${BOOTSTRAP_IR_TIMEOUT_SEC:-60}" \
BOOTSTRAP_IR_MEM_MB="${BOOTSTRAP_IR_MEM_MB:-2048}" \
  "$ROOT_DIR/scripts/emit_bootstrap_ir.sh" "$COMPILER" "$SRC" "$PREFIX" >"$LOG" 2>&1

for kind in hir mir ll; do
  if [[ ! -s "$PREFIX.$kind" ]]; then
    echo "p2 bootstrap semantic emit regression: missing $kind artifact" >&2
    cat "$LOG" >&2
    exit 1
  fi
done

if grep -R -q '\[PENDING_EXPLOSION\]' "$TMP_DIR"; then
  echo "p2 bootstrap semantic emit regression: pending explosion diagnostic fired" >&2
  grep -R '\[PENDING_EXPLOSION\]' "$TMP_DIR" >&2
  exit 1
fi

echo "p2_bootstrap_semantic_emit_oracle_ok"
