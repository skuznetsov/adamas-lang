#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
crystal_bin="${CRYSTAL_BIN:-$(command -v crystal)}"
args=(spec --no-color "$root/spec/hir/union_receiver_block_include_spec.cr"
  "$root/spec/hir/source_applied_transitive_block_origin_spec.cr" --error-trace)
if [[ -n "${ADAMAS_EXTRA_LINK_FLAGS:-}" ]]; then
  args+=("--link-flags=$ADAMAS_EXTRA_LINK_FLAGS")
fi
"$root/scripts/run_safe.sh" "$crystal_bin" 240 14336 "${args[@]}"
