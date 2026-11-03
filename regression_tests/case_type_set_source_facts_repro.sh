#!/usr/bin/env bash
# Exercise parsed case narrowing and source-kind facts through the stock compiler.
# Usage: ORIGINAL_CRYSTAL_BIN=/path/to/crystal bash <this-script>
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SAFE_RUNNER="$ROOT_DIR/scripts/run_safe.sh"
CRYSTAL_BIN="${ORIGINAL_CRYSTAL_BIN:-${CRYSTAL_BIN:-$(command -v crystal)}}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/case-type-set-facts.XXXXXX")"
trap 'rm -rf -- "$WORK_DIR"' EXIT
export TMPDIR="$WORK_DIR"
export CRYSTAL_CACHE_DIR="$WORK_DIR/cache"
flags=(--single-module --error-trace --no-color)
if [[ -n "${ORIGINAL_LINK_FLAGS:-}" ]]; then
  flags+=("--link-flags=$ORIGINAL_LINK_FLAGS")
fi
"$SAFE_RUNNER" "$CRYSTAL_BIN" 300 14336 spec \
  "$ROOT_DIR/spec/hir/case_type_set_copy_source_facts_spec.cr" \
  "$ROOT_DIR/spec/hir/case_copy_call_argument_pair_spec.cr" "${flags[@]}"
