#!/usr/bin/env bash
# Check inline try failure unwinding and normal lexical scope ownership.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ORIGINAL="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-crystal}}"
ARGS=(spec "$ROOT_DIR/spec/hir/inline_try_scope_cleanup_spec.cr"
  "$ROOT_DIR/spec/hir/inline_caller_locals_stack_spec.cr"
  --single-module --error-trace --no-color)
if [[ "$(uname -s)" == Darwin ]]; then
  ARGS+=(--link-flags=-fuse-ld=/usr/bin/ld)
fi
exec "$ROOT_DIR/scripts/run_safe.sh" "$ORIGINAL" 300 14336 "${ARGS[@]}"
