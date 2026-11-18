#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd -P)"
compiler="${CRYSTAL_BIN:-$(command -v crystal)}"
args=(spec --no-color --error-trace --single-module
  "$root/spec/hir/getter_result_authority_spec.cr"
  "$root/spec/hir/generated_getter_include_precedence_spec.cr")
if [[ -n "${ADAMAS_EXTRA_LINK_FLAGS:-}" ]]; then
  args+=("--link-flags=$ADAMAS_EXTRA_LINK_FLAGS")
fi
"$root/scripts/run_safe.sh" "$compiler" 300 14336 "${args[@]}"
