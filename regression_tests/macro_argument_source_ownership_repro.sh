#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ORIGINAL="${1:-${ORIGINAL_CRYSTAL_BIN:-crystal}}"
if [[ "$ORIGINAL" != */* ]]; then ORIGINAL="$(command -v "$ORIGINAL")"; fi
CACHE="$(mktemp -d "${TMPDIR:-/tmp}/adamas-macro-source-owner.XXXXXX")"
trap 'rm -rf -- "$CACHE"' EXIT
LINK_ARGS=()
if [[ "$(uname -s)" == Darwin ]]; then LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld); fi
CRYSTAL_CACHE_DIR="$CACHE" "$ROOT_DIR/scripts/run_safe.sh" "$ORIGINAL" 120 4096 \
  spec "$ROOT_DIR/spec/hir/macro_argument_source_ownership_spec.cr" \
  "${LINK_ARGS[@]}" --error-trace
