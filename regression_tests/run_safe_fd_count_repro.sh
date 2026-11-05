#!/usr/bin/env bash
# Count numeric lsof descriptors while retaining resource and process-tree guards.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-crystal}"
if [[ "$ORIGINAL" != */* ]]; then
  ORIGINAL="$(command -v "$ORIGINAL")"
fi
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/run-safe-fd-count.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

cd "$ROOT_DIR"
CRYSTAL_CACHE_DIR="$WORK_DIR/cache" "$ROOT_DIR/scripts/run_safe.sh" "$ORIGINAL" 180 4096 \
  spec spec/runtime/run_safe_resource_metrics_spec.cr spec/runtime/run_safe_process_tree_spec.cr \
  --no-debug --error-trace
