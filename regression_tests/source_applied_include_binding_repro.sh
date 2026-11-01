#!/usr/bin/env bash
# Applied module bindings must come from the receiver's source include before
# lazy module materialization, without borrowing ambient formal substitutions.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="${SAFE_RUNNER:-$ROOT_DIR/scripts/run_safe.sh}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-$(command -v crystal)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/source-applied-include.XXXXXX")"
trap 'rm -rf -- "$WORK"' EXIT
LINK_ARGS=()
if [[ -n "${ADAMAS_EXTRA_LINK_FLAGS:-}" ]]; then
  LINK_ARGS=("--link-flags=$ADAMAS_EXTRA_LINK_FLAGS")
elif [[ "$(uname -s)" == Darwin ]]; then
  LINK_ARGS=(--link-flags=-fuse-ld=/usr/bin/ld)
fi

cd "$ROOT_DIR"
CRYSTAL_CACHE_DIR="$WORK/cache" "$SAFE_RUNNER" "$CRYSTAL" 300 14336 \
  spec spec/hir/source_applied_include_lookup_spec.cr --single-module \
  --no-color --error-trace "${LINK_ARGS[@]}"
printf 'PASS: receiver-owned source include bindings\n'
