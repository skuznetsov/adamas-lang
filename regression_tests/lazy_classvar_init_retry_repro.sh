#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
compiler="${CRYSTAL_BIN:-$(command -v crystal)}"
work="$(mktemp -d "${TMPDIR:-/tmp}/lazy-classvar-retry.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

args=(spec --no-color "$root_dir/spec/hir/lazy_classvar_init_transaction_spec.cr" --single-module --error-trace)
if [[ -n "${ADAMAS_EXTRA_LINK_FLAGS:-}" ]]; then
  args+=("--link-flags=$ADAMAS_EXTRA_LINK_FLAGS")
fi
CRYSTAL_CACHE_DIR="$work/cache" TMPDIR="$work" \
  "$root_dir/scripts/run_safe.sh" "$compiler" 240 14336 "${args[@]}"
