#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
CRYSTAL_BIN="${CRYSTAL_BIN:-$(command -v crystal || true)}"

if [[ ! -x "$SAFE_RUNNER" || ! -x "$CRYSTAL_BIN" ]]; then
  echo "ERROR: safe runner and Crystal compiler are required" >&2
  exit 2
fi

cd "$ROOT_DIR"
"$SAFE_RUNNER" "$CRYSTAL_BIN" 180 12288 \
  spec/hir/queued_source_result_demand_spec.cr
"$SAFE_RUNNER" "$CRYSTAL_BIN" 180 12288 \
  spec/hir/force_lower_retry_handoff_spec.cr
"$SAFE_RUNNER" "$CRYSTAL_BIN" 180 12288 \
  spec/hir/queued_static_source_result_spec.cr
