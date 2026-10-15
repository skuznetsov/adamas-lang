#!/usr/bin/env bash
# Preserve NamedTuple field syntax while substituting type parameters.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SPEC_ROOT="${ADAMAS_SPEC_ROOT:-$ROOT_DIR}"
CRYSTAL="${ORIGINAL_CRYSTAL_BIN:-/opt/homebrew/bin/crystal}"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/named-tuple-type-substitution.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$SPEC_ROOT"
env CRYSTAL_CACHE_DIR="$WORK_DIR/cache" \
  "$ROOT_DIR/scripts/run_safe.sh" "$CRYSTAL" 180 12288 \
  spec --no-color --link-flags=-fuse-ld=/usr/bin/ld \
  spec/hir/named_tuple_type_substitution_spec.cr
printf 'PASS: NamedTuple substitution preserves keys and recursively resolves field values\n'
