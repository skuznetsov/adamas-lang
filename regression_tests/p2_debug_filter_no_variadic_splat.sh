#!/usr/bin/env bash
# Guard bootstrap-hot debug filtering helpers against variadic tuple splats.
#
# Generated stage2 currently cannot rely on arbitrary Tuple(*T) helper bodies
# being lowered before debug checks run. Keep these helpers fixed-arity so
# unset debug env checks do not abort through tuple-splat stubs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FILES=(
  "$ROOT_DIR/src/compiler/hir/ast_to_hir.cr"
  "$ROOT_DIR/src/compiler/cli.cr"
)

if rg -n 'def (debug_env_filter_match\?|debug_hook_filter_match\?|debug_class_repair_enabled_for\?)\([^)]*\*' "${FILES[@]}"; then
  echo "p2_debug_filter_no_variadic_splat_failed: debug filter helper uses variadic splat" >&2
  exit 1
fi

if rg -n 'debug_env_filter_match\?\([^)]*\*texts|debug_hook_filter_match\?\([^)]*\*texts|debug_class_repair_enabled_for\?\([^)]*\*texts' "${FILES[@]}"; then
  echo "p2_debug_filter_no_variadic_splat_failed: debug filter helper forwards *texts" >&2
  exit 1
fi

echo "p2_debug_filter_no_variadic_splat_ok"
