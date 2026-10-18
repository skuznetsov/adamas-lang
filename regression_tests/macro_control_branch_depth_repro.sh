#!/usr/bin/env bash
# Exercise the parser directly, independently of HIR lowering and codegen.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ORIGINAL="${1:-${ORIGINAL_CRYSTAL_BIN:-crystal}}"
if [[ "$ORIGINAL" != */* ]]; then ORIGINAL="$(command -v "$ORIGINAL")"; fi
CACHE="$(mktemp -d "${TMPDIR:-/tmp}/adamas-macro-branch-depth.XXXXXX")"
trap 'rm -rf -- "$CACHE"' EXIT
LINK_ARGS=()
if [[ "$(uname -s)" == Darwin ]]; then LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld); fi
CRYSTAL_CACHE_DIR="$CACHE" "$ROOT_DIR/scripts/run_safe.sh" "$ORIGINAL" 120 4096 \
  spec "$ROOT_DIR/regression_tests/macro_control_branch_depth_spec.cr" \
  "${LINK_ARGS[@]}" --error-trace
