#!/usr/bin/env bash
# Exercise the exact source/callshape transport used before nilary inference.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-$(command -v crystal || true)}}"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/exact-nilary-callsite.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
[[ -x "$CRYSTAL_BIN" && -x "$SAFE_RUNNER" ]] || exit 2
export CRYSTAL_CACHE_DIR="$WORK_DIR/cache"
mkdir -p "$CRYSTAL_CACHE_DIR"
flags=()
if [[ -n "${ORIGINAL_LINK_FLAGS:-}" ]]; then flags+=("--link-flags=$ORIGINAL_LINK_FLAGS"); fi
cd "$ROOT_DIR"
"$SAFE_RUNNER" "$CRYSTAL_BIN" 180 14336 spec \
  spec/hir/same_selected_member_callsite_transport_spec.cr \
  --single-module --no-debug "${flags[@]}"
