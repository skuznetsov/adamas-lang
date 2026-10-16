#!/usr/bin/env bash
# Reproduce the field-type inference used before lowering a generic map block.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named-tuple-map-inference.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cd "${1:-$ROOT_DIR}"
CRYSTAL_CACHE_DIR="$WORK_DIR/cache" \
  "$ROOT_DIR/scripts/run_safe.sh" "$CRYSTAL_BIN" 300 8192 \
  spec spec/hir/named_tuple_map_literal_index_inference_spec.cr \
  --link-flags=-fuse-ld=/usr/bin/ld
