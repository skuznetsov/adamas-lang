#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <stage1-compiler> <stage2-compiler>" >&2
  exit 2
fi

STAGE1_COMPILER="$1"
STAGE2_COMPILER="$2"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT_DIR/regression_tests/stage2_absolute_generic_header_leaf_hir_oracle.cr"

run_compiler() {
  local compiler="$1"
  local label="$2"
  local wrapper
  local log
  wrapper="$(mktemp /tmp/${label}_wrapper_sh.XXXXXX)"
  log="$(mktemp /tmp/${label}_log.XXXXXX)"
  cat > "$wrapper" <<EOF
#!/bin/bash
set -euo pipefail
cd "$ROOT_DIR"
export DEBUG_GENERIC_TEMPLATE=1
export ADAMAS_STOP_AFTER_HIR=1
"$compiler" "$SRC" --release --no-prelude --no-ast-cache --emit hir -o /tmp/${label}.hir
EOF
  chmod +x "$wrapper"
  "$ROOT_DIR/scripts/run_safe.sh" "$wrapper" 20 2048 > "$log" 2>&1 || true
  rm -f "$wrapper"
  printf '%s\n' "$log"
}

stage1_log="$(run_compiler "$STAGE1_COMPILER" stage2_abs_leaf_stage1)"
stage2_log="$(run_compiler "$STAGE2_COMPILER" stage2_abs_leaf_stage2)"

expected="[GENERIC_TEMPLATE] Crystal::PointerLinkedList:"
bad="[GENERIC_TEMPLATE] Crystal::Crystal:"

if ! grep -Fq "$expected" "$stage1_log"; then
  echo "stage1 missing expected absolute generic leaf name"
  cat "$stage1_log"
  exit 1
fi

if grep -Fq "$bad" "$stage2_log"; then
  echo "reproduced: stage2 still collapses absolute generic header leaf name to Crystal"
  cat "$stage2_log"
  exit 1
fi

if ! grep -Fq "$expected" "$stage2_log"; then
  echo "stage2 missing expected absolute generic leaf name"
  cat "$stage2_log"
  exit 1
fi

echo "not reproduced: stage2 preserves absolute generic header leaf names in HIR template registration"
